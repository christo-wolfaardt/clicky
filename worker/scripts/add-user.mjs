// Creates a personal access code for one person.
//
//   node scripts/add-user.mjs <name> [daily chat limit] [--models id,id]
//   node scripts/add-user.mjs christo            → unlimited, any model
//   node scripts/add-user.mjs eben 50            → 50 Claude requests per UTC day
//   node scripts/add-user.mjs eben 50 --models claude-sonnet-4-6
//                                                → and Sonnet only
//
// The code is printed once and only its hash is stored, so copy it straight
// to the person. If it's lost, remove the user and add them again.
import { randomInt } from "node:crypto";
import { getKvValue, normalizeUserName, putKvValue, sha256Hex } from "./clicky-kv.mjs";

const commandLineArguments = process.argv.slice(2);
const modelsFlagIndex = commandLineArguments.indexOf("--models");
let allowedModels = null;
if (modelsFlagIndex !== -1) {
  const rawAllowedModels = commandLineArguments[modelsFlagIndex + 1] ?? "";
  allowedModels = rawAllowedModels.split(",").map((modelID) => modelID.trim()).filter(Boolean);
  if (allowedModels.length === 0) {
    console.error("--models needs at least one model ID, e.g. --models claude-sonnet-4-6");
    process.exit(1);
  }
  commandLineArguments.splice(modelsFlagIndex, 2);
}

const userName = normalizeUserName(commandLineArguments[0]);
const rawDailyChatRequestLimit = commandLineArguments[1];
const dailyChatRequestLimit = rawDailyChatRequestLimit === undefined ? null : parseInt(rawDailyChatRequestLimit, 10);

if (dailyChatRequestLimit !== null && !(dailyChatRequestLimit > 0)) {
  console.error("Daily limit must be a positive number, or left out for unlimited.");
  process.exit(1);
}

if (getKvValue(`username:${userName}`) !== null) {
  console.error(`"${userName}" already has a code. Run remove-user.mjs first to replace it.`);
  process.exit(1);
}

// No 0/O/1/I/L so codes are easy to read out loud or type from a message.
const unambiguousCharacters = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const codeGroups = Array.from({ length: 4 }, () =>
  Array.from({ length: 5 }, () => unambiguousCharacters[randomInt(unambiguousCharacters.length)]).join("")
);
const accessCode = `CLK-${codeGroups.join("-")}`;
const accessCodeHash = sha256Hex(accessCode);

putKvValue(`user:${accessCodeHash}`, JSON.stringify({ name: userName, dailyChatRequestLimit, allowedModels }));
putKvValue(`username:${userName}`, accessCodeHash);

console.log(`\nAccess code for ${userName}`);
console.log(`  Daily limit: ${dailyChatRequestLimit ?? "unlimited"} chats`);
console.log(`  Models:      ${allowedModels ? allowedModels.join(", ") : "any"}\n`);
console.log(`    ${accessCode}\n`);
console.log("This is shown only once. Send it to them privately, together with");
console.log("your server address (the workers.dev URL from `npx wrangler deploy`).");
