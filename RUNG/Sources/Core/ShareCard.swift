import Foundation

/// Spoiler-free share text for a finished run. It reveals the day number, the score,
/// and the multiplier reached — never the words played — so sharing can't ruin the
/// puzzle for someone who hasn't played yet (à la Wordle's emoji grid). Voice is the
/// brand's: calm, sentence case, no hype.
enum ShareCard {
    /// `dayNumberOffset` makes the human-facing number 1-based (dayIndex 0 → "#1").
    static func text(for r: RunResult, dayNumberOffset: Int = 1) -> String {
        let day = r.dayIndex + dayNumberOffset
        let score = decimal(r.finalScore)
        let peak = mult(r.peakMultiplier)
        switch r.outcome {
        case .banked:
            return "RUNG #\(day)\n\(score) — banked at \(mult(r.bankedMultiplier))\npeak \(peak)"
        case .bustedOut:
            return "RUNG #\(day)\n\(score) — pushed too far\npeak \(peak)"
        case .inProgress:
            return "RUNG #\(day)\nin progress"
        }
    }

    /// A one-line headline used on the result screen.
    static func headline(for r: RunResult) -> String {
        switch r.outcome {
        case .banked:    return "Nice climb. You banked at \(mult(r.bankedMultiplier))."
        case .bustedOut: return "The clock won that one. You kept your base."
        case .inProgress: return "Run in progress."
        }
    }

    static func mult(_ m: Double) -> String { "×" + String(format: "%.1f", m) }

    static func decimal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
