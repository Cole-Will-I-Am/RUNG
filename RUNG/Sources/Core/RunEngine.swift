import Foundation

enum RunOutcome: String, Codable { case inProgress, banked, bustedOut }

/// The result of a completed run — the shareable, leaderboard-able summary.
struct RunResult: Equatable, Codable {
    let dayIndex: Int
    let outcome: RunOutcome
    let finalScore: Int
    let baseSum: Int
    let peakMultiplier: Double
    let bankedMultiplier: Double   // multiplier captured at bank; 1.0 if busted out
    let wordCount: Int
}

enum SubmitOutcome: Equatable {
    case accepted(word: String, points: Int, refund: Double, multiplier: Double)
    case rejectedTooShort
    case rejectedNotAWord
    case rejectedNotPlayable
    case rejectedAlreadyUsed
    case runEnded
}

/// The heart of the game — a pure, deterministic run state machine. It does NOT own a
/// timer: the UI (or a test) drives the clock via `advance(by:)`, which keeps the whole
/// thing unit-testable. Encodes every rule the design red-team pinned down:
///
/// • payout = baseSum × multiplier, computed at the instant BANK is pressed;
/// • clock-out forfeits the entire multiplier bonus (keep baseSum × 1.0);
/// • an accepted word adds base points, steps the multiplier (clamped to the cap), and
///   refunds time (length-scaled), with the live clock capped at the starting value;
/// • rejected words score nothing and refund nothing — but the wall-clock seconds spent
///   typing them are already gone, so guessing is self-penalising;
/// • a word already used today is rejected.
struct RunEngine {
    let config: GameConfig
    let board: DailyBoard
    let dictionary: WordDictionary

    private(set) var baseSum = 0
    private(set) var multiplier: Double
    private(set) var peakMultiplier: Double
    private(set) var timeRemaining: Double
    private(set) var outcome: RunOutcome = .inProgress
    private(set) var acceptedWords: [String] = []
    private var used: Set<String> = []

    init(config: GameConfig, board: DailyBoard, dictionary: WordDictionary) {
        self.config = config
        self.board = board
        self.dictionary = dictionary
        self.multiplier = config.multiplierStart
        self.peakMultiplier = config.multiplierStart
        self.timeRemaining = config.clockSeconds
    }

    var isRunning: Bool { outcome == .inProgress }

    /// Score the player would lock in by banking right now (base × current multiplier).
    var potentialScore: Int { Int((Double(baseSum) * multiplier).rounded()) }

    /// Score kept if the clock runs out instead (multiplier bonus forfeited).
    var forfeitScore: Int { baseSum }

    /// Fraction of the starting clock still left, 0…1 (for the clock instrument).
    var timeFraction: Double { min(max(timeRemaining / config.clockSeconds, 0), 1) }

    /// Advance the run clock. When it reaches zero the run busts out (multiplier lost).
    mutating func advance(by dt: Double) {
        guard outcome == .inProgress, dt > 0 else { return }
        timeRemaining -= dt
        if timeRemaining <= 0 {
            timeRemaining = 0
            outcome = .bustedOut
        }
    }

    /// Submit a typed word.
    @discardableResult
    mutating func submit(_ raw: String) -> SubmitOutcome {
        guard outcome == .inProgress else { return .runEnded }
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if word.count < 3 { return .rejectedTooShort }
        if used.contains(word) { return .rejectedAlreadyUsed }
        guard dictionary.contains(word) else { return .rejectedNotAWord }
        guard let h = WordDictionary.histogram(of: word), fits(h) else { return .rejectedNotPlayable }

        let points = config.scoring.baseScore(forWord: word)
        baseSum += points
        multiplier = min(config.multiplierCap, multiplier + config.multiplierStep)
        peakMultiplier = max(peakMultiplier, multiplier)
        let refund = config.timeRefund.seconds(forLength: word.count)
        timeRemaining = min(config.clockSeconds, timeRemaining + refund)
        used.insert(word)
        acceptedWords.append(word)
        return .accepted(word: word, points: points, refund: refund, multiplier: multiplier)
    }

    private func fits(_ h: [Int]) -> Bool {
        var k = 0
        while k < 26 {
            if h[k] > board.histogram[k] { return false }
            k += 1
        }
        return true
    }

    /// Bank the current total and end the run. Idempotent once the run has ended.
    @discardableResult
    mutating func bank() -> RunResult {
        if outcome == .inProgress { outcome = .banked }
        return result()
    }

    /// The current result snapshot (valid once banked or busted; 0 while running).
    func result() -> RunResult {
        let final: Int
        let bankedMult: Double
        switch outcome {
        case .banked:
            final = potentialScore; bankedMult = multiplier
        case .bustedOut:
            final = forfeitScore; bankedMult = config.multiplierStart
        case .inProgress:
            final = 0; bankedMult = multiplier
        }
        return RunResult(dayIndex: board.dayIndex, outcome: outcome, finalScore: final,
                         baseSum: baseSum, peakMultiplier: peakMultiplier,
                         bankedMultiplier: bankedMult, wordCount: acceptedWords.count)
    }
}
