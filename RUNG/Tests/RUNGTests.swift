import XCTest
@testable import RUNG

// iOS unit tests (run on the simulator in CI). The engine is pure Foundation, so most
// tests build an in-memory dictionary and need no bundled resource; one optional test
// checks the bundled word list reproduces the reference daily board.

final class RUNGEngineTests: XCTestCase {

    private func dict() -> WordDictionary {
        WordDictionary(words: ["CAT", "DOG", "PEN", "FOUR", "BREAD", "PLANTS",
                               "COUNTER", "COUNTERS", "PLANTER", "EEL", "QUARTZ", "JUKEBOX"],
                       scoring: ScoringRule())
    }

    private func openBoard() -> DailyBoard {
        DailyBoard(dayIndex: 0, tiles: [], histogram: [Int](repeating: 3, count: 26),
                   playableCount: 0, maxWordScore: 0, attempts: 0)
    }

    func testSplitMix64Reference() {
        var rng = SplitMix64(seed: 0)
        XCTAssertEqual(rng.next(), 0xE220_A839_7B1D_CDAF)
    }

    func testScoring() {
        let s = ScoringRule()
        XCTAssertEqual(s.baseScore(forWord: "CAT"), 100)
        XCTAssertEqual(s.baseScore(forWord: "COUNTERS"), 1200)
        XCTAssertEqual(s.baseScore(forWord: "QUARTZ"), 800)   // 700 + Q + Z
    }

    func testTimeRefundTiers() {
        let r = TimeRefundRule()
        XCTAssertEqual(r.seconds(forLength: 4), 0)
        XCTAssertEqual(r.seconds(forLength: 6), 2)
        XCTAssertEqual(r.seconds(forLength: 9), 3)
    }

    func testAcceptAndBank() {
        var e = RunEngine(config: .default, board: openBoard(), dictionary: dict())
        if case .accepted = e.submit("bread") {} else { XCTFail("expected accept") }
        XCTAssertEqual(e.baseSum, 450)
        XCTAssertEqual(e.multiplier, 1.2, accuracy: 1e-9)
        let r = e.bank()
        XCTAssertEqual(r.outcome, .banked)
        XCTAssertEqual(r.finalScore, Int((450.0 * 1.2).rounded()))
    }

    func testBustForfeitsMultiplier() {
        var e = RunEngine(config: .default, board: openBoard(), dictionary: dict())
        _ = e.submit("BREAD")
        e.advance(by: 60)
        let r = e.result()
        XCTAssertEqual(r.outcome, .bustedOut)
        XCTAssertEqual(r.finalScore, 450)            // multiplier bonus forfeited
    }

    func testRejections() {
        var e = RunEngine(config: .default, board: openBoard(), dictionary: dict())
        XCTAssertEqual(e.submit("at"), .rejectedTooShort)
        XCTAssertEqual(e.submit("ZZZQ"), .rejectedNotAWord)
        _ = e.submit("CAT")
        XCTAssertEqual(e.submit("CAT"), .rejectedAlreadyUsed)
    }

    /// Optional: if the bundled dictionary is reachable from the test host, confirm the
    /// deterministic day-0 board matches the validated reference tiles.
    func testBundledDayZeroBoard() throws {
        guard let url = Bundle.main.url(forResource: "words", withExtension: "txt") else {
            throw XCTSkip("words.txt not reachable from the test host bundle")
        }
        let dictionary = try WordDictionary.load(contentsOf: url)
        let board = BoardGenerator.generate(dayIndex: 0, dictionary: dictionary)
        XCTAssertEqual(board.tileString, "AEFGIIKNNPUU")
    }
}
