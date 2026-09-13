import SwiftUI

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: VFTheme.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(VFTheme.Colors.accent)
            Text(title)
                .font(VFTheme.Typography.title)
                .foregroundStyle(VFTheme.Colors.textPrimary)
        }
    }
}
