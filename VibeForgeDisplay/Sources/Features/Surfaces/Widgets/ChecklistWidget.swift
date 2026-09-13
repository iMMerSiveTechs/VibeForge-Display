import SwiftUI

struct ChecklistWidget: View {
    let surfaceID: UUID
    let widgetID: UUID
    let service: SurfaceService

    @State private var items: [ChecklistData.ChecklistItem] = []
    @State private var newItemText = ""
    @State private var initialized = false

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
            Label("Checklist", systemImage: "checklist")
                .font(VFTheme.Typography.headline)
                .foregroundStyle(VFTheme.Colors.textSecondary)

            ForEach($items) { $item in
                HStack(spacing: VFTheme.Spacing.sm) {
                    Button(action: {
                        item.isChecked.toggle()
                        saveData()
                    }) {
                        Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isChecked ? VFTheme.Colors.success : VFTheme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)

                    Text(item.text)
                        .font(VFTheme.Typography.body)
                        .foregroundStyle(item.isChecked ? VFTheme.Colors.textTertiary : VFTheme.Colors.textPrimary)
                        .strikethrough(item.isChecked)

                    Spacer()

                    Button(action: {
                        items.removeAll { $0.id == item.id }
                        saveData()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(VFTheme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: VFTheme.Spacing.sm) {
                TextField("Add item...", text: $newItemText)
                    .textFieldStyle(.plain)
                    .font(VFTheme.Typography.body)
                    .onSubmit { addItem() }

                Button(action: addItem) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(VFTheme.Colors.accent)
                }
                .buttonStyle(.plain)
                .disabled(newItemText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(VFTheme.Spacing.xs)
            .background(VFTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.sm))
        }
        .padding(VFTheme.Spacing.md)
        .background(VFTheme.Colors.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: VFTheme.Radius.md)
                .stroke(VFTheme.Colors.border, lineWidth: 1)
        )
        .onAppear {
            let data = service.checklistData(for: surfaceID, widgetID: widgetID)
            items = data.items
            initialized = true
        }
    }

    private func addItem() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        items.append(ChecklistData.ChecklistItem(text: trimmed))
        newItemText = ""
        saveData()
    }

    private func saveData() {
        guard initialized else { return }
        service.updateChecklist(
            surfaceID: surfaceID,
            widgetID: widgetID,
            data: ChecklistData(items: items)
        )
    }
}
