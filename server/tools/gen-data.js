// Offline data generation for D1: words.sql (152k dictionary rows) and boards.sql
// (precomputed daily boards). Load with `wrangler d1 import`.
//   node server/tools/gen-data.js [numDays]
import { readFileSync, writeFileSync } from "node:fs";
import { Dict, generateBoard } from "../src/boardgen.js";

const NUM_DAYS = Number(process.argv[2] || 730);
const WORDS_PATH = "/root/RUNG/RUNG/Resources/words.txt";
const OUT_DIR = "/root/RUNG/server/data";

const t0 = Date.now();
const words = readFileSync(WORDS_PATH, "utf8").split("\n").map((w) => w.trim()).filter(Boolean);

// ---- words.sql (batched multi-row INSERTs, ~1000 rows/statement) ----
const BATCH = 1000;
let wsql = "";
for (let i = 0; i < words.length; i += BATCH) {
  const chunk = words.slice(i, i + BATCH).map((w) => `('${w}')`).join(",");
  wsql += `INSERT OR IGNORE INTO words(word) VALUES ${chunk};\n`;
}
writeFileSync(`${OUT_DIR}/words.sql`, wsql);

// ---- boards.sql (precompute NUM_DAYS boards) ----
const dict = new Dict(words);
const rows = [];
let totalAttempts = 0;
for (let day = 0; day < NUM_DAYS; day++) {
  const b = generateBoard(day, dict);
  totalAttempts += b.attempts;
  rows.push(`(${day},'${b.tiles}',${b.playableCount},${b.maxWordScore})`);
}
let bsql = "";
for (let i = 0; i < rows.length; i += 200) {
  bsql += `INSERT OR IGNORE INTO boards(day_index,tiles,playable_count,max_word_score) VALUES ${rows.slice(i, i + 200).join(",")};\n`;
}
writeFileSync(`${OUT_DIR}/boards.sql`, bsql);

const secs = ((Date.now() - t0) / 1000).toFixed(1);
console.log(`words: ${words.length} rows -> data/words.sql`);
console.log(`boards: ${NUM_DAYS} days -> data/boards.sql (mean ${(totalAttempts / NUM_DAYS).toFixed(2)} attempts/board)`);
console.log(`day 0 tiles: ${rows[0]}`);
console.log(`done in ${secs}s`);
