import Foundation
import AppKit

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
        persistConfigs()
    }

    // MARK: - Widget Data

    func notePadData(for surfaceID: UUID, widgetID: UUID) -> NotePadData {
        widgetStorage[surfaceID]?.notePads[widgetID] ?? NotePadData()
    }

    func updateNotePad(surfaceID: UUID, widgetID: UUID, data: NotePadData) {
        ensureStorage(for: surfaceID)
        widgetStorage[surfaceID]?.notePads[widgetID] = data
        persistWidgetStorage()
    }

    func checklistData(for surfaceID: UUID, widgetID: UUID) -> ChecklistData {
        widgetStorage[surfaceID]?.checklists[widgetID] ?? ChecklistData()
    }

    func updateChecklist(surfaceID: UUID, widgetID: UUID, data: ChecklistData) {
        ensureStorage(for: surfaceID)
        widgetStorage[surfaceID]?.checklists[widgetID] = data
        persistWidgetStorage()
    }

    func timerData(for surfaceID: UUID, widgetID: UUID) -> TimerData {
        widgetStorage[surfaceID]?.timers[widgetID] ?? TimerData()
    }

    func updateTimer(surfaceID: UUID, widgetID: UUID, data: TimerData) {
        ensureStorage(for: surfaceID)
        widgetStorage[surfaceID]?.timers[widgetID] = data
        persistWidgetStorage()
    }

    func linkCardsData(for surfaceID: UUID, widgetID: UUID) -> LinkCardsData {
        widgetStorage[surfaceID]?.linkCards[widgetID] ?? LinkCardsData()
    }

    func updateLinkCards(surfaceID: UUID, widgetID: UUID, data: LinkCardsData) {
        ensureStorage(for: surfaceID)
        widgetStorage[surfaceID]?.linkCards[widgetID] = data
        persistWidgetStorage()
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
            widgetStorage = Dictionary(uniqueKeysWithValues: storages.map { ($0.surfaceID, $0) })
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
}
