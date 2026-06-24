import XCTest
import Foundation
@testable import RungCore

/// Shared, lazily-loaded dictionary from the bundled word list so we don't re-parse
/// 152k words per test. Path is resolved relative to this source file → repo root.
enum TestDict {
    static let shared: WordDictionary = {
        let here = URL(fileURLWithPath: #filePath)
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent()
        let words = repoRoot.appendingPathComponent("RUNG/Resources/words.txt")
        return try! WordDictionary.load(contentsOf: words)
    }()
}

// MARK: - PRNG (must match the reference stream bit-for-bit)

final class SeededRNGTests: XCTestCase {
    func testSplitMix64ReferenceVectorsSeed0() {
        var rng = SplitMix64(seed: 0)
        let expected: [UInt64] = [
            0xE220_A839_7B1D_CDAF, 0x6E78_9E6A_A1B9_65F4, 0x06C4_5D18_8009_454F,
            0xF88B_B8A8_724C_81EC, 0x1B39_896A_51A8_749B,
        ]
        for (i, e) in expected.enumerated() {
            XCTAssertEqual(rng.next(), e, "SplitMix64(0) output \(i) drifted from reference")
        }
    }

    func testSplitMix64ReferenceVectorSeed1() {
        var rng = SplitMix64(seed: 1)
        XCTAssertEqual(rng.next(), 0x910A_2DEC_8902_5CC1)
    }
}

// MARK: - Scoring table (blueprint §3.5)

final class ScoringTests: XCTestCase {
    let s = ScoringRule()
    func testBaseLengths() {
        XCTAssertEqual(s.baseScore(forWord: "CAT"), 100)
        XCTAssertEqual(s.baseScore(forWord: "FOUR"), 250)
        XCTAssertEqual(s.baseScore(forWord: "BREAD"), 450)
        XCTAssertEqual(s.baseScore(forWord: "PLANTS"), 700)
    }
    func testSevenPlusAndExtras() {
        XCTAssertEqual(s.baseScore(forWord: "COUNTER"), 1000)            // 7 letters, no rare
        XCTAssertEqual(s.baseScore(forWord: "COUNTERS"), 1200)           // 8 letters → +200
    }
    func testRareLetterBonus() {
        XCTAssertEqual(s.baseScore(forWord: "QUARTZ"), 700 + 50 + 50)    // Q + Z
        XCTAssertEqual(s.baseScore(forWord: "JUKEBOX"), 1000 + 150)      // J + K + X
    }
}

// MARK: - Time refund (length-scaled — the red-team's spam fix)

final class TimeRefundTests: XCTestCase {
    let r = TimeRefundRule()
    func testTiers() {
        XCTAssertEqual(r.seconds(forLength: 3), 0)
        XCTAssertEqual(r.seconds(forLength: 4), 0)
        XCTAssertEqual(r.seconds(forLength: 5), 1)
        XCTAssertEqual(r.seconds(forLength: 6), 2)
        XCTAssertEqual(r.seconds(forLength: 7), 3)
        XCTAssertEqual(r.seconds(forLength: 11), 3)
    }
}

// MARK: - Deterministic board generation (reference: day 0 → AEFGIIKNNPUU)

final class BoardGeneratorTests: XCTestCase {
    func testDayZeroMatchesReference() {
        let board = BoardGenerator.generate(dayIndex: 0, dictionary: TestDict.shared)
        XCTAssertEqual(board.tileString, "AEFGIIKNNPUU",
                       "day-0 board drifted from the validated reference tiles")
        XCTAssertEqual(board.tiles.count, 12)
        // Quality gates held.
        XCTAssertGreaterThanOrEqual(board.playableCount, 80)
        XCTAssertLessThanOrEqual(board.playableCount, 800)
        XCTAssertGreaterThanOrEqual(board.maxWordScore, 1000)   // at least one 7+ word
    }

    func testDeterminism() {
        let a = BoardGenerator.generate(dayIndex: 0, dictionary: TestDict.shared)
        let b = BoardGenerator.generate(dayIndex: 0, dictionary: TestDict.shared)
        XCTAssertEqual(a, b)
    }

    func testVowelGate() {
        let board = BoardGenerator.generate(dayIndex: 7, dictionary: TestDict.shared)
        let vowels = board.tiles.filter { "AEIOU".contains($0) }.count
        XCTAssertGreaterThanOrEqual(vowels, 4)
        XCTAssertLessThanOrEqual(vowels, 6)
    }
}

// MARK: - Run engine (bank/push, multiplier, clock, rejections)

final class RunEngineTests: XCTestCase {
    /// A permissive board (3 of every letter) so arbitrary short words are playable.
    private func openBoard(day: Int = 0) -> DailyBoard {
        DailyBoard(dayIndex: day, tiles: [], histogram: [Int](repeating: 3, count: 26),
                   playableCount: 0, maxWordScore: 0, attempts: 0)
    }

