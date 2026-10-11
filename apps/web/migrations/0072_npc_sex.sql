-- One NPC id, drawn as a man or a woman.
--
-- creature_template gives a creature up to four displays, and 651 classic creatures have both
-- sexes among them: a Stormwind City Guard is a man or a woman, at even odds, under one id. The
-- npc row answers one race, gender and flavor for the id, so every guard spoke in a man's voice.
-- An NPC with rows here is split: each sex the client reports (UnitSex: 2 male, 3 female) is
-- answered on its own, and every line the NPC speaks is voiced once per sex. The npc row stays
-- the answer for anything that does not know the sex: an older addon, a name-keyed lookup.
--
-- Same provenance ranking and invariants as npc (0070). The gender is the sex's, so it cannot
-- disagree with it.
--
-- Additive: no reader of npc changes, so the previous release ignores the split.

create table if not exists "npc_sex" (
  "npcKind"    text not null,
  "npcId"      integer not null,
  "sex"        smallint not null,
  "gender"     text generated always as (case "sex" when 2 then 'male' else 'female' end) stored,
  "race"       text not null,
  "flavor"     text,
  "provenance" text not null,
  "confirmed"  boolean not null default false,
  "doubtful"   boolean not null default false,
  "note"       text,
  "resolvedBy" text references "user" ("id") on delete set null,
  "updatedAt"  timestamptz not null default now(),
  primary key ("npcKind", "npcId", "sex"),
  foreign key ("npcKind", "npcId") references "npc" ("npcKind", "npcId") on delete cascade,
  constraint "npc_sex_sex_check" check ("sex" in (2, 3)),
  constraint "npc_sex_provenance_check"
    check ("provenance" in ('corpus', 'display', 'client', 'moderator')),
  constraint "npc_sex_confirmed_provenance_check"
    check (not "confirmed" or "provenance" in ('corpus', 'display', 'moderator')),
  constraint "npc_sex_doubtful_provenance_check"
    check (not "doubtful" or "provenance" in ('moderator', 'corpus'))
);
