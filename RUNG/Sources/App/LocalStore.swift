import Foundation

/// The player's persistent stats (blueprint §6). Local-only for now; a real account +
/// global/friends leaderboards (§5) are designed-for, not built in this scaffold.
struct PlayerStats: Codable, Equatable {
    var currentStreak = 0
    var bestStreak = 0
    var lastPlayedDayIndex: Int? = nil
    var bestScore = 0
    var totalRuns = 0
    var history: [RunResult] = []      // most-recent first, capped

    /// Average final score across recorded runs.
    var averageScore: Int {
        guard !history.isEmpty else { return 0 }
        return history.map(\.finalScore).reduce(0, +) / history.count
    }
}

/// Tiny JSON-file persistence in the app's Documents directory, plus the onboarding flag.
final class LocalStore {
    private let fileName = "rung-stats.json"
    private let onboardedKey = "rung.hasOnboarded"
    private let notifyKey = "rung.notificationsOn"

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    func loadStats() -> PlayerStats {
        guard let data = try? Data(contentsOf: fileURL),
              let stats = try? JSONDecoder().decode(PlayerStats.self, from: data)
        else { return PlayerStats() }
        return stats
    }

    func saveStats(_ stats: PlayerStats) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: onboardedKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardedKey) }
    }

    var notificationsOn: Bool {
        get { UserDefaults.standard.bool(forKey: notifyKey) }
        set { UserDefaults.standard.set(newValue, forKey: notifyKey) }
    }
}
