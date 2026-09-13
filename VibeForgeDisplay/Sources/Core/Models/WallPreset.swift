import Foundation

/// A one-click multi-TV layout: a snapshot of virtual screens and the routes
/// that stream them. Applying a preset recreates the whole setup — screens
/// activated, routes restored, and any auto-start routes begun.
struct WallPreset: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var createdAt: Date
    var virtualScreens: [VirtualScreenConfig]
    /// Surfaces referenced by any `.surface` route, snapshotted so a preset can
    /// recreate a surface-sourced route even if the surface was later deleted.
    var surfaces: [SurfaceConfig]
    var routes: [RouteConfig]

    init(name: String,
         virtualScreens: [VirtualScreenConfig],
         surfaces: [SurfaceConfig],
         routes: [RouteConfig]) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.virtualScreens = virtualScreens
        self.surfaces = surfaces
        self.routes = routes
    }

    // Tolerate presets saved before `surfaces` existed.
    enum CodingKeys: String, CodingKey { case id, name, createdAt, virtualScreens, surfaces, routes }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        virtualScreens = try c.decodeIfPresent([VirtualScreenConfig].self, forKey: .virtualScreens) ?? []
        surfaces = try c.decodeIfPresent([SurfaceConfig].self, forKey: .surfaces) ?? []
        routes = try c.decodeIfPresent([RouteConfig].self, forKey: .routes) ?? []
    }

    var summary: String {
        let s = virtualScreens.count + surfaces.count
        let r = routes.count
        return "\(s) source\(s == 1 ? "" : "s") · \(r) route\(r == 1 ? "" : "s")"
    }
}
