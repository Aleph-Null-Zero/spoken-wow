# AGENTS.md: books

The root `AGENTS.md` applies. This file covers only the books section. `docs/books/README.md`
is the detailed reference.

## Players see Readables; the code says books

The module is Readables wherever a player reads its name, and its folder is `Spoken_Readables`.
The internal names stay books (the README lists them). The ids, saved variables and pack folder
among them are frozen: renaming one loses players' settings or re-ships a pack.

## The table is the corpus; the Lua is an export of it

`book_page` and `book_line` are what the site reads and what an editor changes.
`addons/Spoken_Readables/Data/Books.lua` is generated from them and committed, so the addon builds
on a clone with no Postgres. Nothing on the site may read that file, because it shows the last
export rather than the table. Building the sound pack does need the database (`books-lookup` reads `DATABASE_URL`).

## A page exists in any language

`book_page` holds a page's structure, once: its book, its number and what opens it. `book_line`
holds each language's words for it, so a page may exist in Spanish and nowhere else. Never read
a page's place from `book_line`.

A books contribution names no page, so `apps/web/src/lib/contributions/book-match.ts` finds it:
by the item or object it was read from, then the same words in any language, then the title and
page number. Two candidates are never guessed between; a moderator picks. A page nothing in the
corpus has is minted on accept as `b:n{uuid}`, in a minted `n{uuid}` book when it starts one,
and the import folds it into the real page if the world database turns out to have it
(`pipelines/books/tools/lib/absorb.mjs`).

## The extract must respect `patch`

`gameobject_template` and `item_template` hold one row per content patch, and the server serves
`max(patch)` at or below its own (`pipelines/books/tools/lib/world.mjs`). A query without that
window returns an object under every name it ever had. `page_text` has no patch column.

## The checksum constants are load-bearing

`pageChecksum` in `pipelines/books/tools/lib/naming.mjs` is recomputed by the addon in Lua
(`addons/Spoken_Readables/Checksum.lua`) over UTF-8 bytes, using only multiply, add and modulo.
Changing `CHECKSUM_MODULUS` or `CHECKSUM_FACTOR` means re-exporting the data module, whose lookup
tables are keyed on the result. A title and a page number do not identify a page: two different
objects are both named "A Dusty Tome".

## One page is one entry

A page belongs to exactly one book. Where two chains reach the same page, the chain with the
lower first page keeps it. Chains are walked in sorted order, so the choice comes from the data
and not from MySQL's row order.

## Mail is not a book

`ItemTextFrame` also shows mail. A letter with a creator, or the frame opened under `MailFrame`,
is skipped. Otherwise Spoken would read the player's own post aloud.

## Packs

`make books-full-release` chains sync, pull-live and package-audio, then asks once before
uploading. `package-audio` runs `check-synced`, `sounds` and `lookup` itself.
`addons/SpokenBooksAudio/Data/Sounds.lua` is regenerated locally and committed. The site no
longer writes it.
