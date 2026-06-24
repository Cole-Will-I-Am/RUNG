import SwiftUI

// Calm Paper-mode meta screens (§5.1): onboarding, stats, leaderboard, settings.

private struct SheetHeader: View {
    let title: String
    let onDone: () -> Void
    var body: some View {
        HStack {
            Text(title).font(Type.h1).foregroundStyle(Palette.onPaperPrimary)
            Spacer()
            Button("Done", action: onDone)
                .font(Type.body)
                .foregroundStyle(Palette.onPaperPrimary)
        }
    }
}

private struct StatBox: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(Type.instrumentStd)
                .monospacedDigit()
                .foregroundStyle(Palette.onPaperPrimary)
            Text(label)
                .font(Type.label)
                .foregroundStyle(Palette.onPaperSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.s4)
        .background(RoundedRectangle(cornerRadius: Metrics.radiusCard).fill(Palette.paperDeep))
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s6) {
            Spacer()
            Wordmark(color: Palette.onPaperPrimary, size: 56)
            Text("A word game you play once a day.")
                .font(Type.h1)
                .foregroundStyle(Palette.onPaperPrimary)

            VStack(alignment: .leading, spacing: Metrics.s4) {
                howRow("1", "Everyone gets the same twelve letters.")
                howRow("2", "Find words in 60 seconds. Each one lifts your multiplier.")
                howRow("3", "Bank to lock in your score — or push your luck and risk it.")
            }
            Spacer()
            PrimaryButton(title: "Begin") { store.finishOnboarding() }
        }
        .padding(.horizontal, Metrics.s6)
        .padding(.vertical, Metrics.s8)
    }

    private func howRow(_ n: String, _ t: String) -> some View {
        HStack(alignment: .top, spacing: Metrics.s3) {
            Text(n).font(Type.instrumentStd).foregroundStyle(Palette.taupe)
            Text(t).font(Type.body).foregroundStyle(Palette.onPaperPrimary)
        }
    }
}

// MARK: - Stats

struct StatsView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    private let cols = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        let s = store.stats
        VStack(alignment: .leading, spacing: Metrics.s6) {
            SheetHeader(title: "Stats") { dismiss() }
            LazyVGrid(columns: cols, spacing: Metrics.s3) {
                StatBox(label: "current streak", value: "\(s.currentStreak)")
                StatBox(label: "best streak", value: "\(s.bestStreak)")
                StatBox(label: "best score", value: ShareCard.decimal(s.bestScore))
                StatBox(label: "runs played", value: "\(s.totalRuns)")
                StatBox(label: "recent average", value: ShareCard.decimal(s.averageScore))
            }
            Spacer()
        }
        .padding(Metrics.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper.ignoresSafeArea())
    }
}

// MARK: - Leaderboard

struct LeaderboardView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let ranked = store.stats.history.sorted { $0.finalScore > $1.finalScore }
        VStack(alignment: .leading, spacing: Metrics.s4) {
            SheetHeader(title: "Leaderboard") { dismiss() }
            Text("Global and friends boards are coming. Until then, here are your best climbs.")
                .font(Type.caption)
                .foregroundStyle(Palette.onPaperSecondary)

            if ranked.isEmpty {
                Spacer()
                Text("No runs yet. Play today's board.")
                    .font(Type.body)
                    .foregroundStyle(Palette.onPaperSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(ranked.prefix(20).enumerated()), id: \.offset) { i, r in
                            row(rank: i + 1, r: r)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Metrics.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper.ignoresSafeArea())
    }

    private func row(rank: Int, r: RunResult) -> some View {
        HStack {
            Text("\(rank)")
                .font(Type.instrumentStd)
                .foregroundStyle(Palette.taupe)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("Day \(r.dayIndex + 1)")
                    .font(Type.body)
                    .foregroundStyle(Palette.onPaperPrimary)
                Text(r.outcome == .banked ? "banked at \(ShareCard.mult(r.bankedMultiplier))" : "pushed too far")
                    .font(Type.caption)
                    .foregroundStyle(Palette.onPaperSecondary)
            }
            Spacer()
            Text(ShareCard.decimal(r.finalScore))
                .font(Type.instrumentStd)
                .monospacedDigit()
                .foregroundStyle(Palette.onPaperPrimary)
        }
        .padding(.vertical, Metrics.s3)
        .overlay(Rectangle().fill(Palette.hairlineOnPaper).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var notify = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s6) {
            SheetHeader(title: "Settings") { dismiss() }

            Toggle(isOn: $notify) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily reminder").font(Type.body).foregroundStyle(Palette.onPaperPrimary)
                    Text("One calm notification when the board goes live.")
                        .font(Type.caption).foregroundStyle(Palette.onPaperSecondary)
                }
            }
            .tint(Palette.ink)
            .onChange(of: notify) { _, v in store.setNotifications(v) }

            Rectangle().fill(Palette.hairlineOnPaper).frame(height: 1)

            VStack(alignment: .leading, spacing: Metrics.s2) {
                Text("About").font(Type.label).foregroundStyle(Palette.onPaperSecondary)
                Text("RUNG is an early, experimental build. The name is a working title.")
                    .font(Type.caption).foregroundStyle(Palette.onPaperSecondary)
                Text("Version \(appVersion)")
                    .font(Type.instrumentMicro).foregroundStyle(Palette.taupe)
            }
            Spacer()
        }
        .padding(Metrics.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper.ignoresSafeArea())
        .onAppear { notify = store.notificationsOn }
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
}
