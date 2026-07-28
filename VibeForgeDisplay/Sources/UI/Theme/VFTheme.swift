import SwiftUI

enum VFTheme {

    // MARK: - Colors

    enum Colors {
        static let background = Color(nsColor: .init(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0))
        static let surface = Color(nsColor: .init(red: 0.12, green: 0.12, blue: 0.15, alpha: 1.0))
        static let surfaceHover = Color(nsColor: .init(red: 0.16, green: 0.16, blue: 0.20, alpha: 1.0))
        static let border = Color(nsColor: .init(red: 0.22, green: 0.22, blue: 0.26, alpha: 1.0))

        static let textPrimary = Color(nsColor: .init(red: 0.93, green: 0.93, blue: 0.95, alpha: 1.0))
        static let textSecondary = Color(nsColor: .init(red: 0.60, green: 0.60, blue: 0.65, alpha: 1.0))
        static let textTertiary = Color(nsColor: .init(red: 0.40, green: 0.40, blue: 0.45, alpha: 1.0))

        static let accent = Color(nsColor: .init(red: 0.35, green: 0.55, blue: 0.90, alpha: 1.0))
        static let accentHover = Color(nsColor: .init(red: 0.45, green: 0.65, blue: 1.0, alpha: 1.0))
        static let accentSubtle = Color(nsColor: .init(red: 0.35, green: 0.55, blue: 0.90, alpha: 0.15))

        static let success = Color(nsColor: .init(red: 0.30, green: 0.75, blue: 0.50, alpha: 1.0))
        static let warning = Color(nsColor: .init(red: 0.90, green: 0.70, blue: 0.25, alpha: 1.0))
        static let error = Color(nsColor: .init(red: 0.85, green: 0.30, blue: 0.35, alpha: 1.0))
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner Radius

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
    }

    // MARK: - Typography

    enum Typography {
        static let largeTitle = Font.system(size: 22, weight: .semibold, design: .default)
        static let title = Font.system(size: 17, weight: .semibold, design: .default)
        static let headline = Font.system(size: 14, weight: .medium, design: .default)
        static let body = Font.system(size: 13, weight: .regular, design: .default)
        static let caption = Font.system(size: 11, weight: .regular, design: .default)
        static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    }

    // MARK: - Window

    enum Window {
        static let minWidth: CGFloat = 720
        static let minHeight: CGFloat = 500
        static let defaultWidth: CGFloat = 860
        static let defaultHeight: CGFloat = 600
        static let sidebarWidth: CGFloat = 200
    }
}
