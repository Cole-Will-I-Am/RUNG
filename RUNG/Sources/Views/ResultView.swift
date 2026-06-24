import SwiftUI

struct ResultView: View {
    @EnvironmentObject var store: GameStore
    @State private var shown = 0
    @State private var showLeaderboard = false

    var body: some View {
        VStack(spacing: Metrics.s6) {
            Spacer()
            if let r = store.lastResult {
                Text(store.isPractice ? "Practice" : "Day \(r.dayIndex + 1)")
                    .font(Type.label)
                    .foregroundStyle(Palette.onPaperSecondary)

                Text(ShareCard.decimal(shown))
                    .font(Type.instrument(48, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.onPaperPrimary)
                    .contentTransition(.numericText())

                Text(ShareCard.headline(for: r))
                    .font(Type.h2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.onPaperPrimary)
                    .padding(.horizontal, Metrics.s4)

                if store.isPractice {
                    Text("Practice — this run isn't ranked.")
                        .font(Type.caption)
                        .foregroundStyle(Palette.onPaperSecondary)
                } else if let sr = store.serverResult {
                    Text("You're #\(sr.rank) — top \(max(1, Int((100 - sr.percentile).rounded())))% today.")
                        .font(Type.body)
                        .foregroundStyle(Palette.onPaperPrimary)
                }

                HStack(spacing: Metrics.s8) {
                    statCell("peak", ShareCard.mult(r.peakMultiplier))
                    statCell("words", "\(r.wordCount)")
                    if r.outcome == .banked {
                        statCell("banked at", ShareCard.mult(r.bankedMultiplier))
                    } else {
                        statCell("base kept", ShareCard.decimal(r.baseSum))
                    }
                }
                .padding(.top, Metrics.s2)

                Spacer()

                VStack(spacing: Metrics.s3) {
                    ShareLink(item: ShareCard.text(for: r)) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .font(Type.display(16, .medium))
                        .foregroundStyle(Palette.onPaperPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: Metrics.radiusTile)
                            .strokeBorder(Palette.hairlineOnPaper, lineWidth: 1))
                    }
                    SecondaryButton(title: "View leaderboard", mode: .paper) { showLeaderboard = true }
                    PrimaryButton(title: "Done") { store.goHome() }
                }
            } else {
                PrimaryButton(title: "Done") { store.goHome() }
            }
        }
        .padding(.horizontal, Metrics.s6)
        .padding(.bottom, Metrics.s8)
        .onAppear { countUp(to: store.lastResult?.finalScore ?? 0) }
        .sheet(isPresented: $showLeaderboard) { LeaderboardView() }
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Type.instrumentStd)
                .monospacedDigit()
                .foregroundStyle(Palette.onPaperPrimary)
            Text(label)
                .font(Type.instrumentMicro)
                .foregroundStyle(Palette.onPaperSecondary)
        }
    }

    private func countUp(to target: Int) {
        guard target > 0 else { shown = 0; return }
        Task {
            let steps = 30
            for i in 0...steps {
                withAnimation(.easeOut(duration: 0.02)) { shown = target * i / steps }
                try? await Task.sleep(nanoseconds: 18_000_000)
            }
            shown = target
        }
    }
}
