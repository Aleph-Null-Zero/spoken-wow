/**
 * An admin's answer for one sex of a split NPC, and splitting or unsplitting it.
 *
 *   { npcKind, npcId, action: "split" }    a sex each: the NPC's own answer for its sex, the
 *                                           other sex's default flavor marked doubtful
 *   { npcKind, npcId, action: "unsplit" }  every line back to the NPC's one voice
 *   { npcKind, npcId, sex, race, flavor, doubtful }  a moderator's answer for that sex
 *
 * Admin only: the answer voices every line the NPC speaks, in every language.
 */
import { recordActivity } from "@/lib/activity/store";
import { requireAdmin } from "@/lib/generation/authz";
import { INT32_MAX, isSex, oppositeSex, SEX_GENDER, sexOf } from "@/lib/npc/npc";
import { splitNpc } from "@/lib/npc/split";
import {
  getResolution, getSexes, resolutionKey, unsplit, upsertSex, type NpcRowKind,
} from "@/lib/npc/store";
import { defaultFlavorFor } from "@/lib/quests/catalogue";
import { loadRoster } from "@/lib/voices/roster-store";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const { lang, session, denied } = await requireAdmin(request);
  if (denied) return denied;

  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  // Only a creature is drawn as a man or a woman.
  const npcKind: NpcRowKind | null = body.npcKind === "creature" ? "creature" : null;
  const npcId = Number(body.npcId);
  if (!npcKind) return Response.json({ error: "only a creature can be split by sex" }, { status: 400 });
  if (!Number.isInteger(npcId) || npcId < 0 || npcId > INT32_MAX) {
    return Response.json({ error: "unknown npc" }, { status: 400 });
  }
  const npc = await getResolution(npcKind, npcId);
  if (!npc) return Response.json({ error: "unknown npc" }, { status: 404 });

  const subject = resolutionKey(npcKind, npcId);
  if (body.action === "unsplit") {
    await unsplit(npcKind, npcId);
    await recordActivity({ kind: "npc.unsplit", lang, actorId: session.user.id, subject, detail: { npcName: npc.npcName } });
    return Response.json({ sexes: [] });
  }

  if (body.action === "split") {
    // Only a man or a woman splits: a beast's or a generic creature's type has no gender, and
    // the roster no voice for either sex of it.
    const own = sexOf(npc.gender);
    if (!npc.race || own === null) return Response.json({ error: "answer the NPC as a man or a woman first" }, { status: 400 });
    const other = oppositeSex(own);
    await splitNpc(npc, {
      npcKind, npcId, sex: other, race: npc.race, flavor: await defaultFlavorFor(npc.race, SEX_GENDER[other]),
      provenance: "moderator", confirmed: true, doubtful: true, note: null, resolvedBy: session.user.id,
    }, { provenance: "moderator", confirmed: true, doubtful: false, resolvedBy: session.user.id });
    await recordActivity({ kind: "npc.split", lang, actorId: session.user.id, subject, detail: { npcName: npc.npcName } });
    return Response.json({ sexes: await getSexes(npcKind, npcId) });
  }

  const sex = Number(body.sex);
  if (!isSex(sex)) return Response.json({ error: "sex is 2 or 3" }, { status: 400 });
  // An answer for one sex of an NPC that is not split would leave it half split, the other
  // sex voiceless: the split comes first, and writes both.
  const sexes = await getSexes(npcKind, npcId);
  if (!sexes.length) return Response.json({ error: "split the NPC first" }, { status: 400 });
  const text = (value: unknown, max: number) =>
    typeof value === "string" && value.trim() ? value.trim().slice(0, max) : null;
  const race = text(body.race, 64);
  const flavor = text(body.flavor, 64);
  if (!race) return Response.json({ error: "a sex needs a type" }, { status: 400 });
  const refusal = (await loadRoster()).isAnswer(race, SEX_GENDER[sex], flavor);
  if (refusal) return Response.json({ error: refusal }, { status: 400 });

  const row = await upsertSex({
    npcKind, npcId, sex, race, flavor, provenance: "moderator", confirmed: true,
    doubtful: body.doubtful === true, note: null, resolvedBy: session.user.id,
  });
  await recordActivity({
    kind: "npc.resolved", lang, actorId: session.user.id, subject,
    detail: { npcName: npc.npcName, sex, race: row.race, gender: row.gender, flavor: row.flavor, doubtful: row.doubtful },
  });
  return Response.json({ sexes: sexes.map((answer) => (answer.sex === sex ? row : answer)) });
}
