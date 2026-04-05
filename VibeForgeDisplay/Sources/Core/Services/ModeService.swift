import Foundation

@MainActor
@Observable
final class ModeService {
    private(set) var modes: [Mode] = []
    private let persistence: PersistenceManager
    private let logService: LogService

    init(persistence: PersistenceManager, logService: LogService) {
        self.persistence = persistence
        self.logService = logService
        loadModes()
    }

    func saveMode(_ mode: Mode) {
        if let index = modes.firstIndex(where: { $0.id == mode.id }) {
            modes[index] = mode
            modes[index].updatedAt = Date()
        } else {
            modes.append(mode)
        }
        persistModes()
        logService.log(.mode, "Saved mode: \(mode.name)")
    }

    func createMode(name: String, notes: String, screens: [ScreenInfo], surfaces: [SurfaceConfig]) -> Mode {
        let mainID = screens.first(where: \.isMain)?.displayID
        let mode = Mode(
            name: name,
            notes: notes,
            screens: screens,
            preferredMainDisplayID: mainID,
            surfacePreferences: surfaces
        )
        saveMode(mode)
        return mode
    }

    func deleteMode(_ mode: Mode) {
        modes.removeAll { $0.id == mode.id }
        persistModes()
        logService.log(.mode, "Deleted mode: \(mode.name)")
    }

    func deleteMode(at offsets: IndexSet) {
        let names = offsets.map { modes[$0].name }
        modes.remove(atOffsets: offsets)
        persistModes()
        for name in names {
            logService.log(.mode, "Deleted mode: \(name)")
        }
    }

    struct RestoreResult {
        var restoredItems: [String]
        var manualItems: [String]
        var surfacesRestored: Int
    }

    func restoreMode(_ mode: Mode, currentScreens: [ScreenInfo]) -> RestoreResult {
        var restored: [String] = []
        var manual: [String] = []

        // Check which screens from the mode are still connected
        for savedScreen in mode.screens {
            if currentScreens.contains(where: { $0.displayID == savedScreen.displayID }) {
                restored.append("\(savedScreen.name) — detected")
            } else {
                manual.append("\(savedScreen.name) — not connected")
            }
        }

        // Check main display preference
        if let preferredMain = mode.preferredMainDisplayID {
            if currentScreens.contains(where: { $0.displayID == preferredMain }) {
                restored.append("Preferred main display available")
            } else {
                manual.append("Preferred main display not connected")
            }
        }

        let surfaceCount = mode.surfacePreferences.count
        restored.append("\(surfaceCount) surface preference(s) loaded")

        logService.log(.mode, "Restored mode: \(mode.name)",
                       detail: "Restored: \(restored.count), Manual: \(manual.count)")

        return RestoreResult(
            restoredItems: restored,
            manualItems: manual,
            surfacesRestored: surfaceCount
        )
    }

    private func loadModes() {
        guard persistence.exists(VFConstants.modesFileName) else { return }
        do {
            modes = try persistence.load([Mode].self, from: VFConstants.modesFileName)
            logService.log(.mode, "Loaded \(modes.count) mode(s)")
        } catch {
            logService.log(.error, "Failed to load modes", detail: error.localizedDescription)
        }
    }

    private func persistModes() {
        do {
            try persistence.save(modes, to: VFConstants.modesFileName)
        } catch {
            logService.log(.error, "Failed to save modes", detail: error.localizedDescription)
        }
    }
}
