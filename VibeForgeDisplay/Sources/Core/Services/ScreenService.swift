import Foundation
import SwiftUI
import CoreGraphics
import AppKit

@MainActor
@Observable
final class ScreenService {
    private(set) var screens: [ScreenInfo] = []
    private(set) var isEnumerating = false
    private let logService: LogService

    init(logService: LogService) {
        self.logService = logService
        refresh()
        registerForDisplayChanges()
    }

    func refresh() {
        isEnumerating = true
        defer { isEnumerating = false }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0

        let result = CGGetActiveDisplayList(16, &displayIDs, &displayCount)
        guard result == .success else {
            logService.log(.error, "Failed to enumerate displays", detail: "CGError: \(result.rawValue)")
            screens = []
            return
        }

        let activeIDs = Array(displayIDs.prefix(Int(displayCount)))
        screens = activeIDs.compactMap { buildScreenInfo(for: $0) }
        logService.log(.screen, "Detected \(screens.count) screen(s)")
    }

    func availableModes(for displayID: CGDirectDisplayID) -> [DisplayModeInfo] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let cgModes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
            return []
        }
        return cgModes.map { mode in
            DisplayModeInfo(
                width: mode.pixelWidth,
                height: mode.pixelHeight,
                refreshRate: mode.refreshRate,
                isUsableForDesktop: mode.isUsableForDesktopGUI()
            )
        }
    }

    private func buildScreenInfo(for displayID: CGDirectDisplayID) -> ScreenInfo? {
        let bounds = CGDisplayBounds(displayID)
        let isMain = CGDisplayIsMain(displayID) != 0
        let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
        let rotation = CGDisplayRotation(displayID)

        var pixelWidth = Int(bounds.width)
        var pixelHeight = Int(bounds.height)
        var refreshRate: Double = 0
        var scaleFactor: Double = 1.0

        if let mode = CGDisplayCopyDisplayMode(displayID) {
            pixelWidth = mode.pixelWidth
            pixelHeight = mode.pixelHeight
            refreshRate = mode.refreshRate
            if bounds.width > 0 {
                scaleFactor = Double(mode.pixelWidth) / bounds.width
            }
        }

        let name = displayName(for: displayID, isBuiltIn: isBuiltIn, isMain: isMain)

        return ScreenInfo(
            displayID: displayID,
            name: name,
            isMain: isMain,
            isBuiltIn: isBuiltIn,
            boundsWidth: Int(bounds.width),
            boundsHeight: Int(bounds.height),
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            refreshRate: refreshRate,
            scaleFactor: scaleFactor,
            rotation: rotation,
            availableModeCount: availableModes(for: displayID).count
        )
    }

    private func displayName(for displayID: CGDirectDisplayID, isBuiltIn: Bool, isMain: Bool) -> String {
        // Use NSScreen matching to get localized name on macOS 14+
        if let nsScreen = NSScreen.screens.first(where: { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else {
                return false
            }
            return screenNumber == displayID
        }) {
            return nsScreen.localizedName
        }

        if isBuiltIn {
            return "Built-in Display"
        }
        return isMain ? "Main Display" : "Display \(displayID)"
    }

    private func registerForDisplayChanges() {
        let callback: CGDisplayReconfigurationCallBack = { _, _, _ in
            Task { @MainActor in
                // The ScreenService instance is found through the app state
                // This callback triggers a refresh via notification
                NotificationCenter.default.post(name: .screenConfigurationDidChange, object: nil)
            }
        }
        CGDisplayRegisterReconfigurationCallback(callback, nil)

        NotificationCenter.default.addObserver(
            forName: .screenConfigurationDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }
}

extension Notification.Name {
    static let screenConfigurationDidChange = Notification.Name("VFScreenConfigurationDidChange")
}
