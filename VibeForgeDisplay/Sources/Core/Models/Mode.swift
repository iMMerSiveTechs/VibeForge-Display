import Foundation

struct Mode: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    // Defaults for fields an older saved mode may lack. The custom init(from:)
    // below applies them; synthesized Decodable ignores property defaults and
    // would throw keyNotFound instead.
    var notes: String = ""
    var screens: [ScreenInfo]
    var preferredMainDisplayID: UInt32?
    var surfacePreferences: [SurfaceConfig] = []

    init(
        name: String,
        notes: String = "",
        screens: [ScreenInfo],
        preferredMainDisplayID: UInt32? = nil,
        surfacePreferences: [SurfaceConfig] = []
    ) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.notes = notes
        self.screens = screens
        self.preferredMainDisplayID = preferredMainDisplayID
        self.surfacePreferences = surfacePreferences
    }

    var screenSummary: String {
        if screens.isEmpty { return "No screens" }
        let names = screens.map(\.name)
        return names.joined(separator: ", ")
    }

    var timeLabel: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }
}

extension Mode {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        screens = try c.decode([ScreenInfo].self, forKey: .screens)
        preferredMainDisplayID = try c.decodeIfPresent(UInt32.self, forKey: .preferredMainDisplayID)
        // A key missing from an older file keeps the property default.
        if let v = try c.decodeIfPresent(String.self, forKey: .notes) { notes = v }
        if let v = try c.decodeIfPresent([SurfaceConfig].self, forKey: .surfacePreferences) { surfacePreferences = v }
    }
}
