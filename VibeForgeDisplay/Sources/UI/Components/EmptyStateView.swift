import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionLabel: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: VFTheme.Spacing.lg) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(VFTheme.Colors.textTertiary)
            Text(title)
                .font(VFTheme.Typography.title)
                .foregroundStyle(VFTheme.Colors.textPrimary)
            Text(message)
                .font(VFTheme.Typography.body)
                .foregroundStyle(VFTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let actionLabel {
                Button(action: action) {
                    Text(actionLabel)
                }
                .buttonStyle(.borderedProminent)
                .tint(VFTheme.Colors.accent)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
