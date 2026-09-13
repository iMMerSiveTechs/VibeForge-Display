import SwiftUI

struct RoutesView: View {
    let routeService: RouteService
    let virtualDisplayService: VirtualDisplayService
    let logService: LogService

    @State private var showCreateSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(VFTheme.Colors.border)
            infoBar
            Divider().background(VFTheme.Colors.border)
            routeList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VFTheme.Colors.background)
        .sheet(isPresented: $showCreateSheet) {
            CreateRouteSheet(
                routeService: routeService,
                virtualDisplayService: virtualDisplayService
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
                Text("Routes")
                    .font(VFTheme.Typography.largeTitle)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                Text("Stream virtual screens to iPads, tablets, TVs, and browsers")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
            }
            Spacer()
            Button(action: { showCreateSheet = true }) {
                Label("Add Route", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(VFTheme.Typography.caption)
            }
            .buttonStyle(.borderedProminent)
            .tint(VFTheme.Colors.accent)
        }
        .padding(VFTheme.Spacing.xl)
    }

    private var infoBar: some View {
        HStack(spacing: VFTheme.Spacing.lg) {
            let total = routeService.routes.count
            let active = routeService.activeRouteIDs.count
            let totalClients = routeService.clients.values.reduce(0) { $0 + $1.count }

            Label("\(total) route(s)", systemImage: "point.3.connected.trianglepath.dotted")
                .font(VFTheme.Typography.caption)
                .foregroundStyle(VFTheme.Colors.textSecondary)

            HStack(spacing: VFTheme.Spacing.xs) {
                Circle()
                    .fill(active > 0 ? VFTheme.Colors.success : VFTheme.Colors.textTertiary)
                    .frame(width: 6, height: 6)
                Text("\(active) streaming")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(active > 0 ? VFTheme.Colors.success : VFTheme.Colors.textTertiary)
            }

            if totalClients > 0 {
                HStack(spacing: VFTheme.Spacing.xs) {
                    Image(systemName: "ipad.and.arrow.forward")
                        .font(.system(size: 10))
                    Text("\(totalClients) device(s)")
                        .font(VFTheme.Typography.caption)
                }
                .foregroundStyle(VFTheme.Colors.accent)
            }

            Spacer()

            if !routeService.activeRouteIDs.isEmpty {
                Button("Stop All") {
                    routeService.stopAll()
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
    private var routeList: some View {
        if routeService.routes.isEmpty {
            EmptyStateView(
                icon: "point.3.connected.trianglepath.dotted",
                title: "No Routes Yet",
                message: "Create a route to stream a virtual screen to your iPad, tablet, or any device with a browser. The device becomes an extra monitor — just open the URL.",
                actionLabel: "Add Route",
                action: { showCreateSheet = true }
            )
        } else {
            ScrollView {
                LazyVStack(spacing: VFTheme.Spacing.md) {
                    ForEach(routeService.routes) { route in
                        RouteCard(
                            route: route,
                            isActive: routeService.isActive(route.id),
                            clientCount: routeService.clientCount(for: route.id),
                            frameCount: routeService.frameCounters[route.id] ?? 0,
                            connectURL: routeService.connectURL(for: route),
                            sourceName: virtualDisplayService.configs.first(where: { $0.id == route.sourceDisplayConfigID })?.name,
                            onToggle: { toggleRoute(route) },
                            onDelete: { routeService.removeRoute(route.id) }
                        )
                    }
                }
                .padding(VFTheme.Spacing.xl)
            }
        }
    }

    private func toggleRoute(_ route: RouteConfig) {
        if routeService.isActive(route.id) {
            routeService.stopRoute(route.id)
        } else {
            routeService.startRoute(route.id)
        }
    }
}

// MARK: - Route Card

struct RouteCard: View {
    let route: RouteConfig
    let isActive: Bool
    let clientCount: Int
    let frameCount: Int
    let connectURL: String
    let sourceName: String?
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var copiedURL = false

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.md) {
            cardHeader
            Divider().background(VFTheme.Colors.border)

            // Connection URL (the key piece for iPad)
            if isActive {
                connectionSection
                Divider().background(VFTheme.Colors.border)
            }

            detailGrid
        }
        .padding(VFTheme.Spacing.lg)
        .background(VFTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: VFTheme.Radius.lg)
                .stroke(isActive ? VFTheme.Colors.success.opacity(0.5) : VFTheme.Colors.border, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
    }

    private var cardHeader: some View {
        HStack(spacing: VFTheme.Spacing.md) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 24))
                .foregroundStyle(isActive ? VFTheme.Colors.success : VFTheme.Colors.textTertiary)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: VFTheme.Spacing.xxs) {
                HStack(spacing: VFTheme.Spacing.sm) {
                    Text(route.name)
                        .font(VFTheme.Typography.title)
                        .foregroundStyle(VFTheme.Colors.textPrimary)
                    StatusBadge(
                        label: isActive ? "Streaming" : "Stopped",
                        color: isActive ? VFTheme.Colors.success : VFTheme.Colors.textTertiary
                    )
                    if route.autoStartOnLaunch {
                        StatusBadge(label: "Auto", color: VFTheme.Colors.warning)
                    }
                }
                if let sourceName {
                    Text("Source: \(sourceName)")
                        .font(VFTheme.Typography.caption)
                        .foregroundStyle(VFTheme.Colors.textTertiary)
                } else {
                    Text("Source: Primary Display (fallback)")
                        .font(VFTheme.Typography.caption)
                        .foregroundStyle(VFTheme.Colors.warning)
                }
            }

            Spacer()

            HStack(spacing: VFTheme.Spacing.sm) {
                Button(action: onToggle) {
                    Label(
                        isActive ? "Stop" : "Start",
                        systemImage: isActive ? "stop.fill" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(isActive ? VFTheme.Colors.warning : VFTheme.Colors.accent)
                .controlSize(.small)

                if isHovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(VFTheme.Colors.error)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
            HStack {
                Label("Open this URL on your device", systemImage: "ipad.and.arrow.forward")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
                Spacer()
                if clientCount > 0 {
                    HStack(spacing: VFTheme.Spacing.xxs) {
                        Circle().fill(VFTheme.Colors.success).frame(width: 6, height: 6)
                        Text("\(clientCount) connected")
                            .font(VFTheme.Typography.caption)
                            .foregroundStyle(VFTheme.Colors.success)
                    }
                }
            }

            HStack {
                Text(connectURL)
                    .font(VFTheme.Typography.mono)
                    .foregroundStyle(VFTheme.Colors.accent)
                    .textSelection(.enabled)
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(connectURL, forType: .string)
                    copiedURL = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedURL = false }
                }) {
                    Label(copiedURL ? "Copied!" : "Copy URL", systemImage: copiedURL ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(copiedURL ? VFTheme.Colors.success : nil)
            }
            .padding(VFTheme.Spacing.sm)
            .background(VFTheme.Colors.accentSubtle)
            .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
        }
    }

    private var detailGrid: some View {
        let rows: [(String, String)] = [
            ("Protocol", route.protocol_.rawValue),
            ("Port", "\(route.port)"),
            ("Quality", route.quality.rawValue),
            ("Max FPS", "\(route.maxFPS)"),
            ("Input Relay", route.inputRelayEnabled ? "On" : "Off"),
            ("Frames", isActive ? "\(frameCount)" : "—"),
        ]

        return LazyVGrid(columns: [
            GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()),
            GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()),
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
