import SwiftUI

struct SaveModeSheet: View {
    let modeService: ModeService
    let screenService: ScreenService
    let surfaceService: SurfaceService

    @Environment(\.dismiss) private var dismiss
    @State private var modeName = ""
    @State private var modeNotes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.xl) {
            Text("Save Current Mode")
                .font(VFTheme.Typography.largeTitle)
                .foregroundStyle(VFTheme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                Text("Mode Name")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
                TextField("e.g. Desk Focus, TV Utility", text: $modeName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                Text("Notes")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
                TextEditor(text: $modeNotes)
                    .frame(height: 60)
                    .font(VFTheme.Typography.body)
                    .scrollContentBackground(.hidden)
                    .padding(VFTheme.Spacing.xs)
                    .background(VFTheme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: VFTheme.Radius.sm)
                            .stroke(VFTheme.Colors.border, lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                Text("Current Setup Snapshot")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textSecondary)

                VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
                    Label("\(screenService.screens.count) screen(s) detected", systemImage: "display")
                    ForEach(screenService.screens) { screen in
                        HStack(spacing: VFTheme.Spacing.xs) {
                            Circle()
                                .fill(screen.isMain ? VFTheme.Colors.accent : VFTheme.Colors.textTertiary)
                                .frame(width: 6, height: 6)
                            Text("\(screen.name) — \(screen.resolutionLabel)")
                        }
                    }
                    if !surfaceService.configs.isEmpty {
                        Label("\(surfaceService.configs.count) surface(s) configured", systemImage: "rectangle.on.rectangle.angled")
                    }
                }
                .font(VFTheme.Typography.caption)
                .foregroundStyle(VFTheme.Colors.textTertiary)
                .padding(VFTheme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VFTheme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Button("Save Mode") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(VFTheme.Colors.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(modeName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(VFTheme.Spacing.xl)
        .frame(width: 420)
        .background(VFTheme.Colors.background)
    }

    private func save() {
        let trimmedName = modeName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        _ = modeService.createMode(
            name: trimmedName,
            notes: modeNotes,
            screens: screenService.screens,
            surfaces: surfaceService.configs
        )
        dismiss()
    }
}
