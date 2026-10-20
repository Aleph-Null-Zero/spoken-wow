// Lists bosses whose Adventure Guide text may belong to a namesake: matched by name only, or listed in another
// instance than ours. Writes a JSON array of "map:key" to the path given (default: stdout summary only).
import { writeFile } from "node:fs/promises";

import { flat, readBosses } from "../../lib/bosses.mjs";
import { loadDungeons } from "../../lib/dungeons.mjs";
import { wagoTable } from "../../lib/wago.mjs";

const bosses = await readBosses();
const get = (n) => wagoTable(n, { build: "12.1.5.70448", locale: "enUS" });
const encounters = await get("JournalEncounter");
const instances = await get("JournalInstance");
const instName = new Map(instances.map((r) => [r.ID, r.Name_lang]));
const instMap = new Map(instances.map((r) => [Number(r.MapID), r.Name_lang]));
const known = loadDungeons();
const ours = new Map(Object.entries({ ...known.dungeons, ...known.worldBosses }).map(([m, r]) => [Number(m), r.name]));
const byDE = new Map(encounters.map((r) => [Number(r.DungeonEncounterID), r]));
const byName = new Map(encounters.map((r) => [flat(r.Name_lang), r]));
const rows = [];
for (const boss of bosses) {
  const byId = boss.ids.map((id) => byDE.get(id)).find(Boolean);
  const row = byId ?? byName.get(flat(boss.name));
  if (!row || !String(row.Description_lang ?? "").trim()) continue;
  const guideInstance = instName.get(row.JournalInstanceID) ?? "?";
  const sameInstance = flat(guideInstance) === flat(ours.get(boss.map) ?? "") || instMap.get(boss.map) === guideInstance;
  rows.push({ id: `${boss.map}:${boss.key}`, name: boss.name, ours: ours.get(boss.map), by: byId ? "id" : "name", guideInstance, sameInstance });
}
const bad = rows.filter((r) => r.by === "name" || !r.sameInstance);
console.log(`${rows.length} with guide text, ${bad.length} doubtful`);
for (const r of bad) console.log(`${r.id} | ours: ${r.ours} | guide: ${r.guideInstance} | by ${r.by}`);
if (process.argv[2]) await writeFile(process.argv[2], JSON.stringify(bad.map((r) => r.id)));
