import Foundation

struct SurfaceConfig: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var preset: SurfacePreset
    var opacity: Double
    var alwaysOnTop: Bool
    var frameX: Double
    var frameY: Double
    var frameWidth: Double
    var frameHeight: Double
    var targetScreenID: UInt32?
    var widgets: [WidgetConfig]
    var isOpen: Bool

    init(
        name: String = "Untitled Surface",
        preset: SurfacePreset = .landscape
    ) {
        self.id = UUID()
        self.name = name
        self.preset = preset
        self.opacity = VFConstants.SurfaceDefaults.defaultOpacity
        self.alwaysOnTop = false
        let size = preset.size
        self.frameX = 100
        self.frameY = 100
        self.frameWidth = size.width
        self.frameHeight = size.height
        self.targetScreenID = nil
        self.widgets = []
        self.isOpen = false
    }
}

enum SurfacePreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case smallPanel = "Small Panel"
    case portrait = "Portrait Utility"
    case landscape = "Landscape Utility"

    var id: String { rawValue }

    var size: CGSize {
        switch self {
        case .smallPanel: return VFConstants.SurfaceDefaults.smallPanelSize
        case .portrait: return VFConstants.SurfaceDefaults.portraitSize
        case .landscape: return VFConstants.SurfaceDefaults.landscapeSize
        }
    }

    var icon: String {
        switch self {
        case .smallPanel: return "rectangle.portrait"
        case .portrait: return "rectangle.portrait.fill"
        case .landscape: return "rectangle.fill"
        }
    }
}

struct WidgetConfig: Identifiable, Codable, Sendable {
    let id: UUID
    var kind: WidgetKind
    var order: Int

    init(kind: WidgetKind, order: Int) {
        self.id = UUID()
        self.kind = kind
        self.order = order
    }
}

enum WidgetKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case notePad = "Note Pad"
    case checklist = "Checklist"
    case timer = "Timer"
    case linkCards = "Link Cards"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .notePad: return "note.text"
        case .checklist: return "checklist"
        case .timer: return "timer"
        case .linkCards: return "link"
        }
    }
}
