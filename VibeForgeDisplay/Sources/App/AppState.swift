import SwiftUI

@MainActor
@Observable
final class AppState {
    let logService: LogService
    let screenService: ScreenService
    let modeService: ModeService
    let surfaceService: SurfaceService
    let persistence: PersistenceManager

    var selectedTab: SidebarTab = .screens

    enum SidebarTab: String, CaseIterable, Identifiable {
        case screens = "Screens"
        case modes = "Modes"
        case surfaces = "Surfaces"
        case logs = "Logs"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .screens: return "display"
            case .modes: return "slider.horizontal.3"
            case .surfaces: return "rectangle.on.rectangle.angled"
            case .logs: return "list.bullet.rectangle"
            case .settings: return "gear"
            }
        }
    }

    init() {
        let persistence = PersistenceManager()
        let logService = LogService()
        let screenService = ScreenService(logService: logService)
        let modeService = ModeService(persistence: persistence, logService: logService)
        let surfaceService = SurfaceService(persistence: persistence, logService: logService)

        self.persistence = persistence
        self.logService = logService
        self.screenService = screenService
        self.modeService = modeService
        self.surfaceService = surfaceService

        logService.log(.system, "VibeForge Display launched", detail: "v\(VFConstants.appVersion)")
    }
}
