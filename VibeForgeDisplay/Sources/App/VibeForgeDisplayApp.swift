import SwiftUI

@main
struct VibeForgeDisplayApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        // Menu bar icon and dropdown
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Label(
                "\(appState.screenService.screens.count)",
                systemImage: VFConstants.MenuBar.iconName
            )
        }
        .menuBarExtraStyle(.window)

        // Main settings/control window
        Window("VibeForge Display", id: "main") {
            MainWindowView(appState: appState)
                .frame(
                    minWidth: VFTheme.Window.minWidth,
                    minHeight: VFTheme.Window.minHeight
                )
        }
        .defaultSize(
            width: VFTheme.Window.defaultWidth,
            height: VFTheme.Window.defaultHeight
        )
        .windowStyle(.hiddenTitleBar)
    }
}

// MARK: - Main Window

struct MainWindowView: View {
    @Bindable var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarNavigation(appState: appState)
        } detail: {
            detailView
        }
        .background(VFTheme.Colors.background)
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedTab {
        case .screens:
            ScreensView(
                screenService: appState.screenService,
                logService: appState.logService
            )
        case .modes:
            ModesView(
                modeService: appState.modeService,
                screenService: appState.screenService,
                surfaceService: appState.surfaceService,
                logService: appState.logService
            )
        case .surfaces:
            SurfacesView(
                surfaceService: appState.surfaceService,
                screenService: appState.screenService,
                logService: appState.logService
            )
        case .logs:
            LogsView(
                logService: appState.logService,
                screenService: appState.screenService,
                surfaceService: appState.surfaceService
            )
        case .settings:
            SettingsView(appState: appState)
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(VFTheme.Colors.border)
            ScrollView {
                VStack(alignment: .leading, spacing: VFTheme.Spacing.xl) {
                    aboutSection
                    dataSection
                    limitsSection
                }
                .padding(VFTheme.Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VFTheme.Colors.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
            Text("Settings")
                .font(VFTheme.Typography.largeTitle)
                .foregroundStyle(VFTheme.Colors.textPrimary)
            Text("App configuration and information")
                .font(VFTheme.Typography.caption)
                .foregroundStyle(VFTheme.Colors.textSecondary)
        }
        .padding(VFTheme.Spacing.xl)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.md) {
            SectionHeader(title: "About", icon: "info.circle")

            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                infoRow("Product", VFConstants.appName)
                infoRow("Version", VFConstants.appVersion)
                infoRow("Bundle ID", VFConstants.bundleIdentifier)
                infoRow("Data Directory", VFConstants.appSupportURL.path)
            }
            .padding(VFTheme.Spacing.md)
            .background(VFTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.md) {
            SectionHeader(title: "Data", icon: "externaldrive")

            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                infoRow("Saved Modes", "\(appState.modeService.modes.count)")
                infoRow("Surfaces", "\(appState.surfaceService.configs.count)")
                infoRow("Log Entries", "\(appState.logService.entries.count)")
            }
            .padding(VFTheme.Spacing.md)
            .background(VFTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
        }
    }

    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.md) {
            SectionHeader(title: "Honest Limits", icon: "exclamationmark.triangle")

            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                limitRow("Surfaces are app-managed workspaces, not real hardware displays")
                limitRow("Display configuration uses public macOS APIs only")
                limitRow("No hardware bypass, fake clamshell, or driver-level overrides")
                limitRow("Streaming and routing are planned for a future update")
            }
            .padding(VFTheme.Spacing.md)
            .background(VFTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(VFTheme.Typography.body)
                .foregroundStyle(VFTheme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(VFTheme.Typography.mono)
                .foregroundStyle(VFTheme.Colors.textPrimary)
                .textSelection(.enabled)
        }
    }

    private func limitRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: VFTheme.Spacing.sm) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(VFTheme.Colors.success)
                .padding(.top, 2)
            Text(text)
                .font(VFTheme.Typography.body)
                .foregroundStyle(VFTheme.Colors.textSecondary)
        }
    }
}
