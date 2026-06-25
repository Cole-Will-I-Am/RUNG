// RUNG backend Worker. Server-authoritative scoring + leaderboards on D1.
// The client never sends a score — only the ordered words + timings; the server
// replays the engine (engine.js, verified bit-identical to the Swift client) and
// recomputes everything. See server/arch_*.md for the full design.

import { DEFAULT_CONFIG, DAY_EPOCH, baseScore, tilesToHistogram, replayRun } from "./engine.js";
import {
  HttpError, sha256hex, hmacHex, randomToken, randomId,
  verifyAppleIdentityToken, createSession, authPlayer, makeRunToken, verifyRunToken, constantTimeEqual,
} from "./auth.js";

const BUNDLE_ID = "com.colecantcode.rung";

// Anti-cheat timing thresholds.
const HARD_MIN_INTER_MS = 120;                 // below this between events = impossible -> reject
const softFloor = (len) => 250 + 55 * len;     // human read+type floor; below = shadow (verified=0)
const MAX_EVENTS = 400;
const MAX_BANK_MS = 600_000;                   // 10-min absolute wall guard
const WALL_SLACK_MS = 10_000;                  // client-claimed elapsed may exceed server wall by this

const json = (obj, status = 200, headers = {}) =>
  new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json", ...headers } });
const ok = (obj, headers) => json(obj, 200, headers);
const fail = (status, error) => json({ error }, status);

async function readJson(req) { try { return await req.json(); } catch { return {}; } }
const nowS = () => Math.floor(Date.now() / 1000);
const serverDayIndex = () => Math.floor((Date.now() / 1000 - DAY_EPOCH) / 86400);

/// Fixed-window per-IP rate limiter backed by D1. Returns true if under the limit.
async function rateLimit(env, req, key, limit, windowSec) {
  const ip = req.headers.get("CF-Connecting-IP") || "0";
  const bucket = Math.floor(Date.now() / 1000 / windowSec);
  const k = `${key}:${ip}:${bucket}`;
  const row = await env.DB.prepare(
    "INSERT INTO rate(k,n,exp) VALUES(?,1,?) ON CONFLICT(k) DO UPDATE SET n=n+1 RETURNING n"
  ).bind(k, (bucket + 1) * windowSec).first();
  return (row?.n ?? 1) <= limit;
}

const PUBLIC_CONFIG = {
  clockSeconds: DEFAULT_CONFIG.clockSeconds, multiplierStart: DEFAULT_CONFIG.multiplierStart,
  multiplierStep: DEFAULT_CONFIG.multiplierStep, multiplierCap: DEFAULT_CONFIG.multiplierCap,
  tileCount: DEFAULT_CONFIG.tileCount, scoring: DEFAULT_CONFIG.scoring, timeRefund: DEFAULT_CONFIG.timeRefund,
};

async function getBoard(env, day) {
  return env.DB.prepare("SELECT day_index, tiles, playable_count, max_word_score FROM boards WHERE day_index = ?")
    .bind(day).first();
}

function shortCode() {
  const b = new Uint8Array(2); crypto.getRandomValues(b);
  return (b[0].toString(16) + b[1].toString(16)).toUpperCase().padStart(4, "0").slice(0, 4);
}

async function newPlayer(env, { apple_sub = null, isAnon = 1 }) {
  const id = randomId("p_");
  const code = shortCode();
  await env.DB.prepare(
    `INSERT INTO players(id, apple_sub, display, friend_code, is_anonymous, created_at)
     VALUES(?,?,?,?,?,?)`
  ).bind(id, apple_sub, "Player-" + code, "RUNG-" + code, isAnon, nowS()).run();
  return env.DB.prepare("SELECT * FROM players WHERE id = ?").bind(id).first();
}

function playerView(p) {
  return {
    id: p.id, username: p.username, display: p.display, friendCode: p.friend_code,
    isAnonymous: !!p.is_anonymous, currentStreak: p.current_streak, bestScore: p.best_score, lastDay: p.last_day,
  };
}

