/**
 * Changing a report's status from the browser.
 *
 * One request per report: each row keeps its own resolvedAt and resolvedBy, and a report that
 * fails to resolve stays open rather than taking the rest of its line down with it.
 */
import type { Report, Status } from "./reports";

/** The report as it now stands, or null when the change did not go through. */
export async function resolveReport(id: number, status: Status): Promise<Report | null> {
  const response = await fetch("/api/reports/resolve", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ id, status }),
  }).catch(() => null);
  if (!response?.ok) return null;
  const body = (await response.json().catch(() => null)) as { report?: Report } | null;
  return body?.report ?? null;
}
