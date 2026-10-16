// The structure half of a page: its row in book_page, as the extract places it.

/**
 * Inserts an extracted page's book_page row, or moves it where the extract now places it.
 * Owners an accepted contribution added (accept.ts addOwner) are kept after the extract's own,
 * unless the extract now names owners of the other kind.
 *
 * @param entry an extract entry: lineId, pageId, bookId, pageNumber, ownerKind, ownerIds, material
 */
export function bookPageUpsert(entry) {
  return {
    text: `insert into "book_page"
             ("lineId", "pageTextId", "bookId", "pageNumber", "ownerKind", "ownerIds", "material")
           values ($1, $2, $3, $4, $5, $6, $7)
           on conflict ("lineId") do update
             set "pageTextId" = excluded."pageTextId", "bookId" = excluded."bookId",
                 "pageNumber" = excluded."pageNumber",
                 "ownerKind" = coalesce(excluded."ownerKind", "book_page"."ownerKind"),
                 "ownerIds" = case
                   when excluded."ownerKind" is not null and excluded."ownerKind" <> "book_page"."ownerKind"
                     or "book_page"."ownerIds" is null then excluded."ownerIds"
                   else coalesce(excluded."ownerIds", '{}') || array(
                     select o from unnest("book_page"."ownerIds") with ordinality as k (o, i)
                      where not (o = any(coalesce(excluded."ownerIds", '{}'))) order by i)
                 end,
                 "material" = excluded."material"`,
    values: [
      entry.lineId, entry.pageId, String(entry.bookId), entry.pageNumber,
      entry.ownerKind, entry.ownerIds, entry.material,
    ],
  };
}