// ---------------- handlers ----------------

async function hDaily(req, env, url) {
  const day = url.searchParams.has("day") ? Number(url.searchParams.get("day")) : serverDayIndex();
  if (!Number.isInteger(day) || day < 0) return fail(400, "bad_day");
  if (day > serverDayIndex()) return fail(403, "future_day");
  // Past days locked (archive disabled in v1; Practice mode covers replay client-side).
  if (day < serverDayIndex()) return fail(403, "archived_day");
  const b = await getBoard(env, day);
  if (!b) return fail(404, "no_board");
  return ok({ dayIndex: b.day_index, epoch: DAY_EPOCH, tiles: b.tiles, config: PUBLIC_CONFIG },
            { "cache-control": "public, max-age=300" });
}

async function hAccount(req, env) {
  if (!(await rateLimit(env, req, "acct", 20, 3600))) return fail(429, "rate_limited");
  const body = await readJson(req);

  if (body.appleIdentityToken) {
    const sub = await verifyAppleIdentityToken(body.appleIdentityToken, body.nonce ?? null, BUNDLE_ID);
    const subKey = await hmacHex(sub, env.APPLE_SUB_PEPPER);
    let p = await env.DB.prepare("SELECT * FROM players WHERE apple_sub = ?").bind(subKey).first();
    // Merge an anonymous player into this Apple account only when the caller proves the
    // device with its secret (a leaked deviceId alone can't claim someone's progress).
    if (!p && body.deviceId && body.deviceSecret) {
      const link = await env.DB.prepare("SELECT * FROM device_links WHERE device_id = ?").bind(body.deviceId).first();
      if (link && link.secret_hash && constantTimeEqual(link.secret_hash, await sha256hex(body.deviceSecret))) {
        const anon = await env.DB.prepare("SELECT * FROM players WHERE id = ? AND is_anonymous = 1").bind(link.player_id).first();
        if (anon) {
          await env.DB.prepare("UPDATE players SET apple_sub = ?, is_anonymous = 0 WHERE id = ?").bind(subKey, anon.id).run();
          p = await env.DB.prepare("SELECT * FROM players WHERE id = ?").bind(anon.id).first();
        }
      }
    }
    if (!p) p = await newPlayer(env, { apple_sub: subKey, isAnon: 0 });
    const s = await createSession(env, p.id);
    return ok({ token: s.token, expiresAt: s.expiresAt, player: playerView(p) });
  }

  // Anonymous device registration / resume — authenticated by a server-issued device
  // secret, NOT the raw deviceId (which is not a secret).
  const deviceId = body.deviceId;
  if (!deviceId) return fail(400, "missing_deviceId");
  const link = await env.DB.prepare("SELECT * FROM device_links WHERE device_id = ?").bind(deviceId).first();
  if (link) {
    if (!body.deviceSecret || !link.secret_hash ||
        !constantTimeEqual(link.secret_hash, await sha256hex(body.deviceSecret))) {
      return fail(401, "bad_device_secret");
    }
    const p = await env.DB.prepare("SELECT * FROM players WHERE id = ?").bind(link.player_id).first();
    if (!p) return fail(401, "bad_device_secret");
    const s = await createSession(env, p.id);
    return ok({ token: s.token, expiresAt: s.expiresAt, player: playerView(p) });
  }
  // New device: mint a player + a device secret the client stores for next time.
  const secret = randomToken(32);
  const p = await newPlayer(env, { isAnon: 1 });
  await env.DB.prepare("INSERT OR IGNORE INTO device_links(device_id, player_id, secret_hash, created_at) VALUES(?,?,?,?)")
    .bind(deviceId, p.id, await sha256hex(secret), nowS()).run();
  const s = await createSession(env, p.id);
  return ok({ token: s.token, expiresAt: s.expiresAt, player: playerView(p), deviceSecret: secret });
}

