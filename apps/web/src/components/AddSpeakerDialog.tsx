"use client";

import { useState } from "react";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { flavorOptionsFor } from "@/lib/contributions/speaker";
import { NPC_ROW_KINDS, type NpcRowKind } from "@/lib/npc/npc";
import type { ResultLine } from "@/lib/search";
import { Roster, type RosterData } from "@/lib/voices/roster";

type Props = {
  /** The line gaining a speaker, or null when the dialog is closed. */
  line: ResultLine | null;
  onSaved: () => void;
  onCancel: () => void;
};

type Found = {
  npc: { npcName: string | null; race: string | null; gender: string | null; flavor: string | null; voice: string | null } | null;
  roster: RosterData;
};

const FIELD =
  "border-input bg-transparent focus-visible:ring-ring/50 rounded-md border px-3 py-2 text-sm focus-visible:ring-[3px] focus-visible:outline-none";

/**
 * Adding an NPC as one more speaker of a line: a quest two givers offer, a greeting several
 * guards share. The NPC is looked up first; one already answered speaks in its own voice, and
 * one nobody has answered is answered here, as /npcs would, since a speaker needs a voice.
 */
export default function AddSpeakerDialog({ line, onSaved, onCancel }: Props) {
  const [npcType, setNpcType] = useState<NpcRowKind>("creature");
  const [npcId, setNpcId] = useState("");
  const [found, setFound] = useState<Found | null>(null);
  const [npcName, setNpcName] = useState("");
  const [race, setRace] = useState("");
  const [gender, setGender] = useState("");
  const [flavor, setFlavor] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Which line the form belongs to, so opening another row starts it over (as IgnoreDialog).
  const [seeded, setSeeded] = useState<string | null>(null);

  if (!line) return null;

  if (seeded !== line.key) {
    setSeeded(line.key);
    setNpcType(line.npcType === "gameobject" || line.npcType === "item" ? line.npcType : "creature");
    setNpcId("");
    setFound(null);
    setError(null);
    return null;
  }

  const roster = found ? new Roster(found.roster) : null;
  const answered = Boolean(found?.npc?.voice);
  const genders = roster && race ? roster.gendersOf(race) : [];
  const flavors = roster ? flavorOptionsFor(race || null, gender || null, roster) : [];
  const answerReady = Boolean(race && (gender || genders.length === 0) && npcName.trim());

  async function lookUp() {
    if (!/^\d+$/.test(npcId.trim())) {
      setError("An NPC id is a number");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const response = await fetch(
        `/api/quests/lines/speakers?npcType=${npcType}&npcId=${encodeURIComponent(npcId.trim())}`,
      );
      const body = (await response.json().catch(() => ({}))) as Found & { error?: string };
      if (!response.ok) {
        setError(body.error ?? `request failed (${response.status})`);
        return;
      }
      setFound(body);
      setNpcName(body.npc?.npcName ?? "");
      setRace(body.npc?.race ?? "");
      setGender(body.npc?.gender ?? "");
      setFlavor(body.npc?.flavor ?? "");
    } catch (problem) {
      setError(String(problem));
    } finally {
      setBusy(false);
    }
  }

  async function post(url: string, body: Record<string, unknown>): Promise<boolean> {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (response.ok) return true;
    const { error } = (await response.json().catch(() => ({}))) as { error?: string };
    setError(error ?? `request failed (${response.status})`);
    return false;
  }

  async function add() {
    if (!line) return;
    setBusy(true);
    setError(null);
    const npc = { npcId: Number(npcId.trim()) };
    try {
      // An NPC nobody has answered is answered first, as /npcs would: a speaker needs a voice.
      if (!answered && !(await post("/api/npcs", { ...npc, npcKind: npcType, npcName, race, gender, flavor }))) return;
      if (await post("/api/quests/lines/speakers", { ...npc, lineId: line.lineId, npcType })) onSaved();
    } catch (problem) {
      setError(String(problem));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(open) => !open && onCancel()}>
      <DialogContent className="sm:max-w-xl">
        <DialogHeader>
          <DialogTitle>Add a speaker</DialogTitle>
          <DialogDescription>
            Another NPC who says this line. It is spoken in that NPC&rsquo;s own voice: one whose voice
            differs gets a line of its own here, with no audio until it is generated. Kept across
            imports until the game data lists the NPC too.
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-3">
          <span className="text-muted-foreground text-xs">
            {line.npcName} · {line.lineId}
          </span>
          <p className="text-muted-foreground bg-muted/40 max-h-24 overflow-y-auto rounded-md px-3 py-2 text-xs whitespace-pre-wrap">
            {line.override ?? line.text}
          </p>

          <form
            className="flex gap-2"
            onSubmit={(event) => {
              event.preventDefault();
              void lookUp();
            }}
          >
            <select
              aria-label="Kind"
              value={npcType}
              onChange={(event) => {
                setNpcType(event.target.value as NpcRowKind);
                setFound(null);
              }}
              className={FIELD}
            >
              {NPC_ROW_KINDS.map((kind) => (
                <option key={kind} value={kind}>
                  {kind}
                </option>
              ))}
            </select>
            <input
              aria-label="Id"
              autoFocus
              inputMode="numeric"
              value={npcId}
              onChange={(event) => {
                setNpcId(event.target.value);
                setFound(null);
              }}
              placeholder="id"
              className={`${FIELD} w-32`}
            />
            <Button type="submit" variant="outline" disabled={busy || !npcId.trim()}>
              Look up
            </Button>
          </form>

          {found && answered && (
            <p className="text-sm">
              {found.npc?.npcName ?? `${npcType} ${npcId}`}{" "}
              <span className="text-muted-foreground">speaks as {found.npc?.voice}</span>
            </p>
          )}

          {found && !answered && roster && (
            <div className="grid gap-2">
              <p className="text-muted-foreground text-xs">
                {found.npc?.race
                  ? `No voice reads ${[found.npc.race, found.npc.gender, found.npc.flavor].filter(Boolean).join("-")} yet: answer who this NPC is.`
                  : "Nobody has said who this NPC is yet. The answer holds for every line it speaks."}
              </p>
              <input
                aria-label="Name"
                value={npcName}
                onChange={(event) => setNpcName(event.target.value)}
                maxLength={200}
                placeholder="Name, as the game shows it"
                className={FIELD}
              />
              <div className="flex gap-2">
                <select
                  aria-label="Type"
                  value={race}
                  onChange={(event) => {
                    setRace(event.target.value);
                    setGender("");
                    setFlavor("");
                  }}
                  className={FIELD}
                >
                  <option value="">type</option>
                  {roster.races.map((option) => (
                    <option key={option} value={option}>
                      {option}
                    </option>
                  ))}
                </select>
                {genders.length > 0 && (
                  <select
                    aria-label="Gender"
                    value={gender}
                    onChange={(event) => {
                      setGender(event.target.value);
                      setFlavor("");
                    }}
                    className={FIELD}
                  >
                    <option value="">gender</option>
                    {genders.map((option) => (
                      <option key={option} value={option}>
                        {option}
                      </option>
                    ))}
                  </select>
                )}
                {flavors.length > 0 && (
                  <select
                    aria-label="Flavor"
                    value={flavor}
                    onChange={(event) => setFlavor(event.target.value)}
                    className={FIELD}
                  >
                    <option value="">flavor</option>
                    {flavors.map((option) => (
                      <option key={option} value={option}>
                        {option}
                      </option>
                    ))}
                  </select>
                )}
              </div>
            </div>
          )}
        </div>

        {error && (
          <p role="alert" className="text-destructive text-xs">
            {error}
          </p>
        )}

        <DialogFooter>
          <Button variant="ghost" disabled={busy} onClick={onCancel}>
            Cancel
          </Button>
          <Button disabled={busy || !found || (!answered && !answerReady)} onClick={() => void add()}>
            Add speaker
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
