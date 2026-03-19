import AppKit
import SwiftUI

final class SurfaceWindow: NSPanel {

    static func create(config: SurfaceConfig, service: SurfaceService) -> SurfaceWindow {
        let frame = NSRect(
            x: config.frameX,
            y: config.frameY,
            width: config.frameWidth,
            height: config.frameHeight
        )

        let styleMask: NSWindow.StyleMask = [
            .borderless,
            .resizable,
            .nonactivatingPanel,
        ]

        let window = SurfaceWindow(
            contentRect: frame,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        window.title = config.name
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: config.opacity)
        window.alphaValue = config.opacity
        window.minSize = NSSize(
            width: VFConstants.SurfaceDefaults.minWidth,
            height: VFConstants.SurfaceDefaults.minHeight
        )
        window.isFloatingPanel = config.alwaysOnTop
        window.level = config.alwaysOnTop ? .floating : .normal
        window.animationBehavior = .utilityWindow
        window.isReleasedWhenClosed = false

        let contentView = SurfaceContentView(
            surfaceID: config.id,
            surfaceService: service
        )
        window.contentView = NSHostingView(rootView: contentView)

        // Track frame changes for persistence
        window.surfaceID = config.id
        window.surfaceService = service

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { notification in
            guard let win = notification.object as? SurfaceWindow else { return }
            Task { @MainActor in
                win.surfaceService?.updateWindowFrame(win.surfaceID, frame: win.frame)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { notification in
            guard let win = notification.object as? SurfaceWindow else { return }
            Task { @MainActor in
                win.surfaceService?.updateWindowFrame(win.surfaceID, frame: win.frame)
            }
        }

        return window
    }

    var surfaceID: UUID = UUID()
    var surfaceService: SurfaceService?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
