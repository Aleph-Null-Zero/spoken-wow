# Captions

Spoken shows the words of the line it reads (quest dialogue, NPC dialogue, place lore and book
pages) in each window, and as subtitles. The Small and DialogueUI windows show Lines Shown of
them, one or two lines, and the Small Window's **+** button expands them to eight; the Large
Window shows as many as its box holds, up to three. The captions follow the recording: with
**Type Words Out** on (the default) the words appear as the voice reaches them, and with
**Highlight Words** on (off by default) two adjacent words are lit, in gold, or in deep red on
parchment. They move, resize and scale with their window.

The **Subtitles Only** narrator style shows the words without a window instead, low in the
middle of the screen: a page of whole sentences at a time (Sentences at Once, never more than four
lines), or line by line, typed in a little ahead of the voice. It lights the word being read only
with Type Words Out off: with the timing an estimate, a word lit as it is typed in front of the
reader shows every miss. `/spoken player subtitle` switches to it; see
[`PLAYER-STYLES.md`](PLAYER-STYLES.md) for each style.

![Quest captions in the WoW Forever player](captions.png)

The screenshot above is from WoW Forever on Linux. The player confirmed the
layout and approximate timing in game. Other clients have not been checked
visually. The expanded view and zone/book captions still need an in-game visual check.

## Controls

- `/spoken transcript` turns the captions (Show Words) on and off; `on` and `off` also work.
- In the Small Window, the small **+** button expands the captions to eight lines, and **−**
  goes back to Lines Shown. The window grows downward and keeps its portrait in place.
- `/spoken transcript 1` sets Lines Shown to one line; `/spoken transcript 2` to two.
- `/spoken options` has settings for Lines Shown, Text Size, Highlight Words, Type Words Out,
  **Auto-Scroll** (below), and the subtitles' size and background.
- Scroll over the captions in a window to read back or ahead; they hold there. Click the
  text to follow the recording again. With Ctrl held the wheel sizes the window instead.
  Right-click opens the Small Window's menu, or the settings over the other windows. With
  **Type Words Out** on, a line the voice has not reached yet shows blank until it does; turn
  the setting off to read ahead.
- `/spoken transcript reset` restores the caption and subtitle defaults and
  moves the subtitles back to where they start.

## Auto-Scroll

How the captions in the window follow the voice:

| Mode | Behaviour |
|---|---|
| **Line by Line** (default) | The text glides up a line at a time as the voice reaches each line, about a quarter of a second per line, so there is no jump. The line being read is on the last row with **Type Words Out** on (below), and in the middle with it off, as synced-lyrics players (Apple Music, Spotify) keep the sung line. |
| **Page by Page** | A whole page turns when the voice reaches its end, as the captions always did. Closest to broadcast pop-on captions, which read best when the text should not move while it is read. |
| **Off** | The text holds still; the wheel moves it. Clicking the captions turns following back on, line by line. |

With **Type Words Out** on, the lines below the voice are still blank, so Line by Line keeps the
line being read on the last row instead, with what has been read above it, as roll-up broadcast
captions do. The glide needs the client to clip the captions' frame (`SetClipsChildren`); where it
cannot, the text steps a line at a time. While the text moves, a line partly past the top or bottom
edge fades by as much of it as is out of view, so lines fade out and in at the edges instead of
ending on a hard cut. The subtitles have an Auto-Scroll of their own, Page by Page or Line by
Line, and no Off: they cannot be scrolled by hand.

Stopping freezes the text. Replay restarts it with the recording. Skipping
shows the next clip's text, and a clip without text hides the captions.

## Settings language

Caption settings and tooltips follow the game client language. Translations cover
German, Spanish (EU and Latin America), French, Brazilian Portuguese, Russian,
Korean, Simplified Chinese and Traditional Chinese. English is the fallback.
The caption text itself follows the recording language.

## Timing and text

The sound packs have recording durations but no word timestamps. Timing is
estimated from word length, punctuation and the total duration. Two neighboring
words are highlighted to give the estimate some room. At the end of a page,
the previous word stays highlighted instead of advancing the page early.

A source that knows when each word is spoken passes `clip.present.timings`: one
start time per word, in seconds from the start of the recording, in the order
the captions cut the transcript into words: `Spoken:CaptionWords(transcript)`
returns those words, with the escape sequences the captions do not show
removed. The captions then follow those
times instead of the estimate, `Spoken:GetCaption()` reports them with
`timed = true`, and Subtitles Only turns each page when the voice reaches its
first word. A list whose length does not match the words, with a hole or a time
that is not a number, or whose times go backwards or past the recording's
length, is ignored and the estimate is used.

Captions use the text captured when a quest or gossip clip was queued. Quest
log replays can use the quest description. A completion recording never uses
the acceptance text as a substitute. Different quest wording and pauses in a
recording can still make the highlight drift.

Zone and subzone captions use the full lore in the actual voice language, including
English audio fallback. Book clips carry their own page text, so turning or closing
the book does not change the captions of a queued recording. The English addon
export includes every page. New book sound pack exports include the voice language's
text; older translated packs can caption pages opened during the current session.
Mail is excluded. Captions stay hidden when matching text is unavailable.

Other sources can supply `clip.present.transcript`; the player also accepts
`clip.text`. A source whose text is in a script the game's font cannot draw (Czech on a
Western client, for one) names a font file in `clip.present.font`. The captions, the subtitle
and every window then draw that clip's header, label and text in it, at the player's own size;
a clip without one stays in the player's font, and so does a file the client cannot load. Book captions are exported by `pipelines/books/tools/lib/lua.mjs`
using the same plain text conversion as narration. The current English export
was regenerated from the public `/api/books/search?lang=enUS` catalogue on
2026-09-27; page IDs, book order and lookup checksums are unchanged.

The DialogueUI window draws the captions in DialogueUI's font, size and colours, with an
empty line between paragraphs, at the player's Text Size and Lines Shown like the other
windows. See
[`PLAYER-STYLES.md`](PLAYER-STYLES.md).

## Captions in another window

`Spoken:GetCaption()` returns the clip, the words and the reading position the captions use,
and whether **Highlight Words** and **Type Words Out** are on. It stays current while the
captions are hidden or turned off. `Spoken:SplitCaption(text)` splits any text the way the
captions do, and records where each word sits in that text. With the two, another addon can
mark the same words in its own copy of the line. Spoken Quests does this inside DialogueUI's
window (see [`docs/quests/DIALOGUEUI-BRIDGE.md`](../quests/DIALOGUEUI-BRIDGE.md)), and Spoken
Readables in its book view. So **Show Words**, **Highlight Words** and **Type Words Out** apply to
DialogueUI's own text under every narrator style, Voice Only included; with DialogueUI installed
their tooltips say so, and `DialogueUIOptions:WordRowsShown` offers them under Voice Only.
**Type By** does not apply there: DialogueUI's text is typed by whole words.

## Checks

Run from the repository root:

```sh
make test-player
node scripts/check-addon-xml.mjs
make zones-check
make books-test
```

The caption suite is `tests/captions/verify.lua`. It runs the real queue,
player layouts, actions and quest adapter with simulated widgets and time.
It checks playback changes, page boundaries, Unicode, resizing, attachment,
queue placement, expansion and settings. The books and zones suites also cover
caption sources, language fallback and queued pages. The fixture models layout and text width; it
does not reproduce the game's font rendering or audio.
