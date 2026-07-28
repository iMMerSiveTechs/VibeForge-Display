import SwiftUI

struct TimerWidget: View {
    let surfaceID: UUID
    let widgetID: UUID
    let service: SurfaceService

    @State private var targetSeconds: Int = 300
    @State private var elapsedSeconds: Int = 0
    @State private var isRunning = false
    @State private var isCountingUp = false
    @State private var timer: Timer?

    var displayTime: String {
        let total = isCountingUp ? elapsedSeconds : max(targetSeconds - elapsedSeconds, 0)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var isFinished: Bool {
        !isCountingUp && elapsedSeconds >= targetSeconds
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
            HStack {
                Label("Timer", systemImage: "timer")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
                Spacer()
                Picker("", selection: $isCountingUp) {
                    Text("Countdown").tag(false)
                    Text("Stopwatch").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .onChange(of: isCountingUp) { _, _ in
                    reset()
                    saveData()
                }
            }

            HStack(spacing: VFTheme.Spacing.lg) {
                Text(displayTime)
                    .font(.system(size: 36, weight: .light, design: .monospaced))
                    .foregroundStyle(isFinished ? VFTheme.Colors.warning : VFTheme.Colors.textPrimary)

                Spacer()

                if !isCountingUp {
                    presetButtons
                }

                controlButtons
            }
        }
        .padding(VFTheme.Spacing.md)
        .background(VFTheme.Colors.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: VFTheme.Radius.md)
                .stroke(VFTheme.Colors.border, lineWidth: 1)
        )
        .onAppear {
            let data = service.timerData(for: surfaceID, widgetID: widgetID)
            targetSeconds = data.targetSeconds
            isCountingUp = data.isCountingUp
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private var presetButtons: some View {
        HStack(spacing: VFTheme.Spacing.xs) {
            ForEach([60, 300, 600, 1500], id: \.self) { seconds in
                Button(action: {
                    targetSeconds = seconds
                    reset()
                    saveData()
                }) {
                    Text(formatPreset(seconds))
                        .font(VFTheme.Typography.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var controlButtons: some View {
        HStack(spacing: VFTheme.Spacing.sm) {
            Button(action: toggleTimer) {
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    .foregroundStyle(VFTheme.Colors.accent)
            }
            .buttonStyle(.bordered)

            Button(action: reset) {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundStyle(VFTheme.Colors.textSecondary)
            }
            .buttonStyle(.bordered)
        }
    }

    private func toggleTimer() {
        if isRunning {
            timer?.invalidate()
            timer = nil
            isRunning = false
        } else {
            isRunning = true
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in
                    if isCountingUp {
                        elapsedSeconds += 1
                    } else if elapsedSeconds < targetSeconds {
                        elapsedSeconds += 1
                    } else {
                        timer?.invalidate()
                        isRunning = false
                    }
                }
            }
        }
    }

    private func reset() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        elapsedSeconds = 0
    }

    private func formatPreset(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m"
    }

    private func saveData() {
        service.updateTimer(
            surfaceID: surfaceID,
            widgetID: widgetID,
            data: TimerData(targetSeconds: targetSeconds, isCountingUp: isCountingUp)
        )
    }
}
