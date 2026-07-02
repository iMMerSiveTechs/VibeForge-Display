import SwiftUI

/// VibeForge Receiver — a tiny tvOS app that finds a VibeForge Display Mac on the
/// local network and plays its streamed screens with AVPlayer (HLS). This is the
/// native receiver Apple TV needs, since tvOS has no web browser.
@main
struct VibeForgeReceiverApp: App {
    var body: some Scene {
        WindowGroup {
            StreamListView()
        }
    }
}

/// The fixed HTTP/HLS port the Mac sender listens on (mirrors VFConstants.Streaming.httpPort).
enum ReceiverConfig {
    static let port = 8760
    static let bonjourType = "_vibeforge._tcp"
    static let bonjourDomain = "local."
}
