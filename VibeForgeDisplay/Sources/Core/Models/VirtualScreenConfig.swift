import Foundation

struct VirtualScreenConfig: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var width: Int
    var height: Int
    var refreshRate: Double
    var hiDPI: Bool
    var autoCreateOnLaunch: Bool
    var createdAt: Date

    init(
        name: String,
        width: Int,
        height: Int,
        refreshRate: Double = 60.0,
        hiDPI: Bool = true,
        autoCreateOnLaunch: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
        self.hiDPI = hiDPI
        self.autoCreateOnLaunch = autoCreateOnLaunch
        self.createdAt = Date()
    }

    var resolutionLabel: String {
        "\(width) x \(height)"
    }

    var refreshLabel: String {
        String(format: "%.0f Hz", refreshRate)
    }

    var scaleLabel: String {
        hiDPI ? "Retina (2x)" : "Standard (1x)"
    }
}

// MARK: - Common TV/Monitor Presets

enum VirtualScreenPreset: String, CaseIterable, Identifiable {
    case hd720 = "720p HD"
    case hd1080 = "1080p Full HD"
    case qhd1440 = "1440p QHD"
    case uhd4k = "4K UHD"

    var id: String { rawValue }

    var width: Int {
        switch self {
        case .hd720: return 1280
        case .hd1080: return 1920
        case .qhd1440: return 2560
        case .uhd4k: return 3840
        }
    }

    var height: Int {
        switch self {
        case .hd720: return 720
        case .hd1080: return 1080
        case .qhd1440: return 1440
        case .uhd4k: return 2160
        }
    }

    var description: String {
        "\(rawValue) (\(width) x \(height))"
    }

    func toConfig(name: String = "") -> VirtualScreenConfig {
        VirtualScreenConfig(
            name: name.isEmpty ? rawValue : name,
            width: width,
            height: height,
            refreshRate: 60.0,
            hiDPI: self == .uhd4k || self == .qhd1440
        )
    }
}
