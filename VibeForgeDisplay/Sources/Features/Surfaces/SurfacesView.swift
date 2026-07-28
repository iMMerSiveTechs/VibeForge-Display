import SwiftUI

struct SurfacesView: View {
    let surfaceService: SurfaceService
    let screenService: ScreenService
    let logService: LogService

    @State private var showCreateSheet = false
    @State private var selectedSurfaceID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(VFTheme.Colors.border)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VFTheme.Colors.background)
        .sheet(isPresented: $showCreateSheet) {
            CreateSurfaceSheet(surfaceService: surfaceService)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
                Text("Surfaces")
                    .font(VFTheme.Typography.largeTitle)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                Text("Create useful side-space for notes, timers, checklists, and reference panels")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
            }
            Spacer()
            Button(action: { showCreateSheet = true }) {
                Label("Create Surface", systemImage: "plus.rectangle")
                    .font(VFTheme.Typography.caption)
            }
            .buttonStyle(.borderedProminent)
            .tint(VFTheme.Colors.accent)
        }
        .padding(VFTheme.Spacing.xl)
    }

    @ViewBuilder
    private var content: some View {
        if surfaceService.configs.isEmpty {
            EmptyStateView(
                icon: "rectangle.on.rectangle.angled",
                title: "No Surfaces Yet",
                message: "Create a Surface for notes, timers, checklists, or link panels and place useful side-space where you need it.",
                actionLabel: "Create Surface",
                action: { showCreateSheet = true }
            )
        } else {
            HSplitView {
                surfaceList
                    .frame(minWidth: 220, maxWidth: 280)
                surfaceDetail
            }
        }
    }

    private var surfaceList: some View {
        ScrollView {
            LazyVStack(spacing: VFTheme.Spacing.xs) {
                ForEach(surfaceService.configs) { config in
                    surfaceRow(config)
                }
            }
            .padding(VFTheme.Spacing.md)
        }
        .background(VFTheme.Colors.surface.opacity(0.3))
    }

    private func surfaceRow(_ config: SurfaceConfig) -> some View {
        let isSelected = selectedSurfaceID == config.id
        return HStack(spacing: VFTheme.Spacing.sm) {
            Circle()
                .fill(config.isOpen ? VFTheme.Colors.success : VFTheme.Colors.textTertiary)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                Text(config.preset.rawValue)
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textTertiary)
            }
            Spacer()
            Button(action: {
                if config.isOpen {
                    surfaceService.closeSurfaceWindow(config.id)
                } else {
                    surfaceService.openSurfaceWindow(config.id)
                }
            }) {
                Image(systemName: config.isOpen ? "eye.slash" : "eye")
                    .foregroundStyle(VFTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(VFTheme.Spacing.sm)
        .background(isSelected ? VFTheme.Colors.accentSubtle : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.sm))
        .onTapGesture { selectedSurfaceID = config.id }
    }

    @ViewBuilder
    private var surfaceDetail: some View {
        if let id = selectedSurfaceID, surfaceService.configs.contains(where: { $0.id == id }) {
            ScrollView {
                VStack(spacing: VFTheme.Spacing.lg) {
                    SurfaceSettingsView(
                        surfaceID: id,
                        surfaceService: surfaceService,
                        screenService: screenService
                    )

                    HStack {
                        Button("Open Surface") {
                            surfaceService.openSurfaceWindow(id)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(VFTheme.Colors.accent)

                        Spacer()

                        Button("Delete Surface") {
                            surfaceService.deleteSurface(id)
                            selectedSurfaceID = nil
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(VFTheme.Colors.error)
                    }
                }
                .padding(VFTheme.Spacing.xl)
            }
        } else {
            VStack {
                Spacer()
                Text("Select a Surface to configure")
                    .font(VFTheme.Typography.body)
                    .foregroundStyle(VFTheme.Colors.textTertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Create Surface Sheet

struct CreateSurfaceSheet: View {
    let surfaceService: SurfaceService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedPreset: SurfacePreset = .landscape

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.xl) {
            Text("Create Surface")
                .font(VFTheme.Typography.largeTitle)
                .foregroundStyle(VFTheme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                Text("Surface Name")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
                TextField("e.g. Side Notes, Work Timer", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                Text("Size Preset")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textSecondary)

                HStack(spacing: VFTheme.Spacing.md) {
                    ForEach(SurfacePreset.allCases) { preset in
                        presetCard(preset)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .tint(VFTheme.Colors.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(VFTheme.Spacing.xl)
        .frame(width: 460)
        .background(VFTheme.Colors.background)
    }

    private func presetCard(_ preset: SurfacePreset) -> some View {
        let isSelected = selectedPreset == preset
        return VStack(spacing: VFTheme.Spacing.sm) {
            Image(systemName: preset.icon)
                .font(.system(size: 24))
                .foregroundStyle(isSelected ? VFTheme.Colors.accent : VFTheme.Colors.textSecondary)
            Text(preset.rawValue)
                .font(VFTheme.Typography.caption)
                .foregroundStyle(isSelected ? VFTheme.Colors.textPrimary : VFTheme.Colors.textSecondary)
            Text("\(Int(preset.size.width)) x \(Int(preset.size.height))")
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

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        _ = surfaceService.createSurface(name: trimmed, preset: selectedPreset)
        dismiss()
    }
}
