import Foundation

enum VFConstants {
    static let appName = "VibeForge Display"
    static let bundleIdentifier = "com.vibeforge.display"
    static let appVersion = "0.1.0"

    static let appSupportDirectoryName = "VibeForgeDisplay"
    static let modesFileName = "modes.json"
    static let surfacesFileName = "surfaces.json"
    static let virtualScreensFileName = "virtual_screens.json"
    static let routesFileName = "routes.json"
    static let logFileName = "events.log"
    static let cleanExitMarkerFileName = "clean_exit.marker"

    enum Streaming {
        /// TCP port the embedded HLS/HTTP server listens on.
        static let httpPort: UInt16 = 8760
        /// Bonjour service type advertised for receiver discovery.
        static let bonjourServiceType = "_vibeforge._tcp"
        /// Target LL-HLS segment duration in seconds.
        static let segmentDuration: Double = 1.0
        /// How many recent media segments to retain per stream in memory.
        static let segmentWindow = 8
    }

    enum Security {
        /// Seconds a pairing PIN stays valid after the user opens pairing on the Mac.
        static let pairingWindow: TimeInterval = 120
        /// Wrong-PIN attempts allowed before pairing auto-closes and must be re-armed.
        static let maxPairingAttempts = 5
    }

    static var appSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(appSupportDirectoryName)
    }

    enum SurfaceDefaults {
        static let minWidth: CGFloat = 200
        static let minHeight: CGFloat = 150
        static let defaultOpacity: Double = 1.0
        static let smallPanelSize = CGSize(width: 320, height: 480)
        static let portraitSize = CGSize(width: 400, height: 700)
        static let landscapeSize = CGSize(width: 700, height: 400)
    }

    enum MenuBar {
        static let iconName = "rectangle.on.rectangle"
        static let title = "VF Display"
    }
}
