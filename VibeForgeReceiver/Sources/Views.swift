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

/// Lists the live streams available on one Mac, then plays the chosen one.
struct ServerStreamsView: View {
    let name: String
    let host: String
    let port: Int

    @State private var streams: [StreamInfo] = []
    @State private var loading = true

    var body: some View {
        List {
            if loading {
                Label("Loading streams…", systemImage: "clock")
                    .foregroundStyle(.secondary)
            } else if streams.isEmpty {
                Text("No active streams. Start a Route on the Mac, then Rescan.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(streams) { stream in
                    if let url = StreamsClient.mediaURL(host: host, port: port, key: stream.key) {
                        NavigationLink(value: url) {
                            Label(stream.name, systemImage: "play.rectangle")
                        }
                    }
                }
            }
        }
        .navigationTitle(name)
        .navigationDestination(for: URL.self) { url in
            PlayerView(url: url)
        }
        .task { await reload() }
        .toolbar {
            Button {
                Task { await reload() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }

    private func reload() async {
        loading = true
        streams = await StreamsClient.fetch(host: host, port: port)
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
