import Foundation
import CoreGraphics

// CGVirtualDisplay extensions for Sendable compliance
extension CGVirtualDisplayDescriptor: @unchecked @retroactive Sendable {}
extension CGVirtualDisplay: @unchecked @retroactive Sendable {}
extension CGVirtualDisplaySettings: @unchecked @retroactive Sendable {}

@MainActor
@Observable
final class VirtualDisplayService {
    private(set) var configs: [VirtualScreenConfig] = []
    private(set) var activeConfigIDs: Set<UUID> = []
    private var activeDisplays: [UUID: CGVirtualDisplay] = [:]
    private let persistence: PersistenceManager
    private let logService: LogService
    private let configsFileName = "virtual_screens.json"

    // Standard PPI for physical size calculation
    private let standardPPI: Double = 110.0
    // Equivalent to a 27-inch display for safe pixel density
    private let physicalWidth27Inch: Double = 597.0
    private let physicalHeight27Inch: Double = 336.0

    init(persistence: PersistenceManager, logService: LogService) {
        self.persistence = persistence
        self.logService = logService
        loadConfigs()
        autoCreateDisplays()
    }

    // MARK: - Create Virtual Display

    @discardableResult
    func createDisplay(config: VirtualScreenConfig) async -> Bool {
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

        // Non-zero vendor/product IDs required
        descriptor.vendorID = 0xEEEE
        descriptor.productID = 0x0001
        descriptor.serialNum = UInt32(config.id.hashValue & 0xFFFF)

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

    func destroyDisplay(_ id: UUID) {
        guard activeDisplays[id] != nil else { return }
        let name = configs.first(where: { $0.id == id })?.name ?? "Unknown"
        // Releasing the reference destroys the virtual display
        activeDisplays.removeValue(forKey: id)
        activeConfigIDs.remove(id)
        logService.log(.screen, "Destroyed virtual display: \(name)")
    }

    func destroyAll() {
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

    private func autoCreateDisplays() {
        let autoConfigs = configs.filter(\.autoCreateOnLaunch)
        guard !autoConfigs.isEmpty else { return }
        Task { @MainActor in
            // Small delay to let the app finish launching
            try? await Task.sleep(nanoseconds: 800_000_000)
            for config in autoConfigs {
                await createDisplay(config: config)
            }
        }
    }

    // MARK: - Timeout Helper

    private func withTimeout(seconds: Double, operation: @escaping @Sendable () -> Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false

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
