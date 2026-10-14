// The structure half of a page: its row in book_page, as the extract places it.

/**
 * Inserts an extracted page's book_page row, or moves it where the extract now places it.
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
                 "pageNumber" = excluded."pageNumber", "ownerKind" = excluded."ownerKind",
                 "ownerIds" = excluded."ownerIds", "material" = excluded."material"`,
    values: [
      entry.lineId, entry.pageId, String(entry.bookId), entry.pageNumber,
      entry.ownerKind, entry.ownerIds, entry.material,
    ],
  };
}
