// A minted page later found in the world database: its texts, takes, reports and contributions
// move to the real page, and the minted row stays behind as an alias so a pack that shipped it
// still plays. Audio files are not renamed: a take keeps the file it was cut to.

import { normaliseText } from "./text.mjs";

const norm = (t) => normaliseText(t).trim();

export function findAbsorptions(minted, extracted) {
  const candidates = new Map();
  for (const page of minted) {
    const hits = new Set();
    for (const [lang, text] of Object.entries(page.texts)) {
      for (const real of extracted) if (real.texts[lang] !== undefined && norm(real.texts[lang]) === norm(text)) hits.add(real.lineId);
    }
    if (hits.size === 1) candidates.set(page.lineId, [...hits][0]);
  }
  const claims = new Map();
  for (const to of candidates.values()) claims.set(to, (claims.get(to) ?? 0) + 1);
  return [...candidates].filter(([, to]) => claims.get(to) === 1).map(([from, to]) => ({ from, to }));
}

/** Moves everything keyed on `from` to `to`, in the caller's transaction. */
export async function absorb(client, { from, to }) {
  // A language the real page already has keeps its own text; the minted one's becomes history.
  await client.query(
    `update "book_line" m set "isCurrent" = false
      where m."lineId" = $1 and exists (select 1 from "book_line" r where r."lineId" = $2 and r."lang" = m."lang" and r."isCurrent")`,
    [from, to],
  );
  await client.query(
    `update "book_line" m
        set "lineId" = $2,
            "version" = m."version" + coalesce((select max(r."version") from "book_line" r where r."lineId" = $2 and r."lang" = m."lang"), 0)
      where m."lineId" = $1`,
    [from, to],
  );
  for (const table of ["take", "report", "recording"]) {
    await client.query(`update "${table}" set "lineId" = $2 where "lineId" = $1 and "source" = 'books'`, [from, to]);
  }
  // Both pages may have had a current take in one language; the newer stays current.
  await client.query(
    `update "take" set "isCurrent" = false
      where "lineId" = $1 and "source" = 'books' and "isCurrent"
        and "id" <> (select max(t."id") from "take" t
                      where t."lineId" = $1 and t."source" = 'books' and t."isCurrent" and t."lang" = "take"."lang")`,
    [to],
  );
  await client.query(`update "contribution" set "matchLineId" = $2 where "matchLineId" = $1`, [from, to]);
  await client.query(`update "book_page" set "aliasOf" = $2 where "lineId" = $1`, [from, to]);
}
