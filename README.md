# RUNG

A once-per-day competitive word game. Everyone gets the **same 12-letter board**, plays
**one 60-second run**, and competes on a **score** — not a binary win/lose. The hook is
**bank-or-push**: your score is multiplied by a chain that climbs with every word, but the
bonus is *unbanked* until you press **Bank**; let the clock hit zero first and you forfeit
the entire multiplier. (Design docs: the game blueprint + the RUNG brand guide. *RUNG* is a
working title — name clearance is an open item.)

> v1 is **free, no ads, no IAP**. Monetization seams (entitlements/feature flags, config as
> data) are built in but switched off. This repo is the **Milestone 0/1 scaffold**: the core
> run + bank/push loop, a deterministic daily board, server-free local scoring, and a
> spoiler-free share card — skinned in the full RUNG brand system.

## Brand in one line

Calm, warm, and trustworthy at rest (Ink/Paper) — with a single accent, the **Heat ramp**
(gold → amber → orange → red), bound to the multiplier and unleashed only in the dark
**Arena** at the moment that matters. Gold = value you can secure (the Bank button); red =
risk you're courting (a hot multiplier, the draining clock). See `Theme.swift` for the
tokens.

## Architecture

The game **logic** is deliberately UI-independent so it can be unit-tested off-device:

```
RUNG/
  project.yml                 # XcodeGen — the .xcodeproj is GENERATED in CI, never committed
  Package.swift               # Linux/local: compiles + tests the engine via `swift test`
  RUNG/
    Sources/
      App/    RUNGApp.swift, RootView.swift, GameStore.swift, LocalStore.swift
      Core/   # PURE FOUNDATION engine (no SwiftUI/UIKit) — also compiled by Package.swift
              GameConfig.swift, SeededRNG.swift, WordDictionary.swift,
              BoardGenerator.swift, RunEngine.swift, ShareCard.swift
      Theme/  Theme.swift     # the design system: Palette, Heat ramp, Type, Metrics, Haptics
      Views/  # SwiftUI two-mode UI: Home, Onboarding/Stats/Leaderboard/Settings (Paper);
              # Countdown, Run (Arena); Result; Components
    Tests/      # XCTest (@testable import RUNG) — runs on the iOS Simulator in CI
    Resources/  words.txt      # bundled public-domain (ENABLE) dictionary, 152k words
    Assets.xcassets            # AppIcon (climb-and-heat rungs), AccentColor (Ink)
  CoreTests/    # XCTest (@testable import RungCore) — runs on Linux via Package.swift
```

The same `Core/*.swift` files compile two ways: into the `RUNG` app module (iOS) **and** as
the `RungCore` library (`Package.swift`), so the scoring, multiplier, bank/push, board
generation, and dictionary logic are verified with `swift test` on any machine — no Xcode.

**Config as data (blueprint §10.4):** the clock, multiplier curve, time-refund, scoring
table, board gates, and the monetization feature flags all live in `GameConfig` as `Codable`
data, ready to be swapped for a server-delivered config so game feel can be tuned without an
App Store review.

**Deterministic board (no server needed):** `BoardGenerator` seeds SplitMix64 with the UTC
day index and draws a quality-gated board, so every device produces the identical board for
the day. Verified bit-for-bit (day 0 → `AEFGIIKNNPUU`).

## Tuning (why 60s + a length-scaled refund)

A design red-team simulated the loop. At the blueprint's defaults (75s, flat +3s/word) the
clock never meaningfully drains, banking is strictly dominated, and 3-letter-word spam is
the optimal strategy — i.e. **no real bank-vs-push tension**. The shipped defaults fix this:
a **60s** clock and a **length-scaled time refund** (0s for ≤4 letters, +1/+2/+3s for 5/6/7+),
which kills spam and makes the bank decision genuinely tense (expected value peaks *below*
the ×5 cap, so chasing the cap is a real gamble). All values stay in `GameConfig`.

## Verify the engine (Linux/macOS, no Xcode)

```bash
swift test            # compiles Core/ as RungCore, runs CoreTests/ (16 tests)
```

## Build & ship (no Mac — the team's GitHub Actions pattern)

Only `project.yml` is committed; CI generates `RUNG.xcodeproj` with XcodeGen. Signing and
upload use an **App Store Connect API key (Admin role)** on a hosted macOS runner.

One-time setup (see the `ios-testflight` skill): create the ASC app record for
`com.colecantcode.rung`, add repo secrets `ASC_KEY_ID` / `ASC_ISSUER_ID` /
`ASC_KEY_P8_BASE64`, and make the repo public (or resolve Actions billing).

```bash
# Bump MARKETING_VERSION in project.yml on EVERY build, then:
gh workflow run ios-release.yml --ref main -f upload=true
```

Read-only App Store status: `gh workflow run ios-asc-status.yml`.

## Status — what's in this scaffold

- [x] Core engine (unit-tested): deterministic daily board, dictionary validation, scoring + multiplier, bank/push, clock with length-scaled time-refund, spoiler-free share text
- [x] Full RUNG brand system: Ink/Paper two-mode UI, multiplier-bound Heat ramp, gold Bank, climb-and-heat app icon, calm voice, haptics, reduce-motion support
- [x] End-to-end loop: Home → countdown → Run → Bank/bust → Result → Share; streaks + stats persisted locally
- [x] No-Mac TestFlight pipeline (XcodeGen + GitHub Actions)
- [ ] Accounts (Sign in with Apple), global/friends leaderboards, anti-cheat — designed-for, not built (blueprint §5)
- [ ] Server board generation + config delivery (engine is local-first for now)
- [ ] Real Space Grotesk / IBM Plex Mono fonts (roles mapped onto system faces for now; one swap point in `Theme.swift`)
```
