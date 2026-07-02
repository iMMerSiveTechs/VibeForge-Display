import SwiftUI
import AVKit

struct StreamListView: View {
    @StateObject private var discovery = Discovery()
    @State private var manualHost = ""

    var body: some View {
        NavigationStack {
            List {
                discoveredSection
                manualSection
            }
            .navigationTitle("VibeForge Receiver")
            .toolbar {
                Button {
                    discovery.start()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
            }
            .onAppear { discovery.start() }
            .onDisappear { discovery.stop() }
        }
    }

    @ViewBuilder
    private var discoveredSection: some View {
        Section("On your network") {
            if discovery.servers.isEmpty {
                Label("Searching for a VibeForge Mac…", systemImage: "magnifyingglass")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(discovery.servers) { server in
                    NavigationLink(value: server) {
                        Label(server.name, systemImage: "desktopcomputer")
                    }
                }
            }
        }
        .navigationDestination(for: Discovery.Server.self) { server in
            ServerStreamsView(name: server.name, host: server.host, port: server.port)
        }
    }

    @ViewBuilder
    private var manualSection: some View {
        Section("Connect by IP") {
            TextField("Mac IP address (e.g. 192.168.1.20)", text: $manualHost)
            let host = manualHost.trimmingCharacters(in: .whitespaces)
            if !host.isEmpty {
                NavigationLink("Connect to \(host)") {
                    ServerStreamsView(name: host, host: host, port: ReceiverConfig.port)
                }
            }
        }
    }
}

/// Pairs with the Mac (PIN → session token), then lists and plays its streams.
struct ServerStreamsView: View {
    let name: String
    let host: String
    let port: Int

    @State private var token: String?
    @State private var streams: [StreamInfo] = []
    @State private var loading = false
    @State private var pin = ""
    @State private var pairError = false
    @State private var pairing = false

    var body: some View {
        Group {
            if token == nil {
                pinEntry
            } else {
                streamList
            }
        }
        .navigationTitle(name)
        .navigationDestination(for: URL.self) { url in
            PlayerView(url: url)
        }
        .onAppear {
            if token == nil { token = StreamsClient.storedToken(host: host) }
            if token != nil { Task { await reload() } }
        }
    }

    private var pinEntry: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Enter the 6-digit code shown on the Mac")
                .font(.headline)
            Text("On the Mac: Routes → “Pair Apple TV”.")
                .foregroundStyle(.secondary)
            TextField("123456", text: $pin)
                .textContentType(.oneTimeCode)
                .frame(maxWidth: 400)
            if pairError {
                Label("Wrong or expired code — get a fresh one on the Mac.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            Button {
                Task { await submitPIN() }
            } label: {
                Label(pairing ? "Connecting…" : "Connect", systemImage: "link")
            }
            .disabled(pin.filter(\.isNumber).count < 6 || pairing)
        }
        .padding(40)
    }

    private var streamList: some View {
        List {
            if loading {
                Label("Loading streams…", systemImage: "clock").foregroundStyle(.secondary)
            } else if streams.isEmpty {
                Text("No active streams. Start a Route on the Mac, then Refresh.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(streams) { stream in
                    if let t = token, let url = StreamsClient.mediaURL(host: host, port: port, token: t, key: stream.key) {
                        NavigationLink(value: url) {
                            Label(stream.name, systemImage: "play.rectangle")
                        }
                    }
                }
            }
        }
        .toolbar {
            Button { Task { await reload() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }

    private func submitPIN() async {
        pairing = true
        pairError = false
        if let t = await StreamsClient.pair(host: host, port: port, pin: pin) {
            StreamsClient.storeToken(t, host: host)
            token = t
            pin = ""
            await reload()
        } else {
            pairError = true
        }
        pairing = false
    }

    private func reload() async {
        guard let t = token else { return }
        loading = true
        switch await StreamsClient.fetch(host: host, port: port, token: t) {
        case .ok(let list):
            streams = list
        case .unauthorized:
            // Token no longer valid (e.g. Mac restarted) — re-pair.
            StreamsClient.clearToken(host: host)
            token = nil
        case .failed:
            streams = []
        }
        loading = false
    }
}

/// Full-screen HLS playback.
struct PlayerView: View {
    let url: URL
    @State private var player = AVPlayer()

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .onAppear {
                let item = AVPlayerItem(url: url)
                player.replaceCurrentItem(with: item)
                player.play()
            }
            .onDisappear {
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
    }
}
