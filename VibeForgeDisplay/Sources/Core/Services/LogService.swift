import Foundation
import SwiftUI

@MainActor
@Observable
final class LogService {
    private(set) var entries: [LogEntry] = []
    private let maxEntries = 500

    func log(_ category: LogEntry.Category, _ message: String, detail: String? = nil) {
        let entry = LogEntry(category: category, message: message, detail: detail)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
        log(.system, "Log cleared")
    }

    var latestMessage: String? {
        entries.first?.message
    }

    func entries(for category: LogEntry.Category) -> [LogEntry] {
        entries.filter { $0.category == category }
    }
}
