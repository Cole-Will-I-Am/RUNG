import Foundation

/// The word list used both to validate played words and to score candidate daily
/// boards. Built from a bundled, public-domain ENABLE word list (uppercase A–Z).
///
/// `contains` is O(1) membership for live play. The "solve" arrays (precomputed
/// letter histograms for words up to the tile count) let the board generator score a
/// candidate board fast. Pure Foundation so it unit-tests off-device.
final class WordDictionary {
    let scoring: ScoringRule
    let words: [String]
    private let membership: Set<String>

    // Parallel arrays for the board solver (only words of length 3...solveMaxLength).
    let solveCount: Int
    let solveScore: [Int]
    let solveLength: [Int]
    private let solveHist: ContiguousArray<UInt8>   // solveCount * 26, row-major A…Z

    init(words rawWords: [String], scoring: ScoringRule = ScoringRule(), solveMaxLength: Int = 12) {
        self.scoring = scoring
        self.words = rawWords
        self.membership = Set(rawWords)

        var score = [Int](); var length = [Int]()
        var hist = ContiguousArray<UInt8>(); hist.reserveCapacity(rawWords.count * 26)
        for w in rawWords {
            let n = w.count
            guard n >= 3, n <= solveMaxLength else { continue }
            var row = [UInt8](repeating: 0, count: 26)
            var ok = true
            for u in w.unicodeScalars {
                let v = Int(u.value) - 65
                if v < 0 || v > 25 { ok = false; break }
                row[v] &+= 1
            }
            guard ok else { continue }
            score.append(scoring.baseScore(forWord: w))
            length.append(n)
            hist.append(contentsOf: row)
        }
        self.solveScore = score
        self.solveLength = length
        self.solveHist = hist
        self.solveCount = score.count
    }

    func contains(_ word: String) -> Bool { membership.contains(word) }

    /// 26-bucket letter histogram (A…Z) of an uppercase word, or nil if it contains a
    /// non A–Z character.
    static func histogram(of word: String) -> [Int]? {
        var h = [Int](repeating: 0, count: 26)
        for u in word.unicodeScalars {
            let v = Int(u.value) - 65
            if v < 0 || v > 25 { return nil }
            h[v] += 1
        }
        return h
    }

    /// Does solve-word `i` fit under a board histogram (each letter count ≤ board's)?
    func solveWordFits(_ i: Int, board: [Int]) -> Bool {
        let base = i * 26
        var k = 0
        while k < 26 {
            if Int(solveHist[base + k]) > board[k] { return false }
            k += 1
        }
        return true
    }

    /// Load a newline-separated word list from a file (works on iOS and Linux).
    static func load(contentsOf url: URL, scoring: ScoringRule = ScoringRule(), solveMaxLength: Int = 12) throws -> WordDictionary {
        let text = try String(contentsOf: url, encoding: .utf8)
        let words = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.uppercased() }
        return WordDictionary(words: words, scoring: scoring, solveMaxLength: solveMaxLength)
    }
}
