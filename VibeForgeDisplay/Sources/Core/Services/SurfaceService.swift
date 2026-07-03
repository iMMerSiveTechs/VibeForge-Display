import Foundation
import AppKit
import Observation

@MainActor
@Observable
final class SurfaceService {
    private(set) var configs: [SurfaceConfig] = []
    private(set) var widgetStorage: [UUID: SurfaceWidgetStorage] = [:]
    private var windows: [UUID: NSWindow] = [:]
    private let persistence: PersistenceManager
    private let logService: LogService

    init(persistence: PersistenceManager, logService: LogService) {
        self.persistence = persistence
        self.logService = logService
        loadConfigs()
        loadWidgetStorage()
    }

    // MARK: - Surface CRUD

    func createSurface(name: String, preset: SurfacePreset) -> SurfaceConfig {
        var config = SurfaceConfig(name: name, preset: preset)
        // Add default widgets
        config.widgets = WidgetKind.allCases.enumerated().map { index, kind in
            WidgetConfig(kind: kind, order: index)
        }
        configs.append(config)
        widgetStorage[config.id] = SurfaceWidgetStorage(surfaceID: config.id)
        persistConfigs()
        persistWidgetStorage()
        logService.log(.surface, "Created surface: \(name)", detail: "Preset: \(preset.rawValue)")
        return config
    }

    func updateConfig(_ config: SurfaceConfig) {
        guard let index = configs.firstIndex(where: { $0.id == config.id }) else { return }
        configs[index] = config
        persistConfigs()
        applyConfigToOpenWindow(config)
    }

    /// Restores a snapshotted surface (from a Wall Preset) if it's not present.
    @discardableResult
    func addConfigIfMissing(_ config: SurfaceConfig) -> Bool {
        guard !configs.contains(where: { $0.id == config.id }) else { return false }
        var restored = config
        restored.isOpen = false
        configs.append(restored)
        if widgetStorage[config.id] == nil {
            widgetStorage[config.id] = SurfaceWidgetStorage(surfaceID: config.id)
        }
        persistConfigs()
        persistWidgetStorage()
        logService.log(.surface, "Restored surface: \(config.name)")
        return true
    }

