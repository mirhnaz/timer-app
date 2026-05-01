import Foundation

/// Parses common duration shorthand:
///   "5"        → 5 minutes (bare numbers default to minutes)
///   "5m"       → 5 minutes
///   "45s"      → 45 seconds
///   "1h"       → 1 hour
///   "1h30m"    → 90 minutes
///   "1h 30m 15s" → mixed, whitespace-tolerant
///   "1:30"     → mm:ss → 90 seconds
///   "1:30:00"  → hh:mm:ss → 1.5 hours
enum DurationParser {
    static func seconds(from raw: String) -> TimeInterval? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !input.isEmpty else { return nil }

        if input.contains(":") {
            let parts = input.split(separator: ":").map(String.init)
            guard let nums = try? parts.map({ p -> Int in
                guard let n = Int(p) else { throw NumberError.invalid }
                return n
            }) else { return nil }
            switch nums.count {
            case 2: return TimeInterval(nums[0] * 60 + nums[1])
            case 3: return TimeInterval(nums[0] * 3_600 + nums[1] * 60 + nums[2])
            default: return nil
            }
        }

        // Suffixed components like "1h30m15s"
        let pattern = #"(\d+)\s*([hms])"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = regex.matches(in: input, range: range)
        if !matches.isEmpty {
            var total: TimeInterval = 0
            for m in matches {
                guard let valueRange = Range(m.range(at: 1), in: input),
                      let unitRange = Range(m.range(at: 2), in: input),
                      let value = Int(input[valueRange]) else { continue }
                switch input[unitRange] {
                case "h": total += TimeInterval(value * 3_600)
                case "m": total += TimeInterval(value * 60)
                case "s": total += TimeInterval(value)
                default: break
                }
            }
            return total > 0 ? total : nil
        }

        // Bare integer → assume minutes
        if let n = Int(input), n > 0 {
            return TimeInterval(n * 60)
        }
        return nil
    }

    private enum NumberError: Error { case invalid }
}
