// Shows how many Claude requests each person made per UTC day.
//
//   node scripts/show-usage.mjs              → every day still on record (last 45 days)
//   node scripts/show-usage.mjs 2026-10-29   → just that day
import { getKvValue, listKvKeyNames } from "./clicky-kv.mjs";

const onlyThisDay = process.argv[2];
const usageKeyNames = listKvKeyNames("usage:")
  .filter((keyName) => !onlyThisDay || keyName.endsWith(`:${onlyThisDay}`))
  .sort();

if (usageKeyNames.length === 0) {
  console.log("No usage recorded.");
}

for (const usageKeyName of usageKeyNames) {
  const [, userName, day] = usageKeyName.split(":");
  console.log(`${day}  ${userName.padEnd(16)} ${getKvValue(usageKeyName)}`);
}
