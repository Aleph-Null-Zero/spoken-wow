-- book_line's copy of a page's structure is no longer read (book_page holds it), so a page with
-- no pageTextID, or in a book with no integer id, may leave it empty. Relaxing only: every row
-- the previous release reads still has these filled in.
alter table "book_line" alter column "pageId" drop not null;
alter table "book_line" alter column "bookId" drop not null;
alter table "book_line" alter column "pageNumber" drop not null;
alter table "book_line" alter column "pageCount" drop not null;
alter table "book_line" alter column "ownerKind" drop not null;
alter table "book_line" alter column "ownerIds" drop not null;
alter table "book_line" drop constraint if exists "book_line_ownerKind_check";
alter table "book_line" add constraint "book_line_ownerKind_check" check ("ownerKind" is null or "ownerKind" in ('object', 'item'));

-- A page nothing opens names no owner.
create or replace function "entity_name_from_book_line"() returns trigger
language plpgsql as $$
declare
  owner integer;
begin
  if new."ownerKind" is null then return new; end if;
  if new."lang" = 'enUS' and new."isCurrent" then
    foreach owner in array new."ownerIds" loop
      perform "entity_name_set"(
        case new."ownerKind" when 'object' then 'gameobject' else 'item' end,
        owner::text, 'enUS', new."title");
    end loop;
  end if;
  return null;
end;
$$;
