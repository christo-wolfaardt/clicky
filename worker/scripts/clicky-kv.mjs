// Shared helpers for the access-code admin scripts. They shell out to
// wrangler so they use the same Cloudflare login as `wrangler deploy`.
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const workerDirectory = join(dirname(fileURLToPath(import.meta.url)), "..");

function runWranglerKvCommand(argumentsAfterKv) {
  return execFileSync(
    "npx",
    ["wrangler", "kv", ...argumentsAfterKv, "--binding", "CLICKY_USERS", "--remote"],
    { cwd: workerDirectory, encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] }
  ).trim();
}

export function sha256Hex(text) {
  return createHash("sha256").update(text).digest("hex");
}

export function putKvValue(key, value) {
  runWranglerKvCommand(["key", "put", key, value]);
}

/** Returns the value, or null when the key doesn't exist. */
export function getKvValue(key) {
  // wrangler can print notices before the value, and reports a missing key
  // as "Value not found" on stdout with exit code 0. Every value these
  // scripts store is a single line, so the last line is the value.
  const getOutputLines = runWranglerKvCommand(["key", "get", key, "--text"]).split("\n");
  const value = getOutputLines[getOutputLines.length - 1].trim();
  return value === "Value not found" ? null : value;
}

export function deleteKvValue(key) {
  runWranglerKvCommand(["key", "delete", key]);
}

export function listKvKeyNames(prefix) {
  const listOutput = runWranglerKvCommand(["key", "list", "--prefix", prefix]);
  // wrangler may print a banner before the JSON array
  const jsonStartIndex = listOutput.indexOf("[");
  return JSON.parse(listOutput.slice(jsonStartIndex)).map((keyEntry) => keyEntry.name);
}

/** Names are used as identifiers in KV keys, so keep them simple. */
export function normalizeUserName(rawUserName) {
  const userName = (rawUserName ?? "").trim().toLowerCase();
  if (!/^[a-z0-9-]{1,32}$/.test(userName)) {
    console.error("Name must be 1-32 characters: letters, numbers or dashes (e.g. aneska).");
    process.exit(1);
  }
  return userName;
}
