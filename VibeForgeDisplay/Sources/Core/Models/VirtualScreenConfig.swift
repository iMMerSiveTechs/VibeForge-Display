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

// MARK: - Preset Categories

enum PresetCategory: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case iPad = "iPad"
    case tablet = "Tablet"
    case ultrawide = "Ultrawide"
    case headless = "Headless"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .standard: return "display"
        case .iPad: return "ipad"
        case .tablet: return "tablet.landscape"
        case .ultrawide: return "rectangle.split.3x1"
        case .headless: return "server.rack"
        }
    }
}

// MARK: - Presets (Standard + iPad + Tablet + Ultrawide + Headless)

enum VirtualScreenPreset: String, CaseIterable, Identifiable {
    // Standard monitors
    case hd720 = "720p HD"
    case hd1080 = "1080p Full HD"
    case qhd1440 = "1440p QHD"
    case uhd4k = "4K UHD"

    // iPad models
    case iPadPro13 = "iPad Pro 13\""
    case iPadPro11 = "iPad Pro 11\""
    case iPadAir = "iPad Air"
    case iPad10 = "iPad 10th Gen"
    case iPadMini = "iPad Mini"

    // Android / other tablets
    case galaxyTabS9 = "Galaxy Tab S9"
    case pixelTablet = "Pixel Tablet"

    // Ultrawide
    case ultrawide34 = "34\" Ultrawide QHD"
    case ultrawide49 = "49\" Super Ultrawide"

    // Headless / remote
    case headless720 = "Headless 720p"
    case headless1080 = "Headless 1080p"

    var id: String { rawValue }

    var category: PresetCategory {
        switch self {
        case .hd720, .hd1080, .qhd1440, .uhd4k: return .standard
        case .iPadPro13, .iPadPro11, .iPadAir, .iPad10, .iPadMini: return .iPad
        case .galaxyTabS9, .pixelTablet: return .tablet
        case .ultrawide34, .ultrawide49: return .ultrawide
        case .headless720, .headless1080: return .headless
        }
    }

    var width: Int {
        switch self {
        case .hd720: return 1280
        case .hd1080: return 1920
        case .qhd1440: return 2560
        case .uhd4k: return 3840
        case .iPadPro13: return 2752
        case .iPadPro11: return 2388
        case .iPadAir, .iPad10: return 2360
        case .iPadMini: return 2266
        case .galaxyTabS9, .pixelTablet: return 2560
        case .ultrawide34: return 3440
        case .ultrawide49: return 5120
        case .headless720: return 1280
        case .headless1080: return 1920
        }
    }

    var height: Int {
        switch self {
        case .hd720: return 720
        case .hd1080: return 1080
        case .qhd1440: return 1440
        case .uhd4k: return 2160
        case .iPadPro13: return 2064
        case .iPadPro11: return 1668
        case .iPadAir, .iPad10: return 1640
        case .iPadMini: return 1488
        case .galaxyTabS9, .pixelTablet: return 1600
        case .ultrawide34: return 1440
        case .ultrawide49: return 1440
        case .headless720: return 720
        case .headless1080: return 1080
        }
    }

    var defaultRefreshRate: Double {
        switch self {
        case .iPadPro13, .iPadPro11, .galaxyTabS9: return 120.0
        case .headless720, .headless1080: return 30.0
        default: return 60.0
        }
    }

    var defaultHiDPI: Bool {
        switch self {
        case .hd720, .headless720: return false
        default: return true
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
            refreshRate: defaultRefreshRate,
            hiDPI: defaultHiDPI
        )
    }

    static func presets(for category: PresetCategory) -> [VirtualScreenPreset] {
        allCases.filter { $0.category == category }
    }
}

// MARK: - Quick Setup Layouts

enum QuickSetupLayout: String, CaseIterable, Identifiable {
    case dualTV = "Dual TV"
    case tripleMonitor = "Triple Monitor"
    case deskAndIPad = "Desk + iPad"
    case tvAndIPad = "TV + iPad"
    case ultrawideAndSide = "Ultrawide + Side"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dualTV: return "tv.and.mediabox"
        case .tripleMonitor: return "display.2"
        case .deskAndIPad: return "desktopcomputer.and.arrow.down"
        case .tvAndIPad: return "play.display"
        case .ultrawideAndSide: return "rectangle.split.3x1"
        }
    }

    var description: String {
        switch self {
        case .dualTV: return "Two 1080p screens for dual-TV setup"
        case .tripleMonitor: return "Three 1080p screens in a row"
        case .deskAndIPad: return "1440p monitor + iPad Pro 11\""
        case .tvAndIPad: return "1080p TV + iPad Air"
        case .ultrawideAndSide: return "34\" ultrawide + 1080p side monitor"
        }
    }

    var presets: [(name: String, preset: VirtualScreenPreset)] {
        switch self {
        case .dualTV:
            return [("TV Left", .hd1080), ("TV Right", .hd1080)]
        case .tripleMonitor:
            return [("Left", .hd1080), ("Center", .hd1080), ("Right", .hd1080)]
        case .deskAndIPad:
            return [("Monitor", .qhd1440), ("iPad", .iPadPro11)]
        case .tvAndIPad:
            return [("TV", .hd1080), ("iPad", .iPadAir)]
        case .ultrawideAndSide:
            return [("Ultrawide", .ultrawide34), ("Side", .hd1080)]
        }
    }
}
