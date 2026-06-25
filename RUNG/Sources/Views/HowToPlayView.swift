import SwiftUI

/// The full rules — always reachable (Home "?" and Settings), since onboarding only
/// shows once. Paper mode; calm, sentence-case voice.
struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.s6) {
                HStack {
                    Text("How to play").font(Type.h1).foregroundStyle(Palette.onPaperPrimary)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(Type.body).foregroundStyle(Palette.onPaperPrimary)
                }

                section("The daily run",
                        "Everyone gets the same twelve letters each day, and you get one 60-second run. Want more? Practice mode gives unlimited runs on random boards — they don't count toward your rank.")

                section("Make words",
                        "Build words of three or more letters from the board's letters. A letter can be used as often as it appears on the board. Longer words score more, and rare letters (J, Q, X, Z, K, V, W) add a bonus.")
                scoringTable

                section("Build your multiplier",
                        "Every word you find lifts your multiplier — ×1.0, ×1.2, ×1.4, all the way to ×5.0. Your score is your word points times your multiplier, so the multiplier is where the big numbers come from.")

                section("Bank, or push your luck",
                        "Here's the catch: that multiplier bonus is unbanked. Tap Bank to lock in your score and end the run — safe. But if the clock hits zero before you bank, you keep only your base points and the entire multiplier bonus is gone. Every moment is a choice: bank a solid score, or push for one more word and a higher multiplier.")

                section("The clock",
                        "It starts at 60 seconds and always ticks down. Longer words buy a little time back (a 5-letter word +1s, 6 +2s, 7 or more +3s) — but never above 60. A rejected word costs only the seconds you spent typing it.")

                section("Where you rank",
                        "When you bank or bust, your daily run lands on the global leaderboard and you'll see your rank and percentile for the day. The same board for everyone means every rank is earned.")

                section("A couple of tips",
                        "Banking at a high multiplier usually beats a big pile of words at ×1. And the sweet spot is often just below the ×5 cap — chasing the cap all the way is a real gamble.")
            }
            .padding(Metrics.s6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper.ignoresSafeArea())
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: Metrics.s2) {
            Text(title).font(Type.h2).foregroundStyle(Palette.onPaperPrimary)
            Text(body).font(Type.body).foregroundStyle(Palette.onPaperSecondary)
        }
    }

    private var scoringTable: some View {
        VStack(spacing: 0) {
            scoreRow("3 letters", "100")
            scoreRow("4 letters", "250")
            scoreRow("5 letters", "450")
            scoreRow("6 letters", "700")
            scoreRow("7+ letters", "1,000  +200 each")
            scoreRow("each rare letter", "+50")
        }
        .padding(Metrics.s4)
        .background(RoundedRectangle(cornerRadius: Metrics.radiusCard).fill(Palette.paperDeep))
    }

    private func scoreRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Type.body).foregroundStyle(Palette.onPaperPrimary)
            Spacer()
            Text(value).font(Type.instrumentMicro).monospacedDigit().foregroundStyle(Palette.onPaperSecondary)
        }
        .padding(.vertical, 6)
    }
}
