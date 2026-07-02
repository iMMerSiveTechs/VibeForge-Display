import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import CoreGraphics
import ScreenCaptureKit
import UniformTypeIdentifiers

/// What ScreenCaptureKit will capture for a running session.
enum StreamSource: Sendable {
    case display(CGDirectDisplayID)   // a (virtual) display
    case window(CGWindowID)           // a Surface window
}

// MARK: - StreamService

/// Owns live Routes. For each running route it captures its source (a virtual
/// display or a Surface window) with ScreenCaptureKit, encodes to H.264 via
/// AVAssetWriter's HLS segmentation, and feeds segments to the HLSServer so
/// receivers can play them over the LAN.
@MainActor
@Observable
final class StreamService {
    private(set) var routes: [RouteConfig] = []
    private(set) var streamingRouteIDs: Set<UUID> = []

    private var sessions: [UUID: StreamSession] = [:]
    private let persistence: PersistenceManager
    private let logService: LogService
    private let hlsServer: HLSServer
    private let virtualDisplayService: VirtualDisplayService
    private let surfaceService: SurfaceService

    init(
        persistence: PersistenceManager,
        logService: LogService,
        hlsServer: HLSServer,
        virtualDisplayService: VirtualDisplayService,
        surfaceService: SurfaceService
    ) {
        self.persistence = persistence
        self.logService = logService
        self.hlsServer = hlsServer
        self.virtualDisplayService = virtualDisplayService
        self.surfaceService = surfaceService
        loadRoutes()
    }

    // MARK: Route CRUD

    func addRoute(_ route: RouteConfig) {
        routes.append(route)
        persistRoutes()
        logService.log(.system, "Created route: \(route.name)")
    }

    func updateRoute(_ route: RouteConfig) {
        guard let idx = routes.firstIndex(where: { $0.id == route.id }) else { return }
        routes[idx] = route
        persistRoutes()
    }

    func removeRoute(_ id: UUID) {
        stopRoute(id)
        let name = routes.first(where: { $0.id == id })?.name ?? "route"
        routes.removeAll { $0.id == id }
        persistRoutes()
        logService.log(.system, "Removed route: \(name)")
    }

    func isStreaming(_ id: UUID) -> Bool { streamingRouteIDs.contains(id) }

    struct RouteStats {
        let frames: Int
        let segments: Int
        let startedAt: Date
        var uptime: TimeInterval { max(0, Date().timeIntervalSince(startedAt)) }
        var avgFPS: Double { uptime > 0.5 ? Double(frames) / uptime : 0 }
    }

    func stats(for id: UUID) -> RouteStats? {
        guard let s = sessions[id] else { return nil }
        return RouteStats(frames: s.framesEncoded(), segments: s.segmentsOut(), startedAt: s.startedAt)
    }

    func receiverURL(for route: RouteConfig) -> String {
        hlsServer.receiverURL(streamKey: route.streamKey)
    }

    // MARK: Start / stop

    func startRoute(_ id: UUID) async {
        guard let route = routes.first(where: { $0.id == id }) else { return }
        guard !streamingRouteIDs.contains(id) else { return }

        // Resolve the capture source and its dimensions per source kind.
        let source: StreamSource
        let width: Int
        let height: Int

        switch route.sourceKind {
        case .virtualScreen:
            guard let vs = virtualDisplayService.configs.first(where: { $0.id == route.sourceID }) else {
                logService.log(.error, "Route source missing", detail: "No virtual screen for \(route.name)")
                return
            }
            if !virtualDisplayService.isActive(vs.id) {
                await virtualDisplayService.createDisplay(config: vs)
            }
            guard let displayID = virtualDisplayService.displayID(for: vs.id) else {
                logService.log(.error, "Could not activate source display", detail: route.name)
                return
            }
            source = .display(displayID)
            width = vs.width
            height = vs.height

        case .surface:
            guard let sc = surfaceService.configs.first(where: { $0.id == route.sourceID }) else {
                logService.log(.error, "Route source missing", detail: "No surface for \(route.name)")
                return
            }
            guard let windowID = surfaceService.ensureWindowID(for: sc.id) else {
                logService.log(.error, "Could not open source surface window", detail: route.name)
                return
            }
            source = .window(windowID)
            width = max(2, Int(sc.frameWidth))
            height = max(2, Int(sc.frameHeight))
        }

        hlsServer.start()
        hlsServer.store.register(key: route.streamKey, name: route.name)

        let session = StreamSession(
            route: route,
            source: source,
            sourceWidth: width,
            sourceHeight: height,
            store: hlsServer.store,
            logService: logService
        )
        do {
            try await session.start()
            sessions[id] = session
            streamingRouteIDs.insert(id)
            logService.log(.system, "Streaming started: \(route.name)",
                           detail: hlsServer.redactedReceiverURL(streamKey: route.streamKey))
        } catch {
            hlsServer.store.unregister(key: route.streamKey)
            logService.log(.error, "Failed to start stream: \(route.name)",
                           detail: error.localizedDescription)
        }
    }

    func stopRoute(_ id: UUID) {
        guard let session = sessions[id] else { return }
        let route = routes.first(where: { $0.id == id })
        session.stop()
        sessions.removeValue(forKey: id)
        streamingRouteIDs.remove(id)
        if let key = route?.streamKey { hlsServer.store.unregister(key: key) }
        if let name = route?.name { logService.log(.system, "Streaming stopped: \(name)") }
    }

    func stopAll() {
        for id in Array(streamingRouteIDs) { stopRoute(id) }
    }

