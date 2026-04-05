import SwiftUI

struct ScreenDetailCard: View {
    let screen: ScreenInfo
    let screenService: ScreenService
    @State private var showModes = false

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.md) {
            cardHeader
            Divider().background(VFTheme.Colors.border)
            detailGrid
            if showModes {
                Divider().background(VFTheme.Colors.border)
                modesSection
            }
        }
        .padding(VFTheme.Spacing.lg)
        .background(VFTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: VFTheme.Radius.lg)
                .stroke(VFTheme.Colors.border, lineWidth: 1)
        )
    }

    private var cardHeader: some View {
        HStack(spacing: VFTheme.Spacing.md) {
            Image(systemName: screen.isBuiltIn ? "laptopcomputer" : "display")
                .font(.system(size: 24))
                .foregroundStyle(VFTheme.Colors.accent)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: VFTheme.Spacing.xxs) {
                HStack(spacing: VFTheme.Spacing.sm) {
                    Text(screen.name)
                        .font(VFTheme.Typography.title)
                        .foregroundStyle(VFTheme.Colors.textPrimary)
                    if screen.isMain {
                        StatusBadge(label: "Main", color: VFTheme.Colors.accent)
                    }
                    StatusBadge(label: screen.displayTypeLabel, color: VFTheme.Colors.textTertiary)
                }
                Text("ID: \(screen.displayID)")
                    .font(VFTheme.Typography.mono)
                    .foregroundStyle(VFTheme.Colors.textTertiary)
            }

            Spacer()

            Button(action: { showModes.toggle() }) {
                Text(showModes ? "Hide Modes" : "Show Modes (\(screen.availableModeCount))")
                    .font(VFTheme.Typography.caption)
            }
            .buttonStyle(.bordered)
        }
    }

    private var detailGrid: some View {
        let rows: [(String, String)] = [
            ("Resolution", screen.resolutionLabel),
            ("Bounds", screen.boundsLabel),
            ("Refresh Rate", screen.refreshLabel),
            ("Scale", screen.scaleLabel),
            ("Rotation", screen.rotation == 0 ? "None" : "\(Int(screen.rotation))°"),
        ]

        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: VFTheme.Spacing.md),
            GridItem(.flexible(), spacing: VFTheme.Spacing.md),
            GridItem(.flexible(), spacing: VFTheme.Spacing.md),
        ], spacing: VFTheme.Spacing.md) {
            ForEach(rows, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: VFTheme.Spacing.xxs) {
                    Text(label)
                        .font(VFTheme.Typography.caption)
                        .foregroundStyle(VFTheme.Colors.textTertiary)
                    Text(value)
                        .font(VFTheme.Typography.headline)
                        .foregroundStyle(VFTheme.Colors.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var modesSection: some View {
        let modes = screenService.availableModes(for: screen.displayID)
        return VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
            Text("Available Display Modes")
                .font(VFTheme.Typography.headline)
                .foregroundStyle(VFTheme.Colors.textSecondary)

            if modes.isEmpty {
                Text("No modes available")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textTertiary)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: VFTheme.Spacing.xs) {
                    ForEach(modes) { mode in
                        HStack(spacing: VFTheme.Spacing.xs) {
                            Circle()
                                .fill(mode.isUsableForDesktop ? VFTheme.Colors.success : VFTheme.Colors.textTertiary)
                                .frame(width: 6, height: 6)
                            Text(mode.label)
                                .font(VFTheme.Typography.mono)
                                .foregroundStyle(VFTheme.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}
