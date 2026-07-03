import SwiftUI
import AppKit
import CoreGraphics

struct RoutesView: View {
    let streamService: StreamService
    let virtualDisplayService: VirtualDisplayService
    let surfaceService: SurfaceService
    let wallPresetService: WallPresetService
    let hlsServer: HLSServer
    let logService: LogService

    @State private var showCreateSheet = false
    @State private var showPairSheet = false
    @State private var editingRoute: RouteConfig?
    @State private var screenRecordingOK = CGPreflightScreenCaptureAccess()

    private var hasAnySource: Bool {
        !virtualDisplayService.configs.isEmpty || !surfaceService.configs.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(VFTheme.Colors.border)
            infoBar
            Divider().background(VFTheme.Colors.border)
            if !screenRecordingOK { permissionBanner }
            WallPresetsBar(wallPresetService: wallPresetService)
            Divider().background(VFTheme.Colors.border)
            content
        }
        .onAppear { screenRecordingOK = CGPreflightScreenCaptureAccess() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VFTheme.Colors.background)
        .sheet(isPresented: $showCreateSheet) {
            CreateRouteSheet(
                streamService: streamService,
                virtualDisplayService: virtualDisplayService,
                surfaceService: surfaceService
            )
        }
        .sheet(isPresented: $showPairSheet) {
            // Do NOT cancel pairing on dismiss — the user needs the code to stay
            // live while they walk to the TV and type it. The 120s window and
            // one-time use are enforced in SessionSecurity.
            PairingSheet(hlsServer: hlsServer)
        }
        .sheet(item: $editingRoute) { route in
            EditRouteSheet(route: route, streamService: streamService)
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
            Button(action: startPairing) {
                Label("Pair Apple TV", systemImage: "appletv")
                    .font(VFTheme.Typography.caption)
            }
            .buttonStyle(.bordered)
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

    private var permissionBanner: some View {
        HStack(spacing: VFTheme.Spacing.md) {
            Image(systemName: "lock.shield")
                .font(.system(size: 20))
                .foregroundStyle(VFTheme.Colors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Screen Recording permission needed")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                Text("VibeForge captures your screen to stream it. Grant Screen Recording, then relaunch — macOS won't apply it to a running app.")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
            }
            Spacer()
            Button("Grant…") {
                CGRequestScreenCaptureAccess()
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(VFTheme.Colors.accent)
        }
        .padding(VFTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(VFTheme.Colors.warning.opacity(0.12))
    }

    private func startPairing() {
        hlsServer.start()          // ensure the server is up so /pair is reachable
        _ = hlsServer.beginPairing()
        showPairSheet = true
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
                            sourceMissing: !sourceExists(for: route),
                            isStreaming: streamService.isStreaming(route.id),
                            isStarting: streamService.isStarting(route.id),
                            errorMessage: streamService.error(for: route.id),
                            receiverURL: streamService.receiverURL(for: route),
                            hasLANAddress: HLSServer.localIPAddress() != nil,
                            statsProvider: { streamService.stats(for: route.id) },
                            onToggle: { toggle(route) },
                            onEdit: { editingRoute = route },
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
            Text("Browser devices (phones, laptops, smart TVs/sticks): scan the QR or open the link — it carries a one-time access code. Apple TV: open VibeForge Receiver, pick this Mac, and enter the code from “Pair Apple TV”. Streams are gated by a per-session token and served only over your LAN — this is VibeForge's own stream, not Apple AirPlay.")
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

    private func sourceExists(for route: RouteConfig) -> Bool {
        switch route.sourceKind {
        case .virtualScreen: return virtualDisplayService.configs.contains { $0.id == route.sourceID }
        case .surface: return surfaceService.configs.contains { $0.id == route.sourceID }
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
    let sourceMissing: Bool
    let isStreaming: Bool
    let isStarting: Bool
    let errorMessage: String?
    let receiverURL: String
    let hasLANAddress: Bool
    let statsProvider: () -> StreamService.RouteStats?
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var copied = false
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.md) {
            headerRow
            if sourceMissing {
                inlineNote(icon: "exclamationmark.triangle.fill", color: VFTheme.Colors.warning,
                           text: "This route's source no longer exists. Recreate it, or delete this route.")
            } else if let errorMessage {
                inlineNote(icon: "exclamationmark.octagon.fill", color: VFTheme.Colors.error, text: errorMessage)
            }
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
        .confirmationDialog("Delete route “\(route.name)”?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Route", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) { }
        }
    }

    private func inlineNote(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: VFTheme.Spacing.xs) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(VFTheme.Typography.caption).foregroundStyle(VFTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    StatusBadge(label: isStreaming ? "Live" : (isStarting ? "Starting" : "Idle"),
                                color: isStreaming ? VFTheme.Colors.success : (isStarting ? VFTheme.Colors.accent : VFTheme.Colors.textTertiary))
                    StatusBadge(label: route.quality.rawValue, color: VFTheme.Colors.accent)
                    if route.autoStart {
                        StatusBadge(label: "Auto", color: VFTheme.Colors.warning)
                    }
                    StatusBadge(label: route.sourceKind.rawValue, color: VFTheme.Colors.textTertiary)
                }
                Text("Source: \(sourceName) · \(route.quality.detail)")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(sourceMissing ? VFTheme.Colors.warning : VFTheme.Colors.textSecondary)
            }

            Spacer()

            HStack(spacing: VFTheme.Spacing.sm) {
                Button(action: onToggle) {
                    if isStarting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(isStreaming ? "Stop" : "Start",
                              systemImage: isStreaming ? "stop.fill" : "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(isStreaming ? VFTheme.Colors.warning : VFTheme.Colors.accent)
                .controlSize(.small)
                .disabled(isStarting || (sourceMissing && !isStreaming))
                .help(sourceMissing ? "The source for this route is missing." : "")

                Button(action: onEdit) {
                    Image(systemName: "pencil").foregroundStyle(VFTheme.Colors.textSecondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Edit route \(route.name)")
                .disabled(isStreaming)
                .help("Edit name, quality, and auto-start")

                Button(action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash").foregroundStyle(VFTheme.Colors.error)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Delete route \(route.name)")
                .disabled(isStreaming)
            }
        }
    }

    @ViewBuilder
    private var streamingDetail: some View {
        if !hasLANAddress {
            // No real LAN address → the URL would be localhost, which no TV can
            // reach. Don't show a QR that scans "successfully" and then fails.
            inlineNote(icon: "wifi.slash", color: VFTheme.Colors.warning,
                       text: "This Mac has no Wi-Fi/Ethernet address, so receivers can't connect. Join a network and this route will become reachable.")
        } else {
            HStack(alignment: .top, spacing: VFTheme.Spacing.lg) {
                if let qr = QRCode.nsImage(from: receiverURL, size: 140) {
                    Image(nsImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 140, height: 140)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.sm))
                        .accessibilityLabel("QR code linking to this stream")
                }
                VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                    Text("Open on the TV or phone")
                        .font(VFTheme.Typography.headline)
                        .foregroundStyle(VFTheme.Colors.textSecondary)
                    Text(receiverURL)
                        .font(VFTheme.Typography.mono)
                        .foregroundStyle(VFTheme.Colors.textPrimary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Button(action: copy) {
                        Label(copied ? "Copied" : "Copy link",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(VFTheme.Typography.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Text("Scan the QR with a phone, or open the link in a browser on the TV / streaming stick. For Apple TV, use “Pair Apple TV”.")
                        .font(VFTheme.Typography.caption)
                        .foregroundStyle(VFTheme.Colors.textTertiary)
                }
                Spacer()
            }
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

// MARK: - Pairing Sheet

/// Shows the one-time PIN the user enters on the Apple TV. Stays open (the code
/// must survive the walk to the TV) and shows a clear terminal state — paired,
/// or expired with a way to get a fresh code — instead of silently vanishing.
struct PairingSheet: View {
    let hlsServer: HLSServer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            content(hlsServer.pairingSnapshot())
        }
        .frame(width: 440)
        .background(VFTheme.Colors.background)
    }

    @ViewBuilder
    private func content(_ state: SessionSecurity.PairingState) -> some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.lg) {
            Text("Pair an Apple TV")
                .font(VFTheme.Typography.largeTitle)
                .foregroundStyle(VFTheme.Colors.textPrimary)

            if state.active {
                activeContent(state)
            } else if state.paired {
                terminal(icon: "checkmark.circle.fill", color: VFTheme.Colors.success,
                         title: "Paired", detail: "Your Apple TV is connected. You can close this.")
            } else {
                terminal(icon: "clock.badge.xmark", color: VFTheme.Colors.warning,
                         title: "Code expired", detail: "Generate a fresh code and try again.")
            }

            HStack(spacing: VFTheme.Spacing.sm) {
                if !state.active && !state.paired {
                    Button("New Code") { _ = hlsServer.beginPairing() }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if state.active {
                    Button("Cancel") { hlsServer.cancelPairing(); dismiss() }
                        .buttonStyle(.bordered)
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(VFTheme.Colors.accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(VFTheme.Spacing.xl)
    }

    @ViewBuilder
    private func activeContent(_ state: SessionSecurity.PairingState) -> some View {
        Text("On the Apple TV, open VibeForge Receiver, choose this Mac, and enter this code. Keep this window open until it connects.")
            .font(VFTheme.Typography.body)
            .foregroundStyle(VFTheme.Colors.textSecondary)

        Text(formattedPIN(state.pin))
            .font(.system(size: 48, weight: .semibold, design: .monospaced))
            .foregroundStyle(VFTheme.Colors.accent)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, VFTheme.Spacing.md)
            .accessibilityLabel("Pairing code \(state.pin.map { Array($0).map(String.init).joined(separator: " ") } ?? "")")

        HStack {
            Image(systemName: "clock")
            Text("Expires in \(state.secondsLeft)s")
        }
        .font(VFTheme.Typography.caption)
        .foregroundStyle(VFTheme.Colors.textTertiary)
    }

    private func terminal(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(spacing: VFTheme.Spacing.md) {
            Image(systemName: icon).font(.system(size: 32)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: VFTheme.Spacing.xxs) {
                Text(title).font(VFTheme.Typography.title).foregroundStyle(VFTheme.Colors.textPrimary)
                Text(detail).font(VFTheme.Typography.caption).foregroundStyle(VFTheme.Colors.textSecondary)
            }
        }
        .padding(.vertical, VFTheme.Spacing.md)
    }

    private func formattedPIN(_ pin: String?) -> String {
        guard let pin, pin.count == 6 else { return "–––  –––" }
        let mid = pin.index(pin.startIndex, offsetBy: 3)
        return "\(pin[pin.startIndex..<mid])  \(pin[mid...])"
    }
}

// MARK: - Edit Route Sheet

struct EditRouteSheet: View {
    let route: RouteConfig
    let streamService: StreamService
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var quality: StreamQuality
    @State private var autoStart: Bool

    init(route: RouteConfig, streamService: StreamService) {
        self.route = route
        self.streamService = streamService
        _name = State(initialValue: route.name)
        _quality = State(initialValue: route.quality)
        _autoStart = State(initialValue: route.autoStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.xl) {
            Text("Edit Route")
                .font(VFTheme.Typography.largeTitle)
                .foregroundStyle(VFTheme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                Text("Name").font(VFTheme.Typography.headline).foregroundStyle(VFTheme.Colors.textSecondary)
                TextField("Route name", text: $name).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
                Text("Quality").font(VFTheme.Typography.headline).foregroundStyle(VFTheme.Colors.textSecondary)
                Picker("", selection: $quality) {
                    ForEach(StreamQuality.allCases) { q in Text("\(q.rawValue) — \(q.detail)").tag(q) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            Toggle("Start automatically on launch", isOn: $autoStart)
                .font(VFTheme.Typography.body)
                .foregroundStyle(VFTheme.Colors.textPrimary)
            Text("Changes to quality apply the next time this route starts.")
                .font(VFTheme.Typography.caption)
                .foregroundStyle(VFTheme.Colors.textTertiary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.bordered).keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent).tint(VFTheme.Colors.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(VFTheme.Spacing.xl)
        .frame(width: 460)
        .background(VFTheme.Colors.background)
    }

    private func save() {
        var updated = route
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.quality = quality
        updated.autoStart = autoStart
        streamService.updateRoute(updated)
        dismiss()
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
    @State private var autoStart = false

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

            Toggle(isOn: $autoStart) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start automatically on launch")
                        .font(VFTheme.Typography.body)
                        .foregroundStyle(VFTheme.Colors.textPrimary)
                    Text("Virtual-screen routes only auto-start if the screen came up cleanly (safe mode).")
                        .font(VFTheme.Typography.caption)
                        .foregroundStyle(VFTheme.Colors.textTertiary)
                }
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
        let route = RouteConfig(name: trimmed, sourceKind: sourceKind, sourceID: sourceID,
                                quality: quality, autoStart: autoStart)
        streamService.addRoute(route)
        dismiss()
    }
}
