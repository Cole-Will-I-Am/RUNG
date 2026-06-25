// End-to-end smoke test against the deployed Worker.  node server/test/e2e.mjs
import { readFileSync } from "node:fs";
const BASE = process.env.BASE || "https://rung-api.yw895rcd6x.workers.dev";
const words = readFileSync("/root/RUNG/RUNG/Resources/words.txt", "utf8").split("\n").filter(Boolean);

const hist = (s) => { const h = new Array(26).fill(0); for (const c of s) h[c.charCodeAt(0) - 65]++; return h; };
const fits = (w, b) => { const h = hist(w); for (let i = 0; i < 26; i++) if (h[i] > b[i]) return false; return true; };
const j = async (path, opts = {}) => { const r = await fetch(BASE + path, opts); const t = await r.text(); let d; try { d = JSON.parse(t); } catch { d = t; } return { status: r.status, d }; };

console.log("BASE", BASE);
console.log("health:", (await j("/healthz")).d);
const daily = (await j("/v1/daily")).d;
console.log("daily: day", daily.dayIndex, "tiles", daily.tiles);
const bh = hist(daily.tiles);

const valid = words.filter((w) => w.length >= 3 && w.length <= 7 && fits(w, bh));
const pick = []; const seen = new Set();
for (const w of valid) { if (!seen.has(w.length)) { pick.push(w); seen.add(w.length); } if (pick.length >= 4) break; }
console.log("playable words chosen:", pick);

const dev = "test-" + Math.floor(Math.random() * 1e9);
const acct = (await j("/v1/account", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ deviceId: dev }) })).d;
console.log("account:", acct.player?.display, acct.player?.id, "anon", acct.player?.isAnonymous, "| deviceSecret:", acct.deviceSecret ? "issued" : "MISSING");
// device-secret auth: deviceId alone must NOT resume; the secret must.
const noSecret = await j("/v1/account", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ deviceId: dev }) });
console.log("  resume w/o secret ->", noSecret.status, noSecret.d.error || "");
const withSecret = (await j("/v1/account", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ deviceId: dev, deviceSecret: acct.deviceSecret }) })).d;
console.log("  resume w/ secret  -> player", withSecret.player?.id, withSecret.player?.id === acct.player?.id ? "(same ✓)" : "(DIFFERENT!)");
const auth = { authorization: "Bearer " + acct.token, "content-type": "application/json" };

const start = (await j("/v1/run/start", { method: "POST", headers: auth, body: "{}" })).d;
console.log("run/start:", start.runId, "alreadyPlayed", start.alreadyPlayed);

const events = pick.map((w, i) => ({ word: w, t_ms: 1500 + i * 1800 }));
const bankT_ms = events[events.length - 1].t_ms + 1500;
const run = await j("/v1/run", { method: "POST", headers: auth, body: JSON.stringify({ runId: start.runId, runToken: start.runToken, dayIndex: start.dayIndex, events, bankT_ms }) });
console.log("run:", run.status, JSON.stringify(run.d));

console.log("leaderboard:", JSON.stringify((await j("/v1/leaderboard?period=daily", { headers: auth })).d));
console.log("me:", JSON.stringify((await j("/v1/me", { headers: auth })).d));

const dup = await j("/v1/run", { method: "POST", headers: auth, body: JSON.stringify({ runId: start.runId, runToken: start.runToken, dayIndex: start.dayIndex, events, bankT_ms }) });
console.log("run (duplicate):", dup.status, "duplicate=", dup.d.duplicate, "score=", dup.d.finalScore);

console.log("username:", JSON.stringify((await j("/v1/username", { method: "PUT", headers: auth, body: JSON.stringify({ username: "tester_" + Math.floor(Math.random() * 9999) }) })).d));

// anti-cheat negatives
const a2 = (await j("/v1/account", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ deviceId: "test-" + Math.floor(Math.random() * 1e9) }) })).d;
const s2 = (await j("/v1/run/start", { method: "POST", headers: { authorization: "Bearer " + a2.token, "content-type": "application/json" }, body: "{}" })).d;
const cheatScore = await j("/v1/run", { method: "POST", headers: { authorization: "Bearer " + a2.token, "content-type": "application/json" }, body: JSON.stringify({ runId: s2.runId, runToken: s2.runToken, dayIndex: s2.dayIndex, events: [{ word: pick[0], t_ms: 0 }, { word: pick[1], t_ms: 10 }], bankT_ms: 50 }) });
console.log("anti-cheat (impossible cadence) ->", cheatScore.status, JSON.stringify(cheatScore.d));
const fabricate = await j("/v1/run", { method: "POST", headers: { authorization: "Bearer " + a2.token, "content-type": "application/json" }, body: JSON.stringify({ runId: s2.runId, runToken: s2.runToken, dayIndex: s2.dayIndex, events: pick.map((w, i) => ({ word: w, t_ms: 2000 + i * 2000 })), bankT_ms: 55000 }) });
console.log("anti-cheat (fabricated 55s timeline, posted instantly) ->", fabricate.status, JSON.stringify(fabricate.d));
