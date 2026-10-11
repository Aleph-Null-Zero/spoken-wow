/**
 * Splitting an NPC by sex when a player sees it drawn as the sex its voice is not. The extract
 * splits the NPCs the world database knows; a contribution splits the rest. The NPC's own answer
 * becomes its sex's, and the sex seen is answered from the client's report.
 */
import { defaultFlavorFor } from "@/lib/quests/catalogue";

import { voiceFromDisplays } from "./display-voices";
import { raceForModel } from "./models";
import type { Observed } from "./resolve";
import { isSex, SEX_GENDER, sexOf, type Sex } from "./npc";
import { getSexes, upsertSex, type NpcResolution, type NpcSexAnswer } from "./store";

type SexInput = Omit<NpcSexAnswer, "gender" | "updatedAt">;

/** The sex the player saw, answered from what the client reported, for an NPC of `race`. */
async function answerFor(observed: Observed, sex: Sex, race: string): Promise<SexInput> {
  const gender = SEX_GENDER[sex];
  const body = raceForModel(observed.modelFileId);
  const seen = body?.gender === gender ? body : null;
  const displays = seen && observed.displayIds.length
    ? await voiceFromDisplays(observed.displayIds, observed.modelFileId)
    : null;
  const exact = displays?.exact && displays.voice.gender === gender ? displays.voice : null;
  const offered = displays && !displays.exact && displays.gender === gender ? displays.flavors : [];
  const answered = exact?.race ?? seen?.race ?? race;
  const fallback = exact ? null : await defaultFlavorFor(answered, gender);
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
 * Split `npc`, a man or a woman, into a sex each: `other` for the sex it is not, and its own
 * answer, as `own` restamps it, for the sex it is -- unless that sex is answered already. Every
 * split goes through here, so a split NPC always has its own sex's row.
 */
export async function splitNpc(
  npc: NpcResolution,
  other: SexInput,
  own: Partial<SexInput> = {},
  sexes?: NpcSexAnswer[],
): Promise<void> {
  const sex = sexOf(npc.gender);
  if (sex === null || !npc.race || other.sex === sex) throw new Error(`splitNpc: ${npc.npcKind}/${npc.npcId} is not the other sex`);
  if (!(sexes ?? (await getSexes(npc.npcKind, npc.npcId))).some((row) => row.sex === sex)) {
    await upsertSex({
      npcKind: npc.npcKind,
      npcId: npc.npcId,
      sex,
      race: npc.race,
      flavor: npc.flavor,
      provenance: npc.provenance === "none" ? "client" : npc.provenance,
      confirmed: npc.confirmed,
      doubtful: npc.doubtful,
      note: null,
      resolvedBy: npc.resolvedBy,
      ...own,
    });
  }
  await upsertSex(other);
}

/**
 * Split `npc` if the player saw it drawn as the sex its voice is not, or answer the sex seen on
 * an NPC split already. Returns whether the NPC is split; false where the player saw the sex it
 * is voiced in, which a split NPC has answered already.
 */
export async function splitBySex(observed: Observed, npc: NpcResolution | null): Promise<boolean> {
  const sex = observed.sex;
  if (observed.npcKind !== "creature" || observed.npcId === null || !isSex(sex) || !npc?.race) return false;
  const own = sexOf(npc.gender);
  if (own === null || own === sex || npc.provenance === "none") return false;
  const sexes = await getSexes("creature", observed.npcId);
  if (!sexes.some((row) => row.sex === sex)) await splitNpc(npc, await answerFor(observed, sex, npc.race), {}, sexes);
  return true;
}
