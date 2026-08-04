import SwiftUI

@MainActor
@Observable
final class AppState {
    let logService: LogService
    let screenService: ScreenService
    let modeService: ModeService
    let surfaceService: SurfaceService
    let virtualDisplayService: VirtualDisplayService
    let hlsServer: HLSServer
    let streamService: StreamService
    let wallPresetService: WallPresetService
    let persistence: PersistenceManager

    var selectedTab: SidebarTab = .virtualScreens

    enum SidebarTab: String, CaseIterable, Identifiable {
        case screens = "Screens"
        case virtualScreens = "Virtual Screens"
        case quickSetup = "Quick Setup"
        case modes = "Modes"
        case surfaces = "Surfaces"
        case routes = "Routes"
        case logs = "Logs"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .screens: return "display"
            case .virtualScreens: return "plus.display"
            case .quickSetup: return "wand.and.stars"
            case .modes: return "slider.horizontal.3"
            case .surfaces: return "rectangle.on.rectangle.angled"
            case .routes: return "point.3.connected.trianglepath.dotted"
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
        let virtualDisplayService = VirtualDisplayService(persistence: persistence, logService: logService)
        let hlsServer = HLSServer(logService: logService)
        let streamService = StreamService(
            persistence: persistence,
            logService: logService,
            hlsServer: hlsServer,
            virtualDisplayService: virtualDisplayService,
            surfaceService: surfaceService
        )

        self.persistence = persistence
        self.logService = logService
        self.screenService = screenService
        self.modeService = modeService
        self.surfaceService = surfaceService
        let wallPresetService = WallPresetService(
            persistence: persistence,
            logService: logService,
            virtualDisplayService: virtualDisplayService,
            surfaceService: surfaceService,
            streamService: streamService
        )

        self.virtualDisplayService = virtualDisplayService
        self.hlsServer = hlsServer
        self.streamService = streamService
        self.wallPresetService = wallPresetService

        // Deactivating/deleting a source stops any route streaming it (was dead code).
        virtualDisplayService.onSourceWillDeactivate = { [weak streamService] id in
            streamService?.stopRoutesUsing(sourceID: id)
        }
        surfaceService.onSourceWillDeactivate = { [weak streamService] id in
            streamService?.stopRoutesUsing(sourceID: id)
        }

        logService.log(.system, "VibeForge Display launched", detail: "v\(VFConstants.appVersion)")
        streamService.scheduleAutoStart()
        registerTerminationHook()
    }

    /// On a clean quit, stop streams and record the clean-exit marker so the next
    /// launch may auto-create virtual screens (a quick quit otherwise looked like
    /// an unclean exit and silently disabled auto-create).
    private func registerTerminationHook() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.streamService.stopAll()
                self?.hlsServer.stop()
                self?.surfaceService.flushPendingSaves()   // don't lose the last note keystroke
                self?.virtualDisplayService.markCleanExit()
            }
        }
    }
}
