#!/usr/bin/env node
// Push RUNG's listing metadata to the App Store Connect DRAFT (does not submit). Each
// PATCH is isolated so one failure doesn't abort the rest. Re-runnable.
import crypto from "node:crypto";
const API = "https://api.appstoreconnect.apple.com/v1";
const KEY_ID = "CL8R428N2X", ISSUER = "deed181a-e993-4eec-9c9a-574186992beb";

// resource ids from asc_discover.mjs
const VERSION_LOC = "3680d41d-a91d-4956-bf18-823e3b441269";
const INFO = "8f6f91ba-7d23-494a-ac62-ba534296b04c";
const INFO_LOC = "7564cf6c-12b4-4c3c-b492-3c48726ef241";
const AGE = "8f6f91ba-7d23-494a-ac62-ba534296b04c";

function b64u(b) { return Buffer.from(b).toString("base64").replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", ""); }
function token() {
  const key = Buffer.from(process.env.ASC_KEY_P8_BASE64, "base64").toString("utf8");
  const now = Math.floor(Date.now() / 1000);
  const si = `${b64u(JSON.stringify({ alg: "ES256", kid: KEY_ID, typ: "JWT" }))}.${b64u(JSON.stringify({ iss: ISSUER, iat: now, exp: now + 1100, aud: "appstoreconnect-v1" }))}`;
  return `${si}.${b64u(crypto.sign("sha256", Buffer.from(si), { key, dsaEncoding: "ieee-p1363" }))}`;
}
const T = token();
async function patch(path, body, label) {
  try {
    const r = await fetch(API + path, { method: "PATCH", headers: { Authorization: `Bearer ${T}`, "Content-Type": "application/json" }, body: JSON.stringify(body) });
    if (r.ok) { console.log(`✅ ${label}`); return true; }
    const j = await r.json().catch(() => ({}));
    console.log(`❌ ${label}: ${r.status} ${JSON.stringify((j.errors || []).map((e) => e.detail || e.title))}`);
  } catch (e) { console.log(`❌ ${label}: ${e.message}`); }
  return false;
}

const DESCRIPTION = `RUNG is a once-a-day word game built around a single, nerve-wracking decision: bank your score, or push your luck for one more word.

Every day, everyone in the world gets the SAME 12 letters. You get one 60-second run. Each word you find adds points and lifts your multiplier — but that multiplier bonus is unbanked. Press BANK to lock it in, or keep going and risk losing it all when the clock hits zero. The longer you push, the more you stand to win… and to lose.

Then you see exactly where you landed: a real global leaderboard and your percentile for the day. No pay-to-win, no gimmicks — the same board for everyone makes every rank earned.

• ONE daily board, shared worldwide — pure, comparable competition
• Push-your-luck scoring — bank a safe score or gamble on the multiplier
• 60 seconds to play, ~5 to share
• Global daily + all-time leaderboards, with your live rank and percentile
• Practice mode — unlimited runs on random boards to warm up (never affects your rank)
• Streaks and personal bests to chase
• Play anonymously, or Sign in with Apple to claim a username and carry your stats
• No ads. No in-app purchases. No tracking.

One board. One shot. Every day. How high can you climb?`;

const PROMO = "A new 12-letter board drops every day — everyone plays the same one. Find words, build your multiplier, then make the call: bank it, or push your luck for one more word.";

// 1) version localization
await patch(`/appStoreVersionLocalizations/${VERSION_LOC}`, {
  data: { type: "appStoreVersionLocalizations", id: VERSION_LOC, attributes: {
    description: DESCRIPTION,
    keywords: "word,daily,puzzle,anagram,words,leaderboard,brain,vocabulary,letters,spelling,wordle,score,bank",
    promotionalText: PROMO,
    supportUrl: "https://rung-api.manticthink.com",
    marketingUrl: "https://rung-api.manticthink.com",
  } } }, "version localization (description / keywords / urls / promo)");

// 2) app info localization — name, subtitle, privacy policy
await patch(`/appInfoLocalizations/${INFO_LOC}`, {
  data: { type: "appInfoLocalizations", id: INFO_LOC, attributes: {
    name: "RUNG: Daily Word Climb",
    subtitle: "One board. One run. Bank it.",
    privacyPolicyUrl: "https://rung-api.manticthink.com/privacy",
  } } }, "app name / subtitle / privacy URL");

// 2b) fallback if the longer name is taken: at least set subtitle + privacy, keep name
//     (handled by re-running with name omitted if the above fails — see note in output)

// 3) categories
await patch(`/appInfos/${INFO}`, {
  data: { type: "appInfos", id: INFO, relationships: {
    primaryCategory: { data: { type: "appCategories", id: "GAMES" } },
    primarySubcategoryOne: { data: { type: "appCategories", id: "GAMES_WORD" } },
    primarySubcategoryTwo: { data: { type: "appCategories", id: "GAMES_PUZZLE" } },
  } } }, "category Games → Word / Puzzle");

// 4) age rating → 4+
await patch(`/ageRatingDeclarations/${AGE}`, {
  data: { type: "ageRatingDeclarations", id: AGE, attributes: {
    alcoholTobaccoOrDrugUseOrReferences: "NONE", contests: "NONE", gamblingSimulated: "NONE",
    horrorOrFearThemes: "NONE", matureOrSuggestiveThemes: "NONE", medicalOrTreatmentInformation: "NONE",
    profanityOrCrudeHumor: "NONE", sexualContentGraphicAndNudity: "NONE", sexualContentOrNudity: "NONE",
    violenceCartoonOrFantasy: "NONE", violenceRealistic: "NONE", violenceRealisticProlongedGraphicOrSadistic: "NONE",
    gunsOrOtherWeapons: "NONE",
    gambling: false, unrestrictedWebAccess: false, advertising: false, healthOrWellnessTopics: false,
    messagingAndChat: false, lootBox: false, parentalControls: false, ageAssurance: false, userGeneratedContent: false,
  } } }, "age rating (4+)");

console.log("\nDone. Review in App Store Connect before submitting.");
