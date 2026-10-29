// Revokes a person's access code immediately.
//
//   node scripts/remove-user.mjs <name>
import { deleteKvValue, getKvValue, normalizeUserName } from "./clicky-kv.mjs";

const userName = normalizeUserName(process.argv[2]);
const accessCodeHash = getKvValue(`username:${userName}`);

if (accessCodeHash === null) {
  console.error(`No access code found for "${userName}".`);
  process.exit(1);
}

deleteKvValue(`user:${accessCodeHash}`);
deleteKvValue(`username:${userName}`);
console.log(`Removed ${userName}. Their Clicky will ask them to sign in again.`);
