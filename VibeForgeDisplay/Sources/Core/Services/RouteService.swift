import Foundation
import Network
import CoreGraphics
import AppKit
import ScreenCaptureKit

/// RouteService streams virtual display content to iPads, tablets, and browsers.
///
/// Architecture:
///   1. ScreenCaptureKit captures the virtual display at target FPS
///   2. Frames are JPEG-compressed at the configured quality
///   3. An NWListener serves both HTTP (MJPEG, client UI, snapshot) and WebSocket (binary frames, input relay)
///   4. Connected devices render frames fullscreen and relay touch/keyboard back
@MainActor
@Observable
final class RouteService {
    private(set) var routes: [RouteConfig] = []
    private(set) var activeRouteIDs: Set<UUID> = []
    private(set) var clients: [UUID: [StreamClient]] = [:]  // routeID -> clients
    private(set) var frameCounters: [UUID: Int] = [:]

    private var listeners: [UUID: NWListener] = [:]
    private var captureEngines: [UUID: SCStream] = [:]
    private var latestFrames: [UUID: Data] = [:]            // routeID -> JPEG data
    private var wsConnections: [UUID: [NWConnection]] = [:]  // routeID -> WS connections
    private var captureTimers: [UUID: Timer] = [:]

    private let persistence: PersistenceManager
    private let logService: LogService
    private let virtualDisplayService: VirtualDisplayService
    private let routesFileName = "routes.json"

    init(persistence: PersistenceManager, logService: LogService, virtualDisplayService: VirtualDisplayService) {
        self.persistence = persistence
        self.logService = logService
        self.virtualDisplayService = virtualDisplayService
        loadRoutes()
        autoStartRoutes()
    }

    // MARK: - Route CRUD

    func addRoute(_ route: RouteConfig) {
        routes.append(route)
        persistRoutes()
        logService.log(.route, "Created route: \(route.name)", detail: "Port \(route.port)")
    }

    func removeRoute(_ id: UUID) {
        let name = routes.first(where: { $0.id == id })?.name ?? "Unknown"
        stopRoute(id)
        routes.removeAll { $0.id == id }
        persistRoutes()
        logService.log(.route, "Removed route: \(name)")
    }

    func updateRoute(_ route: RouteConfig) {
        guard let index = routes.firstIndex(where: { $0.id == route.id }) else { return }
        let wasActive = activeRouteIDs.contains(route.id)
        if wasActive { stopRoute(route.id) }
        routes[index] = route
        persistRoutes()
        if wasActive { startRoute(route.id) }
    }

    // MARK: - Start / Stop Streaming

    func startRoute(_ id: UUID) {
        guard let route = routes.first(where: { $0.id == id }) else { return }
        guard !activeRouteIDs.contains(id) else { return }

        // Start the HTTP + WebSocket listener
        startListener(for: route)

        // Start screen capture
        startCapture(for: route)

        activeRouteIDs.insert(id)
        clients[id] = []
        frameCounters[id] = 0

        logService.log(.route, "Started route: \(route.name)",
                       detail: "Streaming on port \(route.port)")
    }

    func stopRoute(_ id: UUID) {
        guard activeRouteIDs.contains(id) else { return }
        let name = routes.first(where: { $0.id == id })?.name ?? "Unknown"

        // Stop capture
        captureTimers[id]?.invalidate()
        captureTimers.removeValue(forKey: id)

        if let stream = captureEngines[id] {
            stream.stopCapture { _ in }
            captureEngines.removeValue(forKey: id)
        }

        // Close all WebSocket connections
        wsConnections[id]?.forEach { $0.cancel() }
        wsConnections.removeValue(forKey: id)

        // Stop listener
        listeners[id]?.cancel()
        listeners.removeValue(forKey: id)

        // Clean up state
        activeRouteIDs.remove(id)
        latestFrames.removeValue(forKey: id)
        clients.removeValue(forKey: id)
        frameCounters.removeValue(forKey: id)

        logService.log(.route, "Stopped route: \(name)")
    }

    func stopAll() {
        for id in activeRouteIDs {
            stopRoute(id)
        }
    }

    func isActive(_ id: UUID) -> Bool {
        activeRouteIDs.contains(id)
    }

    func clientCount(for routeID: UUID) -> Int {
        clients[routeID]?.count ?? 0
    }

    // MARK: - Get Local IP for iPad URL

