"use client";

/**
 * The sorting queue: one line with open reports at a time, everything needed to decide on
 * it, and the three answers pinned under the thumb.
 *
 * Walks the list the server sorted without navigating, so answering a card costs one
 * request and no page load, and the next card's line is fetched while this one is read.
 */
import { ArrowLeft, ChevronsDownUp, ChevronsUpDown, Pause, Pencil, Play, RefreshCw, Undo2 } from "lucide-react";
import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";

import { useLang } from "@/components/LangProvider";
import { ACCEPT_TONE, LiteButton, REJECT_TONE } from "@/components/LiteControls";
import Link from "@/components/LocaleLink";
import OverrideDialog from "@/components/OverrideDialog";
import QuestsPlayer from "@/components/Player";
import TakeSelector from "@/components/TakeSelector";
import { TranslateDialog, type TranslateSubject } from "@/components/TranslateDialog";
import { PageTextDialog } from "@/components/books/PageTextDialog";
import { Player as BooksPlayer } from "@/components/books/Player";
import { Button } from "@/components/ui/button";
import { LoreDialog } from "@/components/zones/LoreDialog";
import { Player as ZonesPlayer } from "@/components/zones/Player";
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

/** The answer a revisited card was given. */
const CHOSEN = "ring-foreground/60 ring-2";

/** Enough to read a typical complaint whole without pushing the actions off a phone screen. */
const PREVIEW = 3;
/** Longer than this and the line's text is clamped behind "more". */
const LONG_TEXT = 280;

type Answer = Exclude<Status, "open"> | "skip";
type Busy = Answer | "regenerate" | null;

const ANSWER_LABELS: Record<Answer, string> = {
  fixed: "Fixed",
  not_an_issue: "Not a problem",
  skip: "Skipped",
};
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

