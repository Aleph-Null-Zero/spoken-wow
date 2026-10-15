/**
 * Which of a page of reported lines have audio made from text that has since changed.
 *
 * Asked once per page by the server rather than once per row by the table: a row's flag is
 * one boolean, and the section's search, which answers it along with everything else about
 * the line, costs a corpus scan and a dozen queries a time.
 */
import { audioRelPath } from "@/lib/audio";
import { catalogue as bookCatalogue } from "@/lib/books/catalogue";
import { db } from "@/lib/db";
import { BASE_LANG, type Lang } from "@/lib/lang";
import { corpus } from "@/lib/quests/catalogue";
import { staleFiles } from "@/lib/quests/staleness";
import type { Source } from "@/lib/sections";
import { catalogue as zoneCatalogue } from "@/lib/zones/catalogue";

export async function staleLineIds(
  source: Source,
  lineIds: string[],
  lang: Lang = BASE_LANG,
): Promise<string[]> {
  if (lineIds.length === 0) return [];
  return source === "quests" ? staleQuestLines(lineIds, lang) : staleTextLines(source, lineIds, lang);
}

/** By file, which is what a quests take is of: the first line carrying each id, as the search's. */
async function staleQuestLines(lineIds: string[], lang: Lang): Promise<string[]> {
  const wanted = new Set(lineIds);
  const fileOf = new Map<string, string>();
  for (const line of (await corpus(lang)).lines) {
    if (wanted.has(line.lineId) && !fileOf.has(line.lineId)) fileOf.set(line.lineId, audioRelPath(line));
  }
  const stale = await staleFiles([...new Set(fileOf.values())], lang);
  return [...fileOf].filter(([, file]) => stale.has(file)).map(([lineId]) => lineId);
}

/** Zones and books: the live take's hash against the catalogue's, as their searches compare them. */
async function staleTextLines(source: "zones" | "books", lineIds: string[], lang: Lang): Promise<string[]> {
  const [entries, { rows }] = await Promise.all([
    source === "zones" ? zoneCatalogue(lang) : bookCatalogue(lang),
    db().query<{ lineId: string; spokenHash: string | null }>(
      `select "lineId", "spokenHash" from "take"
        where "source" = $1 and "lang" = $2 and "isCurrent" and "lineId" = any($3::text[])`,
      [source, lang, lineIds],
    ),
  ]);
  const hashOf = new Map<string, string>(entries.map((entry) => [entry.id, entry.hash]));
  // A null hash counts as changed here, unlike quests, because the zones and books searches
  // count it so (their loadContext reads it as "").
  return rows
    .filter((row) => hashOf.has(row.lineId) && hashOf.get(row.lineId) !== (row.spokenHash ?? ""))
    .map((row) => row.lineId);
}
