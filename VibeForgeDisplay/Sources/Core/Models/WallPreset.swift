import Foundation

/// A one-click multi-TV layout: a snapshot of virtual screens and the routes
/// that stream them. Applying a preset recreates the whole setup — screens
/// activated, routes restored, and any auto-start routes begun.
struct WallPreset: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var createdAt: Date
    var virtualScreens: [VirtualScreenConfig]
    var routes: [RouteConfig]

    init(name: String, virtualScreens: [VirtualScreenConfig], routes: [RouteConfig]) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.virtualScreens = virtualScreens
        self.routes = routes
    }

    var summary: String {
        let s = virtualScreens.count
        let r = routes.count
        return "\(s) screen\(s == 1 ? "" : "s") · \(r) route\(r == 1 ? "" : "s")"
    }
}
