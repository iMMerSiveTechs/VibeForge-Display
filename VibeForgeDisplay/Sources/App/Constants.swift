import Foundation

enum VFConstants {
    static let appName = "VibeForge Display"
    static let bundleIdentifier = "com.vibeforge.display"
    static let appVersion = "0.1.0"

    static let appSupportDirectoryName = "VibeForgeDisplay"
    static let modesFileName = "modes.json"
    static let surfacesFileName = "surfaces.json"
    static let logFileName = "events.log"

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
