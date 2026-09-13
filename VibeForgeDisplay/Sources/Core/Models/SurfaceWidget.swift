import Foundation

// MARK: - Widget Data Models (persisted per-surface)
//
// Every defaulted property below needs an explicit init(from:): synthesized
// Decodable ignores property defaults and throws keyNotFound for a missing key
// (same reason Mode and RouteConfig carry one). Without it, widget data saved
// before a field existed fails to decode, and loadArray drops that whole
// surface's notes, checklists and timers.
//
// These live in extensions, not in the struct bodies: an init declared in the
// body would suppress the memberwise init that the widget views rely on
// (NotePadData(text:), TimerData(targetSeconds:isCountingUp:), and so on).

struct NotePadData: Codable, Sendable {
    var text: String = ""
}

extension NotePadData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(String.self, forKey: .text) { text = v }
    }
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

extension ChecklistData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent([ChecklistItem].self, forKey: .items) { items = v }
    }
}

struct TimerData: Codable, Sendable {
    var targetSeconds: Int = 300  // 5 minutes default
    var isCountingUp: Bool = false
}

extension TimerData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(Int.self, forKey: .targetSeconds) { targetSeconds = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .isCountingUp) { isCountingUp = v }
    }
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

extension LinkCardsData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent([LinkCard].self, forKey: .links) { links = v }
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

extension SurfaceWidgetStorage {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        surfaceID = try c.decode(UUID.self, forKey: .surfaceID)
        // A key missing from an older file keeps the property default, so one
        // absent widget category doesn't discard the whole surface's data.
        if let v = try c.decodeIfPresent([UUID: NotePadData].self, forKey: .notePads) { notePads = v }
        if let v = try c.decodeIfPresent([UUID: ChecklistData].self, forKey: .checklists) { checklists = v }
        if let v = try c.decodeIfPresent([UUID: TimerData].self, forKey: .timers) { timers = v }
        if let v = try c.decodeIfPresent([UUID: LinkCardsData].self, forKey: .linkCards) { linkCards = v }
    }
}