async function hRunStart(req, env, player) {
  if (!(await rateLimit(env, req, "start", 60, 3600))) return fail(429, "rate_limited");
  const day = serverDayIndex();
  const b = await getBoard(env, day);
  if (!b) return fail(404, "no_board");
  const already = await env.DB.prepare("SELECT 1 FROM runs WHERE day_index = ? AND player_id = ?").bind(day, player.id).first();
  const runId = randomId("r_");
  const runToken = await makeRunToken(env, runId, player.id, day, Date.now());
  return ok({ runId, runToken, dayIndex: day, tiles: b.tiles, alreadyPlayed: !!already });
}

async function hRun(req, env, player) {
  const body = await readJson(req);
  const { runId, runToken, dayIndex, events, bankT_ms } = body;
  const day = serverDayIndex();
  if (dayIndex !== day) return fail(403, "wrong_day");
  if (!runId || !runToken) return fail(400, "missing_run_token");
  if (!Array.isArray(events) || events.length > MAX_EVENTS) return fail(422, "bad_events");

  const serverStartMs = await verifyRunToken(env, runToken, runId, player.id, day);
  const wall = Date.now() - serverStartMs;
  if (wall < -2000 || wall > 3_600_000) return fail(422, "stale_run_token");

  // structural + timing validation
  const bank = bankT_ms == null ? null : Number(bankT_ms);
  if (bank != null && (!Number.isFinite(bank) || bank < 0 || bank > MAX_BANK_MS)) return fail(422, "bad_bank");
  let prev = -1;
  for (const e of events) {
    if (!e || typeof e.word !== "string" || e.word.length > 15 || !Number.isInteger(e.t_ms) || e.t_ms < 0) return fail(422, "bad_event");
    if (e.t_ms < prev) return fail(422, "out_of_order");
    if (prev >= 0 && e.t_ms - prev < HARD_MIN_INTER_MS) return fail(422, "impossible_cadence");
    prev = e.t_ms;
  }
  const claimedElapsed = bank != null ? bank : (events.length ? events[events.length - 1].t_ms : 0);
  if (claimedElapsed > wall + WALL_SLACK_MS) return fail(422, "timeline_exceeds_wall");

  const board = await getBoard(env, day);
  if (!board) return fail(404, "no_board");
  const boardHist = tilesToHistogram(board.tiles);

  // dictionary membership for the submitted words (one batched query)
  const uniq = [...new Set(events.map((e) => String(e.word).trim().toUpperCase()).filter((w) => w.length >= 3 && w.length <= 15))];
  const validWords = new Set();
  for (let i = 0; i < uniq.length; i += 90) {   // chunk to stay under D1's bound-param limit
    const chunk = uniq.slice(i, i + 90);
    const ph = chunk.map(() => "?").join(",");
    const { results } = await env.DB.prepare(`SELECT word FROM words WHERE word IN (${ph})`).bind(...chunk).all();
    for (const r of results) validWords.add(r.word);
  }

  const r = replayRun(events, bank, boardHist, validWords);

  // soft timing floor on ACCEPTED words -> verified flag (shadow-rank if dubious)
  let verified = 1;
  {
    let p2 = 0;
    const acc = new Set(r.acceptedWords);
    for (const e of events.sort((a, b) => a.t_ms - b.t_ms)) {
      const w = String(e.word).trim().toUpperCase();
      if (acc.has(w)) { if (e.t_ms - p2 < softFloor(w.length)) verified = 0; }
      p2 = e.t_ms;
    }
  }

  const banked = r.outcome === "banked" ? 1 : 0;
  const now = nowS();
  const ins = await env.DB.prepare(
    `INSERT INTO runs(day_index, player_id, final_score, base_sum, peak_mult, word_count, banked, verified, created_at)
     VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(day_index, player_id) DO NOTHING`
  ).bind(day, player.id, r.finalScore, r.baseSum, r.peakMultiplier, r.wordCount, banked, verified, now).run();

  let duplicate = false;
  let stored = r;
  if (ins.meta.changes === 1) {
    await env.DB.batch([
      env.DB.prepare(
        `UPDATE players SET best_score = MAX(best_score, ?),
           current_streak = CASE WHEN last_day = ? THEN current_streak ELSE
             (CASE WHEN last_day = ? THEN current_streak + 1 ELSE 1 END) END,
           last_day = ? WHERE id = ?`
      ).bind(r.finalScore, day, day - 1, day, player.id),
      env.DB.prepare(
        `INSERT INTO day_stats(day_index, player_count, max_score, updated_at) VALUES(?,1,?,?)
         ON CONFLICT(day_index) DO UPDATE SET player_count = player_count + 1,
           max_score = MAX(max_score, excluded.max_score), updated_at = excluded.updated_at`
      ).bind(day, r.finalScore, now),
    ]);
  } else {
    duplicate = true;
    const ex = await env.DB.prepare("SELECT * FROM runs WHERE day_index = ? AND player_id = ?").bind(day, player.id).first();
    stored = { finalScore: ex.final_score, baseSum: ex.base_sum, peakMultiplier: ex.peak_mult, wordCount: ex.word_count, outcome: ex.banked ? "banked" : "bustedOut" };
  }

  const myScore = stored.finalScore;
  const rankRow = await env.DB.prepare("SELECT COUNT(*) AS c FROM runs WHERE day_index = ? AND final_score > ?").bind(day, myScore).first();
  const beatenRow = await env.DB.prepare("SELECT COUNT(*) AS c FROM runs WHERE day_index = ? AND final_score < ?").bind(day, myScore).first();
  const totalRow = await env.DB.prepare("SELECT player_count AS c FROM day_stats WHERE day_index = ?").bind(day).first();
  const total = totalRow ? totalRow.c : 1;
  const percentile = total > 0 ? Math.round((1000 * beatenRow.c) / total) / 10 : 0;

  return ok({
    dayIndex: day, finalScore: stored.finalScore, baseSum: stored.baseSum,
    peakMultiplier: stored.peakMultiplier, wordCount: stored.wordCount,
    banked: stored.outcome === "banked", verified: !!verified, duplicate,
    rank: rankRow.c + 1, percentile, playerCount: total,
  });
}

