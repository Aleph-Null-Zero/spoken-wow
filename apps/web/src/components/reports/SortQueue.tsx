"use client";

/**
 * The sorting queue: one line with open reports at a time, everything needed to decide on
 * it, and the three answers pinned under the thumb.
 *
 * Walks the list the server sorted without navigating, so answering a card costs one
 * request and no page load, and the next card's line is fetched while this one is read.
 */
import { ArrowLeft, Pause, Pencil, Play, RefreshCw } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";

import { useLang } from "@/components/LangProvider";
import { ACCEPT_TONE, LiteButton, REJECT_TONE } from "@/components/LiteControls";
import Link from "@/components/LocaleLink";
import OverrideDialog from "@/components/OverrideDialog";
import { TranslateDialog, type TranslateSubject } from "@/components/TranslateDialog";
import { PageTextDialog } from "@/components/books/PageTextDialog";
import { Button } from "@/components/ui/button";
import { LoreDialog } from "@/components/zones/LoreDialog";
import type { ResultLine as BookLine } from "@/lib/books/search";
import { BASE_LANG, withLang } from "@/lib/lang";
import { explorerHref } from "@/lib/links";
import { noApiKeyMessage } from "@/lib/no-api-key";
import { detailOf, regeneratePath, searchPath, type SourceLine } from "@/lib/reports/detail";
import { CATEGORY_COLUMN, SOURCE_LABELS, type Report, type Status } from "@/lib/reports/reports";
import type { ReportGroup } from "@/lib/reports/rows";
import type { ResultLine as QuestLine } from "@/lib/search";
import type { Source } from "@/lib/sections";
import { cn } from "@/lib/utils";
import type { ResultLine as ZoneLine } from "@/lib/zones/search";

/** Enough to read a typical complaint whole without pushing the actions off a phone screen. */
const PREVIEW = 3;
/** Longer than this and the line's text is clamped behind "more". */
const LONG_TEXT = 280;

type Busy = Status | "skip" | "regenerate" | null;
/** A line not fetched yet is absent; null is a line the corpus no longer has. */
type Looked = SourceLine | null | "error";

