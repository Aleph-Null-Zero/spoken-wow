/**
 * One more NPC speaking a line, added by hand from the explorer: a quest two givers offer, a
 * greeting several guards share. Each NPC is voiced in its own voice (catalogue.ts), so adding
 * one whose voice differs gives the line a voice's line of its own, missing until generated.
 *
 * Admin only, as an NPC's answer is (api/npcs): who speaks a line holds in every language, and
 * it picks which voices the line is generated in.
 *
 * GET looks an NPC up for the dialog: its answer, and, while that gives it no voice, the roster
 * to answer it with, which the dialog saves through api/npcs first, since a speaker is written
 * with its voice.
 * POST adds it, or with `replaces` puts it in that speaker's place. DELETE takes a speaker off
 * while another still speaks the line.
 */
import { recordActivity } from "@/lib/activity/store";
import { requireAdmin } from "@/lib/generation/authz";
import { INT32_MAX } from "@/lib/npc/npc";
import { getResolution, NPC_ROW_KINDS, type NpcRowKind } from "@/lib/npc/store";
import { baseLineId, momentOf } from "@/lib/contributions/naming";
import type { Lang } from "@/lib/lang";
import { addSpeaker, removeSpeaker, replaceSpeaker } from "@/lib/quests/speakers";
import { loadRoster } from "@/lib/voices/roster-store";

export const dynamic = "force-dynamic";

function npcOf(kind: unknown, id: unknown): { npcType: NpcRowKind; npcId: number } | null {
  const npcType = (NPC_ROW_KINDS as readonly string[]).includes(kind as string) ? (kind as NpcRowKind) : null;
  // `< 0`, not `<= 0`, and bounded, as api/npcs is: id 0 is a real NPC.
  const npcId = typeof id === "string" && /^\d+$/.test(id) ? Number(id) : id;
  if (!npcType || typeof npcId !== "number" || !Number.isInteger(npcId) || npcId < 0 || npcId > INT32_MAX) return null;
  return { npcType, npcId };
}

/** The moment a request's line belongs to, from any of its ids: a voice's, a side's, the plain one. */
function momentFrom(lineId: unknown): string | null {
  return typeof lineId === "string" && lineId ? momentOf(baseLineId(lineId)) : null;
}

export async function GET(request: Request) {
  const { denied } = await requireAdmin(request);
  if (denied) return denied;

  const params = new URL(request.url).searchParams;
  const npc = npcOf(params.get("npcType"), params.get("npcId"));
  if (!npc) return Response.json({ error: "unknown npc" }, { status: 400 });

  const [resolution, roster] = await Promise.all([getResolution(npc.npcType, npc.npcId), loadRoster()]);
  const voice = resolution && roster.voiceFor(resolution.race, resolution.gender, resolution.flavor);
  return Response.json({
    npc: resolution && {
      npcName: resolution.npcName,
      race: resolution.race,
      gender: resolution.gender,
      flavor: resolution.flavor,
      voice,
    },
    roster: voice ? null : roster.data,
  });
}

export async function POST(request: Request) {
  const { lang, session, denied } = await requireAdmin(request);
  if (denied) return denied;

  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const moment = momentFrom(body.lineId);
  if (!moment) return Response.json({ error: "unknown line" }, { status: 404 });
  const npc = npcOf(body.npcType, body.npcId);
  if (!npc) return Response.json({ error: "unknown npc" }, { status: 400 });
  if (body.replaces !== undefined) return replace(moment, npc, body.replaces, lang, session.user.id);

  const outcome = await addSpeaker({ moment, ...npc, addedBy: session.user.id });
  if (!outcome.ok) {
    const status = outcome.reason === "unknown-line" ? 404 : outcome.reason === "spoken" ? 409 : 400;
    return Response.json({ error: outcome.message, reason: outcome.reason }, { status });
  }

  await recordActivity({
    kind: "npc.speaker_added",
    lang,
    actorId: session.user.id,
    subject: moment,
    detail: { npcName: outcome.speaker.npcName, ...npc },
  });
  return Response.json({ added: true });
}

export async function DELETE(request: Request) {
  const { lang, session, denied } = await requireAdmin(request);
  if (denied) return denied;

  const params = new URL(request.url).searchParams;
  const moment = momentFrom(params.get("lineId"));
  if (!moment) return Response.json({ error: "unknown line" }, { status: 404 });
  const npc = npcOf(params.get("npcType"), params.get("npcId"));
  if (!npc) return Response.json({ error: "unknown npc" }, { status: 400 });

  const outcome = await removeSpeaker({ moment, ...npc, removedBy: session.user.id });
  if (!outcome.ok) return Response.json({ error: outcome.message, reason: outcome.reason }, { status: 409 });

  // 200 with nothing removed, as the ignore route does: the speaker the caller wanted gone is gone.
  if (outcome.removed > 0) {
    await recordActivity({
      kind: "npc.speaker_removed",
      lang,
      actorId: session.user.id,
      subject: moment,
      detail: { npcName: outcome.npcName, ...npc },
    });
  }
  return Response.json({ removed: outcome.removed });
}

async function replace(
  moment: string,
  npc: { npcType: NpcRowKind; npcId: number },
  replaces: unknown,
  lang: Lang,
  actorId: string,
): Promise<Response> {
  const from = replaces && typeof replaces === "object"
    ? npcOf((replaces as Record<string, unknown>).npcType, (replaces as Record<string, unknown>).npcId)
    : null;
  if (!from) return Response.json({ error: "unknown npc to replace" }, { status: 400 });

  const outcome = await replaceSpeaker({ moment, from, to: npc, by: actorId });
  if (!outcome.ok) {
    const status = outcome.reason === "unknown-line" ? 404 : outcome.reason === "contributed" ? 409 : 400;
    return Response.json({ error: outcome.message, reason: outcome.reason }, { status });
  }

  await recordActivity({
    kind: "npc.speaker_replaced",
    lang,
    actorId,
    subject: moment,
    detail: { npcName: outcome.speaker.npcName, ...npc, fromName: outcome.npcName, fromType: from.npcType, fromId: from.npcId },
  });
  return Response.json({ replaced: true });
}
