/**
 * The sorting queue at /reports/sort: one section's open reports as lines to answer, one at
 * a time.
 *
 * Node-free, like query.ts: the queue is walked in the browser.
 */
import { groupByLine, type ReportGroup } from "./rows";
import type { Report } from "./reports";

const oldest = (group: ReportGroup) => Math.min(...group.reports.map((report) => Date.parse(report.createdAt)));

/**
 * A line is hidden while every open report on it is one this person skipped, so a new
 * report on a skipped line puts it back. The lines most people complained about come
 * first; between equals, the one whose reporter has waited longest.
 */
export function sortQueue(reports: Report[], skipped: ReadonlySet<number>): ReportGroup[] {
  const open = reports.filter((report) => report.status === "open");
  return groupByLine(open)
    .filter((group) => group.reports.some((report) => !skipped.has(report.id)))
    .sort((a, b) => b.reports.length - a.reports.length || oldest(a) - oldest(b));
}

/** What a section's tile on the picker says: lines left to sort, and lines put aside. */
export function queueCounts(
  reports: Report[],
  skipped: ReadonlySet<number>,
): { left: number; skipped: number } {
  const lines = groupByLine(reports.filter((report) => report.status === "open"));
  const left = sortQueue(reports, skipped).length;
  return { left, skipped: lines.length - left };
}
