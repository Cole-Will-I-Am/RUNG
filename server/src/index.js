// RUNG backend Worker. Server-authoritative scoring + leaderboards on D1.
// The client never sends a score — only the ordered words + timings; the server
// replays the engine (engine.js, verified bit-identical to the Swift client) and
// recomputes everything. See server/arch_*.md for the full design.

import { DEFAULT_CONFIG, DAY_EPOCH, baseScore, tilesToHistogram, replayRun } from "./engine.js";
import {
  HttpError, sha256hex, hmacHex, randomToken, randomId,
  verifyAppleIdentityToken, createSession, authPlayer, makeRunToken, verifyRunToken,
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
  const body = await readJson(req);
  if (body.appleIdentityToken) {
    const sub = await verifyAppleIdentityToken(body.appleIdentityToken, body.nonce ?? null, BUNDLE_ID);
    const subKey = await hmacHex(sub, env.APPLE_SUB_PEPPER);
    let p = await env.DB.prepare("SELECT * FROM players WHERE apple_sub = ?").bind(subKey).first();
    if (!p && body.deviceId) {
      // Upgrade an existing anonymous player tied to this device.
      const link = await env.DB.prepare("SELECT player_id FROM device_links WHERE device_id = ?").bind(body.deviceId).first();
      if (link) {
        const anon = await env.DB.prepare("SELECT * FROM players WHERE id = ? AND is_anonymous = 1").bind(link.player_id).first();
        if (anon) {
          await env.DB.prepare("UPDATE players SET apple_sub = ?, is_anonymous = 0 WHERE id = ?").bind(subKey, anon.id).run();
          p = await env.DB.prepare("SELECT * FROM players WHERE id = ?").bind(anon.id).first();
        }
      }
    }
    if (!p) p = await newPlayer(env, { apple_sub: subKey, isAnon: 0 });
    if (body.deviceId) {
      await env.DB.prepare("INSERT OR IGNORE INTO device_links(device_id, player_id, created_at) VALUES(?,?,?)")
        .bind(body.deviceId, p.id, nowS()).run();
    }
    const s = await createSession(env, p.id);
    return ok({ token: s.token, expiresAt: s.expiresAt, player: playerView(p) });
  }

  // Anonymous device registration.
  const deviceId = body.deviceId;
  if (!deviceId) return fail(400, "missing_deviceId");
  let p;
  const link = await env.DB.prepare("SELECT player_id FROM device_links WHERE device_id = ?").bind(deviceId).first();
  if (link) p = await env.DB.prepare("SELECT * FROM players WHERE id = ?").bind(link.player_id).first();
  if (!p) {
    p = await newPlayer(env, { isAnon: 1 });
    await env.DB.prepare("INSERT OR IGNORE INTO device_links(device_id, player_id, created_at) VALUES(?,?,?)")
      .bind(deviceId, p.id, nowS()).run();
  }
  const s = await createSession(env, p.id);
  return ok({ token: s.token, expiresAt: s.expiresAt, player: playerView(p) });
}

async function hRunStart(req, env, player) {
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
  if (bank != null && (bank < 0 || bank > MAX_BANK_MS)) return fail(422, "bad_bank");
  let prev = -1;
  for (const e of events) {
    if (!e || typeof e.word !== "string" || !Number.isInteger(e.t_ms) || e.t_ms < 0) return fail(422, "bad_event");
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
  const uniq = [...new Set(events.map((e) => String(e.word).trim().toUpperCase()).filter((w) => w.length >= 3))];
  const validWords = new Set();
  if (uniq.length) {
    const ph = uniq.map(() => "?").join(",");
    const { results } = await env.DB.prepare(`SELECT word FROM words WHERE word IN (${ph})`).bind(...uniq).all();
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
      if (path === "/healthz") return hHealth(req, env);
      if (path === "/v1/daily" && method === "GET") return hDaily(req, env, url);
      if (path === "/v1/account" && method === "POST") return hAccount(req, env);
      if (path === "/v1/run/start" && method === "POST") return hRunStart(req, env, await requireAuth(req, env));
      if (path === "/v1/run" && method === "POST") return hRun(req, env, await requireAuth(req, env));
      if (path === "/v1/leaderboard" && method === "GET") return hLeaderboard(req, env, url, await authPlayer(req, env));
      if (path === "/v1/me" && method === "GET") return hMe(req, env, await requireAuth(req, env));
      if (path === "/v1/username" && method === "PUT") return hUsername(req, env, await requireAuth(req, env));
      return fail(404, "not_found");
    } catch (e) {
      if (e instanceof HttpError) return fail(e.status, e.message);
      return fail(500, "internal: " + (e && e.message));
    }
  },
};
