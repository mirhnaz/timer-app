import SwiftUI

struct TimerPanel: View {
    @Bindable var model: TimerModel

    var body: some View {
        VStack(spacing: 14) {
            timeDisplay

            if model.hasDuration {
                runningControls
            } else {
                inputControls
            }
        }
        .animation(.snappy(duration: 0.25), value: model.hasDuration)
        .animation(.snappy(duration: 0.25), value: model.isRunning)
        .animation(.snappy(duration: 0.25), value: model.isFinished)
    }

    // MARK: - Display

    private var timeDisplay: some View {
        Group {
            if model.hasDuration {
                Text(TimeFormat.large(model.remaining))
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .foregroundStyle(model.isFinished ? Color.red : .primary)
            } else {
                Text("Set a Timer")
                    .font(.system(size: 26, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .glassEffect(
            model.isFinished ? .regular.tint(.red.opacity(0.25)) : .regular,
            in: .rect(cornerRadius: 22)
        )
    }

    // MARK: - Input mode

    private static let presets: [(label: String, seconds: TimeInterval)] = [
        ("1m", 60),
        ("5m", 300),
        ("25m", 1_500),
        ("1h", 3_600),
    ]

    @State private var input: String = ""

    private var inputControls: some View {
        VStack(spacing: 10) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.label) { preset in
                        Button(preset.label) {
                            model.setDuration(preset.seconds)
                        }
                        .buttonStyle(.glass)
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("5m, 1:30, 25", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)

                Button(action: submit) {
                    Image(systemName: "arrow.right")
                }
                .buttonStyle(.glassProminent)
                .tint(.green)
                .disabled(parsedDuration == nil)
            }
        }
    }

    private var parsedDuration: TimeInterval? {
        DurationParser.seconds(from: input)
    }

    private func submit() {
        guard let d = parsedDuration else { return }
        model.setDuration(d)
        input = ""
    }

    // MARK: - Running / paused / finished

    private var runningControls: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                primaryButton
                cancelButton
            }
        }
    }

    private var primaryButton: some View {
        Button(action: togglePrimary) {
            Label(primaryLabel, systemImage: primarySymbol)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(primaryTint)
        .keyboardShortcut(.space, modifiers: [])
        .disabled(model.isFinished)
    }

    private var cancelButton: some View {
        Button {
            model.clear()
        } label: {
            Label("Cancel", systemImage: "xmark")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
        .keyboardShortcut(.escape, modifiers: [])
    }

    private func togglePrimary() {
        if model.isFinished { return }
        model.isRunning ? model.pause() : model.start()
    }

    private var primaryLabel: String {
        if model.isFinished { return "Done" }
        if model.isRunning { return "Pause" }
        return model.remaining < model.totalDuration ? "Resume" : "Start"
    }

    private var primarySymbol: String {
        if model.isFinished { return "checkmark" }
        return model.isRunning ? "pause.fill" : "play.fill"
    }

    private var primaryTint: Color {
        if model.isFinished { return .gray }
        return model.isRunning ? .orange : .green
    }
}
