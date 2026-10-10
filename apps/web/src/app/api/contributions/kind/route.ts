/**
 * A moderator's answer to "which NPC is this?", for a contribution whose envelope named its NPC
 * by id alone.
 *
 * Recorded on the contribution, not in the npc table: the answers there are about NPCs and are
 * not wrong, only ambiguous for this row, which could mean either kind. After this every reader
 * (the triage page, accept, the export) reads the row as if its envelope had carried the kind.
 * Refused for a row whose envelope already carried one -- the client's own observation stands.
 *
 * Whoever may edit the language the row was sent in, as for accepting it (../resolve): the
 * answer is about this one row, and the person triaging it is who can give it. Unlike
 * ../npc, which says something about the NPC in every language and stays English regenerate.
 */
import { requireCapability } from "@/lib/generation/authz";
import { contributionLocale, setContributionNpcKind } from "@/lib/contributions/store";
import { BASE_LANG, isLang } from "@/lib/lang";
import { NPC_KINDS, type NpcKind } from "@/lib/npc/npc";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const body = (await request.json().catch(() => ({}))) as { id?: unknown; npcKind?: unknown };

  const id = Number(body.id);
  if (!Number.isInteger(id) || id <= 0 || id > 2147483647) {
    return Response.json({ error: "unknown contribution" }, { status: 404 });
  }
  if (!(NPC_KINDS as readonly unknown[]).includes(body.npcKind)) {
    return Response.json({ error: "unknown kind" }, { status: 400 });
  }

  // Permission before existence, as ../resolve does, so a member learns nothing about which
  // ids exist; an unknown id is checked against English, which it then fails or 404s.
  const locale = await contributionLocale(id);
  const { session, denied } = await requireCapability("edit", isLang(locale) ? locale : BASE_LANG);
  if (denied) return denied;

  const recorded = await setContributionNpcKind(id, body.npcKind as NpcKind, session.user.id);
  if (!recorded) {
    return Response.json({ error: "no such contribution, or its envelope already names the kind" }, { status: 409 });
  }
  return Response.json({ ok: true });
}
