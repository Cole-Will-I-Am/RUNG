// RUNG engine — JS port of RUNG/Sources/Core (Swift). Worker-safe: no dictionary, no
// board solver (those live in boardgen.js, offline only). The Worker uses this to
// RE-SCORE submitted runs server-authoritatively. Must stay bit-for-bit with Swift —
// verified by server/test/verify.js (SplitMix64 vectors, day-0 board, scoring).

export const DAY_EPOCH = 1_735_689_600; // 2025-01-01 UTC
export const LETTER_WEIGHTS = [9, 2, 3, 4, 12, 2, 3, 3, 8, 1, 2, 4, 3, 6, 7, 3, 1, 6, 6, 6, 4, 2, 2, 1, 2, 1];

export const DEFAULT_CONFIG = {
  clockSeconds: 60,
  multiplierStart: 1.0,
  multiplierStep: 0.2,
  multiplierCap: 5.0,
  tileCount: 12,
  scoring: {
    byLength: { 3: 100, 4: 250, 5: 450, 6: 700 },
    sevenPlusBase: 1000,
    sevenPlusPerExtra: 200,
    rareLetters: "JQXZKVW",
    rareLetterBonus: 50,
  },
  timeRefund: [
    { minLength: 5, seconds: 1 },
    { minLength: 6, seconds: 2 },
    { minLength: 7, seconds: 3 },
  ],
};

// --- SplitMix64 (u64 via BigInt, wrapping) ---
const MASK = (1n << 64n) - 1n;
const GOLD = 0x9e3779b97f4a7c15n;
const M1 = 0xbf58476d1ce4e5b9n;
const M2 = 0x94d049bb133111ebn;

export class SplitMix64 {
  constructor(seed) { this.state = BigInt(seed) & MASK; }
  next() {
    this.state = (this.state + GOLD) & MASK;
    let z = this.state;
    z = ((z ^ (z >> 30n)) * M1) & MASK;
    z = ((z ^ (z >> 27n)) * M2) & MASK;
    return (z ^ (z >> 31n)) & MASK;
  }
}

// Swift seeds with UInt64(bitPattern: Int64(dayIndex)); asUintN(64) matches for any sign.
export function seedForDay(dayIndex) { return BigInt.asUintN(64, BigInt(dayIndex)); }

export function dayIndexFor(epochSeconds) {
  return Math.floor((epochSeconds - DAY_EPOCH) / 86400);
}

// --- scoring / playability ---
export function histogramOf(word) {
  const h = new Array(26).fill(0);
  for (let i = 0; i < word.length; i++) {
    const v = word.charCodeAt(i) - 65;
    if (v < 0 || v > 25) return null;
    h[v]++;
  }
  return h;
}

export function fits(wordHist, boardHist) {
  for (let k = 0; k < 26; k++) if (wordHist[k] > boardHist[k]) return false;
  return true;
}

export function baseScore(word, s = DEFAULT_CONFIG.scoring) {
  const n = word.length;
  let sc = n >= 7 ? s.sevenPlusBase + s.sevenPlusPerExtra * (n - 7) : (s.byLength[n] ?? 0);
  if (s.rareLetterBonus) {
    for (let i = 0; i < n; i++) if (s.rareLetters.includes(word[i])) sc += s.rareLetterBonus;
  }
  return sc;
}

export function refundSeconds(len, tiers = DEFAULT_CONFIG.timeRefund) {
  let r = 0;
  for (const t of tiers) if (len >= t.minLength) r = Math.max(r, t.seconds);
  return r;
}

export function tilesToHistogram(tiles) {
  const h = new Array(26).fill(0);
  for (let i = 0; i < tiles.length; i++) h[tiles.charCodeAt(i) - 65]++;
  return h;
}

/**
 * Server-authoritative re-score. Re-runs the exact RunEngine state machine from the
 * ordered accepted-word events (each with t_ms since run start) and the bank time.
 * `validWords` = uppercase Set of the submitted words confirmed to be in the dictionary
 * (the Worker fetches these from D1 in one batched query before calling this).
 *
 * Float ops are incremental (+= step, min(cap, clock+refund)) to match Swift's IEEE-754
 * accumulation exactly. Returns the authoritative result; the client's claimed score is
 * never used.
 */
export function replayRun(events, bankT_ms, boardHist, validWords, config = DEFAULT_CONFIG) {
  let clock = config.clockSeconds;
  let mult = config.multiplierStart;
  let peak = config.multiplierStart;
  let baseSum = 0;
  const used = new Set();
  const accepted = [];
  let outcome = null;
  let prev = 0;

  const sorted = [...events].sort((a, b) => a.t_ms - b.t_ms);
  for (const ev of sorted) {
    clock -= (ev.t_ms - prev) / 1000;
    prev = ev.t_ms;
    if (clock <= 0) { outcome = "bustedOut"; break; }
    const word = String(ev.word).trim().toUpperCase();
    if (word.length < 3) continue;
    if (used.has(word)) continue;
    if (!validWords.has(word)) continue;
    const h = histogramOf(word);
    if (!h || !fits(h, boardHist)) continue;
    baseSum += baseScore(word, config.scoring);
    mult = Math.min(config.multiplierCap, mult + config.multiplierStep);
    peak = Math.max(peak, mult);
    clock = Math.min(config.clockSeconds, clock + refundSeconds(word.length, config.timeRefund));
    used.add(word);
    accepted.push(word);
  }

  if (outcome === null) {
    if (bankT_ms != null) {
      clock -= (bankT_ms - prev) / 1000;
      outcome = clock > 0 ? "banked" : "bustedOut";
    } else {
      outcome = "bustedOut"; // let the clock expire unbanked
    }
  }

  const finalScore = outcome === "banked" ? Math.round(baseSum * mult) : baseSum;
  const bankedMult = outcome === "banked" ? mult : config.multiplierStart;
  return {
    outcome,
    finalScore,
    baseSum,
    peakMultiplier: peak,
    bankedMultiplier: bankedMult,
    wordCount: accepted.length,
    acceptedWords: accepted,
  };
}