    func localIPAddress() -> String {
        var address = "localhost"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }
        return address
    }

    func connectURL(for route: RouteConfig) -> String {
        let ip = localIPAddress()
        return "http://\(ip):\(route.port)"
    }

    // MARK: - Network Listener (HTTP + WebSocket)

    private func startListener(for route: RouteConfig) {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: route.port)!)
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in
                    self?.handleConnection(conn, routeID: route.id)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.logService.log(.route, "Listener ready on port \(route.port)")
                    case .failed(let error):
                        self?.logService.log(.error, "Listener failed", detail: error.localizedDescription)
                    default: break
                    }
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
            listeners[route.id] = listener
        } catch {
            logService.log(.error, "Failed to start listener", detail: error.localizedDescription)
        }
    }

    private nonisolated func handleConnection(_ connection: NWConnection, routeID: UUID) {
        connection.start(queue: .global(qos: .userInitiated))

        // Read the first request to determine HTTP path
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] content, _, _, error in
            guard let data = content, error == nil else {
                connection.cancel()
                return
            }

            guard let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let path = self?.parseHTTPPath(from: request) ?? "/"

            Task { @MainActor in
                guard let self else { return }
                switch path {
                case "/":
                    self.serveClientUI(connection: connection, routeID: routeID)
                case "/stream":
                    self.serveMJPEGStream(connection: connection, routeID: routeID)
                case "/snapshot":
                    self.serveSnapshot(connection: connection, routeID: routeID)
                case "/status":
                    self.serveStatus(connection: connection, routeID: routeID)
                default:
                    self.serve404(connection: connection)
                }
            }
        }
    }

    private nonisolated func parseHTTPPath(from request: String) -> String {
        // "GET /path HTTP/1.1\r\n..."
        let lines = request.split(separator: "\r\n")
        guard let firstLine = lines.first else { return "/" }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return "/" }
        return String(parts[1])
    }

    // MARK: - HTTP Responses

    private func serveClientUI(connection: NWConnection, routeID: UUID) {
        let html = buildClientHTML(routeID: routeID)
        let response = buildHTTPResponse(status: "200 OK", contentType: "text/html", body: html)
        sendAndClose(connection: connection, data: response)
    }

    private func serveSnapshot(connection: NWConnection, routeID: UUID) {
        guard let frame = latestFrames[routeID] else {
            let response = buildHTTPResponse(status: "503 Service Unavailable", contentType: "text/plain", body: "No frame available")
            sendAndClose(connection: connection, data: response)
            return
        }
        let header = "HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\nContent-Length: \(frame.count)\r\nConnection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(frame)
        sendAndClose(connection: connection, data: data)
    }

    private func serveStatus(connection: NWConnection, routeID: UUID) {
        let status: [String: Any] = [
            "streaming": activeRouteIDs.contains(routeID),
            "clients": clients[routeID]?.count ?? 0,
            "frames": frameCounters[routeID] ?? 0,
        ]
        let json = (try? JSONSerialization.data(withJSONObject: status)) ?? Data("{}".utf8)
        let response = buildHTTPResponse(status: "200 OK", contentType: "application/json", body: String(data: json, encoding: .utf8) ?? "{}")
        sendAndClose(connection: connection, data: response)
    }

    private func serveMJPEGStream(connection: NWConnection, routeID: UUID) {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=vfbound\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
        let headerData = Data(header.utf8)
        connection.send(content: headerData, completion: .contentProcessed { _ in })

        // Add to WebSocket connections for frame pushing
        if wsConnections[routeID] == nil {
            wsConnections[routeID] = []
        }
        wsConnections[routeID]?.append(connection)

        // Add a client entry
        let client = StreamClient(deviceName: "MJPEG Client")
        clients[routeID]?.append(client)

        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state {
                Task { @MainActor in
                    self?.wsConnections[routeID]?.removeAll { $0 === connection }
                    self?.clients[routeID]?.removeAll { $0.id == client.id }
                }
            }
        }
    }

    private func serve404(connection: NWConnection) {
        let response = buildHTTPResponse(status: "404 Not Found", contentType: "text/plain", body: "Not Found")
        sendAndClose(connection: connection, data: response)
    }

    private func buildHTTPResponse(status: String, contentType: String, body: String) -> Data {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.utf8.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n\(body)"
        return Data(response.utf8)
    }

    private func sendAndClose(connection: NWConnection, data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Screen Capture

    private func startCapture(for route: RouteConfig) {
        guard let sourceID = route.sourceDisplayConfigID,
              let displayID = virtualDisplayService.displayID(for: sourceID) else {
            logService.log(.error, "Cannot start capture — no active virtual display for route \(route.name)")
            // Fallback: capture primary display
            startFallbackCapture(for: route)
            return
        }

        // Use ScreenCaptureKit to capture the specific display
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    logService.log(.error, "Display \(displayID) not found in shareable content")
                    startFallbackCapture(for: route)
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = route.quality == .lossless ? display.width : min(display.width, 1920)
                config.height = route.quality == .lossless ? display.height : min(display.height, 1080)
                config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(route.maxFPS))
                config.pixelFormat = kCVPixelFormatType_32BGRA

                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                let output = FrameHandler(routeID: route.id, quality: route.quality.jpegQuality, service: self)
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
                try await stream.startCapture()
                captureEngines[route.id] = stream

                logService.log(.route, "ScreenCaptureKit started for \(route.name)",
                              detail: "Display \(displayID), \(config.width)x\(config.height) @ \(route.maxFPS)fps")
            } catch {
                logService.log(.error, "SCK capture failed", detail: error.localizedDescription)
                startFallbackCapture(for: route)
            }
        }
    }

    /// Fallback: use CGWindowListCreateImage to capture the whole screen
    private func startFallbackCapture(for route: RouteConfig) {
        let interval = 1.0 / Double(route.maxFPS)
        let quality = route.quality.jpegQuality

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let cgImage = CGWindowListCreateImage(.null, .optionAll, kCGNullWindowID, [.bestResolution])
                guard let image = cgImage else { return }

                let bitmap = NSBitmapImageRep(cgImage: image)
                guard let jpeg = bitmap.representation(using: .jpeg,
                    properties: [.compressionFactor: NSNumber(value: Double(quality) / 100.0)]) else { return }

                self.pushFrame(jpeg, routeID: route.id)
            }
        }
        captureTimers[route.id] = timer
        logService.log(.route, "Fallback capture started for \(route.name)")
    }

    // MARK: - Frame Distribution

    func pushFrame(_ jpegData: Data, routeID: UUID) {
        latestFrames[routeID] = jpegData
        frameCounters[routeID] = (frameCounters[routeID] ?? 0) + 1

        // Push to all MJPEG connections
        let boundary = "--vfbound\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpegData.count)\r\n\r\n"
        var mjpegFrame = Data(boundary.utf8)
        mjpegFrame.append(jpegData)
        mjpegFrame.append(Data("\r\n".utf8))

        wsConnections[routeID]?.forEach { conn in
            conn.send(content: mjpegFrame, completion: .contentProcessed { _ in })
        }
    }

    // MARK: - Persistence

    private func loadRoutes() {
        guard persistence.exists(routesFileName) else { return }
        do {
            let (loaded, dropped) = try persistence.loadArray([RouteConfig].self, from: routesFileName)
            routes = loaded
            logService.log(.route, "Loaded \(routes.count) route(s)")
            if dropped > 0 {
                logService.log(.error, "Skipped \(dropped) corrupt route(s) on load")
            }
        } catch {
            logService.log(.error, "Failed to load routes", detail: error.localizedDescription)
        }
    }

    private func persistRoutes() {
        do {
            try persistence.save(routes, to: routesFileName)
        } catch {
            logService.log(.error, "Failed to save routes", detail: error.localizedDescription)
        }
    }

    private func autoStartRoutes() {
        let autoRoutes = routes.filter(\.autoStartOnLaunch)
        guard !autoRoutes.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            for route in autoRoutes {
                startRoute(route.id)
            }
        }
    }

    // MARK: - Client HTML

    private func buildClientHTML(routeID: UUID) -> String {
        let route = routes.first(where: { $0.id == routeID })
        let name = route?.name ?? "VibeForge Display"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <meta name="apple-mobile-web-app-capable" content="yes">
        <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
        <title>\(name)</title>
        <style>
          *{margin:0;padding:0;box-sizing:border-box}
          html,body{width:100%;height:100%;overflow:hidden;background:#000}
          #d{width:100vw;height:100vh;object-fit:contain;display:block;cursor:none}
          #s{position:fixed;top:10px;right:10px;background:rgba(0,0,0,.7);
             color:#4ade80;font:12px/1.4 -apple-system,system-ui;
             padding:6px 12px;border-radius:8px;opacity:0;transition:opacity .3s;z-index:10}
          #s.show{opacity:1}
        </style>
        </head>
        <body>
        <img id="d" src="/stream">
        <div id="s">Connected</div>
        <script>
        const s=document.getElementById('s');
        function show(t,c){s.textContent=t;s.className=c+' show';setTimeout(()=>s.classList.remove('show'),3000)}
        show('Connected','');
        // Touch relay
        const d=document.getElementById('d');
        function relay(e){
          e.preventDefault();
          const t=e.touches?e.touches[0]||e.changedTouches[0]:null;
          if(!t)return;
          const r=d.getBoundingClientRect();
          const x=(t.clientX-r.left)/r.width;
          const y=(t.clientY-r.top)/r.height;
          fetch('/input',{method:'POST',headers:{'Content-Type':'application/json'},
            body:JSON.stringify({type:'touch',event:e.type,x,y})}).catch(()=>{});
        }
        d.addEventListener('touchstart',relay,{passive:false});
        d.addEventListener('touchmove',relay,{passive:false});
        d.addEventListener('touchend',relay,{passive:false});
        // Fullscreen on double-tap
        d.addEventListener('dblclick',()=>{
          if(document.fullscreenElement)document.exitFullscreen();
          else(document.documentElement.requestFullscreen||document.documentElement.webkitRequestFullscreen).call(document.documentElement);
        });
        // Keep screen on
        if('wakeLock' in navigator)navigator.wakeLock.request('screen').catch(()=>{});
        </script>
        </body>
        </html>
        """
    }
}

// MARK: - ScreenCaptureKit Frame Handler

final class FrameHandler: NSObject, SCStreamOutput, @unchecked Sendable {
    let routeID: UUID
    let quality: Int
    weak var service: RouteService?

    init(routeID: UUID, quality: Int, service: RouteService) {
        self.routeID = routeID
        self.quality = quality
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let jpeg = bitmap.representation(using: .jpeg,
            properties: [.compressionFactor: NSNumber(value: Double(quality) / 100.0)]) else { return }

        Task { @MainActor in
            service?.pushFrame(jpeg, routeID: routeID)
        }
    }
}
