import Foundation

@MainActor
final class PersistenceManager {
    private let baseURL: URL

    init(baseURL: URL = VFConstants.appSupportURL) {
        self.baseURL = baseURL
        ensureDirectoryExists()
    }

    private func ensureDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: baseURL.path) {
            try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
        }
    }

    func save<T: Encodable>(_ value: T, to fileName: String) throws {
        let url = baseURL.appendingPathComponent(fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    func load<T: Decodable>(_ type: T.Type, from fileName: String) throws -> T {
        let url = baseURL.appendingPathComponent(fileName)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Preserve an unreadable file before the caller (which falls back to an
            // empty collection) can overwrite it on the next save and lose data.
            backupCorruptFile(at: url)
            throw error
        }
    }

    /// Loads an array element by element, so one unreadable record is skipped instead
    /// of failing the whole collection. `load` decodes an array atomically: a single
    /// bad record (schema drift, an unknown enum value, a partial write) throws, and
    /// every caller falls back to an empty list — so the user's entire set of Modes /
    /// Surfaces / Routes disappears because of one entry. Returns what decoded plus a
    /// count of what didn't, so the caller can surface it.
    func loadArray<T: Decodable>(_ type: [T].Type, from fileName: String) throws -> (items: [T], droppedCount: Int) {
        let url = baseURL.appendingPathComponent(fileName)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let wrapped: [FailableDecodable<T>]
        do {
            wrapped = try decoder.decode([FailableDecodable<T>].self, from: data)
        } catch {
            // Not a readable array at all — preserve it, same as `load` does.
            backupCorruptFile(at: url)
            throw error
        }

        let items = wrapped.compactMap(\.value)
        let dropped = wrapped.count - items.count
        if dropped > 0 {
            // The file is still usable, so copy rather than move: the caller's next
            // save rewrites it without the skipped records, and this keeps them.
            copyAside(url, suffix: "partial")
        }
        return (items, dropped)
    }

    private func backupCorruptFile(at url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.appendingPathExtension("corrupt-\(stamp)")
        try? FileManager.default.moveItem(at: url, to: backup)
    }

    private func copyAside(_ url: URL, suffix: String) {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.appendingPathExtension("\(suffix)-\(stamp)")
        try? FileManager.default.copyItem(at: url, to: backup)
    }

    func exists(_ fileName: String) -> Bool {
        let url = baseURL.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path)
    }

    func delete(_ fileName: String) throws {
        let url = baseURL.appendingPathComponent(fileName)
        try FileManager.default.removeItem(at: url)
    }
}

/// Decodes one array element, absorbing the error instead of letting it fail the
/// enclosing array decode. `value` is nil for an element that couldn't be read.
private struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(T.self)
    }
}
