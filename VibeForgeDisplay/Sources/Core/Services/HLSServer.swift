import Foundation
import Network
import Darwin

// MARK: - Segment store (thread-safe)

/// Holds the in-memory LL-HLS artifacts for each active stream: one init
/// segment plus a sliding window of media segments, and generates the playlist.
/// Accessed from the encoder delegate queue (writes) and the HTTP queue (reads),
/// so all access is guarded by a lock.
final class HLSSegmentStore: @unchecked Sendable {
    struct Segment { let index: Int; let data: Data; let duration: Double }
    private struct Stream {
        var name: String
        var initData: Data?
        var segments: [Segment] = []
        var nextIndex = 0
        var mediaSequence = 0
    }

    private var streams: [String: Stream] = [:]
    private let lock = NSLock()
    private let window = VFConstants.Streaming.segmentWindow

    func register(key: String, name: String) {
        lock.lock(); defer { lock.unlock() }
        if streams[key] == nil { streams[key] = Stream(name: name) }
        else { streams[key]?.name = name }
    }

    func unregister(key: String) {
        lock.lock(); defer { lock.unlock() }
        streams[key] = nil
    }

    func setInit(key: String, data: Data) {
        lock.lock(); defer { lock.unlock() }
        streams[key]?.initData = data
    }

    func appendSegment(key: String, data: Data, duration: Double) {
        lock.lock(); defer { lock.unlock() }
        guard var s = streams[key] else { return }
        s.segments.append(Segment(index: s.nextIndex, data: data, duration: duration))
        s.nextIndex += 1
        if s.segments.count > window {
            let drop = s.segments.count - window
            s.segments.removeFirst(drop)
            s.mediaSequence += drop
        }
        streams[key] = s
    }

    func streamList() -> [(key: String, name: String)] {
        lock.lock(); defer { lock.unlock() }
        return streams.map { ($0.key, $0.value.name) }.sorted { $0.name < $1.name }
    }

    func initData(key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return streams[key]?.initData
    }

