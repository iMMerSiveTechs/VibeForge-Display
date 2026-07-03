import SwiftUI

struct VirtualDisplaysView: View {
    let virtualDisplayService: VirtualDisplayService
    let logService: LogService

    @State private var showCreateSheet = false
    @State private var editingConfig: VirtualScreenConfig?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(VFTheme.Colors.border)
            infoBar
            Divider().background(VFTheme.Colors.border)
            displayList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VFTheme.Colors.background)
        .sheet(isPresented: $showCreateSheet) {
            CreateVirtualDisplaySheet(virtualDisplayService: virtualDisplayService)
        }
        .sheet(item: $editingConfig) { config in
            EditVirtualScreenSheet(config: config, virtualDisplayService: virtualDisplayService)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
                Text("Virtual Screens")
                    .font(VFTheme.Typography.largeTitle)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                Text("Create virtual displays to extend your desktop beyond hardware limits")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
            }
            Spacer()
            Button(action: { showCreateSheet = true }) {
                Label("Add Virtual Screen", systemImage: "plus.display")
                    .font(VFTheme.Typography.caption)
            }
            .buttonStyle(.borderedProminent)
            .tint(VFTheme.Colors.accent)
        }
        .padding(VFTheme.Spacing.xl)
    }

    private var infoBar: some View {
        HStack(spacing: VFTheme.Spacing.lg) {
            let total = virtualDisplayService.configs.count
            let active = virtualDisplayService.activeConfigIDs.count

            Label("\(total) configured", systemImage: "display")
                .font(VFTheme.Typography.caption)
                .foregroundStyle(VFTheme.Colors.textSecondary)

            HStack(spacing: VFTheme.Spacing.xs) {
                Circle()
                    .fill(active > 0 ? VFTheme.Colors.success : VFTheme.Colors.textTertiary)
                    .frame(width: 6, height: 6)
                Text("\(active) active")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(active > 0 ? VFTheme.Colors.success : VFTheme.Colors.textTertiary)
            }

            Spacer()

            if !virtualDisplayService.activeConfigIDs.isEmpty {
                Button("Destroy All") {
                    virtualDisplayService.destroyAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(VFTheme.Colors.error)
            }
        }
        .padding(.horizontal, VFTheme.Spacing.xl)
        .padding(.vertical, VFTheme.Spacing.sm)
        .background(VFTheme.Colors.surface.opacity(0.3))
    }

    @ViewBuilder
    private var displayList: some View {
        if virtualDisplayService.configs.isEmpty {
            EmptyStateView(
                icon: "plus.display",
                title: "No Virtual Screens Yet",
                message: "Create a virtual screen to extend your desktop. Virtual screens appear in macOS System Settings > Displays as real monitors, allowing you to use additional TVs or displays beyond your Mac's hardware limit.",
                actionLabel: "Add Virtual Screen",
                action: { showCreateSheet = true }
            )
        } else {
            ScrollView {
                LazyVStack(spacing: VFTheme.Spacing.md) {
                    ForEach(virtualDisplayService.configs) { config in
                        VirtualDisplayCard(
                            config: config,
                            isActive: virtualDisplayService.isActive(config.id),
                            displayID: virtualDisplayService.displayID(for: config.id),
                            onToggle: { toggleDisplay(config) },
                            onEdit: { editingConfig = config },
                            onDelete: { virtualDisplayService.removeConfig(config.id) }
                        )
                    }
                }
                .padding(VFTheme.Spacing.xl)
            }
        }
    }

    private func toggleDisplay(_ config: VirtualScreenConfig) {
        if virtualDisplayService.isActive(config.id) {
            virtualDisplayService.destroyDisplay(config.id)
        } else {
            Task {
                await virtualDisplayService.createDisplay(config: config)
            }
        }
    }
}

// MARK: - Virtual Display Card

