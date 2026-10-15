/**
 * How many rows wait in each tab of /contributions, for the counts on the tabs themselves.
 *
 * Counted as the tab's link lands: new rows, under the default client filter, before any stage
 * or search. A Quests count is both its views, Contributions and Corrections together.
 */
import "server-only";

import { clientFilterOf, clientOf, matchesClient } from "./client";
import { lineStates, tabOf } from "./known";
import type { Section } from "./query";
import { listContributions } from "./store";

export type PendingCounts = {
  sections: Record<Section, number>;
  quests: { contributions: number; corrections: number };
};

export async function pendingCounts(lang: string): Promise<PendingCounts> {
  const client = clientFilterOf(undefined);
  const listed = (await listContributions("new", lang)).filter((row) =>
    matchesClient(clientOf(row.build).family, client),
  );
  const states = await lineStates(listed);
  const counts: PendingCounts = {
    sections: { quests: 0, books: 0, zones: 0 },
    quests: { contributions: 0, corrections: 0 },
  };
  listed.forEach((row, index) => {
    const tab = tabOf(row.status, states[index]);
    if (tab === null) return;
    if (tab === "corrections" && row.source !== "quests") return;
    counts.sections[row.source]++;
    if (row.source === "quests") counts.quests[tab]++;
  });
  return counts;
}
