#!/usr/bin/env node
// Read-only discovery of RUNG's App Store Connect editable draft (version, app info,
// localizations, age rating, categories) so we know what to PATCH. No writes.
import crypto from "node:crypto";
const API = "https://api.appstoreconnect.apple.com/v1";
const KEY_ID = "CL8R428N2X", ISSUER = "deed181a-e993-4eec-9c9a-574186992beb";
const BUNDLE = "com.colecantcode.rung";

function b64u(b) { return Buffer.from(b).toString("base64").replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", ""); }
function token() {
  const key = Buffer.from(process.env.ASC_KEY_P8_BASE64, "base64").toString("utf8");
  const now = Math.floor(Date.now() / 1000);
  const si = `${b64u(JSON.stringify({ alg: "ES256", kid: KEY_ID, typ: "JWT" }))}.${b64u(JSON.stringify({ iss: ISSUER, iat: now, exp: now + 1100, aud: "appstoreconnect-v1" }))}`;
  const sig = crypto.sign("sha256", Buffer.from(si), { key, dsaEncoding: "ieee-p1363" });
  return `${si}.${b64u(sig)}`;
}
const T = token();
async function get(path) {
  const r = await fetch(API + path, { headers: { Authorization: `Bearer ${T}` } });
  const j = await r.json();
  if (!r.ok) throw new Error(`${path} -> ${r.status}: ${JSON.stringify(j.errors || j)}`);
  return j;
}

const app = (await get(`/apps?filter[bundleId]=${BUNDLE}`)).data[0];
console.log("APP", app.id, app.attributes.name);

const vers = await get(`/apps/${app.id}/appStoreVersions?limit=5`);
for (const v of vers.data) console.log("  version", v.id, v.attributes.versionString, v.attributes.appStoreState, v.attributes.platform);
const editable = vers.data.find((v) => ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"].includes(v.attributes.appStoreState)) || vers.data[0];
console.log("EDITABLE VERSION", editable.id, editable.attributes.versionString, editable.attributes.appStoreState);

const vloc = await get(`/appStoreVersions/${editable.id}/appStoreVersionLocalizations`);
for (const l of vloc.data) console.log("  vLoc", l.id, l.attributes.locale, "desc?", !!l.attributes.description, "kw:", l.attributes.keywords);

const infos = await get(`/apps/${app.id}/appInfos?limit=5`);
for (const ai of infos.data) console.log("  appInfo", ai.id, ai.attributes.appStoreState ?? ai.attributes.state, "primaryCat:", ai.relationships?.primaryCategory?.data?.id);
const info = infos.data.find((a) => ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED"].includes(a.attributes.appStoreState ?? a.attributes.state)) || infos.data[0];
console.log("EDITABLE APPINFO", info.id);

const iloc = await get(`/appInfos/${info.id}/appInfoLocalizations`);
for (const l of iloc.data) console.log("  iLoc", l.id, l.attributes.locale, "name:", l.attributes.name, "subtitle:", l.attributes.subtitle, "privacy:", l.attributes.privacyPolicyUrl);

try {
  const ard = await get(`/appInfos/${info.id}/ageRatingDeclaration`);
  console.log("AGE RATING DECL", ard.data?.id);
} catch (e) { console.log("age rating:", e.message); }

const cats = await get(`/appCategories?filter[platforms]=IOS&exists[parent]=false&limit=50`);
console.log("GAMES category present:", cats.data.some((c) => c.id === "GAMES"));
const subs = await get(`/appCategories/GAMES/subcategories?limit=50`).catch((e) => ({ data: [] }));
console.log("GAMES subcategories:", subs.data.map((s) => s.id).join(", "));
