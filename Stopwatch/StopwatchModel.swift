import Foundation
import Observation

@Observable
final class StopwatchModel {
    struct Lap: Identifiable, Hashable {
        let id = UUID()
        let index: Int
        let split: TimeInterval
        let total: TimeInterval
    }

    private(set) var elapsed: TimeInterval = 0
    private(set) var isRunning = false
    private(set) var laps: [Lap] = []

    private var resumeDate: Date?
    private var accumulated: TimeInterval = 0
    private var ticker: Timer?

    var hasActivity: Bool { elapsed > 0 || !laps.isEmpty }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        guard !isRunning else { return }
        resumeDate = Date()
        isRunning = true
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let ticker {
            RunLoop.main.add(ticker, forMode: .common)
        }
    }

    func stop() {
        guard isRunning else { return }
        accumulated = currentElapsed()
        elapsed = accumulated
        resumeDate = nil
        isRunning = false
        ticker?.invalidate()
        ticker = nil
    }

    func reset() {
        ticker?.invalidate()
        ticker = nil
        resumeDate = nil
        accumulated = 0
        elapsed = 0
        isRunning = false
        laps.removeAll()
    }

    func lap() {
        guard isRunning else { return }
        let total = currentElapsed()
        let previousTotal = laps.first?.total ?? 0
        let split = max(0, total - previousTotal)
        laps.insert(Lap(index: laps.count + 1, split: split, total: total), at: 0)
    }

    private func tick() {
        elapsed = currentElapsed()
    }

    private func currentElapsed() -> TimeInterval {
        guard let resumeDate else { return accumulated }
        return accumulated + Date().timeIntervalSince(resumeDate)
    }
}
