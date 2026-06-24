import SwiftUI

// The small reusable kit (brand §7). Everything pulls from Palette / Type / Metrics so
// the design system stays the single source of truth.

/// Subtle press feedback (§7.3): scale to 0.98, no colour change.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The RUNG wordmark (§2): four letters on an ascending baseline, in a single neutral,
/// with the four heat bars beneath. Only the bars carry the heat ramp.
struct Wordmark: View {
    var color: Color
    var size: CGFloat = 52
    var showBars: Bool = true

    // Offset DOWN from the top baseline — larger = lower, so G (0) is highest (§2.1).
    private let letters: [(String, CGFloat)] = [("R", 18), ("U", 12), ("N", 6), ("G", 0)]
    private let barColors = [Palette.heat1, Palette.heat2, Palette.heat3, Palette.heat4]

    var body: some View {
        VStack(spacing: size * 0.16) {
            HStack(spacing: size * 0.03) {
                ForEach(letters.indices, id: \.self) { i in
                    Text(letters[i].0)
                        .font(Type.display(size, .bold))
                        .tracking(-size * 0.02)
                        .foregroundStyle(color)
                        .offset(y: letters[i].1 / 52 * size)
                }
            }
            if showBars {
                HStack(spacing: size * 0.06) {
                    ForEach(Array(barColors.enumerated()), id: \.offset) { _, c in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(c)
                            .frame(width: size * 0.30, height: max(4, size * 0.085))
                    }
                }
            }
        }
    }
}

/// A letter tile — a reusable letter from the set (§7.1), not a grid cell.
struct TileView: View {
    let letter: Character
    var mode: Mode = .arena
    var size: CGFloat = 52

    var body: some View {
        RoundedRectangle(cornerRadius: Metrics.radiusTile)
            .fill(mode.raised)
            .frame(width: size, height: size)
            .overlay(
                Text(String(letter))
                    .font(Type.display(size * 0.44, .medium))
                    .foregroundStyle(mode.textPrimary)
            )
    }
}

/// One live instrument number with its label, always in the mono face (§7.2).
struct Instrument: View {
    let label: String
    let value: String
    var valueColor: Color
    var valueFont: Font = Type.instrumentStd
    var labelColor: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(valueFont)
                .monospacedDigit()
                .foregroundStyle(valueColor)
            Text(label)
                .font(Type.instrumentMicro)
                .foregroundStyle(labelColor)
        }
    }
}

/// Small pill / badge (§7.6). Neutral by default; pass a heat tint only for the streak.
struct PillView: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color
    var background: Color

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 11, weight: .semibold)) }
            Text(text).font(Type.label)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(background))
    }
}

/// Primary CTA in paper mode (§7.3): Ink fill, Paper text. Used sparingly (e.g. Play).
struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Type.display(17, .bold))
                .foregroundStyle(Palette.paper)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(RoundedRectangle(cornerRadius: Metrics.radiusTile).fill(Palette.ink))
        }
        .buttonStyle(PressableStyle())
    }
}

/// The Bank button (§7.3): always gold — the calm, safe action amid the heat (§3.3).
struct BankButton: View {
    let amount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Bank \(ShareCard.decimal(amount))")
                .font(Type.display(18, .bold))
                .foregroundStyle(Palette.onHeatGoldAmber)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: Metrics.radiusTile).fill(Palette.heat1))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Secondary / Share button (§7.3): transparent with a hairline border.
struct SecondaryButton: View {
    let title: String
    var mode: Mode = .paper
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(Type.display(16, .medium))
            .foregroundStyle(mode.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: Metrics.radiusTile).strokeBorder(mode.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

extension View {
    /// Card surface (§7.4).
    func cardStyle(_ mode: Mode) -> some View {
        self
            .padding(mode == .paper ? 22 : 18)
            .background(RoundedRectangle(cornerRadius: Metrics.radiusCard).fill(mode.raised))
    }
}
