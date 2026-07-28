import SwiftUI

struct ScreensView: View {
    let screenService: ScreenService
    let logService: LogService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(VFTheme.Colors.border)
            screenList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VFTheme.Colors.background)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
                Text("Screens")
                    .font(VFTheme.Typography.largeTitle)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                Text("Connected displays and their current configuration")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
            }
            Spacer()
            Button(action: { screenService.refresh() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(VFTheme.Typography.caption)
            }
            .buttonStyle(.bordered)
            .disabled(screenService.isEnumerating)
        }
        .padding(VFTheme.Spacing.xl)
    }

    @ViewBuilder
    private var screenList: some View {
        if screenService.screens.isEmpty {
            EmptyStateView(
                icon: "display.trianglebadge.exclamationmark",
                title: "No Screens Detected",
                message: "Connect a display or refresh to inspect changes.",
                actionLabel: "Refresh Screens",
                action: { screenService.refresh() }
            )
        } else {
            ScrollView {
                LazyVStack(spacing: VFTheme.Spacing.md) {
                    ForEach(screenService.screens) { screen in
                        ScreenDetailCard(screen: screen, screenService: screenService)
                    }
                }
                .padding(VFTheme.Spacing.xl)
            }
        }
    }
}
