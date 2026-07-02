import SwiftUI
import AppKit

struct RoutesView: View {
    let streamService: StreamService
    let virtualDisplayService: VirtualDisplayService
    let surfaceService: SurfaceService
    let hlsServer: HLSServer
    let logService: LogService

    @State private var showCreateSheet = false

    private var hasAnySource: Bool {
        !virtualDisplayService.configs.isEmpty || !surfaceService.configs.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(VFTheme.Colors.border)
            infoBar
            Divider().background(VFTheme.Colors.border)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VFTheme.Colors.background)
        .sheet(isPresented: $showCreateSheet) {
            CreateRouteSheet(
                streamService: streamService,
                virtualDisplayService: virtualDisplayService,
                surfaceService: surfaceService
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
                Text("Routes")
                    .font(VFTheme.Typography.largeTitle)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                Text("Stream a virtual screen to any TV or device on your network")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
            }
            Spacer()
            Button(action: { showCreateSheet = true }) {
                Label("Add Route", systemImage: "plus")
                    .font(VFTheme.Typography.caption)
            }
            .buttonStyle(.borderedProminent)
            .tint(VFTheme.Colors.accent)
            .disabled(!hasAnySource)
        }
        .padding(VFTheme.Spacing.xl)
    }

    private var infoBar: some View {
        HStack(spacing: VFTheme.Spacing.lg) {
            HStack(spacing: VFTheme.Spacing.xs) {
                Circle()
                    .fill(hlsServer.isRunning ? VFTheme.Colors.success : VFTheme.Colors.textTertiary)
                    .frame(width: 7, height: 7)
                Text(hlsServer.isRunning ? "Server on \(HLSServer.localIPAddress() ?? "?"):\(hlsServer.port)" : "Server idle")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
            }
            Text("\(streamService.streamingRouteIDs.count) streaming")
                .font(VFTheme.Typography.caption)
                .foregroundStyle(VFTheme.Colors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, VFTheme.Spacing.xl)
        .padding(.vertical, VFTheme.Spacing.sm)
        .background(VFTheme.Colors.surface.opacity(0.3))
    }

    @ViewBuilder
    private var content: some View {
        if !hasAnySource {
            EmptyStateView(
                icon: "point.3.connected.trianglepath.dotted",
                title: "Create a Source First",
                message: "Routes stream a Virtual Screen or a Surface to a TV. Add one of those, then come back here to route it.",
                actionLabel: nil,
                action: {}
            )
        } else if streamService.routes.isEmpty {
            EmptyStateView(
                icon: "point.3.connected.trianglepath.dotted",
                title: "No Routes Yet",
                message: "Add a route to stream one of your virtual screens to a TV. On the TV (or a phone), open the link or scan the QR code shown when streaming starts.",
                actionLabel: "Add Route",
                action: { showCreateSheet = true }
            )
        } else {
            ScrollView {
                LazyVStack(spacing: VFTheme.Spacing.md) {
                    ForEach(streamService.routes) { route in
                        RouteRow(
                            route: route,
                            sourceName: sourceName(for: route),
                            isStreaming: streamService.isStreaming(route.id),
                            receiverURL: streamService.receiverURL(for: route),
                            statsProvider: { streamService.stats(for: route.id) },
                            onToggle: { toggle(route) },
                            onDelete: { streamService.removeRoute(route.id) }
                        )
                    }
                }
                .padding(VFTheme.Spacing.xl)

                receiverNote
                    .padding(.horizontal, VFTheme.Spacing.xl)
                    .padding(.bottom, VFTheme.Spacing.xl)
            }
        }
    }

    private var receiverNote: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.xs) {
            Label("How receivers connect", systemImage: "info.circle")
                .font(VFTheme.Typography.headline)
                .foregroundStyle(VFTheme.Colors.textSecondary)
            Text("Phones, laptops, and smart TVs/sticks with a browser: open the link (or scan the QR). Apple TV has no browser — a native Apple TV receiver app is coming next. This is VibeForge's own stream, not Apple AirPlay.")
                .font(VFTheme.Typography.caption)
                .foregroundStyle(VFTheme.Colors.textTertiary)
        }
        .padding(VFTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VFTheme.Colors.accentSubtle)
        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
    }

    private func sourceName(for route: RouteConfig) -> String {
        switch route.sourceKind {
        case .virtualScreen:
            return virtualDisplayService.configs.first(where: { $0.id == route.sourceID })?.name ?? "Missing screen"
        case .surface:
            return surfaceService.configs.first(where: { $0.id == route.sourceID })?.name ?? "Missing surface"
        }
    }

    private func toggle(_ route: RouteConfig) {
        if streamService.isStreaming(route.id) {
            streamService.stopRoute(route.id)
        } else {
            Task { await streamService.startRoute(route.id) }
        }
    }
}

// MARK: - Route Row

