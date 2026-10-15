# Narrator styles

How Spoken shows the line it is reading is one setting, **Narrator Style** (`Frame.Style`):
`"subtitle"` (Subtitles Only, the default on the modern clients), `"minimal"` (Small Window),
`"classic"` (Large Window, the legacy clients' default), `"dialogueui"` (with the DialogueUI addon
installed) or `"none"` (Voice Only). They are tiles on Spoken's settings page and in the welcome
window, in that order, and `/spoken player <style>` switches between them, saying why when it
cannot. `Addon:PlayerStyle()` answers what is drawn where the chosen style is not on offer:
`"dialogueui"` is drawn as the Small Window while DialogueUI is missing, and the setting is kept,
so the window comes back with DialogueUI. The setting replaced three switches, `SubtitlePlayer`,
`HideFrame` and `MinimalPlayer`; `Addon:InitDB` carries a profile that set them over to the style
they showed, and removes them.

## What every style shares

- **Controls.** Stop, which turns to Replay once the line is stopped, Skip, and the line's own
  actions (Report, where its module offers it, unless Hide Report Buttons is on), as the round
  buttons of `addons/Spoken/UI/Actions.lua`. The game cannot start a sound part-way through, so
  there is Stop and Replay, never Pause and Resume.
- **After the line's title**: why the line waits, when the queue holds it back ("(Waiting for
  combat to end.)", "(Waiting for the NPC to finish speaking.)"), "(Stopped)" while it is stopped,
  and "+N", the lines waiting behind it. Pointing at "+N" lists them, each with who says it
  (`Actions.WaitingHover`); clicking it does nothing.
- **The face** (`addons/Spoken/UI/Face.lua`): the speaker's still portrait, captured from their
  unit or drawn from their creature (`StaticPortrait.lua`), else the line's own picture, cut
  round, with the line's badge on a dark disc at its lower right. A creature the client has not
  cached shows the book until it comes. The Large Window draws a 3D model instead.
- **Show Progress**: a progress line under the words.
- **Lock Position**: the windows and the subtitles cannot be dragged or resized, and clicks on
  them pass through to the game; their buttons still work. **Reset Positions** forgets the places
  saved for every window and the subtitles.
- **Ctrl and the mouse wheel** over the Small Window, the DialogueUI window or the subtitles step
  their size (Window Size, or Subtitle Size) by 5%; Ctrl, Shift and the wheel step Text Size by 1.
  Both stay within their sliders' ranges (`SIZES` in `Core.lua`), show the new value in a tooltip,
  and do nothing while Lock Position is on. The windows' words pass a Ctrl wheel on to the window
  (`frame.spokenWheel`) and scroll without it.
- **Bronze Border**, on Forever: the round buttons' rings, the faces' rings, the Large Window's
  mover ring and the Small Window's border, progress line and right-click menu in the bronze
  Forever's own frames wear (`Actions.Bronze`).
- **Preview** on Spoken's page shows the chosen style with a sample line while no line plays,
  until it is turned off.
- With a DialogueUI dialog open, the windows step aside unless Spoken Quests' **Show Spoken Over
  DialogueUI** hosts them on it (`Actions.DialogCovers`, `Addon:ApplyHost`).

## Subtitles Only

`addons/Spoken/UI/Subtitle.lua`. No window: the speaker's face, name and the line's title in a
row, the words under it, low in the middle of the screen over a soft shadow (Background
Darkness). The words come from the captions (`Transcript.lua`), so Stop, Replay and Skip behave
as they do in the windows.

- **Auto-Scroll** for the subtitles is Page by Page (the default) or Line by Line. Page by page,
  a page holds Sentences at Once whole sentences (1 to 4) and never more than four lines; a page
  fades out before the next fades in, turned when the voice reaches it. Line by line, the words
  glide up through Lines Shown lines.
- **Type Words Out** types each page in a little ahead of the voice, by letter or by word (Type
  By). **Highlight Words** lights the word being read only while the words show whole, Type Words
  Out off: an estimated timing lit as it is typed in front of the reader shows every miss.