    func segmentData(key: String, index: Int) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return streams[key]?.segments.first(where: { $0.index == index })?.data
    }

    /// Builds a live media playlist referencing the current window of segments.
    func mediaPlaylist(key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let s = streams[key], s.initData != nil else { return nil }
        let target = Int(ceil(VFConstants.Streaming.segmentDuration)) + 1
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-TARGETDURATION:\(target)",
            "#EXT-X-MEDIA-SEQUENCE:\(s.mediaSequence)",
            "#EXT-X-MAP:URI=\"init.mp4\"",
        ]
        for seg in s.segments {
            lines.append(String(format: "#EXTINF:%.3f,", seg.duration))
            lines.append("seg/\(seg.index).m4s")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - HLS / HTTP server

@MainActor
@Observable
final class HLSServer {
    private(set) var isRunning = false
    let store = HLSSegmentStore()
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "vibeforge.hls.http")
    private let logService: LogService

    let security = SessionSecurity()

    init(logService: LogService) {
        self.logService = logService
    }

    var port: UInt16 { VFConstants.Streaming.httpPort }

    /// URL a receiver on the LAN should open. Carries the session token so the
    /// bundled web receiver is authorized; keep this out of logs.
    func receiverURL(streamKey: String? = nil) -> String {
        let host = HLSServer.localIPAddress() ?? "localhost"
        let base = "http://\(host):\(port)/?t=\(security.sessionToken)"
        if let key = streamKey { return "\(base)&s=\(key)" }
        return base
    }

    /// Same URL with the token redacted — safe to log or show in diagnostics.
    func redactedReceiverURL(streamKey: String? = nil) -> String {
        let host = HLSServer.localIPAddress() ?? "localhost"
        let base = "http://\(host):\(port)/?t=…"
        if let key = streamKey { return "\(base)&s=\(key)" }
        return base
    }

    // MARK: Pairing controls (for the UI)

    func beginPairing() -> String { security.beginPairing() }
    func cancelPairing() { security.cancelPairing() }
    func pairingSnapshot() -> SessionSecurity.PairingState { security.snapshot() }

    func start() {
        guard !isRunning else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            let listener = try NWListener(using: params, on: nwPort)
            listener.service = NWListener.Service(
                name: VFConstants.appName,
                type: VFConstants.Streaming.bonjourServiceType
            )
            listener.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.logService.log(.system, "Stream server started",
                                             detail: "port \(self?.port ?? 0)")
                    case .failed(let err):
                        self?.isRunning = false
                        self?.logService.log(.error, "Stream server failed", detail: "\(err)")
                    default: break
                    }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            logService.log(.error, "Could not start stream server", detail: error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        logService.log(.system, "Stream server stopped")
    }

    // MARK: - Connection handling (minimal HTTP/1.1, one request per connection)
    // These run on the network `queue`, not the main actor. They only touch
    // Sendable `let`s (store, security, queue), so they are `nonisolated`.

    nonisolated private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receiveRequest(conn, buffer: Data())
    }

    nonisolated private func receiveRequest(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buf.subdata(in: buf.startIndex..<range.lowerBound)
                let header = String(decoding: headerData, as: UTF8.self)
                self.route(header: header, conn: conn)
                return
            }
            if error != nil || isComplete { conn.cancel(); return }
            if buf.count < 64 * 1024 { self.receiveRequest(conn, buffer: buf) }
            else { conn.cancel() }
        }
    }

    private static func requestLine(_ header: String) -> (method: String, path: String) {
        guard let firstLine = header.split(separator: "\r\n").first else { return ("GET", "/") }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return ("GET", "/") }
        return (String(parts[0]), String(parts[1]))
    }

    private static func headerValue(_ name: String, in header: String) -> String? {
        let lower = name.lowercased() + ":"
        for line in header.split(separator: "\r\n") {
            if line.lowercased().hasPrefix(lower) {
                return line.dropFirst(lower.count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Allow requests addressed to an IP literal, localhost, or an mDNS `.local`
    /// name (used by the Apple TV via Bonjour). A DNS-rebinding attack reaches us
    /// through an attacker-controlled *public domain* Host — which is neither an IP
    /// literal nor `.local` — so we reject those.
    private static func isAllowedHost(_ hostHeader: String?) -> Bool {
        guard let raw = hostHeader, !raw.isEmpty else { return false }
        // Strip a trailing :port (we don't serve on bracketed IPv6 literals).
        let host = (raw.split(separator: ":").first.map(String.init) ?? raw).lowercased()
        if host == "localhost" { return true }
        if host.hasSuffix(".local") { return true }
        // IPv4 literal: 4 numeric octets.
        let octets = host.split(separator: ".")
        if octets.count == 4, octets.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) {
            return true
        }
        return false
    }

    private static func queryParam(_ name: String, in path: String) -> String? {
        guard let q = path.split(separator: "?", maxSplits: 1).dropFirst().first else { return nil }
        for pair in q.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.first.map(String.init) == name {
                let val = kv.count > 1 ? String(kv[1]) : ""
                return val.removingPercentEncoding ?? val
            }
        }
        return nil
    }

    nonisolated private func route(header: String, conn: NWConnection) {
        // Defense against DNS-rebinding: require an IP/localhost Host.
        guard HLSServer.isAllowedHost(HLSServer.headerValue("Host", in: header)) else {
            sendStatus(conn, 403); return
        }

        let (_, fullPath) = HLSServer.requestLine(header)
        let pathOnly = String(fullPath.split(separator: "?").first ?? "/")
        let comps = pathOnly.split(separator: "/").map(String.init)

        // Open endpoints (no screen data): the receiver shell and pairing.
        if pathOnly == "/" || pathOnly == "/index.html" || pathOnly == "/player" {
            send(conn, body: Data(WebReceiver.html.utf8), contentType: "text/html; charset=utf-8")
            return
        }
        if pathOnly == "/pair" {
            handlePair(fullPath: fullPath, conn: conn)
            return
        }

        // Everything below is token-gated: /t/<token>/...
        guard comps.count >= 2, comps[0] == "t", security.isValid(token: comps[1]) else {
            sendStatus(conn, 403); return
        }
        let rest = Array(comps.dropFirst(2))   // components after /t/<token>

        if rest == ["streams.json"] {
            let list = store.streamList().map { ["key": $0.key, "name": $0.name] }
            let data = (try? JSONSerialization.data(withJSONObject: list)) ?? Data("[]".utf8)
            send(conn, body: data, contentType: "application/json")
            return
        }
        // s/<key>/media.m3u8 | s/<key>/init.mp4 | s/<key>/seg/<n>.m4s
        if rest.count >= 3, rest[0] == "s" {
            let key = rest[1]
            let tail = rest[2]
            if tail == "media.m3u8" {
                if let pl = store.mediaPlaylist(key: key) {
                    send(conn, body: Data(pl.utf8), contentType: "application/vnd.apple.mpegurl")
                } else { sendStatus(conn, 404) }
                return
            }
            if tail == "init.mp4" {
                if let d = store.initData(key: key) {
                    send(conn, body: d, contentType: "video/mp4")
                } else { sendStatus(conn, 404) }
                return
            }
            if tail == "seg", rest.count >= 4 {
                let idxStr = rest[3].replacingOccurrences(of: ".m4s", with: "")
                if let idx = Int(idxStr), let d = store.segmentData(key: key, index: idx) {
                    send(conn, body: d, contentType: "video/iso.segment")
                } else { sendStatus(conn, 404) }
                return
            }
        }
        sendStatus(conn, 404)
    }

    /// POST/GET /pair?pin=NNNNNN — exchanges a valid PIN for the session token.
    nonisolated private func handlePair(fullPath: String, conn: NWConnection) {
        guard let pin = HLSServer.queryParam("pin", in: fullPath),
              let token = security.redeem(pin: pin) else {
            sendStatus(conn, 403); return
        }
        let data = (try? JSONSerialization.data(withJSONObject: ["token": token])) ?? Data("{}".utf8)
        send(conn, body: data, contentType: "application/json")
    }

    // MARK: - HTTP responses

    nonisolated private func send(_ conn: NWConnection, body: Data, contentType: String) {
        // No CORS header: the bundled web receiver is same-origin, and a wildcard
        // would let any website read the (unauthenticated-to-the-browser) screen
        // stream cross-origin. X-Content-Type-Options hardens sniffing.
        var head = "HTTP/1.1 200 OK\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "X-Content-Type-Options: nosniff\r\n"
        head += "Cache-Control: no-cache\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    nonisolated private func sendStatus(_ conn: NWConnection, _ code: Int) {
        let reason = code == 404 ? "Not Found" : "Error"
        let head = "HTTP/1.1 \(code) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8), completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: - LAN IP discovery

    /// Returns the primary non-loopback IPv4 address (prefers en0/en1) for building receiver URLs.
    nonisolated static func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var candidates: [(name: String, ip: String)] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let interface = p.pointee
            let family = interface.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                var addr = interface.ifa_addr.pointee
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(&addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    if ip != "127.0.0.1" { candidates.append((name, ip)) }
                }
            }
            ptr = interface.ifa_next
        }
        // Prefer common Wi-Fi/Ethernet interfaces.
        for pref in ["en0", "en1", "en2"] {
            if let match = candidates.first(where: { $0.name == pref }) { address = match.ip; break }
        }
        if address == nil { address = candidates.first?.ip }
        return address
    }
}
