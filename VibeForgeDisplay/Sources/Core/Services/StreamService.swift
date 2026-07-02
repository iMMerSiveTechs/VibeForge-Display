import Foundation
import Observation
import AVFoundation
import CoreMedia
import CoreVideo
import CoreGraphics
import QuartzCore
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
    private(set) var startingRouteIDs: Set<UUID> = []
    /// Last user-facing error per route (permission denied, capture failed, …),
    /// surfaced in the Routes UI. Cleared when a start succeeds.
    private(set) var lastError: [UUID: String] = [:]

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
    func isStarting(_ id: UUID) -> Bool { startingRouteIDs.contains(id) }
    func error(for id: UUID) -> String? { lastError[id] }

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
        // Re-entrancy guard: ignore if already streaming or a start is in flight.
        guard !streamingRouteIDs.contains(id), !startingRouteIDs.contains(id) else { return }
        startingRouteIDs.insert(id)
        lastError[id] = nil
        defer { startingRouteIDs.remove(id) }

        // Resolve the capture source and its dimensions per source kind.
        let source: StreamSource
        let width: Int
        let height: Int

        switch route.sourceKind {
        case .virtualScreen:
            guard let vs = virtualDisplayService.configs.first(where: { $0.id == route.sourceID }) else {
                fail(id, "This route's virtual screen no longer exists. Recreate it or delete the route.")
                return
            }
            if !virtualDisplayService.isActive(vs.id) {
                await virtualDisplayService.createDisplay(config: vs)
            }
            guard let displayID = virtualDisplayService.displayID(for: vs.id) else {
                fail(id, "Couldn't activate the virtual screen “\(vs.name)”.")
                return
            }
            source = .display(displayID)
            width = vs.width
            height = vs.height

        case .surface:
            guard let sc = surfaceService.configs.first(where: { $0.id == route.sourceID }) else {
                fail(id, "This route's Surface no longer exists. Recreate it or delete the route.")
                return
            }
            guard let windowID = surfaceService.ensureWindowID(for: sc.id) else {
                fail(id, "Couldn't open the Surface window for “\(sc.name)”.")
                return
            }
            source = .window(windowID)
            width = max(2, Int(sc.frameWidth))
            height = max(2, Int(sc.frameHeight))
        }

        // Ensure the LAN server is actually listening before we claim "Live".
        let serverUp = await hlsServer.startAndWait()
        guard serverUp else {
            fail(id, "The stream server couldn't start (port \(hlsServer.port) may be in use).")
            return
        }
        hlsServer.store.register(key: route.streamKey, name: route.name)

        let session = StreamSession(
            route: route,
            source: source,
            sourceWidth: width,
            sourceHeight: height,
            store: hlsServer.store,
            logService: logService
        )
        // Clean up if capture dies later (source destroyed, permission revoked, …).
        session.onStopped = { [weak self] message in
            Task { @MainActor in self?.handleSessionStopped(id, error: message) }
        }
        do {
            try await session.start()
            // If the user stopped/removed the route while we were awaiting, abort.
            guard startingRouteIDs.contains(id), routes.contains(where: { $0.id == id }) else {
                session.stop()
                hlsServer.store.unregister(key: route.streamKey)
                return
            }
            sessions[id] = session
            streamingRouteIDs.insert(id)
            logService.log(.system, "Streaming started: \(route.name)",
                           detail: hlsServer.redactedReceiverURL(streamKey: route.streamKey))
        } catch {
            hlsServer.store.unregister(key: route.streamKey)
            fail(id, friendlyStartError(error))
        }
    }

    private func fail(_ id: UUID, _ message: String) {
        lastError[id] = message
        logService.log(.error, "Route start failed", detail: message)
    }

    /// Turns capture errors into user-actionable text. Screen Recording denial is
    /// the common first-run failure (SCShareableContent throws), so lead with it.
    private func friendlyStartError(_ error: Error) -> String {
        "Couldn't start capture — if this is the first time, grant Screen Recording "
        + "in System Settings → Privacy & Security and relaunch VibeForge. (\(error.localizedDescription))"
    }

    func stopRoute(_ id: UUID) {
        // Cancel an in-flight start (startRoute re-checks startingRouteIDs after its awaits).
        let wasStarting = startingRouteIDs.remove(id) != nil
        guard let session = sessions[id] else {
            if wasStarting { logService.log(.system, "Cancelled starting route") }
            return
        }
        let route = routes.first(where: { $0.id == id })
        session.onStopped = nil          // we're stopping deliberately; no failure callback
        session.stop()
        sessions.removeValue(forKey: id)
        streamingRouteIDs.remove(id)
        if let key = route?.streamKey { hlsServer.store.unregister(key: key) }
        if let name = route?.name { logService.log(.system, "Streaming stopped: \(name)") }
    }

    func stopAll() {
        for id in Array(streamingRouteIDs) { stopRoute(id) }
        for id in Array(startingRouteIDs) { startingRouteIDs.remove(id) }
    }

    /// Stops any live/starting route whose source is `sourceID` — call before
    /// deleting or deactivating a virtual screen or Surface.
    func stopRoutesUsing(sourceID: UUID) {
        for route in routes where route.sourceID == sourceID {
            if streamingRouteIDs.contains(route.id) || startingRouteIDs.contains(route.id) {
                stopRoute(route.id)
            }
        }
    }

    /// Invoked when a session's capture dies on its own (SCStream didStopWithError).
    private func handleSessionStopped(_ id: UUID, error: String?) {
        guard sessions[id] != nil else { return }
        let route = routes.first(where: { $0.id == id })
        sessions.removeValue(forKey: id)
        streamingRouteIDs.remove(id)
        if let key = route?.streamKey { hlsServer.store.unregister(key: key) }
        lastError[id] = error.map { "Streaming stopped: \($0)" } ?? "Streaming stopped unexpectedly."
    }

    /// Starts routes flagged auto-start shortly after launch. Respects the
    /// virtual-display safe mode: a virtual-screen route is only auto-started if
    /// its screen is already active (i.e. the last session exited cleanly), so we
    /// never force-create a possibly-black-screening display at launch.
    func scheduleAutoStart() {
        let autos = routes.filter(\.autoStart)
        guard !autos.isEmpty else { return }
        Task { @MainActor in
            // Wait for the virtual-display auto-create pass to finish rather than
            // guessing with a fixed sleep — otherwise the isActive check below runs
            // before slow displays come up and auto-start silently no-ops.
            await virtualDisplayService.awaitAutoCreate()
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

    /// Called (once) if the capture stops on its own — e.g. the source display is
    /// destroyed, the Surface window closes, or Screen Recording is revoked. Nil'd
    /// out on a deliberate stop() so we don't report a user-initiated stop as failure.
    var onStopped: (@Sendable (String?) -> Void)?

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var isStopping = false
    // Set synchronously the instant stop() is called (any thread), so the writer
    // delegate can't push a late final segment into a re-registered stream key
    // after a rapid stop -> start on the same route.
    private let stopLock = NSLock()
    private var stopped = false
    private let sampleQueue = DispatchQueue(label: "vibeforge.stream.samples")

    // Zero-based encode timeline (so init/segment times are consistent) plus a
    // keep-alive that re-emits the last frame on a static screen — otherwise
    // ScreenCaptureKit stops delivering frames and the HLS playlist freezes.
    private var baselineHost: CFTimeInterval?
    private var lastAdjustedPTS: CMTime = .zero
    private var lastSample: CMSampleBuffer?
    private var lastRealFrameHost: CFTimeInterval = 0
    private var keepAliveTimer: DispatchSourceTimer?
    private var frameInterval: CMTime {
        CMTime(value: 1, timescale: CMTimeScale(max(1, route.quality.frameRate)))
    }

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
        // All access below is on sampleQueue (the sample handler queue) plus the
        // keep-alive timer, which also runs on sampleQueue — so no locking needed.
        guard !isStopping, type == .screen, sampleBuffer.isValid else { return }
        guard StreamSession.isComplete(sampleBuffer) else { return }
        guard let writer, let input = videoInput, writer.status == .writing else { return }

        let now = CACurrentMediaTime()
        if baselineHost == nil {
            baselineHost = now
            writer.startSession(atSourceTime: .zero)
            sessionStarted = true
        }
        appendRetimed(sampleBuffer, at: now, input: input)
        lastSample = sampleBuffer
        lastRealFrameHost = now
        startKeepAliveIfNeeded()
    }

    /// Appends a copy of `sample` timestamped to real elapsed time since the first
    /// frame — so media-time tracks wall-clock and segments cut at ~1s regardless
    /// of the source frame cadence (including synthesized keep-alive frames).
    private func appendRetimed(_ sample: CMSampleBuffer, at host: CFTimeInterval, input: AVAssetWriterInput) {
        guard input.isReadyForMoreMediaData, let baselineHost else { return }
        let elapsed = max(0, host - baselineHost)
        var pts = CMTime(seconds: elapsed, preferredTimescale: 600)
        if CMTimeCompare(pts, lastAdjustedPTS) <= 0 {           // strictly increasing
            pts = CMTimeAdd(lastAdjustedPTS, frameInterval)
        }
        var timing = CMSampleTimingInfo(duration: frameInterval,
                                        presentationTimeStamp: pts,
                                        decodeTimeStamp: .invalid)
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: sample,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &copy)
        guard status == noErr, let out = copy else { return }
        input.append(out)
        lastAdjustedPTS = pts
        statsLock.lock(); _framesEncoded += 1; statsLock.unlock()
    }

    private func startKeepAliveIfNeeded() {
        guard keepAliveTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: sampleQueue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in self?.keepAliveTick() }
        keepAliveTimer = timer
        timer.resume()
    }

    /// If no real frame arrived recently (static screen), re-emit the last one at
    /// the current wall-clock time so AVAssetWriter keeps cutting segments.
    private func keepAliveTick() {
        guard !isStopping, sessionStarted,
              let input = videoInput, let last = lastSample else { return }
        let now = CACurrentMediaTime()
        if now - lastRealFrameHost < 0.9 { return }
        appendRetimed(last, at: now, input: input)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let message = error.localizedDescription
        onStopped?(message)
        onStopped = nil
        Task { @MainActor in
            self.logService.log(.error, "Capture stopped: \(self.route.name)", detail: message)
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
        stopLock.lock(); let done = stopped; stopLock.unlock()
        guard !done else { return }   // drop late segments after stop()
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
        onStopped = nil
        stopLock.lock(); stopped = true; stopLock.unlock()
        stream?.stopCapture { _ in }
        stream = nil
        // Finalize the writer on sampleQueue so it can't race an in-flight append
        // (append-after-markAsFinished throws NSInternalInconsistencyException).
        sampleQueue.async { [weak self] in
            guard let self else { return }
            self.isStopping = true
            self.keepAliveTimer?.cancel()
            self.keepAliveTimer = nil
            self.videoInput?.markAsFinished()
            self.writer?.finishWriting { }
            self.writer = nil
            self.videoInput = nil
            self.lastSample = nil
        }
    }
}
