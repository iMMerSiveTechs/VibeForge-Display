import Foundation

/// Saves and restores whole multi-TV layouts (Wall Presets). A preset snapshots
/// the current virtual screens + routes; applying it re-materializes them.
@MainActor
@Observable
final class WallPresetService {
    private(set) var presets: [WallPreset] = []
    private let persistence: PersistenceManager
    private let logService: LogService
    private let virtualDisplayService: VirtualDisplayService
    private let streamService: StreamService

    init(
        persistence: PersistenceManager,
        logService: LogService,
        virtualDisplayService: VirtualDisplayService,
        streamService: StreamService
    ) {
        self.persistence = persistence
        self.logService = logService
        self.virtualDisplayService = virtualDisplayService
        self.streamService = streamService
        load()
    }

    func saveCurrent(name: String) {
        let preset = WallPreset(
            name: name,
            virtualScreens: virtualDisplayService.configs,
            routes: streamService.routes
        )
        presets.append(preset)
        persist()
        logService.log(.system, "Saved wall preset: \(name)", detail: preset.summary)
    }

    func delete(_ id: UUID) {
        let name = presets.first(where: { $0.id == id })?.name ?? "preset"
        presets.removeAll { $0.id == id }
        persist()
        logService.log(.system, "Deleted wall preset: \(name)")
    }

    /// Recreates the layout: adds+activates any missing virtual screens, adds any
    /// missing routes, then starts routes flagged auto-start.
    func apply(_ preset: WallPreset) async {
        for vs in preset.virtualScreens {
            if !virtualDisplayService.configs.contains(where: { $0.id == vs.id }) {
                virtualDisplayService.addConfig(vs)
            }
            if !virtualDisplayService.isActive(vs.id) {
                await virtualDisplayService.createDisplay(config: vs)
            }
        }
        for route in preset.routes where !streamService.routes.contains(where: { $0.id == route.id }) {
            streamService.addRoute(route)
        }
        for route in preset.routes where route.autoStart {
            await streamService.startRoute(route.id)
        }
        logService.log(.system, "Applied wall preset: \(preset.name)", detail: preset.summary)
    }

    // MARK: Persistence

    private func load() {
        guard persistence.exists(VFConstants.wallPresetsFileName) else { return }
        do {
            presets = try persistence.load([WallPreset].self, from: VFConstants.wallPresetsFileName)
            logService.log(.system, "Loaded \(presets.count) wall preset(s)")
        } catch {
            logService.log(.error, "Failed to load wall presets", detail: error.localizedDescription)
        }
    }

    private func persist() {
        do { try persistence.save(presets, to: VFConstants.wallPresetsFileName) }
        catch { logService.log(.error, "Failed to save wall presets", detail: error.localizedDescription) }
    }
}
