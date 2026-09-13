import SwiftUI

struct NotePadWidget: View {
    let surfaceID: UUID
    let widgetID: UUID
    let service: SurfaceService

    @State private var text: String = ""
    @State private var initialized = false

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
            Label("Note Pad", systemImage: "note.text")
                .font(VFTheme.Typography.headline)
                .foregroundStyle(VFTheme.Colors.textSecondary)

            TextEditor(text: $text)
                .font(VFTheme.Typography.body)
                .foregroundStyle(VFTheme.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(VFTheme.Spacing.xs)
                .background(VFTheme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.sm))
                .onChange(of: text) { _, newValue in
                    guard initialized else { return }
                    service.updateNotePad(
                        surfaceID: surfaceID,
                        widgetID: widgetID,
                        data: NotePadData(text: newValue)
                    )
                }
        }
        .padding(VFTheme.Spacing.md)
        .background(VFTheme.Colors.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: VFTheme.Radius.md)
                .stroke(VFTheme.Colors.border, lineWidth: 1)
        )
        .onAppear {
            let data = service.notePadData(for: surfaceID, widgetID: widgetID)
            text = data.text
            initialized = true
        }
    }
}
