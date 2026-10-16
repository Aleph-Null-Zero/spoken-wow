/**
 * One more NPC speaking a line, added by hand from the explorer: a quest two givers offer, a
 * greeting several guards share. Each NPC is voiced in its own voice (catalogue.ts), so adding
 * one whose voice differs gives the line a voice's line of its own, missing until generated.
 *
 * Admin only, as an NPC's answer is (api/npcs): who speaks a line holds in every language, and
 * it picks which voices the line is generated in.
 *
 * GET looks an NPC up for the dialog: its answer, and the roster to answer it with when it has
 * none. POST adds it; an NPC nobody has answered yet is answered in the same request, the way
 * /npcs would. DELETE takes back a speaker added here, and only those (speakers.ts).
 */
import { recordActivity } from "@/lib/activity/store";
import { requireAdmin } from "@/lib/generation/authz";
import { INT32_MAX } from "@/lib/npc/npc";
import { getResolution, NPC_ROW_KINDS, resolutionKey, upsertResolution, type NpcRowKind } from "@/lib/npc/store";
import { baseLineId, momentOf } from "@/lib/contributions/naming";
import { addSpeaker, removeSpeaker } from "@/lib/quests/speakers";
import { loadRoster } from "@/lib/voices/roster-store";

export const dynamic = "force-dynamic";

function npcOf(kind: unknown, id: unknown): { npcType: NpcRowKind; npcId: number } | null {
  const npcType = (NPC_ROW_KINDS as readonly string[]).includes(kind as string) ? (kind as NpcRowKind) : null;
  // `< 0`, not `<= 0`, and bounded, as api/npcs is: id 0 is a real NPC.
  const npcId = typeof id === "string" && /^\d+$/.test(id) ? Number(id) : id;
  if (!npcType || typeof npcId !== "number" || !Number.isInteger(npcId) || npcId < 0 || npcId > INT32_MAX) return null;
  return { npcType, npcId };
}

const text = (value: unknown, max: number) =>
  typeof value === "string" && value.trim() ? value.trim().slice(0, max) : null;

export async function GET(request: Request) {
  const { denied } = await requireAdmin(request);
  if (denied) return denied;

  const params = new URL(request.url).searchParams;
  const npc = npcOf(params.get("npcType"), params.get("npcId"));
  if (!npc) return Response.json({ error: "unknown npc" }, { status: 400 });

  const [resolution, roster] = await Promise.all([getResolution(npc.npcType, npc.npcId), loadRoster()]);
  return Response.json({
    npc: resolution && {
      npcName: resolution.npcName,
      race: resolution.race,
      gender: resolution.gender,
      flavor: resolution.flavor,
      voice: roster.voiceFor(resolution.race, resolution.gender, resolution.flavor),
    },
    roster: roster.data,
  });
}

export async function POST(request: Request) {
  const { lang, session, denied } = await requireAdmin(request);
  if (denied) return denied;

  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const lineId = typeof body.lineId === "string" && body.lineId ? baseLineId(body.lineId) : null;
  if (!lineId) return Response.json({ error: "unknown line" }, { status: 404 });
  const npc = npcOf(body.npcType, body.npcId);
  if (!npc) return Response.json({ error: "unknown npc" }, { status: 400 });

  // An NPC nobody has answered is answered here, as /npcs would: the speaker is written with its
  // voice. One already answered keeps its answer; changing it is /npcs's job.
  const existing = await getResolution(npc.npcType, npc.npcId);
  if (!existing?.race && "race" in body) {
    const npcName = text(body.npcName, 200) ?? existing?.npcName ?? null;
    if (!npcName) return Response.json({ error: "name the NPC" }, { status: 400 });
    const race = text(body.race, 64);
    const gender = text(body.gender, 16);
    const flavor = text(body.flavor, 64);
    const refusal = (await loadRoster()).isAnswer(race, gender, flavor);
    if (refusal) return Response.json({ error: refusal }, { status: 400 });
    const row = await upsertResolution({
      npcKind: npc.npcType,
      npcId: npc.npcId,
      npcName,
      race,
      gender,
      flavor,
      provenance: "moderator",
      confirmed: true,
      doubtful: false,
      modelFileId: existing?.modelFileId ?? null,
      sex: existing?.sex ?? null,
      creatureType: existing?.creatureType ?? null,
      build: existing?.build ?? null,
      note: existing?.note ?? null,
      resolvedBy: session.user.id,
    });
    await recordActivity({
      kind: "npc.resolved",
      lang,
      actorId: session.user.id,
      subject: resolutionKey(npc.npcType, npc.npcId),
      detail: { npcName: row.npcName, race: row.race, gender: row.gender, flavor: row.flavor, doubtful: false },
    });
  }

  const outcome = await addSpeaker({ lineId, ...npc, addedBy: session.user.id });
  if (!outcome.ok) {
    const status = outcome.reason === "unknown-line" ? 404 : outcome.reason === "spoken" ? 409 : 400;
    return Response.json({ error: outcome.message, reason: outcome.reason }, { status });
  }

  const npcName = (await getResolution(npc.npcType, npc.npcId))?.npcName ?? null;
  await recordActivity({
    kind: "npc.speaker_added",
    lang,
    actorId: session.user.id,
    subject: momentOf(lineId),
    detail: { npcName, npcType: npc.npcType, npcId: npc.npcId },
  });
  return Response.json({ added: true });
}

export async function DELETE(request: Request) {
  const { lang, session, denied } = await requireAdmin(request);
  if (denied) return denied;

  const params = new URL(request.url).searchParams;
  const lineId = params.get("lineId") ? baseLineId(params.get("lineId")!) : null;
  if (!lineId) return Response.json({ error: "unknown line" }, { status: 404 });
  const npc = npcOf(params.get("npcType"), params.get("npcId"));
  if (!npc) return Response.json({ error: "unknown npc" }, { status: 400 });

  const outcome = await removeSpeaker({ lineId, ...npc });
  if (!outcome.ok) return Response.json({ error: outcome.message, reason: outcome.reason }, { status: 409 });

  // 200 with nothing removed, as the ignore route does: the speaker the caller wanted gone is gone.
  if (outcome.removed > 0) {
    const npcName = (await getResolution(npc.npcType, npc.npcId))?.npcName ?? null;
    await recordActivity({
      kind: "npc.speaker_removed",
      lang,
      actorId: session.user.id,
      subject: momentOf(lineId),
      detail: { npcName, npcType: npc.npcType, npcId: npc.npcId },
    });
  }
  return Response.json({ removed: outcome.removed });
}
