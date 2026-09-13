import SwiftUI

struct SurfaceSettingsView: View {
    let surfaceID: UUID
    let surfaceService: SurfaceService
    let screenService: ScreenService

    private var config: SurfaceConfig? {
        surfaceService.configs.first(where: { $0.id == surfaceID })
    }

    @State private var name: String = ""
    @State private var opacity: Double = 1.0
    @State private var alwaysOnTop: Bool = false
    @State private var selectedPreset: SurfacePreset = .landscape
    @State private var targetScreenID: UInt32? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.lg) {
            SectionHeader(title: "Surface Settings", icon: "rectangle.on.rectangle.angled")

            VStack(alignment: .leading, spacing: VFTheme.Spacing.md) {
                // Name
                VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
                    Text("Name")
                        .font(VFTheme.Typography.caption)
                        .foregroundStyle(VFTheme.Colors.textTertiary)
                    TextField("Surface name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: name) { _, _ in updateConfig() }
                }

                // Preset
                VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
                    Text("Size Preset")
                        .font(VFTheme.Typography.caption)
                        .foregroundStyle(VFTheme.Colors.textTertiary)
                    Picker("", selection: $selectedPreset) {
                        ForEach(SurfacePreset.allCases) { preset in
                            Label(preset.rawValue, systemImage: preset.icon).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedPreset) { _, newPreset in
                        guard var updated = config else { return }
                        updated.preset = newPreset
                        updated.frameWidth = newPreset.size.width
                        updated.frameHeight = newPreset.size.height
                        surfaceService.updateConfig(updated)
                    }
                }

                // Opacity
                VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
                    HStack {
                        Text("Opacity")
                            .font(VFTheme.Typography.caption)
                            .foregroundStyle(VFTheme.Colors.textTertiary)
                        Spacer()
                        Text(String(format: "%.0f%%", opacity * 100))
                            .font(VFTheme.Typography.mono)
                            .foregroundStyle(VFTheme.Colors.textSecondary)
                    }
                    Slider(value: $opacity, in: 0.2...1.0, step: 0.05)
                        .onChange(of: opacity) { _, _ in updateConfig() }
                }

                // Always on top
                Toggle("Always on Top", isOn: $alwaysOnTop)
                    .font(VFTheme.Typography.body)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                    .onChange(of: alwaysOnTop) { _, _ in updateConfig() }

                // Target screen
                VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
                    Text("Snap to Screen")
                        .font(VFTheme.Typography.caption)
                        .foregroundStyle(VFTheme.Colors.textTertiary)
                    Picker("", selection: $targetScreenID) {
                        Text("None").tag(nil as UInt32?)
                        ForEach(screenService.screens) { screen in
                            Text(screen.name).tag(screen.displayID as UInt32?)
                        }
                    }
                    .onChange(of: targetScreenID) { _, _ in updateConfig() }
                }
            }
            .padding(VFTheme.Spacing.md)
            .background(VFTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: VFTheme.Radius.md)
                    .stroke(VFTheme.Colors.border, lineWidth: 1)
            )
        }
        .onAppear { loadFromConfig() }
    }

    private func loadFromConfig() {
        guard let config else { return }
        name = config.name
        opacity = config.opacity
        alwaysOnTop = config.alwaysOnTop
        selectedPreset = config.preset
        targetScreenID = config.targetScreenID
    }

    private func updateConfig() {
        guard var updated = config else { return }
        updated.name = name
        updated.opacity = opacity
        updated.alwaysOnTop = alwaysOnTop
        updated.targetScreenID = targetScreenID
        surfaceService.updateConfig(updated)
    }
}
