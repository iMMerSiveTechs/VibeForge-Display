import SwiftUI

struct LogsView: View {
    let logService: LogService
    let screenService: ScreenService
    let surfaceService: SurfaceService
    let virtualDisplayService: VirtualDisplayService

    @State private var selectedCategory: LogEntry.Category?
    @State private var searchText = ""

    var filteredEntries: [LogEntry] {
        var entries = logService.entries
        if let category = selectedCategory {
            entries = entries.filter { $0.category == category }
        }
        if !searchText.isEmpty {
            entries = entries.filter {
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                ($0.detail?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        return entries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(VFTheme.Colors.border)
            diagnosticsCards
            Divider().background(VFTheme.Colors.border)
            filterBar
            eventLog
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VFTheme.Colors.background)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
                Text("Logs")
                    .font(VFTheme.Typography.largeTitle)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                Text("Event log and system diagnostics")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
            }
            Spacer()
            Button(action: { logService.clear() }) {
                Label("Clear", systemImage: "trash")
                    .font(VFTheme.Typography.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(VFTheme.Spacing.xl)
    }

    private var diagnosticsCards: some View {
        let activeVirtual = virtualDisplayService.activeConfigIDs.count
        let totalVirtual = virtualDisplayService.configs.count

        return HStack(spacing: VFTheme.Spacing.md) {
            diagnosticCard(
                title: "Physical Screens",
                status: screenService.screens.isEmpty ? "No screens" : "\(screenService.screens.count) detected",
                color: screenService.screens.isEmpty ? VFTheme.Colors.warning : VFTheme.Colors.success,
                icon: "display"
            )
            diagnosticCard(
                title: "Virtual Screens",
                status: totalVirtual == 0 ? "None configured" : "\(activeVirtual)/\(totalVirtual) active",
                color: activeVirtual > 0 ? VFTheme.Colors.success : (totalVirtual > 0 ? VFTheme.Colors.warning : VFTheme.Colors.textTertiary),
                icon: "plus.display"
            )
            diagnosticCard(
                title: "Surfaces",
                status: "\(surfaceService.configs.count) configured, \(surfaceService.configs.filter(\.isOpen).count) open",
                color: VFTheme.Colors.success,
                icon: "rectangle.on.rectangle.angled"
            )
            diagnosticCard(
                title: "System",
                status: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
                color: VFTheme.Colors.success,
                icon: "desktopcomputer"
            )
        }
        .padding(VFTheme.Spacing.xl)
    }

    private func diagnosticCard(title: String, status: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
            HStack(spacing: VFTheme.Spacing.xs) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
            }
            HStack(spacing: VFTheme.Spacing.xs) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(status)
                    .font(VFTheme.Typography.mono)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VFTheme.Spacing.md)
        .background(VFTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: VFTheme.Radius.md)
                .stroke(VFTheme.Colors.border, lineWidth: 1)
        )
    }

    private var filterBar: some View {
        HStack(spacing: VFTheme.Spacing.sm) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(VFTheme.Colors.textTertiary)
                TextField("Search events...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(VFTheme.Typography.body)
            }
            .padding(VFTheme.Spacing.sm)
            .background(VFTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.sm))

            Picker("Category", selection: $selectedCategory) {
                Text("All").tag(nil as LogEntry.Category?)
                ForEach(LogEntry.Category.allCases, id: \.self) { cat in
                    Text(cat.rawValue).tag(cat as LogEntry.Category?)
                }
            }
            .frame(width: 120)
        }
        .padding(.horizontal, VFTheme.Spacing.xl)
        .padding(.vertical, VFTheme.Spacing.sm)
    }

    private var eventLog: some View {
        Group {
            if filteredEntries.isEmpty {
                VStack {
                    Spacer()
                    Text("No recent activity")
                        .font(VFTheme.Typography.body)
                        .foregroundStyle(VFTheme.Colors.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredEntries) { entry in
                            logRow(entry)
                        }
                    }
                    .padding(.horizontal, VFTheme.Spacing.xl)
                    .padding(.vertical, VFTheme.Spacing.sm)
                }
            }
        }
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(spacing: VFTheme.Spacing.sm) {
            Text(entry.timestamp, style: .time)
                .font(VFTheme.Typography.mono)
                .foregroundStyle(VFTheme.Colors.textTertiary)
                .frame(width: 70, alignment: .leading)

            StatusBadge(label: entry.category.rawValue, color: categoryColor(entry.category))
                .frame(width: 60)

            Text(entry.message)
                .font(VFTheme.Typography.body)
                .foregroundStyle(VFTheme.Colors.textPrimary)
                .lineLimit(1)

            if let detail = entry.detail {
                Text(detail)
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, VFTheme.Spacing.xs)
        .padding(.horizontal, VFTheme.Spacing.sm)
    }

    private func categoryColor(_ category: LogEntry.Category) -> Color {
        switch category {
        case .screen: return VFTheme.Colors.accent
        case .mode: return VFTheme.Colors.success
        case .surface: return VFTheme.Colors.warning
        case .system: return VFTheme.Colors.textSecondary
        case .error: return VFTheme.Colors.error
        }
    }
}
