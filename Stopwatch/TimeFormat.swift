import Foundation

enum TimeFormat {
    /// Large display: mm:ss.cc, or h:mm:ss.cc once the hour hand turns.
    static func large(_ t: TimeInterval) -> String {
        let totalCs = max(0, Int((t * 100).rounded(.down)))
        let cs = totalCs % 100
        let s = (totalCs / 100) % 60
        let m = (totalCs / 6_000) % 60
        let h = totalCs / 360_000
        return h > 0
            ? String(format: "%d:%02d:%02d.%02d", h, m, s, cs)
            : String(format: "%02d:%02d.%02d", m, s, cs)
    }

    /// Menu bar: mm:ss (or h:mm:ss). Updates only once per second so the bar doesn't jitter.
    static func menuBar(_ t: TimeInterval) -> String {
        let totalS = max(0, Int(t))
        let s = totalS % 60
        let m = (totalS / 60) % 60
        let h = totalS / 3_600
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
