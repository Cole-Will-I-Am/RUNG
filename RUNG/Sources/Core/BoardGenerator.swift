import Foundation

/// One day's shared board: a multiset of `tileCount` letters every player gets. Tiles
/// are reusable across words; a word is playable iff its letter histogram is ≤ the
/// board's histogram.
struct DailyBoard: Equatable {
    let dayIndex: Int
    let tiles: [Character]    // sorted A…Z, count == tileCount
    let histogram: [Int]      // 26 buckets, A…Z
    let playableCount: Int    // dictionary words playable on this board
    let maxWordScore: Int     // best single-word base score available
    let attempts: Int         // resample attempts the generator needed

    var tileString: String { String(tiles) }
}

/// Deterministic daily-board generation. Same `dayIndex` → identical board on every
/// device (SplitMix64 + a fixed weighted draw + solver-checked quality gates), so the
/// global leaderboard is fair with zero server state. Validated against the design
/// agent's reference: day 0 → "AEFGIIKNNPUU" (after vowel-gate resamples).
enum BoardGenerator {

    /// Whole UTC days since 2025-01-01 (the day-index epoch).
    static func dayIndex(for date: Date, epoch: TimeInterval = GameConfig.dayEpoch) -> Int {
        Int(floor((date.timeIntervalSince1970 - epoch) / 86_400))
    }

    private static let vowelIndices: Set<Int> = [0, 4, 8, 14, 20]   // A E I O U

    /// Inclusive prefix sums of the letter weights, plus the total.
    private static func cumulative(_ weights: [Int]) -> (cum: [UInt64], total: UInt64) {
        var cum = [UInt64](); cum.reserveCapacity(weights.count)
        var run: UInt64 = 0
        for w in weights { run &+= UInt64(w); cum.append(run) }
        return (cum, run)
    }

    /// Draw one letter index A…Z (0…25) consuming exactly one RNG output. Matches the
    /// reference spec bit-for-bit: r = next() % total, smallest i with r < cum[i].
    static func drawLetterIndex(_ rng: inout SplitMix64, cum: [UInt64], total: UInt64) -> Int {
        let r = rng.next() % total
        var i = 0
        while r >= cum[i] { i += 1 }
        return i
    }

    static func generate(dayIndex: Int, dictionary: WordDictionary, config: GameConfig = .default) -> DailyBoard {
        let gates = config.board
        let (cum, total) = cumulative(gates.letterWeights)
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(dayIndex)))

        var attempts = 0
        while attempts < gates.maxAttempts {
            attempts += 1

            var hist = [Int](repeating: 0, count: 26)
            var vowels = 0
            for _ in 0..<config.tileCount {
                let i = drawLetterIndex(&rng, cum: cum, total: total)
                hist[i] += 1
                if vowelIndices.contains(i) { vowels += 1 }
            }

            // Cheap gate first: vowel balance. Reject → the stream has already advanced,
            // so the next attempt deterministically differs (no re-seed, no rewind).
            if vowels < gates.minVowels || vowels > gates.maxVowels { continue }

            // Solve the candidate board.
            var playable = 0, maxScore = 0, longWords = 0, shortWords = 0
            var k = 0
            while k < dictionary.solveCount {
                if dictionary.solveWordFits(k, board: hist) {
                    playable += 1
                    let sc = dictionary.solveScore[k]
                    if sc > maxScore { maxScore = sc }
                    let len = dictionary.solveLength[k]
                    if len >= gates.longWordLength { longWords += 1 }
                    if len <= gates.shortWordLength { shortWords += 1 }
                }
                k += 1
            }

            if playable < gates.minPlayable || playable > gates.maxPlayable { continue }
            if longWords < gates.minLongWords || shortWords < gates.minShortWords { continue }

            // Accept: expand the histogram to sorted tiles.
            var tiles = [Character]()
            tiles.reserveCapacity(config.tileCount)
            for idx in 0..<26 {
                for _ in 0..<hist[idx] {
                    tiles.append(Character(UnicodeScalar(65 + idx)!))
                }
            }
            return DailyBoard(dayIndex: dayIndex, tiles: tiles, histogram: hist,
                              playableCount: playable, maxWordScore: maxScore, attempts: attempts)
        }

        // Unreachable in practice (observed max ≈ 9 attempts). Surface loudly if hit.
        fatalError("BoardGenerator exceeded maxAttempts=\(gates.maxAttempts) for day \(dayIndex)")
    }
}
