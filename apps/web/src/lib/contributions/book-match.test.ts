import { describe, expect, it } from "vitest";

import { matchBook, type BookCorpus, type BookMatchInput } from "./book-match";

function page(lineId: string, bookId: string, pageNumber: number, texts: Record<string, string>, titles: Record<string, string>, owner?: [ "object" | "item", number ]) {
  return {
    lineId, bookId, pageNumber,
    ownerKind: owner?.[0] ?? null, ownerIds: owner ? [owner[1]] : [],
    texts: new Map(Object.entries(texts)), titles: new Map(Object.entries(titles)),
  };
}

const corpus: BookCorpus = {
  pages: [
    page("b:38", "38", 1, { enUS: "Stoutmantle --", esES: "Stoutmantle -- Qué descaro", esMX: "Mantorrecio: Hay que tener osadía" }, { enUS: "Wiley's Note", esES: "Nota de Wiley", esMX: "Nota de Wiley" }, ["item", 1]),
    page("b:39", "38", 2, { enUS: "They have a vast network", esMX: "Han mandado construir" }, { enUS: "Wiley's Note", esES: "Nota de Wiley", esMX: "Nota de Wiley" }, ["item", 1]),
    page("b:500", "500", 1, { enUS: "Dust one." }, { enUS: "A Dusty Tome" }),
    page("b:600", "600", 1, { enUS: "Dust two." }, { enUS: "A Dusty Tome" }),
  ],
};

function row(over: Partial<BookMatchInput>): BookMatchInput {
  return { locale: "esES", text: null, meta: {}, matchLineId: null, matchBookId: null, matchPageNumber: null, matchNewBook: false, ...over };
}

describe("matchBook", () => {
  it("finds a page by another language's exact words, as a correction where this language differs", () => {
    expect(matchBook(row({ text: "Mantorrecio: Hay que tener osadía", meta: { book: "Nota de Wiley", number: "1" } }), corpus))
      .toEqual({ kind: "correction", lineId: "b:38", current: "Stoutmantle -- Qué descaro", via: "text" });
  });

  it("calls a page this language has with the same words known", () => {
    expect(matchBook(row({ text: "Stoutmantle -- Qué descaro" }), corpus)).toMatchObject({ kind: "known", lineId: "b:38" });
  });

  it("calls a page this language lacks a translation", () => {
    expect(matchBook(row({ text: "Han mandado construir" }), corpus)).toMatchObject({ kind: "translation", lineId: "b:39", via: "text" });
  });

  it("places by title and number when the words are new", () => {
    expect(matchBook(row({ text: "Otras palabras", meta: { book: "Nota de Wiley", number: "2" } }), corpus))
      .toMatchObject({ kind: "translation", lineId: "b:39", via: "title" });
    expect(matchBook(row({ text: "Otras palabras", meta: { book: "Nota de Wiley", number: "3" } }), corpus))
      .toEqual({ kind: "new-page", bookId: "38", pageNumber: 3, via: "title" });
  });

  it("never guesses between two books of one title", () => {
    expect(matchBook(row({ locale: "enUS", text: "Dust three.", meta: { book: "A Dusty Tome", number: "1" } }), corpus))
      .toEqual({ kind: "ambiguous", candidates: ["500", "600"] });
  });

  it("starts a new book when nothing matches", () => {
    expect(matchBook(row({ text: "Trotamundos de los elfos:", meta: { book: "Instrucciones del consejero Nazgrel", number: "1" } }), corpus))
      .toEqual({ kind: "new-book", title: "Instrucciones del consejero Nazgrel", pageNumber: 1, via: "none" });
  });

  it("matches by the item that was read before anything else", () => {
    expect(matchBook(row({ text: "Otras palabras", meta: { item: "1", number: "2" } }), corpus))
      .toMatchObject({ kind: "translation", lineId: "b:39", via: "owner" });
  });

  it("takes a moderator's answer over every guess", () => {
    expect(matchBook(row({ text: "Mantorrecio: Hay que tener osadía", matchLineId: "b:39" }), corpus))
      .toMatchObject({ kind: "translation", lineId: "b:39", via: "moderator" });
    expect(matchBook(row({ text: "x", matchBookId: "500", matchPageNumber: 4 }), corpus))
      .toEqual({ kind: "new-page", bookId: "500", pageNumber: 4, via: "moderator" });
    expect(matchBook(row({ text: "x", meta: { book: "Nota de Wiley", number: "1" }, matchNewBook: true }), corpus))
      .toEqual({ kind: "new-book", title: "Nota de Wiley", pageNumber: 1, via: "moderator" });
  });

  it("calls two pages with the same words in any language ambiguous", () => {
    const twin = { pages: [...corpus.pages, page("b:700", "700", 1, { enUS: "Dust one." }, { enUS: "Another" })] };
    expect(matchBook(row({ locale: "deDE", text: "Dust one." }), twin)).toEqual({ kind: "ambiguous", candidates: ["b:500", "b:700"] });
  });
  it("falls through to the words when the owner id is one the corpus does not know", () => {
    expect(matchBook(row({ text: "Han mandado construir", meta: { object: "999999", number: "2" } }), corpus))
      .toMatchObject({ kind: "translation", lineId: "b:39", via: "text" });
  });
});