struct RouteRow: View {
    let route: RouteConfig
    let sourceName: String
    let isStreaming: Bool
    let receiverURL: String
    let statsProvider: () -> StreamService.RouteStats?
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.md) {
            headerRow
            if isStreaming {
                Divider().background(VFTheme.Colors.border)
                streamingDetail
                statsLine
            }
        }
        .padding(VFTheme.Spacing.lg)
        .background(VFTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: VFTheme.Radius.lg)
                .stroke(isStreaming ? VFTheme.Colors.success.opacity(0.5) : VFTheme.Colors.border, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
    }

    private var headerRow: some View {
        HStack(spacing: VFTheme.Spacing.md) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 22))
                .foregroundStyle(isStreaming ? VFTheme.Colors.success : VFTheme.Colors.textTertiary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: VFTheme.Spacing.xxs) {
                HStack(spacing: VFTheme.Spacing.sm) {
                    Text(route.name)
                        .font(VFTheme.Typography.title)
                        .foregroundStyle(VFTheme.Colors.textPrimary)
                    StatusBadge(label: isStreaming ? "Live" : "Idle",
                                color: isStreaming ? VFTheme.Colors.success : VFTheme.Colors.textTertiary)
                    StatusBadge(label: route.quality.rawValue, color: VFTheme.Colors.accent)
                }
                Text("Source: \(sourceName) · \(route.quality.detail)")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
            }

            Spacer()

            HStack(spacing: VFTheme.Spacing.sm) {
                Button(action: onToggle) {
                    Label(isStreaming ? "Stop" : "Start",
                          systemImage: isStreaming ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(isStreaming ? VFTheme.Colors.warning : VFTheme.Colors.accent)
                .controlSize(.small)

                if isHovering && !isStreaming {
                    Button(action: onDelete) {
                        Image(systemName: "trash").foregroundStyle(VFTheme.Colors.error)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var streamingDetail: some View {
        HStack(alignment: .top, spacing: VFTheme.Spacing.lg) {
            if let qr = QRCode.nsImage(from: receiverURL, size: 140) {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 140, height: 140)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.sm))
            }
            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                Text("Open on the TV or phone")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
                Text(receiverURL)
                    .font(VFTheme.Typography.mono)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                    .textSelection(.enabled)
                Button(action: copy) {
                    Label(copied ? "Copied" : "Copy link",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(VFTheme.Typography.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Text("Scan the QR with a phone, or type the link into a browser on the TV / streaming stick.")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textTertiary)
            }
            Spacer()
        }
    }

    /// Live telemetry line, refreshed every second while streaming.
    private var statsLine: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let s = statsProvider()
            HStack(spacing: VFTheme.Spacing.md) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(VFTheme.Colors.success)
                if let s {
                    Text(String(format: "%.0f fps avg", s.avgFPS))
                    Text("· \(s.frames) frames")
                    Text("· \(s.segments) segments")
                    Text(String(format: "· %.0fs", s.uptime))
                } else {
                    Text("Starting…")
                }
                Spacer()
            }
            .font(VFTheme.Typography.mono)
            .foregroundStyle(VFTheme.Colors.textTertiary)
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(receiverURL, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}

// MARK: - Create Route Sheet

struct CreateRouteSheet: View {
    let streamService: StreamService
    let virtualDisplayService: VirtualDisplayService
    let surfaceService: SurfaceService

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var sourceKind: RouteSourceKind = .virtualScreen
    @State private var selectedSourceID: UUID?
    @State private var quality: StreamQuality = .balanced

    private var hasVirtual: Bool { !virtualDisplayService.configs.isEmpty }
    private var hasSurface: Bool { !surfaceService.configs.isEmpty }

    /// The selectable sources for the currently chosen kind.
    private var sources: [(id: UUID, label: String)] {
        switch sourceKind {
        case .virtualScreen:
            return virtualDisplayService.configs.map { ($0.id, "\($0.name) · \($0.resolutionLabel)") }
        case .surface:
            return surfaceService.configs.map { ($0.id, "\($0.name) · \($0.preset.rawValue)") }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.xl) {
            Text("Add Route")
                .font(VFTheme.Typography.largeTitle)
                .foregroundStyle(VFTheme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                Text("Route Name")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
                TextField("e.g. Living Room TV", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            if hasVirtual && hasSurface {
                VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                    Text("Source Type")
                        .font(VFTheme.Typography.headline)
                        .foregroundStyle(VFTheme.Colors.textSecondary)
                    Picker("", selection: $sourceKind) {
                        Text("Virtual Screen").tag(RouteSourceKind.virtualScreen)
                        Text("Surface").tag(RouteSourceKind.surface)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: sourceKind) { _, _ in selectedSourceID = sources.first?.id }
                    Text(sourceKind == .virtualScreen
                         ? "A full extra desktop. True “extra screen”, but relies on capturing a headless virtual display."
                         : "A VibeForge Surface window. Always capturable and App-Store-safe — the reliable option.")
                        .font(VFTheme.Typography.caption)
                        .foregroundStyle(VFTheme.Colors.textTertiary)
                }
            }

            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                Text("Source")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
                Picker("", selection: $selectedSourceID) {
                    Text("Select…").tag(nil as UUID?)
                    ForEach(sources, id: \.id) { src in
                        Text(src.label).tag(src.id as UUID?)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                Text("Quality")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
                Picker("", selection: $quality) {
                    ForEach(StreamQuality.allCases) { q in
                        Text("\(q.rawValue) — \(q.detail)").tag(q)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .tint(VFTheme.Colors.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedSourceID == nil)
            }
        }
        .padding(VFTheme.Spacing.xl)
        .frame(width: 460)
        .background(VFTheme.Colors.background)
        .onAppear {
            // Default to whichever source kind actually has options.
            sourceKind = hasVirtual ? .virtualScreen : .surface
            selectedSourceID = sources.first?.id
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let sourceID = selectedSourceID else { return }
        let route = RouteConfig(name: trimmed, sourceKind: sourceKind, sourceID: sourceID, quality: quality)
        streamService.addRoute(route)
        dismiss()
    }
}
