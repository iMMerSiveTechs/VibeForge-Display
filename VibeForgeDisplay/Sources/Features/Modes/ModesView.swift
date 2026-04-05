import SwiftUI

struct ModesView: View {
    let modeService: ModeService
    let screenService: ScreenService
    let surfaceService: SurfaceService
    let logService: LogService

    @State private var showSaveSheet = false
    @State private var restoreResult: ModeService.RestoreResult?
    @State private var showRestoreAlert = false
    @State private var searchText = ""

    var filteredModes: [Mode] {
        if searchText.isEmpty { return modeService.modes }
        return modeService.modes.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(VFTheme.Colors.border)
            modesList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VFTheme.Colors.background)
        .sheet(isPresented: $showSaveSheet) {
            SaveModeSheet(
                modeService: modeService,
                screenService: screenService,
                surfaceService: surfaceService
            )
        }
        .alert("Mode Restored", isPresented: $showRestoreAlert) {
            Button("OK") { restoreResult = nil }
        } message: {
            if let result = restoreResult {
                let restoredText = result.restoredItems.joined(separator: "\n")
                let manualText = result.manualItems.isEmpty
                    ? ""
                    : "\n\nManual action needed:\n" + result.manualItems.joined(separator: "\n")
                Text(restoredText + manualText)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
                Text("Modes")
                    .font(VFTheme.Typography.largeTitle)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                Text("Save and restore your screen setup presets")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
            }
            Spacer()
            Button(action: { showSaveSheet = true }) {
                Label("Save Current Mode", systemImage: "plus.rectangle")
                    .font(VFTheme.Typography.caption)
            }
            .buttonStyle(.borderedProminent)
            .tint(VFTheme.Colors.accent)
        }
        .padding(VFTheme.Spacing.xl)
    }

    @ViewBuilder
    private var modesList: some View {
        if modeService.modes.isEmpty {
            EmptyStateView(
                icon: "slider.horizontal.3",
                title: "No Modes Saved Yet",
                message: "Save your current setup as a Mode so you can return to it later without rebuilding everything from scratch.",
                actionLabel: "Save Current Mode",
                action: { showSaveSheet = true }
            )
        } else {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(VFTheme.Colors.textTertiary)
                    TextField("Search modes...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(VFTheme.Typography.body)
                }
                .padding(VFTheme.Spacing.sm)
                .background(VFTheme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
                .padding(.horizontal, VFTheme.Spacing.xl)
                .padding(.top, VFTheme.Spacing.md)

                ScrollView {
                    LazyVStack(spacing: VFTheme.Spacing.sm) {
                        ForEach(filteredModes) { mode in
                            ModeRow(
                                mode: mode,
                                onRestore: { restoreMode(mode) },
                                onDelete: { modeService.deleteMode(mode) }
                            )
                        }
                    }
                    .padding(VFTheme.Spacing.xl)
                }
            }
        }
    }

    private func restoreMode(_ mode: Mode) {
        restoreResult = modeService.restoreMode(mode, currentScreens: screenService.screens)
        showRestoreAlert = true
    }
}
