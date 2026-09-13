import Foundation
import Combine

struct StreamInfo: Identifiable, Hashable {
    let key: String
    let name: String
    var id: String { key }
}

/// Talks to the Mac's token-gated HTTP server: pairs with a PIN to obtain the
/// session token, then lists streams and builds playback URLs under /t/<token>/.
enum StreamsClient {
    enum FetchResult { case ok([StreamInfo]); case unauthorized; case failed }
    /// Distinguishes "couldn't reach the Mac" (network) from "the Mac said no"
    /// (wrong/expired PIN) so the receiver can show an accurate, actionable error.
    enum PairResult { case ok(String); case rejected; case unreachable }

    /// Exchanges a 6-digit PIN (shown on the Mac) for the session token.
    static func pair(host: String, port: Int, pin: String) async -> PairResult {
        let digits = pin.filter { $0.isNumber }
        guard let url = URL(string: "http://\(host):\(port)/pair?pin=\(digits)") else { return .rejected }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            // Any HTTP reply means we reached the Mac: a non-200 (or missing
            // token) is a rejection, not a connectivity problem.
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: String],
                  let token = obj["token"] else { return .rejected }
            return .ok(token)
        } catch {
            return .unreachable
        }
    }

    static func fetch(host: String, port: Int, token: String) async -> FetchResult {
        guard let url = URL(string: "http://\(host):\(port)/t/\(token)/streams.json") else { return .failed }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 403 { return .unauthorized }
            guard code == 200 else { return .failed }
            let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: String]] ?? []
            let streams = arr.compactMap { dict -> StreamInfo? in
                guard let key = dict["key"] else { return nil }
                return StreamInfo(key: key, name: dict["name"] ?? key)
            }
            return .ok(streams)
        } catch {
            return .failed
        }
    }

    static func mediaURL(host: String, port: Int, token: String, key: String) -> URL? {
        URL(string: "http://\(host):\(port)/t/\(token)/s/\(key)/media.m3u8")
    }

    /// Per-host session token, stored in the Keychain (an access credential), so
    /// the user doesn't re-enter the PIN each launch.
    static func storedToken(host: String) -> String? {
        Keychain.get("token.\(host)")
    }
    static func storeToken(_ token: String, host: String) {
        Keychain.set(token, for: "token.\(host)")
    }
    static func clearToken(host: String) {
        Keychain.delete("token.\(host)")
    }
}

/// Discovers VibeForge Display Macs via Bonjour (_vibeforge._tcp).
final class Discovery: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    struct Server: Identifiable, Hashable {
        let id: String    // Bonjour service name (stable per host)
        let name: String
        let host: String
        let port: Int
    }

    @Published var servers: [Server] = []
    private let browser = NetServiceBrowser()
    private var resolving: Set<NetService> = []

    func start() {
        browser.delegate = self
        browser.stop()
        servers.removeAll()
        browser.searchForServices(ofType: ReceiverConfig.bonjourType, inDomain: ReceiverConfig.bonjourDomain)
    }

    func stop() {
        browser.stop()
        // NetService.delegate is unowned(unsafe): if we go away with resolves in
        // flight, a completing resolve would call into a freed delegate → crash.
        for service in resolving { service.delegate = nil; service.stop() }
        resolving.removeAll()
    }

    deinit {
        browser.stop()
        for service in resolving { service.delegate = nil; service.stop() }
    }

    // MARK: NetServiceBrowserDelegate

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        resolving.insert(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        servers.removeAll { $0.id == service.name }
        if let stale = resolving.first(where: { $0.name == service.name }) {
            stale.delegate = nil; stale.stop(); resolving.remove(stale)
        }
    }

    // MARK: NetServiceDelegate

    func netServiceDidResolveAddress(_ sender: NetService) {
        resolving.remove(sender)
        guard let rawHost = sender.hostName else { return }
        let host = rawHost.hasSuffix(".") ? String(rawHost.dropLast()) : rawHost
        let server = Server(id: sender.name, name: sender.name, host: host, port: sender.port)
        if !servers.contains(where: { $0.id == server.id }) {
            servers.append(server)
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolving.remove(sender)
    }
}
