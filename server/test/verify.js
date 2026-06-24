// Engine-port verification: the JS engine MUST match the Swift CoreTests bit-for-bit,
// or server re-scoring diverges from the client. Run: node server/test/verify.js
import { readFileSync } from "node:fs";
import { SplitMix64, baseScore, refundSeconds, replayRun, tilesToHistogram } from "../src/engine.js";
import { Dict, generateBoard } from "../src/boardgen.js";

let pass = 0, fail = 0;
function eq(actual, expected, name) {
  if (actual === expected) { pass++; }
  else { fail++; console.error(`FAIL ${name}: got ${actual}, want ${expected}`); }
}

// 1) SplitMix64 reference vectors
const r0 = new SplitMix64(0n);
eq(r0.next(), 0xe220a8397b1dcdafn, "sm64(0)#1");
eq(r0.next(), 0x6e789e6aa1b965f4n, "sm64(0)#2");
eq(new SplitMix64(1n).next(), 0x910a2dec89025cc1n, "sm64(1)#1");

// 2) Scoring table
eq(baseScore("CAT"), 100, "score CAT");
eq(baseScore("BREAD"), 450, "score BREAD");
eq(baseScore("QUARTZ"), 800, "score QUARTZ (Q+Z)");
eq(baseScore("COUNTERS"), 1200, "score COUNTERS (8 letters)");
eq(baseScore("JUKEBOX"), 1150, "score JUKEBOX (J+K+X)");

// 3) Time refund tiers
eq(refundSeconds(4), 0, "refund len4");
eq(refundSeconds(5), 1, "refund len5");
eq(refundSeconds(6), 2, "refund len6");
eq(refundSeconds(9), 3, "refund len9");

// 4) Deterministic board (the bit-exact reference)
const words = readFileSync("/root/RUNG/RUNG/Resources/words.txt", "utf8").split("\n").filter(Boolean);
const dict = new Dict(words);
const b0 = generateBoard(0, dict);
eq(b0.tiles, "AEFGIIKNNPUU", "day 0 board tiles");

// 5) Replay re-scoring sanity (open board, words confirmed valid)
const open = new Array(26).fill(3);
const valid = new Set(["BREAD", "COUNTER"]);
const banked = replayRun(
  [{ word: "BREAD", t_ms: 1000 }, { word: "COUNTER", t_ms: 3000 }],
  5000, open, valid
);
eq(banked.outcome, "banked", "replay banked outcome");
eq(banked.baseSum, 450 + 1000, "replay baseSum");
eq(banked.finalScore, Math.round((450 + 1000) * 1.4), "replay finalScore (×1.4)");

// bust: clock runs out before bank
const bust = replayRun([{ word: "BREAD", t_ms: 1000 }], 65000, open, valid);
eq(bust.outcome, "bustedOut", "replay bust outcome");
eq(bust.finalScore, 450, "replay bust forfeits multiplier");

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
