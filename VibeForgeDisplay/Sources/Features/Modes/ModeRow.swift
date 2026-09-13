import SwiftUI

struct ModeRow: View {
    let mode: Mode
    let onRestore: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: VFTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
                HStack(spacing: VFTheme.Spacing.sm) {
                    Text(mode.name)
                        .font(VFTheme.Typography.headline)
                        .foregroundStyle(VFTheme.Colors.textPrimary)
                    Text(mode.timeLabel)
                        .font(VFTheme.Typography.caption)
                        .foregroundStyle(VFTheme.Colors.textTertiary)
                }

                Text(mode.screenSummary)
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
                    .lineLimit(1)

                if !mode.notes.isEmpty {
                    Text(mode.notes)
                        .font(VFTheme.Typography.caption)
                        .foregroundStyle(VFTheme.Colors.textTertiary)
                        .lineLimit(2)
                }

                HStack(spacing: VFTheme.Spacing.sm) {
                    Label("\(mode.screens.count) screen(s)", systemImage: "display")
                    if !mode.surfacePreferences.isEmpty {
                        Label("\(mode.surfacePreferences.count) surface(s)", systemImage: "rectangle.on.rectangle.angled")
                    }
                }
                .font(VFTheme.Typography.caption)
                .foregroundStyle(VFTheme.Colors.textTertiary)
            }

            Spacer()

            HStack(spacing: VFTheme.Spacing.sm) {
                Button("Check", action: onRestore)
                    .buttonStyle(.borderedProminent)
                    .tint(VFTheme.Colors.accent)
                    .controlSize(.small)

                Button(action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash")
                        .foregroundStyle(VFTheme.Colors.error)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Delete mode \(mode.name)")
                .confirmationDialog("Delete mode “\(mode.name)”?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                    Button("Delete", role: .destructive, action: onDelete)
                    Button("Cancel", role: .cancel) { }
                }
            }
        }
        .padding(VFTheme.Spacing.md)
        .background(isHovering ? VFTheme.Colors.surfaceHover : VFTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: VFTheme.Radius.md)
                .stroke(VFTheme.Colors.border, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}
