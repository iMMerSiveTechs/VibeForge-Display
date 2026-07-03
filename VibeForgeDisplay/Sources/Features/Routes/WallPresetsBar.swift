import SwiftUI

/// A horizontal strip of saved multi-TV layouts. Tap a chip to restore that whole
/// setup (screens + routes); use "Save layout" to snapshot the current one.
struct WallPresetsBar: View {
    let wallPresetService: WallPresetService
    @State private var showSaveSheet = false
    @State private var applying: UUID?
    @State private var showReport = false

    var body: some View {
        HStack(spacing: VFTheme.Spacing.sm) {
            Label("Presets", systemImage: "square.grid.2x2")
                .font(VFTheme.Typography.caption)
                .foregroundStyle(VFTheme.Colors.textTertiary)
                .fixedSize()

            if wallPresetService.presets.isEmpty {
                Text("Save your current layout to restore it in one click.")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textTertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: VFTheme.Spacing.sm) {
                        ForEach(wallPresetService.presets) { preset in
                            chip(preset)
                        }
                    }
                }
            }

            Spacer(minLength: VFTheme.Spacing.sm)

            Button(action: { showSaveSheet = true }) {
                Label("Save layout", systemImage: "plus.square.on.square")
                    .font(VFTheme.Typography.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, VFTheme.Spacing.xl)
        .padding(.vertical, VFTheme.Spacing.sm)
        .background(VFTheme.Colors.surface.opacity(0.15))
        .sheet(isPresented: $showSaveSheet) {
            SaveWallPresetSheet(wallPresetService: wallPresetService)
        }
        .alert("Preset applied", isPresented: $showReport) {
            Button("OK") { wallPresetService.clearApplyReport() }
        } message: {
            if let r = wallPresetService.lastApplyReport {
                var lines = ["Restored \(r.screensRestored) screen(s), \(r.surfacesRestored) surface(s), \(r.routesRestored) route(s); started \(r.routesStarted)."]
                if !r.failures.isEmpty { lines.append("\nIssues:\n" + r.failures.joined(separator: "\n")) }
                Text(lines.joined(separator: "\n"))
            }
        }
    }

    private func chip(_ preset: WallPreset) -> some View {
        Button(action: { apply(preset) }) {
            HStack(spacing: VFTheme.Spacing.xs) {
                if applying == preset.id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.square")
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(preset.name)
                        .font(VFTheme.Typography.caption)
                        .foregroundStyle(VFTheme.Colors.textPrimary)
                    Text(preset.summary)
                        .font(.system(size: 9))
                        .foregroundStyle(VFTheme.Colors.textTertiary)
                }
            }
            .padding(.horizontal, VFTheme.Spacing.sm)
            .padding(.vertical, VFTheme.Spacing.xs)
            .background(VFTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: VFTheme.Radius.sm)
                    .stroke(VFTheme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                wallPresetService.delete(preset.id)
            } label: {
                Label("Delete Preset", systemImage: "trash")
            }
        }
    }

    private func apply(_ preset: WallPreset) {
        applying = preset.id
        Task {
            await wallPresetService.apply(preset)
            applying = nil
            showReport = true
        }
    }
}

// MARK: - Save Wall Preset Sheet

struct SaveWallPresetSheet: View {
    let wallPresetService: WallPresetService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.lg) {
            Text("Save Wall Preset")
                .font(VFTheme.Typography.largeTitle)
                .foregroundStyle(VFTheme.Colors.textPrimary)
            Text("Snapshots your current virtual screens, the surfaces they use, and all routes — so you can restore the whole layout with one tap. (Applying adds this preset's items; it doesn't remove others.)")
                .font(VFTheme.Typography.caption)
                .foregroundStyle(VFTheme.Colors.textSecondary)
            TextField("e.g. Living Room + Kitchen TVs", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    wallPresetService.saveCurrent(name: trimmed)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(VFTheme.Colors.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(VFTheme.Spacing.xl)
        .frame(width: 440)
        .background(VFTheme.Colors.background)
    }
}
