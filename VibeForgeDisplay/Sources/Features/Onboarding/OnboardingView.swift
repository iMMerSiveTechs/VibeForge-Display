import SwiftUI

/// First-run welcome. Explains the core flow honestly (including that Routes is
/// VibeForge's own stream, not AirPlay) and dismisses into the app.
struct OnboardingView: View {
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.xl) {
            header
            steps
            limits
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(action: onDone) {
                    Text("Get Started")
                        .font(VFTheme.Typography.headline)
                        .padding(.horizontal, VFTheme.Spacing.md)
                }
                .buttonStyle(.borderedProminent)
                .tint(VFTheme.Colors.accent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(VFTheme.Spacing.xxl)
        .frame(width: 560, height: 560)
        .background(VFTheme.Colors.background)
    }

    private var header: some View {
        HStack(spacing: VFTheme.Spacing.md) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 34))
                .foregroundStyle(VFTheme.Colors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to VibeForge Display")
                    .font(VFTheme.Typography.largeTitle)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                Text("Shape your screens. Route your workspace.")
                    .font(VFTheme.Typography.body)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.md) {
            step("plus.display", "Create a Virtual Screen",
                 "Make an extra desktop your Mac treats as a real monitor.")
            step("point.3.connected.trianglepath.dotted", "Route it to a TV",
                 "Stream a screen (or a Surface) over your network — scan the QR on a phone/TV, or pair an Apple TV with a code.")
            step("square.grid.2x2", "Save a Wall Preset",
                 "Snapshot your whole multi-TV layout and restore it in one tap.")
            step("rectangle.on.rectangle.angled", "Surfaces",
                 "Lightweight utility windows (notes, timers, checklists) you can also route to a screen.")
        }
    }

    private func step(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: VFTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(VFTheme.Colors.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                Text(body)
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
            }
        }
    }

    private var limits: some View {
        HStack(alignment: .top, spacing: VFTheme.Spacing.sm) {
            Image(systemName: "info.circle")
                .foregroundStyle(VFTheme.Colors.textTertiary)
            Text("Routes stream over VibeForge's own transport on your local network — not Apple AirPlay. Streams are gated by a per-session token; treat the QR/PIN like a password.")
                .font(VFTheme.Typography.caption)
                .foregroundStyle(VFTheme.Colors.textTertiary)
        }
        .padding(VFTheme.Spacing.md)
        .background(VFTheme.Colors.accentSubtle)
        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
    }
}
