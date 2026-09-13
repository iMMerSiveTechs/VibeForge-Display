import Foundation
import CoreGraphics

struct ScreenInfo: Identifiable, Codable, Sendable {
    let displayID: UInt32
    var name: String
    var isMain: Bool
    var isBuiltIn: Bool
    var boundsWidth: Int
    var boundsHeight: Int
    var pixelWidth: Int
    var pixelHeight: Int
    var refreshRate: Double
    var scaleFactor: Double
    var rotation: Double
    var availableModeCount: Int

    var id: UInt32 { displayID }

    var resolutionLabel: String {
        "\(pixelWidth) x \(pixelHeight)"
    }

    var boundsLabel: String {
        "\(boundsWidth) x \(boundsHeight) pt"
    }

    var refreshLabel: String {
        if refreshRate > 0 {
            return String(format: "%.0f Hz", refreshRate)
        }
        return "Unknown"
    }

    var scaleLabel: String {
        if scaleFactor == 2.0 {
            return "Retina (2x)"
        } else if scaleFactor == 1.0 {
            return "Standard (1x)"
        }
        return String(format: "%.1fx", scaleFactor)
    }

    var displayTypeLabel: String {
        isBuiltIn ? "Built-in" : "External"
    }
}
