import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: GameStore
    @State private var showStats = false
    @State private var showLeaderboard = false
    @State private var showSettings = false
    @State private var showHowTo = false

    private let tileColumns = [GridItem(.adaptive(minimum: 40), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.s6) {

                // Top bar
                HStack(alignment: .center, spacing: Metrics.s4) {
                    Wordmark(color: Palette.onPaperPrimary, size: 34)
                    Spacer()
                    Button { showHowTo = true } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(Palette.onPaperSecondary)
                    }
                    .accessibilityLabel("How to play")
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(Palette.onPaperSecondary)
                    }
                    .accessibilityLabel("Settings")
                }
                .padding(.top, Metrics.s2)

                // Today card
                VStack(alignment: .leading, spacing: Metrics.s4) {
                    HStack {
                        Text("Day \(store.dayNumber)")
                            .font(Type.h2)
                            .foregroundStyle(Palette.onPaperPrimary)
                        Spacer()
                        if store.stats.currentStreak > 0 {
                            PillView(text: "\(store.stats.currentStreak) day streak",
                                     systemImage: "flame.fill",
                                     tint: Palette.heat4,
                                     background: Palette.paper)
                        }
                    }

                    if let tiles = store.board?.tiles {
                        LazyVGrid(columns: tileColumns, spacing: 8) {
                            ForEach(Array(tiles.enumerated()), id: \.offset) { _, ch in
                                TileView(letter: ch, mode: .paper, size: 40)
                            }
                        }
                    }

                    Text("Today's board is live. One run, 60 seconds — bank it, or push your luck.")
                        .font(Type.caption)
                        .foregroundStyle(Palette.onPaperSecondary)
                }
                .cardStyle(.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radiusCard)
                        .strokeBorder(Palette.hairlineOnPaper, lineWidth: 1)
                )

                if store.playedToday {
                    VStack(spacing: Metrics.s2) {
                        Text("You've climbed today.")
                            .font(Type.h2)
                            .foregroundStyle(Palette.onPaperPrimary)
                        Text("Come back tomorrow for a new board.")
                            .font(Type.caption)
                            .foregroundStyle(Palette.onPaperSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Metrics.s2)
                } else {
                    PrimaryButton(title: "Play today's board") { store.startCountdown() }
                }

                // Practice (Endless) is always available — random boards, unranked.
                SecondaryButton(title: "Practice — unlimited", mode: .paper) {
                    store.startCountdown(practice: true)
                }

                HStack(spacing: Metrics.s3) {
                    SecondaryButton(title: "Stats", mode: .paper) { showStats = true }
                    SecondaryButton(title: "Leaderboard", mode: .paper) { showLeaderboard = true }
                }

                Text("Practice runs use random boards and don't affect your rank.")
                    .font(Type.caption)
                    .foregroundStyle(Palette.onPaperSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, Metrics.s2)
            }
            .padding(.horizontal, Metrics.s6)
            .padding(.bottom, Metrics.s8)
        }
        .sheet(isPresented: $showStats) { StatsView() }
        .sheet(isPresented: $showLeaderboard) { LeaderboardView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showHowTo) { HowToPlayView() }
    }
}
