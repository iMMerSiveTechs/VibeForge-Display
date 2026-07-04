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
    private var observerToken: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?

    // Capture-free C thunk (must be a stable reference for register+remove).
    private static let reconfigCallback: CGDisplayReconfigurationCallBack = { _, _, _ in
        Task { @MainActor in
            NotificationCenter.default.post(name: .screenConfigurationDidChange, object: nil)
        }
    }

    init(logService: LogService) {
        self.logService = logService
        refresh()
        registerForDisplayChanges()
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(ScreenService.reconfigCallback, nil)
        if let observerToken { NotificationCenter.default.removeObserver(observerToken) }
        refreshTask?.cancel()
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
        // Dedupe — the duplicate-low-res option can yield modes that map to the
        // same DisplayModeInfo.id, which would break ForEach identity in the UI.
        var seen = Set<String>()
        return cgModes.compactMap { mode -> DisplayModeInfo? in
            let info = DisplayModeInfo(
                width: mode.pixelWidth,
                height: mode.pixelHeight,
                refreshRate: mode.refreshRate,
                isUsableForDesktop: mode.isUsableForDesktopGUI()
            )
            return seen.insert(info.id).inserted ? info : nil
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
        CGDisplayRegisterReconfigurationCallback(ScreenService.reconfigCallback, nil)

        // A single hot-plug fires the CG callback several times (begin+completed
        // per display); coalesce so we don't run refresh() — which enumerates
        // every display's modes on the main thread — in a hitchy burst.
        observerToken = NotificationCenter.default.addObserver(
            forName: .screenConfigurationDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            refresh()
        }
    }
}

extension Notification.Name {
    static let screenConfigurationDidChange = Notification.Name("VFScreenConfigurationDidChange")
}
