import SwiftUI

struct MenuBarView: View {
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            screensSummary
            Divider()
            surfacesSummary
            Divider()
            recentEventSection
            Divider()
            actionsSection
        }
        .frame(width: 280)
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
            ForEach(appState.screenService.screens.prefix(3)) { screen in
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

    private var surfacesSummary: some View {
        let configs = appState.surfaceService.configs
        let openCount = configs.filter(\.isOpen).count
        return VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
            Label("\(configs.count) Surface(s), \(openCount) open", systemImage: "rectangle.on.rectangle.angled")
                .font(VFTheme.Typography.body)
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
