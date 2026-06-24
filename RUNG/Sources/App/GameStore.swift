import Foundation
import Combine

/// The app's central state: loads the bundled dictionary and today's deterministic
/// board, drives the live run clock, and persists stats. The run rules all live in the
/// pure `RunEngine` (unit-tested); this class is the timer + glue + navigation.
@MainActor
final class GameStore: ObservableObject {
    enum Phase: Equatable { case loading, onboarding, home, countdown, run, result }

    @Published var phase: Phase = .loading
    @Published private(set) var board: DailyBoard?
    @Published private(set) var run: RunEngine?
    @Published private(set) var lastResult: RunResult?
    @Published private(set) var stats: PlayerStats
    @Published private(set) var loadFailed = false
    /// A practice run does not count toward the daily once-per-day run, streak, or best.
    @Published private(set) var isPractice = false

    let config = GameConfig.default
    private var dictionary: WordDictionary?
    private let local = LocalStore()
    private var timer: Timer?
    private var lastTick: Date?
    private var lastWholeSecond = -1

    /// Human-facing day number (1-based).
    var dayNumber: Int { (board?.dayIndex ?? 0) + 1 }
    var notificationsOn: Bool { local.notificationsOn }

    /// Whether the official once-a-day run has already been played for today's board.
    var playedToday: Bool {
        guard let d = board?.dayIndex else { return false }
        return stats.lastPlayedDayIndex == d
    }

    init() {
        self.stats = LocalStore().loadStats()
    }

    // MARK: load

    func bootstrap() {
        guard dictionary == nil else { return }
        let cfg = config
        Task.detached(priority: .userInitiated) {
            guard let url = Bundle.main.url(forResource: "words", withExtension: "txt"),
                  let dict = try? WordDictionary.load(contentsOf: url) else {
                await MainActor.run { [weak self] in self?.loadFailed = true }
                return
            }
            let day = BoardGenerator.dayIndex(for: Date())
            let board = BoardGenerator.generate(dayIndex: day, dictionary: dict, config: cfg)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.dictionary = dict
                self.board = board
                if self.phase == .loading {
                    self.phase = self.local.hasOnboarded ? .home : .onboarding
                }
                // Re-arm the daily reminder if the player previously authorized it.
                NotificationService.scheduleDailyIfAuthorized()
            }
        }
    }

    func finishOnboarding() {
        local.hasOnboarded = true
        phase = .home
    }

    // MARK: run lifecycle

    /// Start the daily run. The official run is once per day (blueprint scarcity); pass
    /// `practice: true` for an extra run that doesn't count toward the day/streak/best —
    /// useful for playtesting the core loop (Milestone 0).
    func startCountdown(practice: Bool = false) {
        guard board != nil, dictionary != nil else { return }
        if playedToday && !practice { return }
        isPractice = practice
        phase = .countdown
    }

    func beginRun() {
        guard let board, let dictionary else { return }
        run = RunEngine(config: config, board: board, dictionary: dictionary)
        lastTick = Date()
        lastWholeSecond = Int(config.clockSeconds.rounded(.up))
        phase = .run
        startTimer()
    }

    @discardableResult
    func submit(_ raw: String) -> SubmitOutcome {
        guard var r = run, r.isRunning else { return .runEnded }
        let out = r.submit(raw)
        run = r
        switch out {
        case .accepted:  Haptics.wordValid()
        case .runEnded:  break
        default:         Haptics.reject()
        }
        return out
    }

    func bank() {
        guard var r = run, r.isRunning else { return }
        let result = r.bank()
        run = r
        Haptics.bank()
        endRun(result)
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard phase == .run, var r = run, r.isRunning else { return }
        let now = Date()
        r.advance(by: now.timeIntervalSince(lastTick ?? now))
        lastTick = now
        run = r

        // Calm tick haptics in the final 5 seconds, once per whole second (§8.1).
        let whole = Int(r.timeRemaining.rounded(.up))
        if r.timeRemaining <= 5, whole != lastWholeSecond, whole > 0 {
            Haptics.tick()
        }
        lastWholeSecond = whole

        if !r.isRunning { endRun(r.result()) }   // busted out
    }

    private func endRun(_ result: RunResult) {
        timer?.invalidate(); timer = nil
        lastResult = result
        if !isPractice { recordStats(result) }
        phase = .result
    }

    /// Called when the app returns to the foreground. Don't charge the time spent in the
    /// background to a mid-run clock, and roll the board over if the UTC day changed.
    func handleBecameActive() {
        lastTick = Date()
        guard phase == .home || phase == .result || phase == .onboarding else { return }
        guard let dictionary, let board,
              BoardGenerator.dayIndex(for: Date()) != board.dayIndex else { return }
        let cfg = config
        Task.detached(priority: .userInitiated) {
            let day = BoardGenerator.dayIndex(for: Date())
            let nb = BoardGenerator.generate(dayIndex: day, dictionary: dictionary, config: cfg)
            await MainActor.run { [weak self] in
                self?.board = nb
                self?.run = nil
                if self?.phase == .result { self?.phase = .home }
            }
        }
    }

    func goHome() {
        run = nil
        phase = .home
    }

    // MARK: stats

    private func recordStats(_ result: RunResult) {
        var s = stats
        let today = result.dayIndex
        if s.lastPlayedDayIndex != today {
            if let last = s.lastPlayedDayIndex, last == today - 1 {
                s.currentStreak += 1
            } else {
                s.currentStreak = 1
            }
            s.lastPlayedDayIndex = today
            s.bestStreak = max(s.bestStreak, s.currentStreak)
        }
        s.totalRuns += 1
        s.bestScore = max(s.bestScore, result.finalScore)
        s.history.insert(result, at: 0)
        if s.history.count > 50 { s.history.removeLast(s.history.count - 50) }
        stats = s
        local.saveStats(s)
    }

    func setNotifications(_ on: Bool) {
        local.notificationsOn = on
        if on { NotificationService.requestAndSchedule() } else { NotificationService.disable() }
    }
}
