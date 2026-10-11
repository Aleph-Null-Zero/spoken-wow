/**
 * Splitting an NPC by sex when a player sees it drawn as the sex its voice is not.
 *
 * One creature id can be a man or a woman (migration 0072). The extract splits every such NPC
 * the world database knows (tts_cli/npc_sexes.py); a contribution splits the ones it does not:
 * another client's data, a server's own creatures. The NPC's own answer becomes its sex's, and
 * the sex the player saw is answered as resolve.ts answers an NPC from the client: the
 * appearances drawn with the reported body, else that body's race and a default flavor.
 */
import { defaultFlavorFor } from "@/lib/quests/catalogue";

import { voiceFromDisplays } from "./display-voices";
import { raceForModel } from "./models";
import type { Observed } from "./resolve";
import { isSex, type Sex } from "./npc";
import { getSexes, upsertSex, type NpcResolution, type NpcSexAnswer } from "./store";

const GENDER: Record<Sex, "male" | "female"> = { 2: "male", 3: "female" };

/** The sex the player saw, answered from what the client reported, for an NPC of `race`. */
async function answerFor(observed: Observed, sex: Sex, race: string): Promise<Omit<NpcSexAnswer, "gender" | "updatedAt">> {
  const gender = GENDER[sex];
  const body = raceForModel(observed.modelFileId);
  const seen = body?.gender === gender ? body : null;
  const displays = seen && observed.displayIds.length
    ? await voiceFromDisplays(observed.displayIds, observed.modelFileId)
    : null;
  const exact = displays?.exact && displays.voice.gender === gender ? displays.voice : null;
  const offered = displays && !displays.exact && displays.gender === gender ? displays.flavors : [];
  const answered = exact?.race ?? seen?.race ?? race;
  const fallback = await defaultFlavorFor(answered, gender);
  return {
    npcKind: "creature",
    npcId: observed.npcId as number,
    sex,
    race: answered,
    flavor: exact ? exact.flavor : offered.length && !offered.includes(fallback ?? "") ? offered[0] : fallback,
    provenance: exact ? "display" : "client",
    confirmed: Boolean(exact),
    doubtful: false,
    note: null,
    resolvedBy: null,
  };
}

/**
 * Split `npc` if the player saw it drawn as the other sex, and answer the sex they saw where it
 * is split already. Returns the NPC's sexes, none for one that is not split.
 */
export async function splitBySex(observed: Observed, npc: NpcResolution | null): Promise<NpcSexAnswer[]> {
  const sex = observed.sex;
  if (observed.npcKind !== "creature" || observed.npcId === null || !isSex(sex) || !npc?.race) return [];
  const sexes = await getSexes("creature", observed.npcId);
  if (sexes.length) {
    if (sexes.some((row) => row.sex === sex)) return sexes;
    await upsertSex(await answerFor(observed, sex, npc.race));
    return getSexes("creature", observed.npcId);
  }

  const own = npc.gender === "male" ? 2 : npc.gender === "female" ? 3 : null;
  if (own === null || own === sex || npc.provenance === "none") return [];
  await upsertSex({
    npcKind: "creature",
    npcId: observed.npcId,
    sex: own,
    race: npc.race,
    flavor: npc.flavor,
    provenance: npc.provenance,
    confirmed: npc.confirmed,
    doubtful: npc.doubtful,
    note: null,
    resolvedBy: npc.resolvedBy,
  });
  await upsertSex(await answerFor(observed, sex, npc.race));
  return getSexes("creature", observed.npcId);
}
