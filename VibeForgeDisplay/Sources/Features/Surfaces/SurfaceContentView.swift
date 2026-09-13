import SwiftUI

struct SurfaceContentView: View {
    let surfaceID: UUID
    let surfaceService: SurfaceService

    var body: some View {
        let config = surfaceService.configs.first(where: { $0.id == surfaceID })

        VStack(spacing: 0) {
            surfaceHeader(config: config)
            Divider().background(VFTheme.Colors.border)
            widgetArea(config: config)
        }
        .background(VFTheme.Colors.background.opacity(0.95))
    }

    private func surfaceHeader(config: SurfaceConfig?) -> some View {
        HStack {
            Circle()
                .fill(VFTheme.Colors.accent)
                .frame(width: 8, height: 8)
            Text(config?.name ?? "Surface")
                .font(VFTheme.Typography.headline)
                .foregroundStyle(VFTheme.Colors.textPrimary)
            Spacer()
            Button(action: { surfaceService.closeSurfaceWindow(surfaceID) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(VFTheme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, VFTheme.Spacing.md)
        .padding(.vertical, VFTheme.Spacing.sm)
        .background(VFTheme.Colors.surface)
    }

    @ViewBuilder
    private func widgetArea(config: SurfaceConfig?) -> some View {
        let widgets = config?.widgets.sorted(by: { $0.order < $1.order }) ?? []

        if widgets.isEmpty {
            EmptyStateView(
                icon: "rectangle.on.rectangle.angled",
                title: "Start with a simple utility layout",
                message: "Add a note, checklist, timer, or link card to turn this Surface into useful workspace.",
                actionLabel: nil,
                action: {}
            )
        } else {
            ScrollView {
                LazyVStack(spacing: VFTheme.Spacing.sm) {
                    ForEach(widgets) { widget in
                        widgetView(for: widget)
                    }
                }
                .padding(VFTheme.Spacing.md)
            }
        }
    }

    @ViewBuilder
    private func widgetView(for widget: WidgetConfig) -> some View {
        switch widget.kind {
        case .notePad:
            NotePadWidget(surfaceID: surfaceID, widgetID: widget.id, service: surfaceService)
        case .checklist:
            ChecklistWidget(surfaceID: surfaceID, widgetID: widget.id, service: surfaceService)
        case .timer:
            TimerWidget(surfaceID: surfaceID, widgetID: widget.id, service: surfaceService)
        case .linkCards:
            LinkCardWidget(surfaceID: surfaceID, widgetID: widget.id, service: surfaceService)
        }
    }
}
