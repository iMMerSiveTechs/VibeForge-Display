import Foundation

struct DisplayModeInfo: Identifiable, Codable, Sendable {
    let width: Int
    let height: Int
    let refreshRate: Double
    let isUsableForDesktop: Bool

    // Deterministic ID based on mode properties to avoid ForEach identity churn
    var id: String {
        "\(width)x\(height)@\(refreshRate)_\(isUsableForDesktop)"
    }

    var label: String {
        var parts = ["\(width) x \(height)"]
        if refreshRate > 0 {
            parts.append(String(format: "@ %.0f Hz", refreshRate))
        }
        return parts.joined(separator: " ")
    }

    init(width: Int, height: Int, refreshRate: Double, isUsableForDesktop: Bool) {
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
        self.isUsableForDesktop = isUsableForDesktop
    }
}
