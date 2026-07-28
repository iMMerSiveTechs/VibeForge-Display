import Foundation

/// A Route connects a virtual display to a streaming destination.
/// Virtual Display -> Capture -> Encode -> Stream -> Device (iPad, tablet, browser)
struct RouteConfig: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var sourceDisplayConfigID: UUID?    // links to VirtualScreenConfig.id
    var protocol_: StreamProtocol
    var port: UInt16
    var quality: StreamQuality
    var maxFPS: Int
    var inputRelayEnabled: Bool         // relay touch/keyboard back to Mac
    var autoStartOnLaunch: Bool
    var createdAt: Date

    init(
        name: String = "New Route",
        sourceDisplayConfigID: UUID? = nil,
        protocol_: StreamProtocol = .mjpeg,
        port: UInt16 = 7867,
        quality: StreamQuality = .balanced,
        maxFPS: Int = 30,
        inputRelayEnabled: Bool = true,
        autoStartOnLaunch: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.sourceDisplayConfigID = sourceDisplayConfigID
        self.protocol_ = protocol_
        self.port = port
        self.quality = quality
        self.maxFPS = maxFPS
        self.inputRelayEnabled = inputRelayEnabled
        self.autoStartOnLaunch = autoStartOnLaunch
        self.createdAt = Date()
    }

    var portLabel: String { ":\(port)" }
}

// MARK: - Stream Protocol

enum StreamProtocol: String, Codable, Sendable, CaseIterable, Identifiable {
    case mjpeg = "MJPEG"
    case websocket = "WebSocket"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .mjpeg: return "MJPEG — universal, works in any browser <img> tag"
        case .websocket: return "WebSocket — lower latency binary frames"
        }
    }

    var icon: String {
        switch self {
        case .mjpeg: return "photo.stack"
        case .websocket: return "bolt.horizontal"
        }
    }
}

// MARK: - Stream Quality

enum StreamQuality: String, Codable, Sendable, CaseIterable, Identifiable {
    case low = "Low"
    case balanced = "Balanced"
    case high = "High"
    case lossless = "Lossless"

    var id: String { rawValue }

    var jpegQuality: Int {
        switch self {
        case .low: return 40
        case .balanced: return 70
        case .high: return 85
        case .lossless: return 95
        }
    }

    var description: String {
        switch self {
        case .low: return "Low bandwidth, faster on slow networks"
        case .balanced: return "Good quality with reasonable bandwidth"
        case .high: return "Sharp image, higher bandwidth"
        case .lossless: return "Near-lossless, highest bandwidth"
        }
    }
}

// MARK: - Connected Client

struct StreamClient: Identifiable, Sendable {
    let id: UUID
    let connectedAt: Date
    var deviceName: String
    var deviceWidth: Int
    var deviceHeight: Int
    var devicePixelRatio: Double
    var userAgent: String

    init(deviceName: String = "Unknown", deviceWidth: Int = 0, deviceHeight: Int = 0, devicePixelRatio: Double = 1.0, userAgent: String = "") {
        self.id = UUID()
        self.connectedAt = Date()
        self.deviceName = deviceName
        self.deviceWidth = deviceWidth
        self.deviceHeight = deviceHeight
        self.devicePixelRatio = devicePixelRatio
        self.userAgent = userAgent
    }

    var deviceLabel: String {
        if !deviceName.isEmpty && deviceName != "Unknown" { return deviceName }
        if deviceWidth > 0 { return "\(deviceWidth)x\(deviceHeight)" }
        return "Unknown Device"
    }

    var uptimeLabel: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: connectedAt, relativeTo: Date())
    }
}