function ago(at: string): string {
  const minutes = Math.round((Date.now() - Date.parse(at)) / 60_000);
  if (minutes < 60) return `${Math.max(minutes, 1)}m ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 48) return `${hours}h ago`;
  return `${Math.round(hours / 24)}d ago`;
}

/** What TranslateDialog edits for a quest line outside English, as the explorer opens it. */
function translateSubject(line: QuestLine): TranslateSubject {
  return {
    title: line.npcName,
    subtitle: line.lineId,
    english: line.english ? line.originalText : "There is no English line yet.",
    current: line.missing?.text ? null : line.text,
    endpoint: "/api/quests/lines/text",
    address: { lineId: line.lineId, variant: line.variant ?? 0 },
    field: "text",
    multiline: true,
  };
}

function isTyping(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  return target.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName);
}

export default function SortQueue({
  source,
  groups: initial,
  canRegenerate,
  canEditText,
}: {
  source: Source;
  /** The queue as the server sorted it, open reports only, skipped lines already left out. */
  groups: ReportGroup[];
  canRegenerate: boolean;
  canEditText: boolean;
}) {
  const lang = useLang();
  // Held from the first render: a refresh while sorting brings back a list without the lines
  // already answered, and the position would then point past the card on screen.
  const [groups] = useState(initial);
  const [index, setIndex] = useState(0);
  const [lines, setLines] = useState<Record<string, Looked>>({});
  /** Takes written here, so the player plays the new one rather than the browser's cache. */
  const [versions, setVersions] = useState<Record<string, number>>({});
  const [busy, setBusy] = useState<Busy>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const [showAll, setShowAll] = useState(false);
  const [fullText, setFullText] = useState(false);
  const [playing, setPlaying] = useState(false);
  const audio = useRef<HTMLAudioElement>(null);
  /** Lines asked for, so a re-render while one is in flight does not ask again. */
  const requested = useRef(new Set<string>());
  /** Set by a regeneration: play the new take as soon as its line is back. */
  const playWhenReady = useRef(false);

  const group = groups[index] as ReportGroup | undefined;
  const lineId = group?.reports[0].lineId ?? null;
  const looked = lineId === null ? undefined : lines[lineId];
  const line = looked && looked !== "error" ? looked : null;
  const detail = line ? detailOf(source, line, lineId ? versions[lineId] : undefined, lang) : null;

  const fetchLine = useCallback(
    async (id: string) => {
      const response = await fetch(searchPath(source, id, lang)).catch(() => null);
      const body = response?.ok
        ? ((await response.json().catch(() => null)) as { lines?: SourceLine[] } | null)
        : null;
      setLines((current) => ({ ...current, [id]: body ? (body.lines?.[0] ?? null) : "error" }));
    },
    [source, lang],
  );

  const reload = useCallback(
    (id: string) => {
      requested.current.add(id);
      void fetchLine(id);
    },
    [fetchLine],
  );

  useEffect(() => {
    for (const next of groups.slice(index, index + 2)) {
      const id = next.reports[0].lineId;
      if (id && !requested.current.has(id)) reload(id);
    }
  }, [groups, index, reload]);

  useEffect(() => {
    if (!playWhenReady.current || !detail?.audioSrc) return;
    playWhenReady.current = false;
    void audio.current?.play().catch(() => {});
  }, [detail?.audioSrc]);

  function advance() {
    audio.current?.pause();
    setIndex((current) => current + 1);
    setError(null);
    setNotice(null);
    setEditing(false);
    setShowAll(false);
    setFullText(false);
    setPlaying(false);
  }

  /** One request per report, as the triage table does: each keeps its own resolver. */
  async function resolve(status: Status) {
    if (!group || busy) return;
    setBusy(status);
    setError(null);
    const results = await Promise.all(
      group.reports.map((report) =>
        fetch("/api/reports/resolve", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ id: report.id, status }),
        })
          .then((response) => response.ok)
          .catch(() => false),
      ),
    );
    setBusy(null);
    const failed = results.filter((ok) => !ok).length;
    if (failed) return setError(`${failed} of ${results.length} didn't save. Try again.`);
    advance();
  }

  async function skip() {
    if (!group || busy) return;
    setBusy("skip");
    setError(null);
    const response = await fetch(withLang(lang, "/api/reports/skip"), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ids: group.reports.map((report) => report.id) }),
    }).catch(() => null);
    setBusy(null);
    if (!response?.ok) return setError("Couldn't skip. Try again.");
    advance();
  }

  async function regenerate() {
    if (!lineId || busy) return;
    setBusy("regenerate");
    setError(null);
    setNotice(null);
    const response = await fetch(regeneratePath(source, lang), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ lineId }),
    }).catch(() => null);
    const body = (await response?.json().catch(() => ({}))) as {
      ok?: boolean;
      version?: number;
      error?: string;
      code?: string;
    };
    setBusy(null);

    if (!response) return setError("The request did not go through.");
    const noKey = noApiKeyMessage(response.status, body);
    if (noKey) return setError(noKey);
    if (!response.ok || !body.ok || body.version === undefined) {
      return setError(body.error ?? `Regenerate failed (${response.status}).`);
    }

    setVersions((current) => ({ ...current, [lineId]: body.version! }));
    setNotice("New take saved.");
    playWhenReady.current = true;
    // Refetched rather than patched: a line that had no take until now only gains its audio
    // path from the search.
    reload(lineId);
  }

  function togglePlay() {
    const element = audio.current;
    if (!element || !detail?.audioSrc) return;
    if (element.paused) void element.play().catch(() => {});
    else element.pause();
  }

  const canEdit = canEditText && line !== null;
  const actions = useRef({ togglePlay, resolve, skip, edit: () => canEdit && setEditing(true) });
  actions.current = { togglePlay, resolve, skip, edit: () => canEdit && setEditing(true) };

  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      if (event.metaKey || event.ctrlKey || event.altKey || isTyping(event.target)) return;
      // A dialog owns the keyboard while it is open.
      if (document.querySelector("[role=dialog]")) return;
      const act = actions.current;
      if (event.key === " ") {
        event.preventDefault();
        act.togglePlay();
      } else if (event.key === "f") void act.resolve("fixed");
      else if (event.key === "n") void act.resolve("not_an_issue");
      else if (event.key === "s") void act.skip();
      else if (event.key === "e") act.edit();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const total = groups.length;

  if (!group) {
    return (
      <main className="mx-auto flex max-w-xl flex-col items-center px-4 pt-16 pb-24 text-center">
        <p className="text-2xl font-semibold">All sorted</p>
        <p className="text-muted-foreground mt-2 text-sm">
          No open {SOURCE_LABELS[source].toLowerCase()} reports left in your queue.
        </p>
        <Link href="/reports/sort" className="mt-6 text-sm underline underline-offset-2">
          Back to sections
        </Link>
      </main>
    );
  }

  const reports = showAll ? group.reports : group.reports.slice(0, PREVIEW);
  const text = detail?.text ?? "";
  const clamped = !fullText && text.length > LONG_TEXT;

  return (
    <main className="mx-auto flex max-w-xl flex-col gap-4 px-4 pt-4 pb-32">
      <header className="flex flex-col gap-2">
        <div className="flex items-center gap-2">
          <Link
            href="/reports/sort"
            aria-label="Back to sections"
            className="hover:bg-muted -ml-2 rounded-md p-2"
          >
            <ArrowLeft className="size-5" />
          </Link>
          <span className="flex-1 font-medium">{SOURCE_LABELS[source]}</span>
          <span className="text-muted-foreground text-sm tabular-nums">
            {index + 1} / {total}
          </span>
        </div>
        <div className="bg-muted h-1 overflow-hidden rounded-full">
          <div className="bg-primary h-full transition-[width]" style={{ width: `${(index / total) * 100}%` }} />
        </div>
      </header>

      <section className="bg-card flex flex-col gap-2 rounded-xl border p-4">
        {lineId === null ? (
          <>
            <p className="font-medium">{group.reports[0].target ? "No line picked" : "About the project"}</p>
            {group.reports[0].target ? (
              <p className="text-muted-foreground font-mono text-xs break-all">{group.reports[0].target}</p>
            ) : null}
          </>
        ) : looked === undefined ? (
          <p className="text-muted-foreground text-sm">Looking up the line…</p>
        ) : looked === "error" ? (
          <p className="text-sm">
            Couldn&apos;t load the line.{" "}
            <button type="button" className="underline underline-offset-2" onClick={() => reload(lineId)}>
              Retry
            </button>
          </p>
        ) : detail === null ? (
          <p className="text-muted-foreground text-sm">
            No line in the corpus carries <span className="font-mono">{lineId}</span> any more.
          </p>
        ) : (
          <>
            <div>
              <p className="leading-snug font-medium">{detail.heading}</p>
              <p className="text-muted-foreground mt-0.5 text-xs">{detail.context}</p>
            </div>
            <p className={cn("text-sm whitespace-pre-wrap", clamped && "line-clamp-5")}>{text}</p>
            <div className="text-muted-foreground flex items-center gap-3 text-xs">
              {text.length > LONG_TEXT ? (
                <button type="button" className="underline underline-offset-2" onClick={() => setFullText(!fullText)}>
                  {fullText ? "less" : "more"}
                </button>
              ) : null}
              <Link href={explorerHref(source, lineId)} className="font-mono underline-offset-2 hover:underline">
                {lineId}
              </Link>
            </div>
          </>
        )}

        <div className="mt-1 grid grid-cols-3 gap-2">
          <Button
            variant="outline"
            className="h-11"
            disabled={!detail?.audioSrc}
            onClick={togglePlay}
            title="Play (space)"
          >
            {playing ? <Pause /> : <Play />}
            {playing ? "Pause" : "Play"}
          </Button>
          <Button
            variant="outline"
            className="h-11"
            disabled={!canEdit || busy !== null}
            onClick={() => setEditing(true)}
            title="Edit text (e)"
          >
            <Pencil />
            Edit
          </Button>
          <Button
            variant="outline"
            className="h-11"
            disabled={!canRegenerate || !line || busy !== null}
            onClick={() => void regenerate()}
            title={canRegenerate ? "Regenerate this line" : "You can't regenerate in this language"}
          >
            <RefreshCw className={cn(busy === "regenerate" && "animate-spin")} />
            {busy === "regenerate" ? "Working…" : "Regenerate"}
          </Button>
        </div>
        {detail && !detail.audioSrc ? <p className="text-muted-foreground text-xs">No audio on file.</p> : null}
        {notice ? <p className="text-xs text-emerald-500">{notice}</p> : null}
        <audio
          ref={audio}
          src={detail?.audioSrc ?? undefined}
          preload="none"
          onPlay={() => setPlaying(true)}
          onPause={() => setPlaying(false)}
          onEnded={() => setPlaying(false)}
          onError={() => detail?.audioSrc && setError("Couldn't play the audio.")}
        />
      </section>

      <section className="flex flex-col gap-2">
        <p className="text-sm font-medium">
          {group.reports.length} {group.reports.length === 1 ? "report" : "reports"}
        </p>
        {reports.map((report) => (
          <ReportPreview key={report.id} report={report} />
        ))}
        {group.reports.length > PREVIEW ? (
          <button
            type="button"
            className="text-muted-foreground self-start text-sm underline underline-offset-2"
            onClick={() => setShowAll(!showAll)}
          >
            {showAll ? "Show fewer" : `Show all ${group.reports.length}`}
          </button>
        ) : null}
      </section>

      {error ? <p className="text-destructive text-sm">{error}</p> : null}

      <nav className="bg-background/95 fixed inset-x-0 bottom-0 z-20 border-t backdrop-blur">
        <div className="mx-auto grid max-w-xl grid-cols-3 gap-2 px-4 pt-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
          <LiteButton
            className={cn("h-12 justify-center text-sm", ACCEPT_TONE)}
            disabled={busy !== null}
            onClick={() => void resolve("fixed")}
            title="Fixed (f)"
          >
            {busy === "fixed" ? "Saving…" : "Fixed"}
          </LiteButton>
          <LiteButton
            className={cn("h-12 justify-center text-sm", REJECT_TONE)}
            disabled={busy !== null}
            onClick={() => void resolve("not_an_issue")}
            title="Not a problem (n)"
          >
            {busy === "not_an_issue" ? "Saving…" : "Not a problem"}
          </LiteButton>
          <LiteButton
            className="h-12 justify-center text-sm"
            disabled={busy !== null}
            onClick={() => void skip()}
            title="Skip (s)"
          >
            {busy === "skip" ? "Skipping…" : "Skip"}
          </LiteButton>
        </div>
      </nav>

      {editing && line && lineId ? (
        source === "quests" ? (
          lang === BASE_LANG ? (
            <OverrideDialog
              line={line as QuestLine}
              onSaved={() => {
                setEditing(false);
                reload(lineId);
              }}
              onCancel={() => setEditing(false)}
            />
          ) : (
            <TranslateDialog
              subject={translateSubject(line as QuestLine)}
              onClose={() => setEditing(false)}
              onSaved={() => reload(lineId)}
            />
          )
        ) : source === "zones" ? (
          <LoreDialog line={line as ZoneLine} onClose={() => setEditing(false)} onSaved={() => reload(lineId)} />
        ) : (
          <PageTextDialog line={line as BookLine} onClose={() => setEditing(false)} onSaved={() => reload(lineId)} />
        )
      ) : null}
    </main>
  );
}

/** Never shows the reporter's email or address: who they are is not what triage weighs. */
function ReportPreview({ report }: { report: Report }) {
  const [whole, setWhole] = useState(false);
  return (
    <article className="bg-card cursor-pointer rounded-lg border px-3 py-2.5" onClick={() => setWhole(!whole)}>
      <div className="text-muted-foreground flex items-center gap-2 text-xs">
        <span className="bg-muted text-foreground rounded px-1.5 py-0.5 font-medium">
          {CATEGORY_COLUMN[report.category]}
        </span>
        <span className="truncate">{report.name ?? "anonymous"}</span>
        <span className="ml-auto shrink-0">{ago(report.createdAt)}</span>
      </div>
      <p className={cn("mt-1.5 text-sm break-words whitespace-pre-wrap", !whole && "line-clamp-3")}>{report.body}</p>
    </article>
  );
}
