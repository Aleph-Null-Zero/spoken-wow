/**
 * Who a report about an NPC, rather than about one of its lines, is about.
 *
 * A gossip NPC with a dozen takes is reported by its address alone when the reporter never
 * picks a take, so the table has no line to show beside the report. What it can show is the
 * speaker: name, what picked the voice, the voice, and how many lines they say.
 *
 * Asked once per page by the server, like stale.ts: a corpus scan per row would be one per
 * report.
 */
import type { Corpus } from "@/lib/corpus";
import { BASE_LANG, type Lang } from "@/lib/lang";
import { npcHref, npcPageHref } from "@/lib/links";
import { corpus as questCorpus } from "@/lib/quests/catalogue";
import type { LineDetail } from "@/lib/reports/detail";
import { parseTarget, resolveTarget } from "@/lib/reports/target";

/** What LineHeading draws, for a speaker rather than a line. */
export type NpcDetail = Pick<LineDetail, "heading" | "headingHref" | "speaker" | "speakerIsHeading" | "aside">;

/** Each NPC or object address among `targets`, by address. Addresses that resolve to nothing are left out. */
export async function npcDetails(
  targets: string[],
  lang: Lang = BASE_LANG,
  corpus?: Corpus,
): Promise<Record<string, NpcDetail>> {
  const wanted = [...new Set(targets)].flatMap((address) => {
    const target = parseTarget(address.split("/"));
    return target && target.kind !== "quest" ? [{ address, target }] : [];
  });
  if (wanted.length === 0) return {};

  const lines = corpus ?? (await questCorpus(lang));
  const details: Record<string, NpcDetail> = {};
  for (const { address, target } of wanted) {
    const spoken = await resolveTarget(target, lines);
    const [first] = spoken;
    if (!first) continue;

    // Race, gender and flavor beside the voice, as a line's heading has them: the complaint
    // about an NPC is most often about that triple.
    const who = [first.race, first.gender, first.flavor].filter(Boolean).join(" ");
    const count = new Set(spoken.map((line) => line.lineId)).size;
    details[address] = {
      heading: first.npcName,
      headingHref: null,
      speaker: {
        name: first.npcName,
        page: npcPageHref(first.npcId),
        search: npcHref({ npcId: first.npcId, npcType: first.npcType, gossip: first.source === "gossip" }),
      },
      speakerIsHeading: true,
      aside: [who, first.voice, count === 1 ? "1 line" : `${count} lines`].filter(Boolean).join(" · "),
    };
  }
  return details;
}
