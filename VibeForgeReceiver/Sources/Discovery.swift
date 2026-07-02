import Foundation
import Combine

struct StreamInfo: Identifiable, Hashable {
    let key: String
    let name: String
    var id: String { key }
}

/// Fetches the list of live streams and builds playback URLs from the Mac's HTTP server.
enum StreamsClient {
    static func fetch(host: String, port: Int) async -> [StreamInfo] {
        guard let url = URL(string: "http://\(host):\(port)/streams.json") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: String]] ?? []
            return arr.compactMap { dict in
                guard let key = dict["key"] else { return nil }
                return StreamInfo(key: key, name: dict["name"] ?? key)
            }
        } catch {
            return []
        }
    }

    static func mediaURL(host: String, port: Int, key: String) -> URL? {
        URL(string: "http://\(host):\(port)/s/\(key)/media.m3u8")
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
    }

    // MARK: NetServiceBrowserDelegate

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        resolving.insert(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        servers.removeAll { $0.id == service.name }
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
