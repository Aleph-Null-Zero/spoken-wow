/**
 * Changing many contributions' status in one request -- the moderator page's bulk buttons.
 *
 * The same verb as api/contributions/resolve, row for row, with the same refusals; one round
 * trip instead of one per row, and the rows resolved side by side on this end
 * (resolveContributions says how that stays safe).
 *
 * Permission is per row, by the language it was sent in, as the single route has it. A row the
 * viewer may not edit is answered the same as one that is not there, so a batch learns no more
 * about which ids exist than the single route does.
 *
 * Accepting books rows in bulk takes only those the matcher places in a page that exists or
 * will (bulkAcceptable): an ambiguous, known or new-book row is left as it is and answered with
 * why, one corpus read for the lot.
 */
import { requireCapability } from "@/lib/generation/authz";
import { booksContributions, contributionLocales } from "@/lib/contributions/store";
import { BASE_LANG, isLang, type Lang } from "@/lib/lang";
import { isStatus, RESOLVE_MANY_MAX, type ResolveManyResult } from "@/lib/contributions/contributions";
import { bulkAcceptable, loadBookCorpus, matchBook } from "@/lib/contributions/book-match";
import { resolveContributions } from "@/lib/contributions/accept";

export const dynamic = "force-dynamic";

const UNKNOWN = "unknown contribution";

const SKIPPED: Record<string, string> = {
  ambiguous: "Several pages could be this one -- pick it first.",
  known: "The corpus already has these words for this page.",
  "new-book": "A new book is accepted one row at a time, so the title is checked first.",
};

export async function POST(request: Request) {
  const body = (await request.json().catch(() => ({}))) as { ids?: unknown; status?: unknown };

  if (!isStatus(body.status)) {
    return Response.json({ error: "unknown status" }, { status: 400 });
  }
  const ids = Array.isArray(body.ids) ? [...new Set(body.ids.map(Number))] : [];
  if (ids.length === 0 || ids.length > RESOLVE_MANY_MAX || !ids.every((id) => Number.isInteger(id) && id > 0)) {
    return Response.json({ error: `send 1 to ${RESOLVE_MANY_MAX} contribution ids` }, { status: 400 });
  }

  const locales = await contributionLocales(ids);
  const allowed = new Map<Lang, boolean>();
  let userId: string | null = null;
  for (const locale of new Set(locales.values())) {
    const lang = isLang(locale) ? locale : BASE_LANG;
    if (allowed.has(lang)) continue;
    const { session, denied } = await requireCapability("edit", lang);
    allowed.set(lang, !denied);
    if (session) userId = session.user.id;
  }
  // Nothing here the viewer may edit: answered as the single route answers it.
  if (userId === null) {
    const { denied } = await requireCapability("edit", BASE_LANG);
    if (denied) return denied;
    return Response.json({ results: Object.fromEntries(ids.map((id) => [id, { ok: false, error: UNKNOWN }])) });
  }

  let permitted = ids.filter((id) => {
    const locale = locales.get(id);
    return locale !== undefined && allowed.get(isLang(locale) ? locale : BASE_LANG);
  });
  const skipped = new Map<number, string>();
  if (body.status === "accepted" && permitted.length > 0) {
    const books = await booksContributions(permitted);
    if (books.length > 0) {
      const corpus = await loadBookCorpus();
      for (const row of books) {
        const match = matchBook(row, corpus);
        if (!bulkAcceptable(match)) skipped.set(row.id, SKIPPED[match.kind]);
      }
      permitted = permitted.filter((id) => !skipped.has(id));
    }
  }
  const outcomes = await resolveContributions(permitted, body.status, userId);

  const results: Record<number, ResolveManyResult> = {};
  for (const id of ids) {
    const outcome = outcomes.get(id);
    if (skipped.has(id)) {
      results[id] = { ok: false, error: skipped.get(id)! };
    } else if (!outcome || (!(outcome instanceof Error) && !outcome.ok && outcome.reason === "not-found")) {
      results[id] = { ok: false, error: UNKNOWN };
    } else if (outcome instanceof Error) {
      console.error(`resolving contribution ${id}`, outcome);
      results[id] = { ok: false, error: "That didn't go through -- try again." };
    } else if (!outcome.ok) {
      results[id] = { ok: false, error: outcome.message };
    } else {
      results[id] = { ok: true };
    }
  }
  return Response.json({ results });
}
