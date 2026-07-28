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

    func exists(_ fileName: String) -> Bool {
        let url = baseURL.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path)
    }

    func delete(_ fileName: String) throws {
        let url = baseURL.appendingPathComponent(fileName)
        try FileManager.default.removeItem(at: url)
    }
}