    func testAcceptScoresAndStepsMultiplier() {
        var e = RunEngine(config: .default, board: openBoard(), dictionary: TestDict.shared)
        let out = e.submit("cat")                 // lowercase tolerated
        guard case .accepted(let w, let pts, let refund, let mult) = out else { return XCTFail("expected accept, got \(out)") }
        XCTAssertEqual(w, "CAT")
        XCTAssertEqual(pts, 100)
        XCTAssertEqual(refund, 0)                 // 3 letters → no refund
        XCTAssertEqual(mult, 1.2, accuracy: 1e-9)
        XCTAssertEqual(e.baseSum, 100)
        XCTAssertEqual(e.potentialScore, 120)     // 100 × 1.2
    }

    func testRejections() {
        var e = RunEngine(config: .default, board: openBoard(), dictionary: TestDict.shared)
        XCTAssertEqual(e.submit("at"), .rejectedTooShort)
        XCTAssertEqual(e.submit("ZZZQ"), .rejectedNotAWord)      // not in dictionary
        _ = e.submit("CAT")
        XCTAssertEqual(e.submit("CAT"), .rejectedAlreadyUsed)

        // Tight board (one of every letter) → a real word needing a doubled letter is
        // unplayable: "EEL" needs two E's.
        var tight = RunEngine(config: .default,
                              board: DailyBoard(dayIndex: 0, tiles: [], histogram: [Int](repeating: 1, count: 26),
                                                playableCount: 0, maxWordScore: 0, attempts: 0),
                              dictionary: TestDict.shared)
        XCTAssertEqual(tight.submit("EEL"), .rejectedNotPlayable)
    }

    func testMultiplierClampsToCap() {
        var cfg = GameConfig.default
        cfg.multiplierCap = 1.4
        var e = RunEngine(config: cfg, board: openBoard(), dictionary: TestDict.shared)
        _ = e.submit("CAT"); _ = e.submit("DOG"); _ = e.submit("PEN")  // 1.2, 1.4, clamp 1.4
        XCTAssertEqual(e.multiplier, 1.4, accuracy: 1e-9)
        XCTAssertEqual(e.peakMultiplier, 1.4, accuracy: 1e-9)
    }

    func testRefundIsCappedAtStartingClock() {
        var e = RunEngine(config: .default, board: openBoard(), dictionary: TestDict.shared)
        XCTAssertEqual(e.timeRemaining, 60, accuracy: 1e-9)
        _ = e.submit("COUNTER")                    // 7 letters → +3s, but clock already full
        XCTAssertEqual(e.timeRemaining, 60, accuracy: 1e-9)
        e.advance(by: 10)                          // 50s left
        _ = e.submit("PLANTER")                    // +3 → 53
        XCTAssertEqual(e.timeRemaining, 53, accuracy: 1e-9)
    }

    func testBankLocksScoreAndEndsRun() {
        var e = RunEngine(config: .default, board: openBoard(), dictionary: TestDict.shared)
        _ = e.submit("BREAD")                       // 450 base, mult 1.2
        let r = e.bank()
        XCTAssertEqual(r.outcome, .banked)
        XCTAssertEqual(r.finalScore, Int((450.0 * 1.2).rounded()))   // 540
        XCTAssertFalse(e.isRunning)
        XCTAssertEqual(e.submit("CAT"), .runEnded)
    }

    func testBustForfeitsMultiplierBonus() {
        var e = RunEngine(config: .default, board: openBoard(), dictionary: TestDict.shared)
        _ = e.submit("BREAD")                       // baseSum 450, mult 1.2
        e.advance(by: 60)                           // clock to zero → bust
        let r = e.result()
        XCTAssertEqual(r.outcome, .bustedOut)
        XCTAssertEqual(r.finalScore, 450)           // base only, multiplier forfeited
    }
}

// MARK: - Share text (spoiler-free)

final class ShareCardTests: XCTestCase {
    func testRevealsNoWords() {
        let r = RunResult(dayIndex: 141, outcome: .banked, finalScore: 4820,
                          baseSum: 1148, peakMultiplier: 4.2, bankedMultiplier: 4.2, wordCount: 9)
        let text = ShareCard.text(for: r)
        XCTAssertTrue(text.contains("RUNG #142"))   // 1-based day number
        XCTAssertTrue(text.contains("4,820"))
        XCTAssertTrue(text.contains("×4.2"))
    }
}
