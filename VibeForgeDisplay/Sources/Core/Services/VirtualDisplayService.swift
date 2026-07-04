import Foundation
import CoreGraphics
import Observation

// CGVirtualDisplay extensions for Sendable compliance
// These ObjC classes come from our bridging header, not a separate module
extension CGVirtualDisplayDescriptor: @unchecked Sendable {}
extension CGVirtualDisplay: @unchecked Sendable {}
extension CGVirtualDisplaySettings: @unchecked Sendable {}

@MainActor
@Observable
final class VirtualDisplayService {
    private(set) var configs: [VirtualScreenConfig] = []
    private(set) var activeConfigIDs: Set<UUID> = []
    private var activeDisplays: [UUID: CGVirtualDisplay] = [:]
    private let persistence: PersistenceManager
    private let logService: LogService
    private let configsFileName = "virtual_screens.json"

    // Standard PPI for physical size calculation (pixels to mm)
    private let standardPPI: Double = 110.0

    init(persistence: PersistenceManager, logService: LogService) {
        self.persistence = persistence
        self.logService = logService
        loadConfigs()

        // Black-screen crash guard: a bad virtual-display config can make macOS
        // go dark, forcing a reboot. If we auto-created on every launch, we could
        // trap the user in a reboot loop. So we only auto-create when the PREVIOUS
        // session ended cleanly (a marker file we arm ~20s after a stable launch).
        // A hard reboot clears the marker, so the next launch comes up safe.
        let lastRunWasStable = persistence.exists(VFConstants.cleanExitMarkerFileName)
        try? persistence.delete(VFConstants.cleanExitMarkerFileName)
        if lastRunWasStable {
            autoCreateDisplays()
        } else if configs.contains(where: \.autoCreateOnLaunch) {
            logService.log(.system, "Safe mode: skipped auto-creating virtual screens",
                           detail: "Last session didn't exit cleanly. Activate manually once your display is stable.")
        }
        armStableRunMarker()
    }

