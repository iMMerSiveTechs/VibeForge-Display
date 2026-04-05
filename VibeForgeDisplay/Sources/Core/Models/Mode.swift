import Foundation

struct Mode: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var notes: String
    var screens: [ScreenInfo]
    var preferredMainDisplayID: UInt32?
    var surfacePreferences: [SurfaceConfig]

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
