import SwiftUI

// RUNG design system — the single source of truth for the brand (see the RUNG brand
// guide §3, §4, §10). Two ideas drive everything:
//
//  1) A warm, calm foundation (Ink/Paper, never pure black/white) so the resting state
//     feels human and premium.
//  2) The Heat ramp — gold → amber → orange → red — is bound to the multiplier and is
//     the ONLY place these colours appear. It is unleashed only in the dark Arena.
//
// The gold-vs-red split is meaningful: gold = value you can secure (the Bank button);
// red = risk you are courting (a hot multiplier, the draining clock). Red is reserved —
// never used for ordinary errors (that would dilute its meaning).

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

enum Palette {
    // Foundation (§3.1)
    static let ink        = Color(hex: 0x17130E)   // primary dark surface (the arena)
    static let inkRaised  = Color(hex: 0x221C15)   // raised surfaces on dark: tiles, cards
    static let paper      = Color(hex: 0xF6F1E7)   // primary light surface (meta screens)
    static let paperDeep  = Color(hex: 0xEFE8DA)   // secondary light surface / borders
    static let taupe      = Color(hex: 0x8A7E6E)   // muted labels on light

    static let onInkPrimary    = Color(hex: 0xF6F1E7)
    static let onInkSecondary  = Color(hex: 0xC9BFAE)
    static let onPaperPrimary  = Color(hex: 0x17130E)
    static let onPaperSecondary = Color(hex: 0x8A7E6E)

    static let hairlineOnInk   = Color(hex: 0xF6F1E7, alpha: 0.14)
    static let hairlineOnPaper = Color(hex: 0x17130E, alpha: 0.12)

    // Heat ramp (§3.2) — bound to the multiplier, nothing else.
    static let heat1 = Color(hex: 0xF3C04A)   // gold — safe        (×1.0–1.6)
    static let heat2 = Color(hex: 0xF0993D)   // amber — warming    (×1.8–2.6)
    static let heat3 = Color(hex: 0xE96B2E)   // orange — hot       (×2.8–3.8)
    static let heat4 = Color(hex: 0xDE3B22)   // red — critical     (×4.0+)

    static let onHeatGoldAmber = Color(hex: 0x854F0B)
    static let onHeatOrange    = Color(hex: 0x712B13)
    static let onHeatRed       = Color(hex: 0x501313)

    // Heat anchors (multiplier → rgb) for smooth interpolation between named stops.
    private static let heatAnchors: [(m: Double, rgb: (Double, Double, Double))] = [
        (1.0, (0.953, 0.753, 0.290)),
        (2.2, (0.941, 0.600, 0.239)),
        (3.3, (0.914, 0.420, 0.180)),
        (4.0, (0.871, 0.231, 0.133)),
    ]

    /// The accent colour for a given multiplier — gold at rest, sliding to red as the
    /// climb (and the risk) heats up. Continuous between the named stops.
    static func heat(forMultiplier m: Double) -> Color {
        if m <= heatAnchors.first!.m { return rgb(heatAnchors.first!.rgb) }
        if m >= heatAnchors.last!.m { return rgb(heatAnchors.last!.rgb) }
        for i in 0..<(heatAnchors.count - 1) {
            let a = heatAnchors[i], b = heatAnchors[i + 1]
            if m >= a.m && m <= b.m {
                let t = (m - a.m) / (b.m - a.m)
                return rgb((a.rgb.0 + (b.rgb.0 - a.rgb.0) * t,
                            a.rgb.1 + (b.rgb.1 - a.rgb.1) * t,
                            a.rgb.2 + (b.rgb.2 - a.rgb.2) * t))
            }
        }
        return heat4
    }

    /// Dark-family text colour to place on a heat fill of the given multiplier.
    static func onHeat(forMultiplier m: Double) -> Color {
        if m < 2.8 { return onHeatGoldAmber }
        if m < 4.0 { return onHeatOrange }
        return onHeatRed
    }

    private static func rgb(_ c: (Double, Double, Double)) -> Color {
        Color(.sRGB, red: c.0, green: c.1, blue: c.2, opacity: 1)
    }
}

/// The two visual modes (§5). Paper = calm meta screens; Arena = the focused dark run.
enum Mode {
    case paper, arena
    var surface: Color { self == .paper ? Palette.paper : Palette.ink }
    var raised: Color { self == .paper ? Palette.paperDeep : Palette.inkRaised }
    var textPrimary: Color { self == .paper ? Palette.onPaperPrimary : Palette.onInkPrimary }
    var textSecondary: Color { self == .paper ? Palette.onPaperSecondary : Palette.onInkSecondary }
    var hairline: Color { self == .paper ? Palette.hairlineOnPaper : Palette.hairlineOnInk }
}

/// Typography (§4). Two roles: a warm grotesque for display/UI (human, words) and a
/// tabular monospace for live instruments (machine, numbers). Reference faces are Space
/// Grotesk + IBM Plex Mono (§13, licensing pending); until they're bundled we map the
/// ROLES onto the system faces — system default for display, system monospaced (with
/// tabular figures) for instruments. Swap these two functions to drop in the real faces.
enum Type {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func instrument(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // Named roles from the scale table (§4.3).
    static let wordmark        = display(52, .bold)
    static let h1              = display(28, .bold)
    static let h2              = display(20, .medium)
    static let body            = display(16, .regular)
    static let caption         = display(14, .regular)
    static let label           = display(13, .medium)
    static let tile            = display(22, .medium)
    static let instrumentHero  = instrument(42, .semibold)
    static let instrumentStd   = instrument(25, .semibold)
    static let instrumentMicro = instrument(12, .medium)
}

/// Spacing, radii, and motion timings (§10).
enum Metrics {
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12
    static let s4: CGFloat = 16, s6: CGFloat = 24, s8: CGFloat = 32
    static let radiusTile: CGFloat = 10
    static let radiusCard: CGFloat = 16
    static let radiusIcon: CGFloat = 20
    static let tapTarget: CGFloat = 44

    // Motion durations (seconds).
    static let feedback = 0.16     // word pop, ease-out
    static let heatShift = 0.20    // multiplier colour cross-fade
    static let bank = 0.35         // lock-in, ease-out-back
    static let bust = 0.50         // drain
    static let resultCount = 0.60  // count-up
}

#if canImport(UIKit)
import UIKit

/// Haptics (§8) — kept even under reduce-motion, since they aid rather than overwhelm.
enum Haptics {
    static func wordValid() {
        let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
    }
    static func bank() {
        let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.success)
    }
    static func tick() {
        let g = UIImpactFeedbackGenerator(style: .soft); g.impactOccurred(intensity: 0.6)
    }
    static func reject() {
        let g = UIImpactFeedbackGenerator(style: .rigid); g.impactOccurred(intensity: 0.4)
    }
}
#else
enum Haptics {
    static func wordValid() {}
    static func bank() {}
    static func tick() {}
    static func reject() {}
}
#endif
