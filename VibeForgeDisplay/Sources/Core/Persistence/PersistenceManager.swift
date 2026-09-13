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
        return try decoder.decode(T.self, from: data)
    }

    /// Loads an array where each element is decoded independently, so one corrupt or
    /// schema-mismatched record is skipped instead of failing the whole collection.
    /// Returns the elements that decoded successfully and the count of ones that didn't.
    func loadArray<T: Decodable>(_ type: [T].Type, from fileName: String) throws -> (items: [T], droppedCount: Int) {
        let url = baseURL.appendingPathComponent(fileName)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let wrapped = try decoder.decode([FailableDecodable<T>].self, from: data)
        let items = wrapped.compactMap(\.value)
        return (items, wrapped.count - items.count)
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

/// Decodes a single array element, swallowing the error instead of propagating it so the
/// containing array decode doesn't fail as a whole. `value` is nil for an element that failed.
private struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(T.self)
    }
}
