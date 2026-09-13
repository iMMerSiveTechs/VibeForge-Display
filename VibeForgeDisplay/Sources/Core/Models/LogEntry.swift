import Foundation

struct LogEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let category: Category
    let message: String
    let detail: String?

    enum Category: String, Codable, Sendable, CaseIterable {
        case screen = "Screen"
        case mode = "Mode"
        case surface = "Surface"
        case system = "System"
        case error = "Error"
    }

    init(category: Category, message: String, detail: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.category = category
        self.message = message
        self.detail = detail
    }
}
