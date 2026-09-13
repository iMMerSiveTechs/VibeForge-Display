import SwiftUI

struct CreateRouteSheet: View {
    let routeService: RouteService
    let virtualDisplayService: VirtualDisplayService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedSourceID: UUID?
    @State private var selectedProtocol: StreamProtocol = .mjpeg
    @State private var selectedQuality: StreamQuality = .balanced
    @State private var port: String = "7867"
    @State private var maxFPS = 30
    @State private var inputRelay = true
    @State private var autoStart = false

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.xl) {
            Text("Add Route")
                .font(VFTheme.Typography.largeTitle)
                .foregroundStyle(VFTheme.Colors.textPrimary)

            // Name
            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                Text("Route Name")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
                TextField("e.g. iPad Pro, Living Room TV", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            // Source Display
            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                Text("Source Virtual Screen")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textSecondary)

                if virtualDisplayService.configs.isEmpty {
                    HStack(spacing: VFTheme.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(VFTheme.Colors.warning)
                        Text("No virtual screens configured. Create one first, or the route will capture your primary display.")
                            .font(VFTheme.Typography.caption)
                            .foregroundStyle(VFTheme.Colors.warning)
                    }
                    .padding(VFTheme.Spacing.md)
                    .background(VFTheme.Colors.warning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
                } else {
                    VStack(spacing: VFTheme.Spacing.xs) {
                        ForEach(virtualDisplayService.configs) { config in
                            sourceRow(config)
                        }
                    }
                }
            }

            // Settings
            VStack(alignment: .leading, spacing: VFTheme.Spacing.md) {
                Text("Stream Settings")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textSecondary)

                HStack {
                    Text("Protocol")
                        .font(VFTheme.Typography.body)
                        .foregroundStyle(VFTheme.Colors.textPrimary)
                    Spacer()
                    Picker("", selection: $selectedProtocol) {
                        ForEach(StreamProtocol.allCases) { proto in
                            Text(proto.rawValue).tag(proto)
                        }
                    }
                    .frame(width: 140)
                }

                HStack {
                    Text("Quality")
                        .font(VFTheme.Typography.body)
                        .foregroundStyle(VFTheme.Colors.textPrimary)
                    Spacer()
                    Picker("", selection: $selectedQuality) {
                        ForEach(StreamQuality.allCases) { q in
                            Text(q.rawValue).tag(q)
                        }
                    }
                    .frame(width: 140)
                }

                HStack {
                    Text("Port")
                        .font(VFTheme.Typography.body)
                        .foregroundStyle(VFTheme.Colors.textPrimary)
                    Spacer()
                    TextField("7867", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                HStack {
                    Text("Max FPS")
                        .font(VFTheme.Typography.body)
                        .foregroundStyle(VFTheme.Colors.textPrimary)
                    Spacer()
                    Picker("", selection: $maxFPS) {
                        Text("15").tag(15)
                        Text("24").tag(24)
                        Text("30").tag(30)
                        Text("60").tag(60)
                    }
                    .frame(width: 100)
                }

                Toggle("Relay touch/keyboard input from device", isOn: $inputRelay)
                    .font(VFTheme.Typography.body)
                    .foregroundStyle(VFTheme.Colors.textPrimary)

                Toggle("Auto-start on app launch", isOn: $autoStart)
                    .font(VFTheme.Typography.body)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
            }
            .padding(VFTheme.Spacing.md)
            .background(VFTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))

            // How it works
            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                Label("How Routes Work", systemImage: "info.circle")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textSecondary)

                VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
                    infoRow("1.", "The route captures your virtual screen and streams it as video")
                    infoRow("2.", "Open the URL on your iPad/tablet/TV browser")
                    infoRow("3.", "Double-tap to go fullscreen — the device becomes a monitor")
                    infoRow("4.", "Touch and keyboard input is relayed back to your Mac")
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

                Button("Create Route") { create() }
                    .buttonStyle(.borderedProminent)
                    .tint(VFTheme.Colors.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(resolvedName.isEmpty)
            }
        }
        .padding(VFTheme.Spacing.xl)
        .frame(width: 520)
        .background(VFTheme.Colors.background)
    }

    private func sourceRow(_ config: VirtualScreenConfig) -> some View {
        let isSelected = selectedSourceID == config.id
        let isActive = virtualDisplayService.isActive(config.id)
        return HStack(spacing: VFTheme.Spacing.sm) {
            Image(systemName: "display")
                .foregroundStyle(isActive ? VFTheme.Colors.success : VFTheme.Colors.textTertiary)
            VStack(alignment: .leading, spacing: 0) {
                Text(config.name)
                    .font(VFTheme.Typography.body)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                Text(config.resolutionLabel)
                    .font(VFTheme.Typography.mono)
                    .foregroundStyle(VFTheme.Colors.textTertiary)
            }
            Spacer()
            if isActive {
                StatusBadge(label: "Active", color: VFTheme.Colors.success)
            }
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(VFTheme.Colors.accent)
            }
        }
        .padding(VFTheme.Spacing.sm)
        .background(isSelected ? VFTheme.Colors.accentSubtle : VFTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: VFTheme.Radius.md)
                .stroke(isSelected ? VFTheme.Colors.accent : VFTheme.Colors.border, lineWidth: 1)
        )
        .onTapGesture { selectedSourceID = config.id }
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
        return trimmed.isEmpty ? "Route" : trimmed
    }

    private func create() {
        let route = RouteConfig(
            name: resolvedName,
            sourceDisplayConfigID: selectedSourceID,
            protocol_: selectedProtocol,
            port: UInt16(port) ?? 7867,
            quality: selectedQuality,
            maxFPS: maxFPS,
            inputRelayEnabled: inputRelay,
            autoStartOnLaunch: autoStart
        )
        routeService.addRoute(route)
        dismiss()
    }
}
