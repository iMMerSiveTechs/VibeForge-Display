import SwiftUI

/// A one-click starting point for a new user with nothing configured yet.
/// Complements WallPreset (save/restore YOUR OWN already-built setup) rather
/// than duplicating it: this offers curated, built-in multi-screen "layouts"
/// plus a full preset browser, so the first virtual screen doesn't require
/// hand-picking a resolution.
struct QuickSetupView: View {
    let virtualDisplayService: VirtualDisplayService
    let logService: LogService

    @State private var isCreating: String?  // layout ID being created

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(VFTheme.Colors.border)
            ScrollView {
                VStack(alignment: .leading, spacing: VFTheme.Spacing.xl) {
                    layoutsSection
                    presetsSection
                }
                .padding(VFTheme.Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VFTheme.Colors.background)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
                Text("Quick Setup")
                    .font(VFTheme.Typography.largeTitle)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                Text("One-click multi-display layouts. Pick a setup and go.")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(VFTheme.Spacing.xl)
    }

    // MARK: - One-Click Layouts

    private var layoutsSection: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.md) {
            SectionHeader(title: "Layouts", icon: "rectangle.stack.badge.plus")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: VFTheme.Spacing.md) {
                ForEach(QuickSetupLayout.allCases) { layout in
                    layoutCard(layout)
                }
            }
        }
    }

    private func layoutCard(_ layout: QuickSetupLayout) -> some View {
        let creating = isCreating == layout.id
        return VStack(alignment: .leading, spacing: VFTheme.Spacing.md) {
            HStack {
                Image(systemName: layout.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(VFTheme.Colors.accent)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: VFTheme.Spacing.xxs) {
                    Text(layout.rawValue)
                        .font(VFTheme.Typography.title)
                        .foregroundStyle(VFTheme.Colors.textPrimary)
                    Text(layout.description)
                        .font(VFTheme.Typography.caption)
                        .foregroundStyle(VFTheme.Colors.textSecondary)
                }
                Spacer()
            }

            // Show what screens will be created
            HStack(spacing: VFTheme.Spacing.sm) {
                ForEach(layout.presets, id: \.name) { item in
                    HStack(spacing: VFTheme.Spacing.xxs) {
                        Image(systemName: item.preset.category.icon)
                            .font(.system(size: 10))
                        Text(item.name)
                            .font(VFTheme.Typography.mono)
                    }
                    .foregroundStyle(VFTheme.Colors.textTertiary)
                    .padding(.horizontal, VFTheme.Spacing.xs)
                    .padding(.vertical, 2)
                    .background(VFTheme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.sm))
                }
            }

            Button(action: { createLayout(layout) }) {
                if creating {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Create \(layout.presets.count) Screen(s)", systemImage: "plus.display")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(VFTheme.Colors.accent)
            .controlSize(.small)
            .disabled(creating)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(VFTheme.Spacing.lg)
        .background(VFTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: VFTheme.Radius.lg)
                .stroke(VFTheme.Colors.border, lineWidth: 1)
        )
    }

    private func createLayout(_ layout: QuickSetupLayout) {
        isCreating = layout.id
        Task {
            for item in layout.presets {
                let config = VirtualScreenConfig(
                    name: item.name,
                    width: item.preset.width,
                    height: item.preset.height,
                    refreshRate: item.preset.defaultRefreshRate,
                    hiDPI: item.preset.defaultHiDPI,
                    autoCreateOnLaunch: true
                )
                await virtualDisplayService.addAndCreate(config)
            }
            logService.log(.screen, "Quick setup: \(layout.rawValue)",
                          detail: "Created \(layout.presets.count) virtual screen(s)")
            isCreating = nil
        }
    }

    // MARK: - Browse All Presets by Category

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.md) {
            SectionHeader(title: "All Presets by Category", icon: "square.grid.2x2")

            ForEach(PresetCategory.allCases) { category in
                let presets = VirtualScreenPreset.presets(for: category)
                if !presets.isEmpty {
                    VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                        HStack(spacing: VFTheme.Spacing.sm) {
                            Image(systemName: category.icon)
                                .foregroundStyle(VFTheme.Colors.accent)
                            Text(category.rawValue)
                                .font(VFTheme.Typography.headline)
                                .foregroundStyle(VFTheme.Colors.textPrimary)
                        }

                        FlowLayout(spacing: VFTheme.Spacing.sm) {
                            ForEach(presets) { preset in
                                presetChip(preset)
                            }
                        }
                    }
                    .padding(VFTheme.Spacing.md)
                    .background(VFTheme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
                }
            }
        }
    }

    private func presetChip(_ preset: VirtualScreenPreset) -> some View {
        Button(action: { createSinglePreset(preset) }) {
            VStack(spacing: VFTheme.Spacing.xxs) {
                Text(preset.rawValue)
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                Text("\(preset.width)x\(preset.height)")
                    .font(VFTheme.Typography.mono)
                    .foregroundStyle(VFTheme.Colors.textTertiary)
            }
            .padding(.horizontal, VFTheme.Spacing.md)
            .padding(.vertical, VFTheme.Spacing.sm)
        }
        .buttonStyle(.bordered)
    }

    private func createSinglePreset(_ preset: VirtualScreenPreset) {
        Task {
            let config = preset.toConfig()
            await virtualDisplayService.addAndCreate(config)
        }
    }
}

// MARK: - Simple Flow Layout for Preset Chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                   proposal: .unspecified)
        }
    }

    private struct ArrangeResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return ArrangeResult(positions: positions, size: CGSize(width: maxX, height: y + rowHeight))
    }
}
