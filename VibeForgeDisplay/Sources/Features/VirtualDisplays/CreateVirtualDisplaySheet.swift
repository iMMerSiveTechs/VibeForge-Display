import SwiftUI

struct CreateVirtualDisplaySheet: View {
    let virtualDisplayService: VirtualDisplayService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedPreset: VirtualScreenPreset = .hd1080
    @State private var customWidth = "1920"
    @State private var customHeight = "1080"
    @State private var refreshRate = 60.0
    @State private var hiDPI = true
    @State private var autoCreate = true
    @State private var useCustom = false
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.xl) {
            Text("Add Virtual Screen")
                .font(VFTheme.Typography.largeTitle)
                .foregroundStyle(VFTheme.Colors.textPrimary)

            // Name
            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                Text("Display Name")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
                TextField("e.g. TV2, Side Monitor", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            // Resolution
            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                HStack {
                    Text("Resolution")
                        .font(VFTheme.Typography.headline)
                        .foregroundStyle(VFTheme.Colors.textSecondary)
                    Spacer()
                    Toggle("Custom", isOn: $useCustom)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                if useCustom {
                    HStack(spacing: VFTheme.Spacing.sm) {
                        TextField("Width", text: $customWidth)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("x")
                            .foregroundStyle(VFTheme.Colors.textTertiary)
                        TextField("Height", text: $customHeight)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("px")
                            .font(VFTheme.Typography.caption)
                            .foregroundStyle(VFTheme.Colors.textTertiary)
                    }
                } else {
                    HStack(spacing: VFTheme.Spacing.sm) {
                        ForEach(VirtualScreenPreset.allCases) { preset in
                            presetButton(preset)
                        }
                    }
                }
            }

            // Options
            VStack(alignment: .leading, spacing: VFTheme.Spacing.md) {
                Text("Options")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textSecondary)

                HStack {
                    Text("Refresh Rate")
                        .font(VFTheme.Typography.body)
                        .foregroundStyle(VFTheme.Colors.textPrimary)
                    Spacer()
                    Picker("", selection: $refreshRate) {
                        Text("30 Hz").tag(30.0)
                        Text("50 Hz").tag(50.0)
                        Text("60 Hz").tag(60.0)
                        Text("75 Hz").tag(75.0)
                    }
                    .frame(width: 120)
                }

                Toggle("HiDPI (Retina scaling)", isOn: $hiDPI)
                    .font(VFTheme.Typography.body)
                    .foregroundStyle(VFTheme.Colors.textPrimary)

                Toggle("Auto-create on app launch", isOn: $autoCreate)
                    .font(VFTheme.Typography.body)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
            }
            .padding(VFTheme.Spacing.md)
            .background(VFTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))

            // How it works
            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                Label("How Virtual Screens Work", systemImage: "info.circle")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textSecondary)

                VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
                    infoRow("1.", "A virtual display is created that macOS treats as a real monitor")
                    infoRow("2.", "It appears in System Settings > Displays alongside your real screens")
                    infoRow("3.", "You can arrange it and extend your desktop to it")
                    infoRow("4.", "Use AirPlay or HDMI to show the virtual display on your TV")
                }
            }
            .padding(VFTheme.Spacing.md)
            .background(VFTheme.Colors.accentSubtle)
            .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))

            // Actions
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Button(action: create) {
                    if isCreating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Create & Activate")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(VFTheme.Colors.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(resolvedName.isEmpty || isCreating)
            }
        }
        .padding(VFTheme.Spacing.xl)
        .frame(width: 500)
        .background(VFTheme.Colors.background)
    }

    private func presetButton(_ preset: VirtualScreenPreset) -> some View {
        let isSelected = selectedPreset == preset
        return VStack(spacing: VFTheme.Spacing.xs) {
            Text(preset.rawValue)
                .font(VFTheme.Typography.headline)
                .foregroundStyle(isSelected ? VFTheme.Colors.textPrimary : VFTheme.Colors.textSecondary)
            Text("\(preset.width) x \(preset.height)")
                .font(VFTheme.Typography.mono)
                .foregroundStyle(VFTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(VFTheme.Spacing.md)
        .background(isSelected ? VFTheme.Colors.accentSubtle : VFTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: VFTheme.Radius.md)
                .stroke(isSelected ? VFTheme.Colors.accent : VFTheme.Colors.border, lineWidth: 1)
        )
        .onTapGesture { selectedPreset = preset }
    }

    private func infoRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: VFTheme.Spacing.xs) {
            Text(number)
                .font(VFTheme.Typography.caption)
                .foregroundStyle(VFTheme.Colors.accent)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(VFTheme.Typography.caption)
                .foregroundStyle(VFTheme.Colors.textSecondary)
        }
    }

    private var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? selectedPreset.rawValue : trimmed
    }

    private var resolvedWidth: Int {
        if useCustom, let w = Int(customWidth), w > 0 { return w }
        return selectedPreset.width
    }

    private var resolvedHeight: Int {
        if useCustom, let h = Int(customHeight), h > 0 { return h }
        return selectedPreset.height
    }

    private func create() {
        isCreating = true
        let config = VirtualScreenConfig(
            name: resolvedName,
            width: resolvedWidth,
            height: resolvedHeight,
            refreshRate: refreshRate,
            hiDPI: hiDPI,
            autoCreateOnLaunch: autoCreate
        )
        Task {
            await virtualDisplayService.addAndCreate(config)
            isCreating = false
            dismiss()
        }
    }
}