async function hLeaderboard(req, env, url, player) {
  const scope = url.searchParams.get("scope") || "global";
  const period = url.searchParams.get("period") || "daily";
  const limit = Math.min(Number(url.searchParams.get("limit") || 50), 100);
  if (scope !== "global") return fail(400, "scope_unsupported"); // friends: next iteration

  let entries;
  if (period === "alltime") {
    const { results } = await env.DB.prepare(
      `SELECT id, username, display, best_score AS score FROM players
       WHERE best_score > 0 ORDER BY best_score DESC LIMIT ?`
    ).bind(limit).all();
    entries = results;
    return ok({ scope, period, entries });
  }
  // daily
  const day = url.searchParams.has("day") ? Number(url.searchParams.get("day")) : serverDayIndex();
  if (!Number.isInteger(day) || day < 0 || day > serverDayIndex()) return fail(400, "bad_day");
  const { results } = await env.DB.prepare(
    `SELECT p.id, p.username, p.display, r.final_score AS score, r.word_count
     FROM runs r JOIN players p ON p.id = r.player_id
     WHERE r.day_index = ? ORDER BY r.final_score DESC, r.created_at ASC LIMIT ?`
  ).bind(day, limit).all();
  let me = null;
  if (player) {
    const mine = await env.DB.prepare("SELECT final_score FROM runs WHERE day_index = ? AND player_id = ?").bind(day, player.id).first();
    if (mine) {
      const rank = (await env.DB.prepare("SELECT COUNT(*) AS c FROM runs WHERE day_index = ? AND final_score > ?").bind(day, mine.final_score).first()).c + 1;
      const beaten = (await env.DB.prepare("SELECT COUNT(*) AS c FROM runs WHERE day_index = ? AND final_score < ?").bind(day, mine.final_score).first()).c;
      const total = (await env.DB.prepare("SELECT player_count AS c FROM day_stats WHERE day_index = ?").bind(day).first())?.c || 1;
      me = { score: mine.final_score, rank, percentile: Math.round((1000 * beaten) / total) / 10 };
    }
  }
  return ok({ scope, period, day, entries: results, me });
}