    /// Starts routes flagged auto-start shortly after launch. Respects the
    /// virtual-display safe mode: a virtual-screen route is only auto-started if
    /// its screen is already active (i.e. the last session exited cleanly), so we
    /// never force-create a possibly-black-screening display at launch.
    func scheduleAutoStart() {
        let autos = routes.filter(\.autoStart)
        guard !autos.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            for route in autos {
                switch route.sourceKind {
                case .surface:
                    await startRoute(route.id)
                case .virtualScreen:
                    if virtualDisplayService.isActive(route.sourceID) {
                        await startRoute(route.id)
                    } else {
                        logService.log(.system, "Skipped auto-start (screen inactive): \(route.name)")
                    }
                }
            }
        }
    }

    // MARK: Persistence

    private func loadRoutes() {
        guard persistence.exists(VFConstants.routesFileName) else { return }
        do {
            routes = try persistence.load([RouteConfig].self, from: VFConstants.routesFileName)
            logService.log(.system, "Loaded \(routes.count) route(s)")
        } catch {
            logService.log(.error, "Failed to load routes", detail: error.localizedDescription)
        }
    }

    private func persistRoutes() {
        do { try persistence.save(routes, to: VFConstants.routesFileName) }
        catch { logService.log(.error, "Failed to save routes", detail: error.localizedDescription) }
    }
}

// MARK: - StreamSession (per-route capture + encode pipeline)

/// One capture→encode→segment pipeline. Runs its ScreenCaptureKit output and
/// AVAssetWriter delegate callbacks on background queues; only touches the
/// (lock-protected) HLSSegmentStore and its own serial state from those queues.
final class StreamSession: NSObject, SCStreamOutput, SCStreamDelegate, AVAssetWriterDelegate, @unchecked Sendable {
    private let route: RouteConfig
    private let source: StreamSource
    private let sourceWidth: Int
    private let sourceHeight: Int
    private let store: HLSSegmentStore
    private let logService: LogService

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var sessionStarted = false
    private let sampleQueue = DispatchQueue(label: "vibeforge.stream.samples")

    // Lightweight live telemetry (read from the UI on the main thread).
    let startedAt = Date()
    private let statsLock = NSLock()
    private var _framesEncoded = 0
    private var _segmentsOut = 0

    func framesEncoded() -> Int { statsLock.lock(); defer { statsLock.unlock() }; return _framesEncoded }
    func segmentsOut() -> Int { statsLock.lock(); defer { statsLock.unlock() }; return _segmentsOut }

    init(route: RouteConfig, source: StreamSource, sourceWidth: Int, sourceHeight: Int,
         store: HLSSegmentStore, logService: LogService) {
        self.route = route
        self.source = source
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.store = store
        self.logService = logService
        super.init()
    }

    // Output pixel dimensions after applying the quality scale (kept even).
    private var outWidth: Int { max(2, Int(Double(sourceWidth) * route.quality.scale) / 2 * 2) }
    private var outHeight: Int { max(2, Int(Double(sourceHeight) * route.quality.scale) / 2 * 2) }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        let filter: SCContentFilter
        switch source {
        case .display(let displayID):
            guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
                throw NSError(domain: "VibeForge", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Display \(displayID) not capturable"])
            }
            filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        case .window(let windowID):
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                throw NSError(domain: "VibeForge", code: 4,
                              userInfo: [NSLocalizedDescriptionKey: "Window \(windowID) not capturable"])
            }
            filter = SCContentFilter(desktopIndependentWindow: scWindow)
        }

        try setupWriter()

        let config = SCStreamConfiguration()
        config.width = outWidth
        config.height = outHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(route.quality.frameRate))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 6
        config.showsCursor = true

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    private func setupWriter() throws {
        let writer = try AVAssetWriter(contentType: UTType.mpeg4Movie)
        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = CMTime(
            seconds: VFConstants.Streaming.segmentDuration, preferredTimescale: 1)
        writer.initialSegmentStartTime = .zero
        writer.delegate = self

        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: route.quality.bitrate,
            AVVideoMaxKeyFrameIntervalDurationKey: VFConstants.Streaming.segmentDuration,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoAllowFrameReorderingKey: false,
        ]
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outWidth,
            AVVideoHeightKey: outHeight,
            AVVideoCompressionPropertiesKey: compression,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw NSError(domain: "VibeForge", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "VibeForge", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "startWriting failed"])
        }
        self.writer = writer
        self.videoInput = input
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        guard StreamSession.isComplete(sampleBuffer) else { return }
        guard let writer, let input = videoInput, writer.status == .writing else { return }

        if !sessionStarted {
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            sessionStarted = true
        }
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
            statsLock.lock(); _framesEncoded += 1; statsLock.unlock()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            logService.log(.error, "Capture stopped: \(route.name)", detail: error.localizedDescription)
        }
    }

    /// ScreenCaptureKit sends idle/blank frames; only forward frames with fresh image data.
    private static func isComplete(_ sb: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }

    // MARK: AVAssetWriterDelegate

    func assetWriter(_ writer: AVAssetWriter, didOutputSegmentData segmentData: Data,
                     segmentType: AVAssetSegmentType, segmentReport: AVAssetSegmentReport?) {
        switch segmentType {
        case .initialization:
            store.setInit(key: route.streamKey, data: segmentData)
        case .separable:
            let duration = segmentReport?.trackReports.first?.duration.seconds
                ?? VFConstants.Streaming.segmentDuration
            store.appendSegment(key: route.streamKey, data: segmentData, duration: duration)
            statsLock.lock(); _segmentsOut += 1; statsLock.unlock()
        @unknown default:
            break
        }
    }

    // MARK: Teardown

    func stop() {
        stream?.stopCapture { _ in }
        stream = nil
        videoInput?.markAsFinished()
        writer?.finishWriting { }
        writer = nil
        videoInput = nil
    }
}
