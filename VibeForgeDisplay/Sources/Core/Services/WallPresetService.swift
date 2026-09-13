import Foundation
import Observation

/// Saves and restores whole multi-TV layouts (Wall Presets). A preset snapshots
/// the current virtual screens + routes; applying it re-materializes them.
@MainActor
@Observable
final class WallPresetService {
    struct ApplyReport: Sendable {
        var screensRestored = 0
        var surfacesRestored = 0
        var routesRestored = 0
        var routesStarted = 0
        var failures: [String] = []
    }

    private(set) var presets: [WallPreset] = []
    /// Result of the most recent apply, for the UI to surface.
    private(set) var lastApplyReport: ApplyReport?

    private let persistence: PersistenceManager
    private let logService: LogService
    private let virtualDisplayService: VirtualDisplayService
    private let surfaceService: SurfaceService
    private let streamService: StreamService

    init(
        persistence: PersistenceManager,
        logService: LogService,
        virtualDisplayService: VirtualDisplayService,
        surfaceService: SurfaceService,
        streamService: StreamService
    ) {
        self.persistence = persistence
        self.logService = logService
        self.virtualDisplayService = virtualDisplayService
        self.surfaceService = surfaceService
        self.streamService = streamService
        load()
    }

    func saveCurrent(name: String) {
        // Snapshot only the surfaces actually referenced by surface routes.
        let usedSurfaceIDs = Set(streamService.routes
            .filter { $0.sourceKind == .surface }
            .map(\.sourceID))
        let surfaces = surfaceService.configs.filter { usedSurfaceIDs.contains($0.id) }
        let preset = WallPreset(
            name: name,
            virtualScreens: virtualDisplayService.configs,
            surfaces: surfaces,
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

    /// Recreates the layout: restores+activates virtual screens, restores
    /// snapshotted surfaces, restores routes, then starts routes flagged
    /// auto-start. Records an ApplyReport (surfaced by the UI).
    func apply(_ preset: WallPreset) async {
        var report = ApplyReport()

        for vs in preset.virtualScreens {
            if !virtualDisplayService.configs.contains(where: { $0.id == vs.id }) {
                virtualDisplayService.addConfig(vs)
                report.screensRestored += 1
            }
            if !virtualDisplayService.isActive(vs.id) {
                let ok = await virtualDisplayService.createDisplay(config: vs)
                if !ok { report.failures.append("Couldn't activate screen “\(vs.name)”.") }
            }
        }

        for surface in preset.surfaces where surfaceService.addConfigIfMissing(surface) {
            report.surfacesRestored += 1
        }

        for route in preset.routes {
            // Skip routes whose source can't be resolved (e.g. a deleted surface
            // that predates surface-snapshotting).
            let resolvable: Bool
            switch route.sourceKind {
            case .virtualScreen: resolvable = virtualDisplayService.configs.contains { $0.id == route.sourceID }
            case .surface: resolvable = surfaceService.configs.contains { $0.id == route.sourceID }
            }
            guard resolvable else {
                report.failures.append("Route “\(route.name)” has no source and was skipped.")
                continue
            }
            if !streamService.routes.contains(where: { $0.id == route.id }) {
                streamService.addRoute(route)
                report.routesRestored += 1
            }
            if route.autoStart {
                await streamService.startRoute(route.id)
                if streamService.isStreaming(route.id) { report.routesStarted += 1 }
                else if let err = streamService.error(for: route.id) { report.failures.append(err) }
            }
        }

        lastApplyReport = report
        logService.log(.system, "Applied wall preset: \(preset.name)", detail: preset.summary)
    }

    func clearApplyReport() { lastApplyReport = nil }

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
