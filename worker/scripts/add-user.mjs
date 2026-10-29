// Creates a personal access code for one person.
//
//   node scripts/add-user.mjs <name> [daily chat limit]
//   node scripts/add-user.mjs christo            → unlimited
//   node scripts/add-user.mjs eben 50            → 50 Claude requests per UTC day
//
// The code is printed once and only its hash is stored, so copy it straight
// to the person. If it's lost, remove the user and add them again.
import { randomInt } from "node:crypto";
import { getKvValue, normalizeUserName, putKvValue, sha256Hex } from "./clicky-kv.mjs";

const userName = normalizeUserName(process.argv[2]);
const rawDailyChatRequestLimit = process.argv[3];
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

putKvValue(`user:${accessCodeHash}`, JSON.stringify({ name: userName, dailyChatRequestLimit }));
putKvValue(`username:${userName}`, accessCodeHash);

console.log(`\nAccess code for ${userName} (${dailyChatRequestLimit ?? "unlimited"} chats/day):\n`);
console.log(`    ${accessCode}\n`);
console.log("This is shown only once. Send it to them privately.");
