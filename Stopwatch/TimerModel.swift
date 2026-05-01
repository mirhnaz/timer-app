import Foundation
import Observation
import AppKit
import UserNotifications

@Observable
final class TimerModel {
    private(set) var totalDuration: TimeInterval = 0
    private(set) var remaining: TimeInterval = 0
    private(set) var isRunning = false
    private(set) var isFinished = false

    private var endDate: Date?
    private var ticker: Timer?
    private var hasRequestedAuth = false

    var hasDuration: Bool { totalDuration > 0 }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1 - (remaining / totalDuration)
    }

    func setDuration(_ seconds: TimeInterval) {
        invalidateTicker()
        totalDuration = seconds
        remaining = seconds
        endDate = nil
        isRunning = false
        isFinished = false
    }

    func start() {
        guard remaining > 0, !isRunning else { return }
        requestAuthorizationIfNeeded()
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        isFinished = false
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func pause() {
        guard isRunning else { return }
        remaining = computeRemaining()
        endDate = nil
        isRunning = false
        invalidateTicker()
    }

    /// Reset to the original duration without clearing it.
    func restart() {
        invalidateTicker()
        remaining = totalDuration
        endDate = nil
        isRunning = false
        isFinished = false
    }

    /// Wipe the duration and return to the input screen.
    func clear() {
        invalidateTicker()
        totalDuration = 0
        remaining = 0
        endDate = nil
        isRunning = false
        isFinished = false
    }

    private func tick() {
        let r = computeRemaining()
        if r <= 0 {
            remaining = 0
            isRunning = false
            isFinished = true
            invalidateTicker()
            endDate = nil
            fireExpiry()
        } else {
            remaining = r
        }
    }

    private func computeRemaining() -> TimeInterval {
        guard let endDate else { return remaining }
        return max(0, endDate.timeIntervalSinceNow)
    }

    private func invalidateTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func requestAuthorizationIfNeeded() {
        guard !hasRequestedAuth else { return }
        hasRequestedAuth = true
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
        }
    }

    private func fireExpiry() {
        // Pre-compute everything that depends on self so the Task closure
        // captures only Sendable values (Swift 6 strict concurrency).
        let body = "\(TimeFormat.menuBar(totalDuration)) finished"
        Task {
            let content = UNMutableNotificationContent()
            content.title = "Timer Done"
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "stopwatch.timer.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
        NSSound.beep()
    }
}
