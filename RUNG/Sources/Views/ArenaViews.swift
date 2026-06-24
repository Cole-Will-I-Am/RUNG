import SwiftUI

// MARK: - Countdown (arena)

struct CountdownView: View {
    @EnvironmentObject var store: GameStore
    @State private var count = 3

    var body: some View {
        VStack(spacing: Metrics.s4) {
            Text("Get ready")
                .font(Type.h2)
                .foregroundStyle(Palette.onInkSecondary)
            Text("\(count)")
                .font(Type.instrument(96, .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.onInkPrimary)
                .contentTransition(.numericText())
                .id(count)
                .transition(.scale.combined(with: .opacity))
        }
        .task {
            for n in stride(from: 3, through: 1, by: -1) {
                withAnimation(.easeOut(duration: 0.2)) { count = n }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
            store.beginRun()
        }
    }
}

// MARK: - Run (arena) — the core loop

struct RunView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var input = ""
    @FocusState private var focused: Bool
    @State private var flash: String?
    @State private var shake = 0
    @State private var pop = false

    private let tileColumns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        if let run = store.run {
            content(run)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func content(_ run: RunEngine) -> some View {
        let heat = Palette.heat(forMultiplier: run.multiplier)
        let lowClock = run.timeRemaining <= 10

        VStack(spacing: Metrics.s4) {
            // Instrument panel (§7.2)
            HStack(alignment: .top) {
                Instrument(label: "score",
                           value: ShareCard.decimal(run.potentialScore),
                           valueColor: Palette.onInkPrimary,
                           labelColor: Palette.onInkSecondary)
                Spacer()
                VStack(spacing: 3) {
                    Text(ShareCard.mult(run.multiplier))
                        .font(Type.instrumentHero)
                        .monospacedDigit()
                        .foregroundStyle(heat)
                        .scaleEffect(pop ? 1.08 : 1)
                        .animation(.easeOut(duration: Metrics.heatShift), value: run.multiplier)
                    Text("multiplier")
                        .font(Type.instrumentMicro)
                        .foregroundStyle(Palette.onInkSecondary)
                }
                Spacer()
                Instrument(label: "time",
                           value: "\(Int(run.timeRemaining.rounded(.up)))",
                           valueColor: lowClock ? Palette.heat4 : Palette.onInkPrimary,
                           labelColor: Palette.onInkSecondary)
                    .scaleEffect(lowClock && !reduceMotion ? 1.06 : 1)
                    .animation(lowClock && !reduceMotion
                               ? .easeInOut(duration: run.timeRemaining <= 5 ? 0.4 : 0.8).repeatForever(autoreverses: true)
                               : .default,
                               value: lowClock)
            }
            .padding(.top, Metrics.s4)

            Spacer(minLength: 0)

            // The letter set (reusable tiles) — tap to append.
            LazyVGrid(columns: tileColumns, spacing: 8) {
                ForEach(Array(run.board.tiles.enumerated()), id: \.offset) { _, ch in
                    Button {
                        input.append(ch)
                    } label: {
                        TileView(letter: ch, mode: .arena, size: 48)
                    }
                    .buttonStyle(PressableStyle())
                }
            }

            // Ephemeral feedback (neutral — never heat red for errors, §3.4)
            Text(flash ?? " ")
                .font(Type.label)
                .foregroundStyle(Palette.onInkSecondary)
                .frame(height: 18)

            Spacer(minLength: 0)

            // Bank — always gold (§3.3)
            BankButton(amount: run.potentialScore) { store.bank() }

            // Word entry
            HStack(spacing: Metrics.s2) {
                TextField("", text: $input, prompt: Text("type a word").foregroundColor(Palette.onInkSecondary))
                    .font(Type.display(20, .medium))
                    .foregroundStyle(Palette.onInkPrimary)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit(handleSubmit)
                    .padding(.horizontal, Metrics.s4)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: Metrics.radiusTile).fill(Palette.inkRaised))
                    .modifier(Shake(animatableData: CGFloat(shake)))
                if !input.isEmpty {
                    Button { input.removeAll() } label: {
                        Image(systemName: "delete.left")
                            .font(.system(size: 18))
                            .foregroundStyle(Palette.onInkSecondary)
                            .frame(width: 44, height: 50)
                    }
                }
            }
            .padding(.bottom, Metrics.s2)
        }
        .padding(.horizontal, Metrics.s6)
        .onAppear { focused = true }
        .onChange(of: run.acceptedWords.count) { _, _ in
            guard !reduceMotion else { return }
            pop = true
            withAnimation(.easeOut(duration: 0.18)) { pop = false }
        }
    }

    private func handleSubmit() {
        let word = input
        guard !word.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let outcome = store.submit(word)
        switch outcome {
        case .accepted(_, let points, _, _):
            flash = "+\(ShareCard.decimal(points))"
        case .rejectedTooShort:    flash = "Too short"
        case .rejectedNotAWord:    flash = "Not a word"; bump()
        case .rejectedNotPlayable: flash = "Not on the board"; bump()
        case .rejectedAlreadyUsed: flash = "Already played"; bump()
        case .runEnded:            flash = nil
        }
        input.removeAll()
        clearFlashSoon()
    }

    private func bump() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 0.3)) { shake += 1 }
    }

    private func clearFlashSoon() {
        let snapshot = flash
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if flash == snapshot { flash = nil }
        }
    }
}

/// A brief horizontal shake for a neutral rejection (no colour change — §3.4).
struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        let dx = 7 * sin(animatableData * .pi * 4)
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: 0))
    }
}
