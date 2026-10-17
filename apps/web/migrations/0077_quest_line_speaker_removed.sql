-- A speaker the dump names that an admin took off a moment by hand, from the explorer.
--
-- The dump is sometimes wrong about who speaks a line, not only short of speakers (0076): a quest
-- it says a gameobject offers is offered by a creature. Deleting the extract's row is not enough,
-- because an import replaces every extracted speaker wholesale (tts_cli/corpus_db.py) and would
-- put it back. The importer skips an extracted speaker this table names on the moment, every
-- line of it (both player-gender sides), in every later import.
--
-- Keyed by the moment, as the explorer adds and removes speakers by it. "removedBy" has no
-- foreign key, like "addedBy": the export carries it, and a database seeded from that file has
-- none of the users it names.
--
-- Additive and forward-only: the previous release ignores the table, and its next import brings
-- the removed speakers back.

create table if not exists "quest_line_speaker_removed" (
  "moment"    text        not null,
  "npcType"   text        not null check ("npcType" in ('creature', 'gameobject', 'item')),
  "npcId"     integer     not null,
  "removedBy" text        not null,
  "removedAt" timestamptz not null default now(),
  primary key ("moment", "npcType", "npcId")
);
