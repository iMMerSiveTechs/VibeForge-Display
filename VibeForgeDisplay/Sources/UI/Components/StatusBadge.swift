import SwiftUI

struct StatusBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(VFTheme.Typography.caption)
            .foregroundStyle(color)
            .padding(.horizontal, VFTheme.Spacing.sm)
            .padding(.vertical, VFTheme.Spacing.xxs)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.sm))
    }
}
