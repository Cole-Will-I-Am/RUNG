# RUNG — App Store listing (draft for App Store Connect)

Paste these into App Store Connect → your app → the version page. Fields capped at the
App Store limits noted.

## Names / URLs
- **App Name** (≤30): `RUNG: Daily Word Climb`
  - *(plain "RUNG" may be taken; this is safe. The on-device app name stays "RUNG".)*
- **Subtitle** (≤30): `One board. One run. Bank it.`
- **Category**: Primary **Games → Word**; Secondary **Games → Puzzle**
- **Age rating**: 4+ (no objectionable content)
- **Privacy Policy URL**: `https://rung-api.manticthink.com/privacy`
- **Support URL**: `https://rung-api.manticthink.com`
- **Marketing URL** (optional): `https://rung-api.manticthink.com`

## Promotional Text (≤170, editable anytime without review)
```
A new 12-letter board drops every day. Everyone plays the same one. Find words, build
your multiplier, then make the call: bank it, or push your luck for one more word.
```

## Description (≤4000)
```
RUNG is a once-a-day word game built around a single, nerve-wracking decision: bank your
score, or push your luck for one more word.

Every day, everyone in the world gets the SAME 12 letters. You get one 60-second run.
Each word you find adds points and lifts your multiplier — but that multiplier bonus is
unbanked. Press BANK to lock it in, or keep going and risk losing it all when the clock
hits zero. The longer you push, the more you stand to win… and to lose.

Then you see exactly where you landed: a real global leaderboard and your percentile for
the day. No pay-to-win, no gimmicks — the same board for everyone makes every rank earned.

• ONE daily board, shared worldwide — pure, comparable competition
• Push-your-luck scoring — bank a safe score or gamble on the multiplier
• 60 seconds, ~5 to share — fits any spare moment
• Global daily + all-time leaderboards, with your live rank and percentile
• Practice mode — unlimited runs on random boards to warm up (never affects your rank)
• Streaks and personal bests to chase
• Play anonymously, or Sign in with Apple to claim a username and carry your stats
• No ads. No in-app purchases. No tracking.

One board. One shot. Every day. How high can you climb?
```

## Keywords (≤100 chars, comma-separated, no spaces after commas)
```
word,daily,puzzle,anagram,words,leaderboard,brain,vocabulary,letters,spelling,wordle,score,bank
```

## What's New (for this version)
```
First release. The daily board, push-your-luck scoring, global leaderboards, and
practice mode. Climb on.
```

## App Review notes
```
- No account is required to play; the app auto-creates an anonymous account so scores can
  be ranked. Sign in with Apple is optional (Settings) and only adds a username + cross-
  device stats.
- Account deletion: Settings → Delete account (removes all server data).
- Backend: rung-api.manticthink.com (Cloudflare). No third-party SDKs, ads, or tracking.
- Encryption: none beyond standard HTTPS (ITSAppUsesNonExemptEncryption = false).
```

## App Privacy answers (Data collection nutrition label)
- **Data linked to you / used to track you:** none (no tracking).
- **Data collected (linked to identity, app functionality only):**
  - *Identifiers* — a user/device identifier (the anonymous account id), for app
    functionality (leaderboards). Not used for tracking.
  - *User Content / Gameplay* — scores and game activity, for app functionality.
- **NOT collected:** name, email, contacts, location, photos, browsing, purchases,
  advertising data.
- (Sign in with Apple stores only a one-way hashed identifier; no name/email requested.)

## Still needed (not copy)
- **Screenshots** — 6.9" + 6.7" iPhone (see screenshot CI job, task 16).
- **App icon** — already in the build (1024² in the asset catalog).
