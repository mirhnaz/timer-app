import SwiftUI
import AppKit

enum AppMode: String, CaseIterable, Identifiable {
    case stopwatch, timer
    var id: String { rawValue }

    var label: String {
        switch self {
        case .stopwatch: "Stopwatch"
        case .timer:     "Timer"
        }
    }

    var symbol: String {
        switch self {
        case .stopwatch: "stopwatch"
        case .timer:     "hourglass"
        }
    }
}

struct StopwatchView: View {
    @Bindable var stopwatch: StopwatchModel
    @Bindable var timer: TimerModel
    @AppStorage("mode") private var mode: AppMode = .stopwatch

    var body: some View {
        VStack(spacing: 14) {
            modePicker

            Group {
                switch mode {
                case .stopwatch: StopwatchPanel(model: stopwatch)
                case .timer:     TimerPanel(model: timer)
                }
            }
            .transition(.opacity)

            footer
        }
        .padding(20)
        .frame(width: 320)
        .animation(.snappy(duration: 0.2), value: mode)
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(AppMode.allCases) { m in
                Text(m.label).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var footer: some View {
        HStack {
            SettingsLink {
                Label("Preferences", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Preferences")

            Spacer()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.caption)
                .keyboardShortcut("q", modifiers: .command)
        }
    }
}

// MARK: - Stopwatch panel

struct StopwatchPanel: View {
    @Bindable var model: StopwatchModel

    var body: some View {
        VStack(spacing: 14) {
            timeDisplay

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    primaryButton
                    lapButton
                    resetButton
                }
            }

            if !model.laps.isEmpty {
                LapList(laps: model.laps, fastest: fastestLapID, slowest: slowestLapID)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.25), value: model.laps)
        .animation(.snappy(duration: 0.25), value: model.isRunning)
    }

    private var timeDisplay: some View {
        Text(TimeFormat.large(model.elapsed))
            .font(.system(size: 44, weight: .light, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: false))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var primaryButton: some View {
        Button {
            model.toggle()
        } label: {
            Label(model.isRunning ? "Stop" : "Start",
                  systemImage: model.isRunning ? "stop.fill" : "play.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(model.isRunning ? .red : .green)
        .keyboardShortcut(.space, modifiers: [])
    }

    private var lapButton: some View {
        Button {
            model.lap()
        } label: {
            Label("Lap", systemImage: "flag.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
        .disabled(!model.isRunning)
        .keyboardShortcut("l", modifiers: [])
    }

    private var resetButton: some View {
        Button {
            model.reset()
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
        .disabled(model.isRunning || !model.hasActivity)
        .keyboardShortcut("r", modifiers: [])
    }

    private var fastestLapID: StopwatchModel.Lap.ID? {
        model.laps.count >= 2 ? model.laps.min(by: { $0.split < $1.split })?.id : nil
    }

    private var slowestLapID: StopwatchModel.Lap.ID? {
        model.laps.count >= 2 ? model.laps.max(by: { $0.split < $1.split })?.id : nil
    }
}

private struct LapList: View {
    let laps: [StopwatchModel.Lap]
    let fastest: StopwatchModel.Lap.ID?
    let slowest: StopwatchModel.Lap.ID?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(laps) { lap in
                    LapRow(lap: lap, accent: accent(for: lap.id))
                    if lap.id != laps.last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .frame(maxHeight: 180)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func accent(for id: StopwatchModel.Lap.ID) -> Color? {
        if id == fastest { return .green }
        if id == slowest { return .red }
        return nil
    }
}

private struct LapRow: View {
    let lap: StopwatchModel.Lap
    let accent: Color?

    var body: some View {
        HStack {
            Text("Lap \(lap.index)")
                .foregroundStyle(.secondary)
            Spacer()
            Text(TimeFormat.large(lap.split))
                .monospacedDigit()
                .foregroundStyle(accent ?? .primary)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
