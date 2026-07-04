import SwiftUI

@main
struct VibeForgeDisplayApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        // Menu bar icon and dropdown
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            // Custom label so we can open the main window on very first launch —
            // an LSUIElement app doesn't auto-open its Window scene, which would
            // otherwise hide onboarding (and its honesty disclosures) forever.
            MenuBarLabel(activeCount: appState.streamService.streamingRouteIDs.count
                         + appState.virtualDisplayService.activeConfigIDs.count)
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

// MARK: - Menu bar label (also the first-launch onboarding opener)

private struct MenuBarLabel: View {
    let activeCount: Int
    @Environment(\.openWindow) private var openWindow
    @AppStorage("vf.onboarded") private var onboarded = false
    @State private var didOpenForOnboarding = false

    var body: some View {
        // Show a count only when something is actually active (streams/virtual
        // screens); a bare physical-screen count read as a meaningless badge.
        Group {
            if activeCount > 0 {
                Label("\(activeCount)", systemImage: VFConstants.MenuBar.iconName)
            } else {
                Image(systemName: VFConstants.MenuBar.iconName)
            }
        }
        .onAppear {
            // The menu-bar label renders at launch even for an accessory app, so
            // this is our reliable hook to surface the window + onboarding once.
            guard !onboarded, !didOpenForOnboarding else { return }
            didOpenForOnboarding = true
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Main Window

struct MainWindowView: View {
    @Bindable var appState: AppState
    @AppStorage("vf.onboarded") private var onboarded = false

    var body: some View {
        NavigationSplitView {
            SidebarNavigation(appState: appState)
        } detail: {
            detailView
        }
        .background(VFTheme.Colors.background)
        // Setter is a no-op: onboarding is completed only via onDone, so a
        // programmatic dismissal (e.g. the window closing) can't mark it seen.
        .sheet(isPresented: Binding(get: { !onboarded }, set: { _ in })) {
            OnboardingView(onDone: { onboarded = true })
                .interactiveDismissDisabled(true)
        }
        // The theme is hard-coded dark; pin the scheme so native controls
        // (text fields, pickers, alerts) don't clash in system light mode.
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedTab {
        case .screens:
            ScreensView(
                screenService: appState.screenService,
                logService: appState.logService
            )
        case .virtualScreens:
            VirtualDisplaysView(
                virtualDisplayService: appState.virtualDisplayService,
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
        case .routes:
            RoutesView(
                streamService: appState.streamService,
                virtualDisplayService: appState.virtualDisplayService,
                surfaceService: appState.surfaceService,
                wallPresetService: appState.wallPresetService,
                hlsServer: appState.hlsServer,
                logService: appState.logService
            )
        case .logs:
            LogsView(
                logService: appState.logService,
                screenService: appState.screenService,
                surfaceService: appState.surfaceService,
                virtualDisplayService: appState.virtualDisplayService,
                streamService: appState.streamService,
                hlsServer: appState.hlsServer
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
                infoRow("Virtual Screens", "\(appState.virtualDisplayService.configs.count) (\(appState.virtualDisplayService.activeConfigIDs.count) active)")
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
            SectionHeader(title: "How It Works", icon: "info.circle")

            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                limitRow("Virtual screens use macOS display APIs to create additional monitors")
                limitRow("They appear in System Settings > Displays as real screens")
                limitRow("Wired TVs use HDMI/display arrangement; wireless TVs use Routes (VibeForge's own stream, not Apple AirPlay)")
                limitRow("Surfaces are app-managed utility workspaces with widgets")
                limitRow("Routes stream over VibeForge's own transport, not Apple AirPlay")
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