- **Show Name and Title** off leaves the row out; it still says "(Stopped)" or why a line waits.
- The words do nothing when clicked, and there is no right-click menu: a subtitle in the middle
  of the screen is clicked by accident, and a right-drag there is the camera turning. Stop or
  Replay, Skip and Report fade in under it while the pointer is over it.
- Dragged, it moves up and down only, staying on the screen's centre line. It takes the mouse
  wheel only while Ctrl is held over it, so the wheel otherwise zooms the camera.
- It shows once the voice has begun, or while the line is stopped or held back, so that it can
  say why nothing is being read.

## Small Window

`addons/Spoken/UI/MinimalPlayer.lua`, contributed as Minimal Classic: see
[`docs/minimal-classic/`](../minimal-classic/README.md). The face beside a panel with the speaker's
name over the line's title, the controls at the header's right, then Lines Shown of the words
(the + button expands them to eight) and the progress line.

- **Background**: Parchment, with dark words (the default), or Dark, with light words.
- **Hide Portrait** leaves the face out.
- Right-click opens a menu: Stop or Replay, Skip Line, Stop All, Settings, and the line's actions
  that name themselves.
- Dragged by the panel or the name; the grabber at the lower right, shown under the pointer while
  unlocked, sets its width. It fades in and out, and out and in again from one line to the next.
- Not on the 1.12, 2.4.3 and 3.3.5 clients.

## Large Window

`addons/Spoken/UI/PlayerFrame.lua`, which also routes every refresh to the style in use. The
game's Talking Head frame where the client has its art (Spoken's own art elsewhere): a bigger
portrait drawn as a 3D model, the speaker's name, up to three lines of the words, the controls at
the top right and the progress line. It is dragged by the ring at the portrait's lower left, and
it fades as the Small Window does. It is the only window the 1.12, 2.4.3 and 3.3.5 clients have.

## DialogueUI