/** The store-relative file a take belongs to, as TakeSelector addresses it. */
function fileOf(source: Source, line: SourceLine): string {
  return source === "quests" ? (line as QuestLine).audioPath : (line as ZoneLine | BookLine).file;
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
  /** What was answered on each card this visit, by position, so Previous can show and change it. */
  const [answers, setAnswers] = useState<Record<number, Answer>>({});
  const [lines, setLines] = useState<Record<string, Looked>>({});
  /** Takes written here, so the player plays the new one rather than the browser's cache. */
  const [versions, setVersions] = useState<Record<string, number>>({});
  const [busy, setBusy] = useState<Busy>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  /** Everything on the card unclamped: the line's whole text and every report in full. */
  const [expanded, setExpanded] = useState(false);
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
  // The take this session made or restored, else the live one: either way a cache buster, since
  // a new take keeps its path and the browser would replay the one it replaced.
  const version = lineId === null || line === null ? undefined : (versions[lineId] ?? line.take?.version);
  const detail = line ? detailOf(source, line, version, lang) : null;

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

  // The player owns the element; the Play button only mirrors it.
  useEffect(() => {
    const element = audio.current;
    if (!element) return;
    const on = () => setPlaying(true);
    const off = () => setPlaying(false);
    element.addEventListener("play", on);
    element.addEventListener("pause", off);
    element.addEventListener("ended", off);
    return () => {
      element.removeEventListener("play", on);
      element.removeEventListener("pause", off);
      element.removeEventListener("ended", off);
    };
  }, [group === undefined]);

  useEffect(() => {
    if (!playWhenReady.current || !detail?.audioSrc) return;
    playWhenReady.current = false;
    void audio.current?.play().catch(() => {});
  }, [detail?.audioSrc]);

  function goTo(next: number) {
    audio.current?.pause();
    setIndex(next);
    setError(null);
    setNotice(null);
    setEditing(false);
    setExpanded(false);
    setPlaying(false);
  }

  function answered(answer: Answer) {
    setAnswers((current) => ({ ...current, [index]: answer }));
    goTo(index + 1);
  }

  /**
   * One request per report, as the triage table does: each keeps its own resolver. Returns
   * how many failed. Resolving a report already resolved is allowed, which is what lets a
   * card revisited through Previous change its answer.
   */
  async function setStatuses(reports: Report[], status: Status): Promise<number> {
    const results = await Promise.all(
      reports.map((report) =>
        fetch("/api/reports/resolve", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ id: report.id, status }),
        })
          .then((response) => response.ok)
          .catch(() => false),
      ),
    );
    return results.filter((ok) => !ok).length;
  }

  async function resolve(status: Exclude<Status, "open">) {
    if (!group || busy) return;
    if (answers[index] === status) return goTo(index + 1);
    setBusy(status);
    setError(null);
    const failed = await setStatuses(group.reports, status);
    setBusy(null);
    if (failed) return setError(`${failed} of ${group.reports.length} didn't save. Try again.`);
    answered(status);
  }

  async function skip() {
    if (!group || busy) return;
    const previous = answers[index];
    if (previous === "skip") return goTo(index + 1);
    setBusy("skip");
    setError(null);
    // A line answered earlier is reopened first: only open reports can be skipped, and a
    // skipped line is one still waiting for somebody.
    if (previous && (await setStatuses(group.reports, "open"))) {
      setBusy(null);
      return setError("Couldn't reopen the reports. Try again.");
    }
    const response = await fetch(withLang(lang, "/api/reports/skip"), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ids: group.reports.map((report) => report.id) }),
    }).catch(() => null);
    setBusy(null);
    if (!response?.ok) return setError("Couldn't skip. Try again.");
    answered("skip");
  }

  function previous() {
    if (index > 0 && !busy) goTo(index - 1);
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
  const canRegenerateLine = canRegenerate && line !== null;
  const keyActions = {
    togglePlay,
    resolve,
    skip,
    edit: () => canEdit && setEditing(true),
    regenerate: () => canRegenerateLine && void regenerate(),
    expand: () => setExpanded((current) => !current),
    previous,
  };
  const actions = useRef(keyActions);
  actions.current = keyActions;

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
      else if (event.key === "r") act.regenerate();
      else if (event.key === "x") act.expand();
      else if (event.key === "p") act.previous();
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
        <div className="mt-6 flex items-center gap-4 text-sm">
          {index > 0 ? (
            <Button variant="outline" size="sm" onClick={previous}>
              <Undo2 />
              Previous
              <Hint>[P]</Hint>
            </Button>
          ) : null}
          <Link href="/reports/sort" className="underline underline-offset-2">
            Back to sections
          </Link>
        </div>
      </main>
    );
  }

  const reports = expanded ? group.reports : group.reports.slice(0, PREVIEW);
  const text = detail?.text ?? "";

  return (
    <main className="mx-auto flex max-w-xl flex-col gap-4 px-4 pt-4 pb-56">
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
          <Button
            variant="ghost"
            size="sm"
            onClick={previous}
            disabled={index === 0 || busy !== null}
            title="Go back to the last line and change its answer"
          >
            <Undo2 />
            Previous
            <Hint>[P]</Hint>
          </Button>
          <Button variant="ghost" size="sm" onClick={() => setExpanded(!expanded)} aria-pressed={expanded}>
            {expanded ? <ChevronsDownUp /> : <ChevronsUpDown />}
            {expanded ? "Collapse" : "Expand"}
            <Hint>[X]</Hint>
          </Button>
          <span className="text-muted-foreground text-sm tabular-nums">
            {index + 1} / {total}
          </span>
        </div>
        <div className="bg-muted h-1 overflow-hidden rounded-full">
          <div className="bg-primary h-full transition-[width]" style={{ width: `${(index / total) * 100}%` }} />
        </div>
      </header>

      {answers[index] ? (
        <p className="bg-muted rounded-lg px-3 py-2 text-sm">
          Answered <span className="font-medium">{ANSWER_LABELS[answers[index]]}</span>. Pick another answer
          below to change it.
        </p>
      ) : null}

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
            <p className={cn("text-sm whitespace-pre-wrap", !expanded && text.length > LONG_TEXT && "line-clamp-5")}>
              {text}
            </p>
            <div className="text-muted-foreground flex items-center gap-3 text-xs">
              <Link href={explorerHref(source, lineId)} className="font-mono underline-offset-2 hover:underline">
                {lineId}
              </Link>
              <TakeSelector
                source={source}
                file={fileOf(source, line!)}
                version={version ?? null}
                takes={line!.take?.takes ?? 0}
                canRestore={canRegenerate}
                onRestored={(restored) => {
                  setVersions((current) => ({ ...current, [lineId]: restored }));
                  reload(lineId);
                }}
              />
            </div>
          </>
        )}

        <div className="mt-1 grid grid-cols-3 gap-2">
          <Button
            variant="outline"
            className="h-11"
            disabled={!detail?.audioSrc}
            onClick={togglePlay}
            title="Play"
          >
            {playing ? <Pause /> : <Play />}
            {playing ? "Pause" : "Play"}
            <Hint>[Space]</Hint>
          </Button>
          <Button
            variant="outline"
            className="h-11"
            disabled={!canEdit || busy !== null}
            onClick={() => setEditing(true)}
            title="Edit text"
          >
            <Pencil />
            Edit
            <Hint>[E]</Hint>
          </Button>
          <Button
            variant="outline"
            className="h-11"
            disabled={!canRegenerateLine || busy !== null}
            onClick={() => void regenerate()}
            title={canRegenerate ? "Regenerate this line" : "You can't regenerate in this language"}
          >
            <RefreshCw className={cn(busy === "regenerate" && "animate-spin")} />
            {busy === "regenerate" ? "Working…" : "Regenerate"}
            <Hint>[R]</Hint>
          </Button>
        </div>
        {detail && !detail.audioSrc ? <p className="text-muted-foreground text-xs">No audio on file.</p> : null}
        {notice ? <p className="text-xs text-emerald-500">{notice}</p> : null}
      </section>

      <section className="flex flex-col gap-2">
        <p className="text-sm font-medium">
          {group.reports.length} {group.reports.length === 1 ? "report" : "reports"}
        </p>
        {reports.map((report) => (
          <ReportPreview key={report.id} report={report} expanded={expanded} />
        ))}
        {!expanded && group.reports.length > PREVIEW ? (
          <button
            type="button"
            className="text-muted-foreground self-start text-sm underline underline-offset-2"
            onClick={() => setExpanded(true)}
          >
            {group.reports.length - PREVIEW} more
          </button>
        ) : null}
      </section>

      {error ? <p className="text-destructive text-sm">{error}</p> : null}

      <nav className="bg-background/95 fixed inset-x-0 bottom-0 z-20 backdrop-blur">
        {/* The explorers' transport, for scrubbing through the line and downloading it. */}
        {source === "quests" ? (
          <QuestsPlayer ref={audio} line={detail?.audioSrc ? (line as QuestLine) : null} version={version} />
        ) : source === "zones" ? (
          <ZonesPlayer audioRef={audio} line={line as ZoneLine | null} version={version} />
        ) : (
          <BooksPlayer audioRef={audio} line={line as BookLine | null} version={version} />
        )}
        <div className="mx-auto grid max-w-xl grid-cols-3 gap-2 px-4 pt-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
          <LiteButton
            className={cn("h-12 justify-center gap-1.5 text-sm", ACCEPT_TONE, answers[index] === "fixed" && CHOSEN)}
            disabled={busy !== null}
            onClick={() => void resolve("fixed")}
            title="Fixed"
          >
            {busy === "fixed" ? "Saving…" : "Fixed"}
            <Hint>[F]</Hint>
          </LiteButton>
          <LiteButton
            className={cn(
              "h-12 justify-center gap-1.5 text-sm",
              REJECT_TONE,
              answers[index] === "not_an_issue" && CHOSEN,
            )}
            disabled={busy !== null}
            onClick={() => void resolve("not_an_issue")}
            title="Not a problem"
          >
            {busy === "not_an_issue" ? "Saving…" : "Not a problem"}
            <Hint>[N]</Hint>
          </LiteButton>
          <LiteButton
            className={cn("h-12 justify-center gap-1.5 text-sm", answers[index] === "skip" && CHOSEN)}
            disabled={busy !== null}
            onClick={() => void skip()}
            title="Skip"
          >
            {busy === "skip" ? "Skipping…" : "Skip"}
            <Hint>[S]</Hint>
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

/** Only where there is a keyboard to press it with: a phone has no use for the hint. */
function Hint({ children }: { children: ReactNode }) {
  return <span className="hidden opacity-60 pointer-fine:inline">{children}</span>;
}

/** Never shows the reporter's email or address: who they are is not what triage weighs. */
function ReportPreview({ report, expanded }: { report: Report; expanded: boolean }) {
  const [opened, setWhole] = useState(false);
  const whole = expanded || opened;
  return (
    <article className="bg-card cursor-pointer rounded-lg border px-3 py-2.5" onClick={() => setWhole(!opened)}>
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
