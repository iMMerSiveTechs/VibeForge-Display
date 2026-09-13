import Foundation

// MARK: - Widget Data Models (persisted per-surface)

struct NotePadData: Codable, Sendable {
    var text: String = ""
}

struct ChecklistData: Codable, Sendable {
    var items: [ChecklistItem] = []

    struct ChecklistItem: Identifiable, Codable, Sendable {
        let id: UUID
        var text: String
        var isChecked: Bool

        init(text: String, isChecked: Bool = false) {
            self.id = UUID()
            self.text = text
            self.isChecked = isChecked
        }
    }
}

struct TimerData: Codable, Sendable {
    var targetSeconds: Int = 300  // 5 minutes default
    var isCountingUp: Bool = false
}

struct LinkCardsData: Codable, Sendable {
    var links: [LinkCard] = []

    struct LinkCard: Identifiable, Codable, Sendable {
        let id: UUID
        var title: String
        var urlString: String

        init(title: String, urlString: String) {
            self.id = UUID()
            self.title = title
            self.urlString = urlString
        }

        var url: URL? { URL(string: urlString) }
    }
}

// MARK: - Combined widget storage

struct SurfaceWidgetStorage: Codable, Sendable {
    var surfaceID: UUID
    var notePads: [UUID: NotePadData] = [:]
    var checklists: [UUID: ChecklistData] = [:]
    var timers: [UUID: TimerData] = [:]
    var linkCards: [UUID: LinkCardsData] = [:]

    init(surfaceID: UUID) {
        self.surfaceID = surfaceID
    }
}
