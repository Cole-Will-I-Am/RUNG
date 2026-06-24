import Foundation

// RUNG tuning lives here as DATA, not hardcoded constants (blueprint §10.4): the
// clock, multiplier curve, time-refund, scoring table, board gates, and monetization
// feature flags are all Codable so a server-delivered config can later tune game feel
// without an App Store review. The defaults below are the playtest-hardened values
// from the design red-team (see Tuning notes in the repo): a 60s clock and a
// LENGTH-SCALED time refund, which together make bank-vs-push genuinely tense and
// defeat the 3-letter-spam exploit that the doc's flat +3s refund allowed.

struct FeatureFlags: Codable, Equatable {
    var adsEnabled = false
    var subscriptionEnabled = false
    var archiveEnabled = false
    var friendsLeaderboardEnabled = false
}

/// Base-point scoring table (blueprint §3.5).
struct ScoringRule: Codable, Equatable {
    var byLength: [Int: Int] = [3: 100, 4: 250, 5: 450, 6: 700]
    var sevenPlusBase = 1000
    var sevenPlusPerExtra = 200
    var rareLetters = "JQXZKVW"
    var rareLetterBonus = 50

    func baseScore(forWord word: String) -> Int {
        let n = word.count
        var s = n >= 7 ? sevenPlusBase + sevenPlusPerExtra * (n - 7) : (byLength[n] ?? 0)
        if rareLetterBonus != 0 {
            let rare = Set(rareLetters)
            for ch in word where rare.contains(ch) { s += rareLetterBonus }
        }
        return s
    }
}

/// Length-scaled time refund for an ACCEPTED word (the red-team's spam fix): a tier's
/// `seconds` applies when the word length is >= its `minLength`; the highest matching
/// tier wins. Default → 0s for len ≤4, +1s for 5, +2s for 6, +3s for 7+.
struct TimeRefundRule: Codable, Equatable {
    struct Tier: Codable, Equatable { var minLength: Int; var seconds: Double }
    var tiers: [Tier] = [
        Tier(minLength: 5, seconds: 1),
        Tier(minLength: 6, seconds: 2),
        Tier(minLength: 7, seconds: 3),
    ]
    func seconds(forLength len: Int) -> Double {
        var r = 0.0
        for t in tiers where len >= t.minLength { r = max(r, t.seconds) }
        return r
    }
}

/// Deterministic daily-board generation parameters (validated by the solver agent).
struct BoardGates: Codable, Equatable {
    var minVowels = 4
    var maxVowels = 6
    var minPlayable = 80
    var maxPlayable = 800
    var minLongWords = 1          // ≥1 word of `longWordLength`+ (guarantees a trophy word)
    var longWordLength = 7
    var minShortWords = 20        // ≥20 words ≤ `shortWordLength` (chain fuel)
    var shortWordLength = 4
    var maxAttempts = 10000
    var solveMaxWordLength = 12   // words longer than the tile count can never be played
    // Weighted tile-draw distribution in A…Z order (tuned: Scrabble-like, vowel-rich).
    var letterWeights: [Int] = [9, 2, 3, 4, 12, 2, 3, 3, 8, 1, 2, 4, 3, 6, 7, 3, 1, 6, 6, 6, 4, 2, 2, 1, 2, 1]
}

struct GameConfig: Codable, Equatable {
    var clockSeconds: Double = 60
    var multiplierStart: Double = 1.0
    var multiplierStep: Double = 0.2
    var multiplierCap: Double = 5.0
    var tileCount: Int = 12
    var scoring = ScoringRule()
    var timeRefund = TimeRefundRule()
    var board = BoardGates()
    var flags = FeatureFlags()

    static let `default` = GameConfig()

    /// Day-index epoch: 2025-01-01 00:00:00 UTC. dayIndex = whole UTC days since then.
    static let dayEpoch: TimeInterval = 1_735_689_600
}
