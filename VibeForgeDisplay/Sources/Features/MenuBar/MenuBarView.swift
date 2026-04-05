import SwiftUI

struct MenuBarView: View {
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            screensSummary
            Divider()
            virtualDisplaysSummary
            Divider()
            recentEventSection
            Divider()
            actionsSection
        }
        .frame(width: 300)
    }

    private var headerSection: some View {
        HStack(spacing: VFTheme.Spacing.sm) {
            Image(systemName: "rectangle.on.rectangle")
                .foregroundStyle(VFTheme.Colors.accent)
            Text("VibeForge Display")
                .font(VFTheme.Typography.headline)
            Spacer()
            Text("v\(VFConstants.appVersion)")
                .font(VFTheme.Typography.caption)
                .foregroundStyle(VFTheme.Colors.textTertiary)
        }
        .padding(VFTheme.Spacing.md)
    }

    private var screensSummary: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
            Label("\(appState.screenService.screens.count) Screen(s) Connected", systemImage: "display")
                .font(VFTheme.Typography.body)
            ForEach(appState.screenService.screens.prefix(4)) { screen in
                HStack(spacing: VFTheme.Spacing.xs) {
                    Circle()
                        .fill(screen.isMain ? VFTheme.Colors.accent : VFTheme.Colors.textTertiary)
                        .frame(width: 5, height: 5)
                    Text(screen.name)
                        .font(VFTheme.Typography.caption)
                        .foregroundStyle(VFTheme.Colors.textSecondary)
                    Spacer()
                    Text(screen.resolutionLabel)
                        .font(VFTheme.Typography.mono)
                        .foregroundStyle(VFTheme.Colors.textTertiary)
                }
            }
        }
        .padding(VFTheme.Spacing.md)
    }

    private var virtualDisplaysSummary: some View {
        let total = appState.virtualDisplayService.configs.count
        let active = appState.virtualDisplayService.activeConfigIDs.count
        return VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
            HStack(spacing: VFTheme.Spacing.xs) {
                Label("\(total) Virtual Screen(s)", systemImage: "plus.display")
                    .font(VFTheme.Typography.body)
                Spacer()
                if active > 0 {
                    HStack(spacing: VFTheme.Spacing.xxs) {
                        Circle()
                            .fill(VFTheme.Colors.success)
                            .frame(width: 6, height: 6)
                        Text("\(active) active")
                            .font(VFTheme.Typography.caption)
                            .foregroundStyle(VFTheme.Colors.success)
                    }
                }
            }

            ForEach(appState.virtualDisplayService.configs.prefix(3)) { config in
                HStack(spacing: VFTheme.Spacing.xs) {
                    Circle()
                        .fill(appState.virtualDisplayService.isActive(config.id)
                              ? VFTheme.Colors.success : VFTheme.Colors.textTertiary)
                        .frame(width: 5, height: 5)
                    Text(config.name)
                        .font(VFTheme.Typography.caption)
                        .foregroundStyle(VFTheme.Colors.textSecondary)
                    Spacer()
                    Text(config.resolutionLabel)
                        .font(VFTheme.Typography.mono)
                        .foregroundStyle(VFTheme.Colors.textTertiary)
                }
            }
        }
        .padding(VFTheme.Spacing.md)
    }

    private var recentEventSection: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
            if let latest = appState.logService.latestMessage {
                HStack(spacing: VFTheme.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(VFTheme.Colors.textTertiary)
                    Text(latest)
                        .font(VFTheme.Typography.caption)
                        .foregroundStyle(VFTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
            } else {
                Text("No recent activity")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textTertiary)
            }
        }
        .padding(VFTheme.Spacing.md)
    }

    private var actionsSection: some View {
        VStack(spacing: VFTheme.Spacing.xs) {
            Button("Open VibeForge Display") {
                openMainWindow()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(VFTheme.Typography.caption)
            .foregroundStyle(VFTheme.Colors.textTertiary)
        }
        .padding(VFTheme.Spacing.md)
    }

    private func openMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: { $0.title == "VibeForge Display" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
