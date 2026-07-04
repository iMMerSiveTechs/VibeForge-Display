import Foundation
import Observation
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

    /// Only streams that are actually playable (init + >=1 segment). Advertising a
    /// stream during its ~1-2s warm-up makes a receiver 404 on the playlist and
    /// (for AVPlayer) fail the item permanently — it looked "ended" for a stream
    /// about to go live.
    func streamList() -> [(key: String, name: String)] {
        lock.lock(); defer { lock.unlock() }
        return streams
            .filter { $0.value.initData != nil && !$0.value.segments.isEmpty }
            .map { ($0.key, $0.value.name) }
            .sorted { $0.name < $1.name }
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
        // Serve only once we have the init segment AND at least one media segment —
        // an init-only playlist makes players raise spurious "empty playlist" errors.
        guard let s = streams[key], s.initData != nil, !s.segments.isEmpty else { return nil }
        // TARGETDURATION MUST be constant for the life of the stream (RFC 8216) —
        // an oscillating value breaks AVPlayer's live-edge/reload math. Pin it; the
        // keep-alive keeps real segments under this bound, and we clamp EXTINF to it
        // defensively so a rare long segment can't exceed the declared target.
        let target = max(2, Int(ceil(VFConstants.Streaming.segmentDuration)))
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-TARGETDURATION:\(target)",
            "#EXT-X-MEDIA-SEQUENCE:\(s.mediaSequence)",
            "#EXT-X-MAP:URI=\"init.mp4\"",
        ]
        for seg in s.segments {
            let dur = min(seg.duration, Double(target))
            lines.append(String(format: "#EXTINF:%.3f,", dur))
            lines.append("seg/\(seg.index).m4s")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - HLS / HTTP server

/// One-shot flag so a per-connection slot is released exactly once even though a
/// connection can report both .failed and (after cancel) .cancelled.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func trigger() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}

/// Lock-guarded concurrent-connection counter, safe to touch from the
/// `nonisolated` connection handlers (which can't reach main-actor state).
final class ConnectionLimiter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let max: Int
    init(max: Int) { self.max = max }
    func tryAcquire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if count >= max { return false }
        count += 1; return true
    }
    func release() {
        lock.lock(); if count > 0 { count -= 1 }; lock.unlock()
    }
}

@MainActor
@Observable
final class HLSServer {
    private(set) var isRunning = false
    let store = HLSSegmentStore()
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "vibeforge.hls.http")
    private let logService: LogService
    private let limiter = ConnectionLimiter(max: VFConstants.Streaming.maxConnections)

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

    private var readinessWaiters: [CheckedContinuation<Bool, Never>] = []

    func start() {
        // Guard on the listener existing, not on isRunning (which only flips to
        // true asynchronously in .ready) — otherwise two rapid start() calls
        // create two NWListeners and leak/split the bind.
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                resolveReadiness(false); return
            }
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
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.logService.log(.system, "Stream server started", detail: "port \(self.port)")
                        self.resolveReadiness(true)
                    case .failed(let err):
                        self.isRunning = false
                        self.listener?.cancel()
                        self.listener = nil
                        self.logService.log(.error, "Stream server failed", detail: "\(err)")
                        self.resolveReadiness(false)
                    default: break
                    }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            listener = nil
            logService.log(.error, "Could not start stream server", detail: error.localizedDescription)
            resolveReadiness(false)
        }
    }

    /// Starts the server if needed and resolves once it's actually listening
    /// (.ready) or has failed to bind. Returns whether it is serving.
    /// A hard deadline guarantees resolution even if NWListener parks in
    /// `.waiting` — which is exactly what a denied macOS Local Network
    /// permission does (it never proceeds to `.ready` or `.failed`), and would
    /// otherwise suspend the caller's Task forever and leak the continuation.
    func startAndWait() async -> Bool {
        if isRunning { return true }
        return await withCheckedContinuation { continuation in
            readinessWaiters.append(continuation)
            start()
            let deadline = DispatchTime.now() + 6
            queue.asyncAfter(deadline: deadline) { [weak self] in
                Task { @MainActor in
                    guard let self, !self.isRunning else { return }
                    self.logService.log(.error, "Stream server didn't become ready",
                                        detail: "check Local Network permission")
                    self.resolveReadiness(false)
                }
            }
        }
    }

    private func resolveReadiness(_ success: Bool) {
        let waiters = readinessWaiters
        readinessWaiters.removeAll()
        for w in waiters { w.resume(returning: success) }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        resolveReadiness(false)
        logService.log(.system, "Stream server stopped")
    }

    // MARK: - Connection handling (minimal HTTP/1.1, one request per connection)
    // These run on the network `queue`, not the main actor. They only touch
    // Sendable `let`s (store, security, queue), so they are `nonisolated`.

    nonisolated private func handle(_ conn: NWConnection) {
        // Cap concurrent connections (FD-exhaustion / slow-loris defense).
        guard limiter.tryAcquire() else { conn.cancel(); return }
        let releaseOnce = OnceFlag()   // .failed then .cancelled must not double-release
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                if releaseOnce.trigger() { self?.limiter.release() }
            default: break
            }
        }
        conn.start(queue: queue)
        // Watchdog: bound every connection's lifetime so a peer that connects and
        // never sends a complete request can't pin a file descriptor forever.
        queue.asyncAfter(deadline: .now() + VFConstants.Streaming.connectionTimeout) {
            conn.cancel()
        }
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

    /// Returns the Mac's private LAN IPv4 address (RFC1918) for receiver URLs,
    /// or nil if there's no usable LAN address. Skips loopback, VPN/tunnel, and
    /// bridge interfaces so we never hand a TV an unreachable (e.g. Tailscale) IP.
    nonisolated static func localIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        let excludedPrefixes = ["utun", "ipsec", "ppp", "bridge", "awdl", "llw", "gif", "stf"]
        var candidates: [(name: String, ip: String)] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let interface = p.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            if excludedPrefixes.contains(where: { name.hasPrefix($0) }) { continue }
            var addr = interface.ifa_addr.pointee
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(&addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                              &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if isPrivateIPv4(ip) { candidates.append((name, ip)) }
        }
        // Prefer Wi-Fi/Ethernet (en*), else the first private candidate.
        if let en = candidates.first(where: { $0.name.hasPrefix("en") }) { return en.ip }
        return candidates.first?.ip
    }

    /// RFC1918 / link-local check: 10/8, 172.16–31/12, 192.168/16, 169.254/16.
    nonisolated private static func isPrivateIPv4(_ ip: String) -> Bool {
        let o = ip.split(separator: ".").compactMap { Int($0) }
        guard o.count == 4 else { return false }
        if o[0] == 10 { return true }
        if o[0] == 172, (16...31).contains(o[1]) { return true }
        if o[0] == 192, o[1] == 168 { return true }
        if o[0] == 169, o[1] == 254 { return true }
        return false
    }
}
