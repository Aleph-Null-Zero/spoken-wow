/**
 * An admin's answer for one sex of an NPC drawn as both (migration 0072), and splitting or
 * unsplitting it. /npcs posts here.
 *
 *   { npcKind, npcId, action: "split" }    a sex each, the NPC's own answer for its own sex and
 *                                           the other sex's default flavor, both to be confirmed
 *   { npcKind, npcId, action: "unsplit" }  every line back to the NPC's one voice
 *   { npcKind, npcId, sex, race, flavor, doubtful }  a moderator's answer for that sex
 *
 * Admin only, for api/npcs's reason: the answer voices every line the NPC speaks, in every
 * language. Refused where the roster has no place for it, as api/npcs refuses.
 */
import { recordActivity } from "@/lib/activity/store";
import { requireAdmin } from "@/lib/generation/authz";
import { INT32_MAX, isSex, type Sex } from "@/lib/npc/npc";
import {
  getResolution, getSexes, resolutionKey, unsplit, upsertSex, type NpcRowKind,
} from "@/lib/npc/store";
import { defaultFlavorFor } from "@/lib/quests/catalogue";
import { loadRoster } from "@/lib/voices/roster-store";

export const dynamic = "force-dynamic";

const GENDER: Record<Sex, "male" | "female"> = { 2: "male", 3: "female" };

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
    if (!npc.race) return Response.json({ error: "answer who the NPC is first" }, { status: 400 });
    for (const sex of [2, 3] as const) {
      const own = npc.gender === GENDER[sex];
      await upsertSex({
        npcKind, npcId, sex, race: npc.race,
        flavor: own ? npc.flavor : await defaultFlavorFor(npc.race, GENDER[sex]),
        provenance: "moderator", confirmed: true, doubtful: !own, note: null, resolvedBy: session.user.id,
      });
    }
    await recordActivity({ kind: "npc.split", lang, actorId: session.user.id, subject, detail: { npcName: npc.npcName } });
    return Response.json({ sexes: await getSexes(npcKind, npcId) });
  }

  const sex = Number(body.sex);
  if (!isSex(sex)) return Response.json({ error: "sex is 2 or 3" }, { status: 400 });
  const text = (value: unknown, max: number) =>
    typeof value === "string" && value.trim() ? value.trim().slice(0, max) : null;
  const race = text(body.race, 64);
  const flavor = text(body.flavor, 64);
  if (!race) return Response.json({ error: "a sex needs a type" }, { status: 400 });
  const refusal = (await loadRoster()).isAnswer(race, GENDER[sex], flavor);
  if (refusal) return Response.json({ error: refusal }, { status: 400 });

  const row = await upsertSex({
    npcKind, npcId, sex, race, flavor, provenance: "moderator", confirmed: true,
    doubtful: body.doubtful === true, note: null, resolvedBy: session.user.id,
  });
  await recordActivity({
    kind: "npc.resolved", lang, actorId: session.user.id, subject,
    detail: { npcName: npc.npcName, sex, race: row.race, gender: row.gender, flavor: row.flavor, doubtful: row.doubtful },
  });
  return Response.json({ sexes: await getSexes(npcKind, npcId) });
}
