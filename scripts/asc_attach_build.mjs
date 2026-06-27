#!/usr/bin/env node
// Attach the latest VALID TestFlight build to RUNG's App Store version, and match the
// version string to that build. Does not submit.
import crypto from "node:crypto";
const API = "https://api.appstoreconnect.apple.com/v1";
const KEY_ID = "CL8R428N2X", ISSUER = "deed181a-e993-4eec-9c9a-574186992beb";
const APP = "6783999371";
const VERSION = "c8a309b3-9a4c-40ca-b24f-124bfe5df6cd";

function b64u(b) { return Buffer.from(b).toString("base64").replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", ""); }
const key = Buffer.from(process.env.ASC_KEY_P8_BASE64, "base64").toString("utf8");
const now = Math.floor(Date.now() / 1000);
const si = `${b64u(JSON.stringify({ alg: "ES256", kid: KEY_ID, typ: "JWT" }))}.${b64u(JSON.stringify({ iss: ISSUER, iat: now, exp: now + 1100, aud: "appstoreconnect-v1" }))}`;
const T = `${si}.${b64u(crypto.sign("sha256", Buffer.from(si), { key, dsaEncoding: "ieee-p1363" }))}`;
async function api(path, opts = {}) {
  const r = await fetch(API + path, { ...opts, headers: { Authorization: `Bearer ${T}`, "Content-Type": "application/json", ...(opts.headers || {}) } });
  const j = r.status === 204 ? {} : await r.json();
  if (!r.ok) throw new Error(`${path} -> ${r.status}: ${JSON.stringify(j.errors || j)}`);
  return j;
}

const builds = await api(`/builds?filter[app]=${APP}&sort=-uploadedDate&limit=10&include=preReleaseVersion`);
const valid = builds.data.find((b) => b.attributes.processingState === "VALID");
if (!valid) { console.log("No VALID build found."); process.exit(1); }
const pre = builds.included?.find((i) => i.id === valid.relationships.preReleaseVersion?.data?.id);
const ver = pre?.attributes?.version || "1.0";
console.log(`Latest VALID build: #${valid.attributes.version}  marketing ${ver}  id ${valid.id}`);

await api(`/appStoreVersions/${VERSION}`, { method: "PATCH", body: JSON.stringify({
  data: { type: "appStoreVersions", id: VERSION, attributes: { versionString: ver },
          relationships: { build: { data: { type: "builds", id: valid.id } } } } }) });
console.log(`✅ Version set to ${ver} and build #${valid.attributes.version} attached.`);
