import Foundation

/// What a Route captures and streams.
/// - `virtualScreen`: an extended desktop created via CGVirtualDisplay (private API).
///   True "extra screen" behavior, but depends on ScreenCaptureKit being able to
///   capture a headless virtual display.
/// - `surface`: a VibeForge Surface window (public API, always capturable, and
///   App-Store-safe). The reliable fallback / alternative source.
enum RouteSourceKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case virtualScreen = "Virtual Screen"
    case surface = "Surface"
    var id: String { rawValue }
    var icon: String { self == .virtualScreen ? "display" : "rectangle.on.rectangle.angled" }
}

/// A Route maps a source to a live LL-HLS stream that receivers (Apple TV app or
/// a browser) can play over the local network.
struct RouteConfig: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var sourceKind: RouteSourceKind
    /// Id of the source: a VirtualScreenConfig.id or a SurfaceConfig.id per `sourceKind`.
    var sourceID: UUID
    var quality: StreamQuality
    /// Stable, URL-safe key used in stream paths (e.g. /s/<streamKey>/media.m3u8).
    var streamKey: String
    var autoStart: Bool
    var createdAt: Date

    init(
        name: String,
        sourceKind: RouteSourceKind = .virtualScreen,
        sourceID: UUID,
        quality: StreamQuality = .balanced,
        autoStart: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.sourceKind = sourceKind
        self.sourceID = sourceID
        self.quality = quality
        self.streamKey = RouteConfig.makeStreamKey()
        self.autoStart = autoStart
        self.createdAt = Date()
    }

    /// Stable, unguessable stream key from a CSPRNG (~62 bits).
    /// Note: the stream key is an identifier, NOT the access-control credential —
    /// the server gates all data endpoints behind the session token (SessionSecurity).
    private static func makeStreamKey() -> String {
        SecureRandom.token(byteCount: 12)
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