With the [DialogueUI](https://www.curseforge.com/wow/addons/dialogueui) addon installed, a smaller
twin of DialogueUI's quest window, in DialogueUI's own art. Without DialogueUI there is no tile.
`/spoken diagnostics` adds a `dialogueui:` line with what was read from DialogueUI.

### The window

A parchment, or dark, panel in DialogueUI's proportions, showing only the line playing:

- DialogueUI's own header strip, with the speaker's face in its socket, the line's title beside it
  in DialogueUI's title type and the speaker's name small above, then why the line waits,
  "(Stopped)" and "+N";
- Stop (Replay once stopped), Skip and the line's own actions, Report among them, at the header's
  right end;
- a place's picture over the words, as Place Lore draws it;
- Lines Shown of the words, in DialogueUI's paragraph font, with an empty line between
  paragraphs, and the progress line under them.

There is no scrollbar: the words follow the caption **Auto-Scroll** mode, and the wheel scrolls
them. Right-click opens the settings. Drag anywhere to move it; it then keeps its own saved place,
apart from the other windows'. Unmoved, or after Reset Positions, it rests at the screen's top
left, out of the next dialog's way. Sizing it with Ctrl and the wheel is not a move: it keeps its
top-left corner.

Every fade is of the window as one image (a frame buffer), and nothing in it may change while it
is one: changing anything inside a frame buffer crashes the Forever client. So while it is, it is
deaf to the pointer, the captions are held, and its own updates wait (`Skin:Buffer`, `Unbuffer`,
`Defer`).

`addons/Spoken/UI/DialogueUITransitions.lua` moves it to and from DialogueUI's dialogs. When
DialogueUI's window closes on a line that plays on, the dialog's words fade first, then this
window slides and shrinks out of it to where it rests. A dialog that closes on a line it queued
behind another sends that line's page behind this window, and its count ripples.

Nothing is source-specific. A zone's lore or a book page plays in it as a quest line does: the
book for a face, the book's or the zone's name as the speaker, the page or the subzone as the
title, or the clip's key when there is none. A book's page is drawn in DialogueUI's book art,
paper or stone by its material.

**Nothing of DialogueUI is copied.** The panel loads DialogueUI's texture files
(`Interface/AddOns/DialogueUI/Art/Theme_Brown/` or `Theme_Dark/`, and `Art/Book/` for books) and
asks DialogueUI's font objects which font they write in. That is why the style exists only with
DialogueUI installed.

### Its settings

It follows the player's own settings on Spoken's page, as the other windows do:

- **Window Size** scales the whole panel, text included. The panel is laid out exactly as
  DialogueUI's window, at its size, paddings, text size (its Font Size setting), line spacing
  (0.35 of the text size) and paragraph gap. At the default Window Size (70%) it is 65% of
  DialogueUI's window; the size scales from there.
- **Text Size** sets the words against DialogueUI's: at the default 16 they are DialogueUI's
  size, at 24 half as large again. The line spacing follows the text; the header and buttons
  stay with the panel.
- **Lines Shown**: 1 or 2 lines of the words. It has no expand button and no resize handle, and
  the other windows' expand state (`CaptionsExpanded`) does not change it.

What only this window has is on Spoken's page, among the other styles' settings, built only with
DialogueUI installed (`addons/Spoken/UI/DialogueUIOptions.lua`) and shown while this style is
chosen: the theme under Look and Fit to the Words under Words. After the narrator style's
settings comes a section from each module that registered one with
`Spoken:AddDialogueUISettings(build)`, shown under every style since it changes DialogueUI's own
window: Spoken Quests puts its DialogueUI switches there (see
[`docs/quests/DIALOGUEUI-BRIDGE.md`](../quests/DIALOGUEUI-BRIDGE.md)). Spoken's Start Over puts all
of them back.

- **Follow DialogueUI's Theme** (on): parchment or dark, whichever DialogueUI is set to,
  switching the moment DialogueUI does. Off, **Theme** picks one for good.
- **Fit to the Words** (on): the panel is only as tall as the line's words need, Lines Shown
  being the most it grows to; a long line scrolls. Off, it always shows Lines Shown.

The highlight on the words being read is deep red on parchment and gold on dark, the same pair
Spoken Quests lights DialogueUI's own text with.

### Over DialogueUI

With Spoken Quests' **Show Spoken Over DialogueUI** on, whichever style is chosen is hosted on
DialogueUI's window while it is open and comes back afterwards: see
[`docs/quests/DIALOGUEUI-BRIDGE.md`](../quests/DIALOGUEUI-BRIDGE.md). The DialogueUI window keeps
its size on screen there, as the others do.

### What it reads, and what happens if DialogueUI changes

Nothing it reads is a public API, and each is checked before use:

- `addons/Spoken/UI/DialogueUITheme.lua`: the saved variables `DialogueUI_DB` (`Theme`,
  `FrameSize`, `MobileDeviceMode`); the window `DUIQuestFrame` (`frameWidth`, `frameHeight`,
  `Parchments`, and its `LoadTheme` and `UpdateFrameSize` methods, hooked to follow changes); the
  font objects `DUIFont_Quest_Paragraph`, `DUIFont_Quest_Title_18` and `DUIFont_QuestType_Left`.
- `DialogueUIPlayer.lua` and `DialogueUITransitions.lua`: whether `DUIQuestFrame` and
  `DUIBookFrame` are shown, watched by a child of each; their `Hide` and `ShowUI`, wrapped so the
  dialog's words fade before it closes; `DUIQuestFrame:GetQuestFinishedDelay()`; the dialogs'
  `BackgroundFrame`, `Footer` and place on screen; DialogueUI's art files.
- `Actions.lua`: whether either dialog is shown (`Actions.DialogCovers`, `Actions.WatchDialogs`),
  and the Play, Skip and Report row Spoken Quests and Spoken Readables put on the dialogs
  (`Spoken:CreateDialogueUIRow`).

If a DialogueUI release renames them, the tile is not offered, `/spoken player dialogueui` says
the version is not recognised, and a profile set to it is drawn as the Small Window; nothing
errors. The window size has a fallback computed the way DialogueUI computes its own.

Tests: `tests/lua/player_dialogueui_style_test.lua`, against a fake DialogueUI.

## Voice Only

Nothing of Spoken's on screen: the lines are only heard. The window and subtitle settings are
hidden, and so is Show Spoken Over DialogueUI. With DialogueUI installed, Show Words, Highlight
Words and Type Words Out still mark DialogueUI's own quest, gossip and book text
(`Spoken:GetCaption`), so the settings page can offer them under this style too
(`DialogueUIOptions:WordRowsShown`).
