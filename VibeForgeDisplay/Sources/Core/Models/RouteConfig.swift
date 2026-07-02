import Foundation

/// A Route maps a source (a virtual screen) to a live LL-HLS stream that
/// receivers (Apple TV app or a browser) can play over the local network.
struct RouteConfig: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    /// The VirtualScreenConfig.id this route captures and streams.
    var sourceVirtualScreenID: UUID
    var quality: StreamQuality
    /// Stable, URL-safe key used in stream paths (e.g. /s/<streamKey>/media.m3u8).
    var streamKey: String
    var autoStart: Bool
    var createdAt: Date

    init(
        name: String,
        sourceVirtualScreenID: UUID,
        quality: StreamQuality = .balanced,
        autoStart: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.sourceVirtualScreenID = sourceVirtualScreenID
        self.quality = quality
        self.streamKey = RouteConfig.makeStreamKey()
        self.autoStart = autoStart
        self.createdAt = Date()
    }

    /// Short random key so stream URLs are stable and collision-free.
    private static func makeStreamKey() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        var key = ""
        var seed = UUID().uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        for _ in 0..<8 {
            seed = (seed &* 1103515245 &+ 12345) & 0x7fffffff
            key.append(chars[seed % chars.count])
        }
        return key
    }
}

enum StreamQuality: String, Codable, Sendable, CaseIterable, Identifiable {
    case low = "Low"
    case balanced = "Balanced"
    case high = "High"

    var id: String { rawValue }

    /// Target encode bitrate in bits/second.
    var bitrate: Int {
        switch self {
        case .low: return 2_500_000
        case .balanced: return 6_000_000
        case .high: return 12_000_000
        }
    }

    var frameRate: Int {
        switch self {
        case .low: return 24
        case .balanced: return 30
        case .high: return 30
        }
    }

    /// Scale factor applied to the source resolution before encoding.
    var scale: Double {
        switch self {
        case .low: return 0.5
        case .balanced: return 0.75
        case .high: return 1.0
        }
    }

    var detail: String {
        "\(bitrate / 1_000_000) Mbps · \(frameRate) fps"
    }
}