struct VirtualDisplayCard: View {
    let config: VirtualScreenConfig
    let isActive: Bool
    let displayID: CGDirectDisplayID?
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.md) {
            cardHeader
            Divider().background(VFTheme.Colors.border)
            detailGrid
        }
        .padding(VFTheme.Spacing.lg)
        .background(VFTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: VFTheme.Radius.lg)
                .stroke(isActive ? VFTheme.Colors.success.opacity(0.5) : VFTheme.Colors.border, lineWidth: 1)
        )
        .confirmationDialog("Delete virtual screen “\(config.name)”?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) { }
        }
    }

    private var cardHeader: some View {
        HStack(spacing: VFTheme.Spacing.md) {
            Image(systemName: "display")
                .font(.system(size: 24))
                .foregroundStyle(isActive ? VFTheme.Colors.success : VFTheme.Colors.textTertiary)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: VFTheme.Spacing.xxs) {
                HStack(spacing: VFTheme.Spacing.sm) {
                    Text(config.name)
                        .font(VFTheme.Typography.title)
                        .foregroundStyle(VFTheme.Colors.textPrimary)
                    StatusBadge(
                        label: isActive ? "Active" : "Inactive",
                        color: isActive ? VFTheme.Colors.success : VFTheme.Colors.textTertiary
                    )
                    if config.hiDPI {
                        StatusBadge(label: "HiDPI", color: VFTheme.Colors.accent)
                    }
                    if config.autoCreateOnLaunch {
                        StatusBadge(label: "Auto", color: VFTheme.Colors.warning)
                    }
                }
                if let displayID {
                    Text("Display ID: \(displayID)")
                        .font(VFTheme.Typography.mono)
                        .foregroundStyle(VFTheme.Colors.textTertiary)
                }
            }

            Spacer()

            HStack(spacing: VFTheme.Spacing.sm) {
                Button(action: onToggle) {
                    Label(
                        isActive ? "Deactivate" : "Activate",
                        systemImage: isActive ? "display.trianglebadge.exclamationmark" : "display"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(isActive ? VFTheme.Colors.warning : VFTheme.Colors.accent)
                .controlSize(.small)

                Button(action: onEdit) {
                    Image(systemName: "pencil").foregroundStyle(VFTheme.Colors.textSecondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isActive)
                .accessibilityLabel("Edit \(config.name)")
                .help("Edit name and auto-start (resolution changes need recreating the screen)")

                Button(action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash").foregroundStyle(VFTheme.Colors.error)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Delete \(config.name)")
            }
        }
    }

    private var detailGrid: some View {
        let rows: [(String, String)] = [
            ("Resolution", config.resolutionLabel),
            ("Refresh Rate", config.refreshLabel),
            ("Scale", config.scaleLabel),
            ("Auto-Start", config.autoCreateOnLaunch ? "Yes" : "No"),
        ]

        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: VFTheme.Spacing.md),
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
}

// MARK: - Edit Virtual Screen Sheet

struct EditVirtualScreenSheet: View {
    let config: VirtualScreenConfig
    let virtualDisplayService: VirtualDisplayService
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var autoCreate: Bool

    init(config: VirtualScreenConfig, virtualDisplayService: VirtualDisplayService) {
        self.config = config
        self.virtualDisplayService = virtualDisplayService
        _name = State(initialValue: config.name)
        _autoCreate = State(initialValue: config.autoCreateOnLaunch)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.xl) {
            Text("Edit Virtual Screen")
                .font(VFTheme.Typography.largeTitle)
                .foregroundStyle(VFTheme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                Text("Name").font(VFTheme.Typography.headline).foregroundStyle(VFTheme.Colors.textSecondary)
                TextField("Display name", text: $name).textFieldStyle(.roundedBorder)
            }
            Toggle("Create automatically on launch", isOn: $autoCreate)
                .font(VFTheme.Typography.body)
                .foregroundStyle(VFTheme.Colors.textPrimary)
            Text("To change resolution or refresh rate, delete this screen and add a new one.")
                .font(VFTheme.Typography.caption)
                .foregroundStyle(VFTheme.Colors.textTertiary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.bordered).keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent).tint(VFTheme.Colors.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(VFTheme.Spacing.xl)
        .frame(width: 440)
        .background(VFTheme.Colors.background)
    }

    private func save() {
        var updated = config
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.autoCreateOnLaunch = autoCreate
        virtualDisplayService.updateConfig(updated)
        dismiss()
    }
}
