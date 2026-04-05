import SwiftUI

struct SidebarNavigation: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
            brandHeader
            Divider().background(VFTheme.Colors.border)
            tabList
            Spacer()
            footerInfo
        }
        .frame(minWidth: VFTheme.Window.sidebarWidth)
        .background(VFTheme.Colors.surface)
    }

    private var brandHeader: some View {
        HStack(spacing: VFTheme.Spacing.sm) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 18))
                .foregroundStyle(VFTheme.Colors.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text("VibeForge")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                Text("Display")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.accent)
            }
        }
        .padding(VFTheme.Spacing.lg)
    }

    private var tabList: some View {
        VStack(spacing: VFTheme.Spacing.xxs) {
            ForEach(AppState.SidebarTab.allCases) { tab in
                sidebarButton(for: tab)
            }
        }
        .padding(.horizontal, VFTheme.Spacing.sm)
    }

    private func sidebarButton(for tab: AppState.SidebarTab) -> some View {
        let isSelected = appState.selectedTab == tab
        return Button(action: { appState.selectedTab = tab }) {
            HStack(spacing: VFTheme.Spacing.sm) {
                Image(systemName: tab.icon)
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? VFTheme.Colors.accent : VFTheme.Colors.textSecondary)
                Text(tab.rawValue)
                    .font(VFTheme.Typography.body)
                    .foregroundStyle(isSelected ? VFTheme.Colors.textPrimary : VFTheme.Colors.textSecondary)
                Spacer()
                badgeView(for: tab)
            }
            .padding(.horizontal, VFTheme.Spacing.sm)
            .padding(.vertical, VFTheme.Spacing.sm)
            .background(isSelected ? VFTheme.Colors.accentSubtle : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.sm))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func badgeView(for tab: AppState.SidebarTab) -> some View {
        switch tab {
        case .screens:
            countBadge(appState.screenService.screens.count, color: VFTheme.Colors.textTertiary)
        case .virtualScreens:
            let active = appState.virtualDisplayService.activeConfigIDs.count
            if active > 0 {
                countBadge(active, color: VFTheme.Colors.success)
            } else {
                let total = appState.virtualDisplayService.configs.count
                if total > 0 {
                    countBadge(total, color: VFTheme.Colors.textTertiary)
                }
            }
        case .surfaces:
            let openCount = appState.surfaceService.configs.filter(\.isOpen).count
            if openCount > 0 {
                countBadge(openCount, color: VFTheme.Colors.success)
            }
        case .routes:
            StatusBadge(label: "Soon", color: VFTheme.Colors.textTertiary)
        default:
            EmptyView()
        }
    }

    private func countBadge(_ count: Int, color: Color) -> some View {
        Text("\(count)")
            .font(VFTheme.Typography.caption)
            .foregroundStyle(color)
            .padding(.horizontal, VFTheme.Spacing.xs)
            .padding(.vertical, 2)
            .background(VFTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.sm))
    }

    private var footerInfo: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.xxs) {
            Text("v\(VFConstants.appVersion)")
                .font(VFTheme.Typography.caption)
                .foregroundStyle(VFTheme.Colors.textTertiary)
        }
        .padding(VFTheme.Spacing.lg)
    }
}