async function hMe(req, env, player) { return ok({ player: playerView(player) }); }

async function hUsername(req, env, player) {
  const { username } = await readJson(req);
  const u = String(username || "").trim().toLowerCase();
  if (!/^[a-z0-9_]{3,16}$/.test(u)) return fail(400, "invalid_username");
  const BLOCK = ["admin", "rung", "moderator", "fuck", "shit", "nigger", "faggot", "cunt"];
  if (BLOCK.some((b) => u.includes(b))) return fail(400, "blocked_username");
  const taken = await env.DB.prepare("SELECT 1 FROM players WHERE username = ? COLLATE NOCASE AND id <> ?").bind(u, player.id).first();
  if (taken) return fail(409, "username_taken");
  await env.DB.prepare("UPDATE players SET username = ?, display = ? WHERE id = ?").bind(u, u, player.id).run();
  const p = await env.DB.prepare("SELECT * FROM players WHERE id = ?").bind(player.id).first();
  return ok({ player: playerView(p) });
}

async function hHealth(req, env) {
  const b0 = await getBoard(env, 0);
  const okBoard = b0 && b0.tiles === "AEFGIIKNNPUU";
  const okScore = baseScore("QUARTZ") === 800;
  return ok({ ok: okBoard && okScore, day0: b0?.tiles, serverDay: serverDayIndex(), scoreCheck: okScore });
}

async function hDeleteAccount(req, env, player) {
  // Explicit deletes (don't rely on D1 FK cascade enforcement).
  await env.DB.batch([
    env.DB.prepare("DELETE FROM runs WHERE player_id = ?").bind(player.id),
    env.DB.prepare("DELETE FROM sessions WHERE player_id = ?").bind(player.id),
    env.DB.prepare("DELETE FROM device_links WHERE player_id = ?").bind(player.id),
    env.DB.prepare("DELETE FROM friendships WHERE player_id = ? OR friend_id = ?").bind(player.id, player.id),
    env.DB.prepare("DELETE FROM players WHERE id = ?").bind(player.id),
  ]);
  return ok({ deleted: true });
}

// ---------------- static pages (privacy / terms / landing) ----------------