    /// Marks this run as stable after it has survived ~20s, so the next launch may auto-create.
    private func armStableRunMarker() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            try? persistence.save(Date(), to: VFConstants.cleanExitMarkerFileName)
        }
    }

    // MARK: - Create Virtual Display

    @discardableResult
    func createDisplay(config: VirtualScreenConfig) async -> Bool {
        // Re-entrancy: if it's already live, don't build a second one (which would
        // drop the first and flash the display with a new ID).
        guard !activeConfigIDs.contains(config.id) else { return true }
        // Build the CGVirtualDisplay descriptor
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.queue = DispatchQueue.global(qos: .userInitiated)
        descriptor.name = "VibeForge: \(config.name)"
        descriptor.maxPixelsWide = UInt32(config.width)
        descriptor.maxPixelsHigh = UInt32(config.height)

        // Physical size: use pixels/PPI * 25.4 to convert to mm
        // Use a safe size to avoid pixel density rejection
        descriptor.sizeInMillimeters = CGSize(
            width: Double(config.width) / standardPPI * 25.4,
            height: Double(config.height) / standardPPI * 25.4
        )

        // Standard Apple display color primaries
        descriptor.whitePoint = CGPoint(x: 0.3125, y: 0.3291)
        descriptor.redPrimary = CGPoint(x: 0.6797, y: 0.3203)
        descriptor.greenPrimary = CGPoint(x: 0.2559, y: 0.6983)
        descriptor.bluePrimary = CGPoint(x: 0.1494, y: 0.0557)

        // Stable, distinct vendor/product/serial derived from the config UUID.
        // macOS keys display arrangement/resolution prefs on these, so they MUST
        // be stable across launches (Swift's hashValue is per-process-random) and
        // distinct per virtual screen (a shared productID/serial makes two screens
        // indistinguishable to WindowServer).
        let u = config.id.uuid
        descriptor.vendorID = 0xEEEE
        descriptor.productID = UInt32(u.4) << 8 | UInt32(u.5) | 0x0001
        descriptor.serialNum = UInt32(u.0) << 24 | UInt32(u.1) << 16 | UInt32(u.2) << 8 | UInt32(u.3) | 0x1

        // Create the virtual display
        guard let virtualDisplay = CGVirtualDisplay(descriptor: descriptor) else {
            logService.log(.error, "Failed to create virtual display",
                          detail: "CGVirtualDisplay init returned nil for \(config.name)")
            return false
        }

        // Build display modes
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = config.hiDPI

        var modes: [CGVirtualDisplayMode] = []
        let refreshRates: [Double] = [75.0, 60.0, 50.0, 30.0]

        // Full resolution modes at multiple refresh rates
        for rate in refreshRates {
            modes.append(CGVirtualDisplayMode(
                width: UInt(config.width),
                height: UInt(config.height),
                refreshRate: rate
            ))
        }

        // HiDPI scaled modes (half resolution = 2x scaling)
        if config.hiDPI {
            let halfW = config.width / 2
            let halfH = config.height / 2
            if halfW >= 1, halfH >= 1 {
                for rate in refreshRates {
                    modes.append(CGVirtualDisplayMode(
                        width: UInt(halfW),
                        height: UInt(halfH),
                        refreshRate: rate
                    ))
                }
            }
        }

        settings.modes = modes

        // Apply settings (run on background thread with timeout to avoid WindowServer hang)
        let displayRef = virtualDisplay
        let settingsRef = settings
        let applied = await withTimeout(seconds: 10) {
            displayRef.applySettings(settingsRef)
        }

        guard applied else {
            logService.log(.error, "Failed to apply virtual display settings",
                          detail: "Timeout or failure for \(config.name)")
            return false
        }

        // Verify we got a valid display ID
        let displayID = virtualDisplay.displayID
        guard displayID != kCGNullDirectDisplay else {
            logService.log(.error, "Virtual display has null display ID",
                          detail: config.name)
            return false
        }

        // Store the active display
        activeDisplays[config.id] = virtualDisplay
        activeConfigIDs.insert(config.id)

        logService.log(.screen, "Created virtual display: \(config.name)",
                       detail: "ID: \(displayID), \(config.resolutionLabel) @ \(config.refreshLabel)")
        return true
    }

    // MARK: - Config Management

    func addConfig(_ config: VirtualScreenConfig) {
        configs.append(config)
        persistConfigs()
        logService.log(.screen, "Saved virtual screen config: \(config.name)")
    }

    func addAndCreate(_ config: VirtualScreenConfig) async {
        addConfig(config)
        await createDisplay(config: config)
    }

    func removeConfig(_ id: UUID) {
        let name = configs.first(where: { $0.id == id })?.name ?? "Unknown"
        destroyDisplay(id)
        configs.removeAll { $0.id == id }
        persistConfigs()
        logService.log(.screen, "Removed virtual screen config: \(name)")
    }

    func updateConfig(_ config: VirtualScreenConfig) {
        guard let index = configs.firstIndex(where: { $0.id == config.id }) else { return }
        configs[index] = config
        persistConfigs()
    }

    // MARK: - Destroy Virtual Display

    /// Set by AppState to stop any route streaming a source before it disappears,
    /// so deactivating/deleting a screen cleanly stops its stream instead of
    /// leaving it to die with a scary error (or freeze on the last frame).
    var onSourceWillDeactivate: ((UUID) -> Void)?

    func destroyDisplay(_ id: UUID) {
        guard activeDisplays[id] != nil else { return }
        onSourceWillDeactivate?(id)
        let name = configs.first(where: { $0.id == id })?.name ?? "Unknown"
        // Releasing the reference destroys the virtual display
        activeDisplays.removeValue(forKey: id)
        activeConfigIDs.remove(id)
        logService.log(.screen, "Destroyed virtual display: \(name)")
    }

    func destroyAll() {
        for id in activeConfigIDs { onSourceWillDeactivate?(id) }
        for id in activeConfigIDs {
            activeDisplays.removeValue(forKey: id)
        }
        activeConfigIDs.removeAll()
        logService.log(.screen, "Destroyed all virtual displays")
    }

    func isActive(_ id: UUID) -> Bool {
        activeConfigIDs.contains(id)
    }

    func displayID(for configID: UUID) -> CGDirectDisplayID? {
        activeDisplays[configID]?.displayID
    }

    // MARK: - Persistence

    private func loadConfigs() {
        guard persistence.exists(configsFileName) else { return }
        do {
            configs = try persistence.load([VirtualScreenConfig].self, from: configsFileName)
            logService.log(.screen, "Loaded \(configs.count) virtual screen config(s)")
        } catch {
            logService.log(.error, "Failed to load virtual screen configs",
                          detail: error.localizedDescription)
        }
    }

    private func persistConfigs() {
        do {
            try persistence.save(configs, to: configsFileName)
        } catch {
            logService.log(.error, "Failed to save virtual screen configs",
                          detail: error.localizedDescription)
        }
    }

    // MARK: - Auto-Create on Launch

    private var autoCreateTask: Task<Void, Never>?

    private func autoCreateDisplays() {
        let autoConfigs = configs.filter(\.autoCreateOnLaunch)
        guard !autoConfigs.isEmpty else { return }
        autoCreateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)   // let launch settle
            for config in autoConfigs {
                await createDisplay(config: config)
            }
        }
    }

    /// Awaits the launch auto-create pass so callers (auto-start routes) don't
    /// race it with a fixed sleep. Returns immediately if there was no pass.
    func awaitAutoCreate() async {
        await autoCreateTask?.value
    }

    /// Records a clean exit so the next launch may auto-create (paired with the
    /// crash guard). Call from the app-termination hook.
    func markCleanExit() {
        try? persistence.save(Date(), to: VFConstants.cleanExitMarkerFileName)
    }

    // MARK: - Timeout Helper

    private func withTimeout(seconds: Double, operation: @escaping @Sendable () -> Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            // Guarded by `lock`; the compiler's syntactic @Sendable-capture rule
            // needs the explicit unsafe opt-out.
            nonisolated(unsafe) var didResume = false

            DispatchQueue.global(qos: .userInitiated).async {
                let result = operation()
                lock.lock()
                guard !didResume else { lock.unlock(); return }
                didResume = true
                lock.unlock()
                continuation.resume(returning: result)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                lock.lock()
                guard !didResume else { lock.unlock(); return }
                didResume = true
                lock.unlock()
                continuation.resume(returning: false)
            }
        }
    }
}