    /// Live-applies opacity / always-on-top / target screen to an open window so
    /// the settings sliders/toggles take effect immediately (not just on reopen).
    private func applyConfigToOpenWindow(_ config: SurfaceConfig) {
        guard let window = windows[config.id] else { return }
        window.alphaValue = config.opacity
        window.level = config.alwaysOnTop ? .floating : .normal
        // Snap to the target screen only if the window isn't already on it — so a
        // continuous opacity/toggle change doesn't keep re-centering the window.
        guard let screenID = config.targetScreenID,
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == screenID
              }) else { return }
        let currentScreenID = window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
        if currentScreenID != screenID {
            var frame = window.frame
            frame.origin = NSPoint(x: screen.frame.midX - frame.width / 2,
                                   y: screen.frame.midY - frame.height / 2)
            window.setFrame(frame, display: true, animate: true)
        }
    }

    func deleteSurface(_ id: UUID) {
        let name = configs.first(where: { $0.id == id })?.name ?? "Unknown"
        closeSurfaceWindow(id)
        configs.removeAll { $0.id == id }
        widgetStorage.removeValue(forKey: id)
        persistConfigs()
        persistWidgetStorage()
        logService.log(.surface, "Deleted surface: \(name)")
    }

    // MARK: - Window Management

    func openSurfaceWindow(_ id: UUID) {
        guard let index = configs.firstIndex(where: { $0.id == id }) else { return }
        let config = configs[index]

        if let existing = windows[id], existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = SurfaceWindow.create(config: config, service: self)
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        configs[index].isOpen = true
        persistConfigs()
        logService.log(.surface, "Opened surface: \(config.name)")
    }

    func closeSurfaceWindow(_ id: UUID) {
        guard let index = configs.firstIndex(where: { $0.id == id }) else { return }
        windows[id]?.close()
        windows.removeValue(forKey: id)
        configs[index].isOpen = false
        persistConfigs()
    }

    func updateWindowFrame(_ id: UUID, frame: NSRect) {
        guard let index = configs.firstIndex(where: { $0.id == id }) else { return }
        configs[index].frameX = frame.origin.x
        configs[index].frameY = frame.origin.y
        configs[index].frameWidth = frame.size.width
        configs[index].frameHeight = frame.size.height
        scheduleConfigSave()
    }

    /// Ensures the surface window is open and returns its CGWindowID for capture.
    func ensureWindowID(for id: UUID) -> CGWindowID? {
        if windows[id] == nil || windows[id]?.isVisible == false {
            openSurfaceWindow(id)
        }
        guard let number = windows[id]?.windowNumber else { return nil }
        return CGWindowID(number)
    }

    // MARK: - Widget Data

    func notePadData(for surfaceID: UUID, widgetID: UUID) -> NotePadData {
        widgetStorage[surfaceID]?.notePads[widgetID] ?? NotePadData()
    }

    func updateNotePad(surfaceID: UUID, widgetID: UUID, data: NotePadData) {
        ensureStorage(for: surfaceID)
        widgetStorage[surfaceID]?.notePads[widgetID] = data
        scheduleWidgetSave()
    }

    func checklistData(for surfaceID: UUID, widgetID: UUID) -> ChecklistData {
        widgetStorage[surfaceID]?.checklists[widgetID] ?? ChecklistData()
    }

    func updateChecklist(surfaceID: UUID, widgetID: UUID, data: ChecklistData) {
        ensureStorage(for: surfaceID)
        widgetStorage[surfaceID]?.checklists[widgetID] = data
        scheduleWidgetSave()
    }

    func timerData(for surfaceID: UUID, widgetID: UUID) -> TimerData {
        widgetStorage[surfaceID]?.timers[widgetID] ?? TimerData()
    }

    func updateTimer(surfaceID: UUID, widgetID: UUID, data: TimerData) {
        ensureStorage(for: surfaceID)
        widgetStorage[surfaceID]?.timers[widgetID] = data
        scheduleWidgetSave()
    }

    func linkCardsData(for surfaceID: UUID, widgetID: UUID) -> LinkCardsData {
        widgetStorage[surfaceID]?.linkCards[widgetID] ?? LinkCardsData()
    }

    func updateLinkCards(surfaceID: UUID, widgetID: UUID, data: LinkCardsData) {
        ensureStorage(for: surfaceID)
        widgetStorage[surfaceID]?.linkCards[widgetID] = data
        scheduleWidgetSave()
    }

    private func ensureStorage(for surfaceID: UUID) {
        if widgetStorage[surfaceID] == nil {
            widgetStorage[surfaceID] = SurfaceWidgetStorage(surfaceID: surfaceID)
        }
    }

    // MARK: - Persistence

    private func loadConfigs() {
        guard persistence.exists(VFConstants.surfacesFileName) else { return }
        do {
            configs = try persistence.load([SurfaceConfig].self, from: VFConstants.surfacesFileName)
            // Mark all as closed on launch
            for i in configs.indices { configs[i].isOpen = false }
            logService.log(.surface, "Loaded \(configs.count) surface config(s)")
        } catch {
            logService.log(.error, "Failed to load surface configs", detail: error.localizedDescription)
        }
    }

    private func persistConfigs() {
        do {
            try persistence.save(configs, to: VFConstants.surfacesFileName)
        } catch {
            logService.log(.error, "Failed to save surface configs", detail: error.localizedDescription)
        }
    }

    private let widgetStorageFileName = "widget_storage.json"

    private func loadWidgetStorage() {
        guard persistence.exists(widgetStorageFileName) else { return }
        do {
            let storages = try persistence.load([SurfaceWidgetStorage].self, from: widgetStorageFileName)
            widgetStorage = Dictionary(storages.map { ($0.surfaceID, $0) }, uniquingKeysWith: { _, latest in latest })
        } catch {
            logService.log(.error, "Failed to load widget data", detail: error.localizedDescription)
        }
    }

    private func persistWidgetStorage() {
        do {
            let storages = Array(widgetStorage.values)
            try persistence.save(storages, to: widgetStorageFileName)
        } catch {
            logService.log(.error, "Failed to save widget data", detail: error.localizedDescription)
        }
    }

    // MARK: - Debounced saves
    // Notes fire per-keystroke and window drags fire per-move; coalesce these into
    // one write ~0.4s after activity stops instead of hammering main-thread disk I/O.

    private var widgetSaveTask: Task<Void, Never>?
    private var configSaveTask: Task<Void, Never>?

    private func scheduleWidgetSave() {
        widgetSaveTask?.cancel()
        widgetSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.persistWidgetStorage()
        }
    }

    private func scheduleConfigSave() {
        configSaveTask?.cancel()
        configSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.persistConfigs()
        }
    }
}