function htmlPage(body) {
  return new Response(
    `<!doctype html><html lang="en"><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width,initial-scale=1"><title>RUNG</title>` +
    `<style>body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;` +
    `background:#17130E;color:#F6F1E7;max-width:680px;margin:0 auto;padding:44px 22px;line-height:1.62}` +
    `h1{font-size:30px;margin:.2em 0}h2{margin-top:1.6em}a{color:#F3C04A}.muted{color:#C9BFAE}` +
    `ul{padding-left:20px}.bars{display:flex;gap:6px;margin-bottom:26px}.bars span{height:7px;width:38px;border-radius:2px}</style>` +
    `</head><body>${body}</body></html>`,
    { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=3600" } }
  );
}
const BARS = `<div class="bars"><span style="background:#F3C04A"></span><span style="background:#F0993D"></span><span style="background:#E96B2E"></span><span style="background:#DE3B22"></span></div>`;

function hLanding() {
  return htmlPage(`${BARS}<h1>RUNG</h1>
    <p class="muted">A once-a-day competitive word game. The same board for everyone, one 60-second run — bank it, or push your luck.</p>
    <p><a href="/privacy">Privacy Policy</a> &middot; <a href="/terms">Terms of Use</a></p>`);
}

function hPrivacy() {
  return htmlPage(`<h1>RUNG — Privacy Policy</h1><p class="muted">Last updated 24 June 2026.</p>
    <p>RUNG is a daily word game. We collect the minimum needed to run the game and its leaderboards. We show no ads, use no third-party analytics or tracking, and never sell your data.</p>
    <h2>What we collect</h2><ul>
      <li><b>Gameplay data</b> — your scores, words-found count, run timing, and streaks, used to score runs and build leaderboards.</li>
      <li><b>An account identifier</b> — if you play anonymously, a random identifier generated on your device; if you Sign in with Apple, a one-way hashed identifier derived from Apple. We never receive or store your real name or email.</li>
      <li><b>A username</b>, only if you choose to set one (shown on leaderboards).</li>
    </ul>
    <h2>What we do not collect</h2>
    <p>No name, email, phone number, contacts, location, photos, or advertising identifier. No cross-app or cross-site tracking.</p>
    <h2>How we use it</h2>
    <p>Only to operate the game: validate and score runs, compute daily and all-time leaderboards, show your rank, and maintain your streak. Your username (or an anonymous label) and score are visible to other players on leaderboards.</p>
    <h2>Where it is stored</h2><p>On Cloudflare, our infrastructure provider, processing the data on our behalf.</p>
    <h2>Your choices</h2>
    <p>You can play entirely anonymously without signing in. You can delete your account and all associated data at any time from <b>Settings &rarr; Delete account</b> in the app, or by emailing us.</p>
    <h2>Children</h2><p>RUNG is not directed to children under 13 and collects no personal information beyond what is described above.</p>
    <h2>Contact</h2><p>Questions or deletion requests: <a href="mailto:cole@manticthink.com">cole@manticthink.com</a>.</p>`);
}

function hTerms() {
  return htmlPage(`<h1>RUNG — Terms of Use</h1><p class="muted">Last updated 24 June 2026.</p>
    <p>RUNG is provided as-is, for personal entertainment. Play fair: do not cheat, automate, or manipulate the leaderboards — we may remove scores or accounts that do. The daily board and word list are provided without warranty. We may update or discontinue the game at any time. By playing, you agree to these terms.</p>
    <p>Contact: <a href="mailto:cole@manticthink.com">cole@manticthink.com</a>.</p>`);
}

// ---------------- router ----------------

async function requireAuth(req, env) {
  const p = await authPlayer(req, env);
  if (!p) throw new HttpError(401, "unauthorized");
  return p;
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const path = url.pathname;
    const method = req.method.toUpperCase();
    try {
      if (!env.SESSION_SECRET || !env.APPLE_SUB_PEPPER) return fail(500, "server_misconfigured");
      if (path === "/healthz") return hHealth(req, env);
      if (path === "/" && method === "GET") return hLanding();
      if (path === "/privacy" && method === "GET") return hPrivacy();
      if (path === "/terms" && method === "GET") return hTerms();
      if (path === "/v1/daily" && method === "GET") return hDaily(req, env, url);
      if (path === "/v1/account" && method === "POST") return hAccount(req, env);
      if (path === "/v1/account" && method === "DELETE") return hDeleteAccount(req, env, await requireAuth(req, env));
      if (path === "/v1/run/start" && method === "POST") return hRunStart(req, env, await requireAuth(req, env));
      if (path === "/v1/run" && method === "POST") return hRun(req, env, await requireAuth(req, env));
      if (path === "/v1/leaderboard" && method === "GET") return hLeaderboard(req, env, url, await authPlayer(req, env));
      if (path === "/v1/me" && method === "GET") return hMe(req, env, await requireAuth(req, env));
      if (path === "/v1/username" && method === "PUT") return hUsername(req, env, await requireAuth(req, env));
      return fail(404, "not_found");
    } catch (e) {
      if (e instanceof HttpError) return fail(e.status, e.message);
      console.error("internal", e && (e.stack || e.message));
      return fail(500, "internal_error");
    }
  },
};
