import Foundation
import Combine

/// The app's central state: loads the dictionary + today's deterministic board, drives
/// the live run clock, persists local stats, and talks to the competitive backend
/// (accounts, server-authoritative run submission, leaderboard). Run rules live in the
/// pure `RunEngine`; this class is the timer + glue + navigation + networking.
@MainActor
final class GameStore: ObservableObject {
    enum Phase: Equatable { case loading, onboarding, home, countdown, run, result }

    @Published var phase: Phase = .loading
    @Published private(set) var board: DailyBoard?
    @Published private(set) var run: RunEngine?
    @Published private(set) var lastResult: RunResult?
    @Published private(set) var stats: PlayerStats
    @Published private(set) var loadFailed = false
    /// A practice run uses a random board and does NOT count toward the daily run,
    /// streak, best, or the leaderboard.
    @Published private(set) var isPractice = false

    // Backend / competitive state
    @Published private(set) var account: BackendAccount?
    @Published private(set) var serverResult: RunResultResponse?
    @Published private(set) var leaderboard: LeaderboardResponse?
    @Published private(set) var leaderboardPeriod = "daily"

    let config = GameConfig.default
    let backend = Backend()
    private var dictionary: WordDictionary?
    private let local = LocalStore()
    private var timer: Timer?
    private var lastTick: Date?
    private var lastWholeSecond = -1

    private var token: String?
    private var practiceBoard: DailyBoard?
    private var runId: String?
    private var runToken: String?
    private var runStartDate: Date?
    private var events: [RunEventDTO] = []

    private var activeBoard: DailyBoard? { isPractice ? practiceBoard : board }

    var dayNumber: Int { (board?.dayIndex ?? 0) + 1 }
    var notificationsOn: Bool { local.notificationsOn }
    var isSignedIn: Bool { account?.isAnonymous == false }

    var playedToday: Bool {
        guard let d = board?.dayIndex else { return false }
        return stats.lastPlayedDayIndex == d
    }

    init() {
        self.stats = LocalStore().loadStats()
        self.token = Keychain.get("rung.session")
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
                NotificationService.scheduleDailyIfAuthorized()
                Task { await self.ensureAccount() }
            }
        }
    }

    func finishOnboarding() {
        local.hasOnboarded = true
        phase = .home
    }

    // MARK: account

    private func ensureAccount() async {
        let device = Keychain.deviceId()
        if let token, let acc = try? await backend.me(token: token) {
            account = acc
            return
        }
        if let resp = try? await backend.registerAnon(deviceId: device) {
            token = resp.token
            Keychain.set("rung.session", resp.token)
            account = resp.player
        }
    }

    func signInWithApple(identityToken: String, nonce: String) {
        let device = Keychain.deviceId()
        Task {
            if let resp = try? await backend.signInApple(identityToken: identityToken, nonce: nonce, deviceId: device) {
                token = resp.token
                Keychain.set("rung.session", resp.token)
                account = resp.player
            }
        }
    }

    func setUsername(_ name: String) async -> String? {
        guard let token else { return "Not signed in." }
        do { account = try await backend.setUsername(token: token, username: name); return nil }
        catch BackendError.server(_, let msg) { return msg }
        catch { return "Couldn't set username." }
    }

    /// Delete the account + all its data (Apple requires in-app deletion), then start
    /// fresh with a new anonymous identity.
    func deleteAccount() async {
        if let token { try? await backend.deleteAccount(token: token) }
        Keychain.delete("rung.session")
        token = nil
        account = nil
        await ensureAccount()
    }

    // MARK: run lifecycle

    /// Start the daily (ranked) run. The official run is once per day; pass
    /// `practice: true` for an unlimited Endless run on a random board (not ranked).
    func startCountdown(practice: Bool = false) {
        guard let dictionary else { return }
        if practice {
            isPractice = true
            let seed = Int.random(in: 1_000_000_000..<2_000_000_000) // never a real day index
            practiceBoard = BoardGenerator.generate(dayIndex: seed, dictionary: dictionary, config: config)
            phase = .countdown
            return
        }
        guard board != nil, !playedToday else { return }
        isPractice = false
        runId = nil; runToken = nil
        // Anchor the run server-side for anti-cheat; resolves during the countdown.
        if let token {
            Task {
                if let s = try? await backend.runStart(token: token) {
                    runId = s.runId; runToken = s.runToken
                }
            }
        }
        phase = .countdown
    }

    func beginRun() {
        guard let dictionary, let b = activeBoard else { return }
        run = RunEngine(config: config, board: b, dictionary: dictionary)
        runStartDate = Date()
        events = []
        serverResult = nil
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
        case .accepted(let word, _, _, _):
            Haptics.wordValid()
            if let start = runStartDate {
                events.append(RunEventDTO(word: word, t_ms: Int(Date().timeIntervalSince(start) * 1000)))
            }
        case .runEnded:
            break
        default:
            Haptics.reject()
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

        let whole = Int(r.timeRemaining.rounded(.up))
        if r.timeRemaining <= 5, whole != lastWholeSecond, whole > 0 { Haptics.tick() }
        lastWholeSecond = whole

        if !r.isRunning { endRun(r.result()) }
    }

    private func endRun(_ result: RunResult) {
        timer?.invalidate(); timer = nil
        lastResult = result
        if !isPractice {
            recordStats(result)
            submitDailyRun(result)
        }
        phase = .result
    }

    /// Submit the finished daily run for server-authoritative scoring + ranking. Silently
    /// no-ops if there's no session or the run wasn't server-anchored (offline) — the run
    /// still counts locally; it just won't appear on the global leaderboard.
    private func submitDailyRun(_ result: RunResult) {
        guard let token, let runId, let runToken, let board else { return }
        let evs = events
        let bankMs: Int? = result.outcome == .banked
            ? Int(Date().timeIntervalSince(runStartDate ?? Date()) * 1000) : nil
        let day = board.dayIndex
        Task {
            if let r = try? await backend.submitRun(token: token, runId: runId, runToken: runToken,
                                                    dayIndex: day, events: evs, bankT_ms: bankMs) {
                serverResult = r
                if let acc = try? await backend.me(token: token) { account = acc }
            }
        }
    }

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

    func goHome() { run = nil; phase = .home }

    // MARK: leaderboard

    func fetchLeaderboard(period: String) {
        leaderboardPeriod = period
        Task {
            if let lb = try? await backend.leaderboard(period: period, token: token) { leaderboard = lb }
        }
    }

    // MARK: stats

    private func recordStats(_ result: RunResult) {
        var s = stats
        let today = result.dayIndex
        if s.lastPlayedDayIndex != today {
            if let last = s.lastPlayedDayIndex, last == today - 1 { s.currentStreak += 1 }
            else { s.currentStreak = 1 }
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
