# Premium UI: neutral surfaces, a hero Home, and cards that read like instruments

Date: 2026-10-08 · Status: approved in brainstorming, awaiting spec review

## Intent

**What the user said.** "The UI of the app looks horrible." Make xBot's UX/UI feel as premium as
four references they supplied (kept out of the repo — they show personal sidebars):

1. **MonoCode**, dark: a quiet two-level sidebar (search ⌘K, Inbox, Notes, Automations, sections),
   session cards, pill tabs, an agent header "Opus 5.5 worked for 41s", relaxed reply typography,
   hover actions under a reply, a composer with a context strip (checkout, branch) and chips.
2. **ChatGPT Work mode**, light: near-white surfaces, a Chat/Work segmented control, a centered
   "What should we work on?" over a large composer card with chips (Approve for me, model) and a
   strip under it (Choose project, Files, Plugins), suggestion rows.
3. **An agent workspace app**, light: workspace switcher, icon-led nav (New, Agents, Inbox,
   Activity), Projects and Recents sections, a hero "What are we working on today?" with four
   suggestion cards, a composer with a context strip ("Bruno") and a Chat/Test switch.
4. **A dashboard home** (dark, illustrated header) and a **Cal-style knowledge base card**
   (video): title + quiet subtitle + mono uppercase metadata ("4,812 CHUNKS"), an inset
   illustration panel, rows with mono counts and tinted status pills ("● CONNECTED", "● SYNCING"
   with a progress hairline), a mono footer ("4 SOURCES · 4,812 CHUNKS · IN SYNC"), dark toasts.

**Decided in brainstorming.**

1. **Palette:** neutral surfaces, with sakura kept only as the single accent (and in the icon).
2. **Home:** a hero composer with suggestion cards (no dashboard yet).
3. **Approach A:** keep `NavigationSplitView` for structure and window behaviour; draw every
   visible surface with our own components. Rejected: fully custom chrome (re-implements what
   macOS does well) and restyling the stock list/toolbar (the source of today's generic look).

**Success.** Side by side with the references, xBot reads as the same class of product: quiet,
dense, typographically confident, with colour used only to mean something.

## 1. Design system

Replaces the sakura `Palette`, `AuroraBackground` and bubble tokens. All tokens resolve in light
and dark; views never name a value.

**Colour** (light / dark)

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `window` | `#F7F7F5` | `#1E1E1E` | content background |
| `sidebar` | `#F0F0EE` | `#191919` | sidebar; solid under Reduce Transparency |
| `raised` | `#FFFFFF` | `#262626` | cards, composer, selected tab, user message |
| `inset` | `#F2F2F0` | `#202020` | panels inside cards, code, context strip |
| `hairline` | black 8% | white 8% | borders, dividers |
| `hover` | black 4% | white 5% | row and button hover |
| `textPrimary` | `#1A1A1A` | `#ECECEC` | |
| `textSecondary` | `#1A1A1A` 60% | `#ECECEC` 60% | |
| `textTertiary` | `#1A1A1A` 40% | `#ECECEC` 40% | |
| `accent` | `#B65E8C` | `#D08AB0` | selection marker, send, focus ring, links, Plan chip on |
| `running` | `#2C6FD1` | `#4C90EE` | the step or tool in progress |
| `success` | `#2F9E5B` | `#4CB876` | done |
| `failure` | `#D0453E` | `#F07A72` | failed |
| `warning` | `#C98A1E` | `#E8A845` | |

Each state colour has a pill pair: background at 12% (dark: 18%) of the colour, text the colour.

**Type** — SF Pro; SF Mono for metadata.

| Token | Spec | Use |
| --- | --- | --- |
| `hero` | 26 semibold, tracking −0.4 | Home headline |
| `title` | 15 semibold, −0.2 | card titles, chat title |
| `body` | 13 regular | UI text |
| `reading` | 13.5 regular, line spacing 4 | replies |
| `emphasis` | 13 medium | |
| `caption` | 11 regular, +0.1 | secondary lines |
| `label` | 10 medium SF Mono, uppercase, +0.6 | metadata, status pills |
| `mono` | 12 SF Mono | paths, commands, code |

**Shape and depth.** Radii 6 (rows, chips), 10 (inset panels), 14 (cards, composer), capsule
(pills, tabs, primary button). Cards: hairline border + shadow y1 blur3 6%. Floating (composer,
toasts): y8 blur24 10%. No gradients; `AuroraBackground` is deleted.

**Components** (`XBotUI/Components/`), each owning its hover, focus and accessibility:
- `Card(title:subtitle:meta:) { body } footer: { … }` and `InsetPanel { … }`
- `Chip(label:systemImage:isOn:)` — quiet rounded control; `.menu` variant with a chevron
- `StatusPill(_ state: PillState, text:)` — mono caps with a dot, tinted per state
- `MonoLabel(_:)`
- `IconButton(systemImage:help:action:)` — 28pt, hover fill
- `PrimaryButton` (black capsule; white in dark) and `QuietButton`
- `SidebarRow(icon:title:trailing:isSelected:)`
- `PillTabs`
- `Toast` and a `ToastCenter` (observable queue)

## 2. Window and sidebar

**Window.** Hidden title bar (`.windowStyle(.hiddenTitleBar)`, full-size content); the traffic
lights float over the sidebar. A 44pt top bar on the content side holds the open chats as pill
tabs (selected tab on `raised`; a running chat shows a spinner instead of its icon; × on hover)
and, right-aligned, the chat's context as a mono label ("XBOT › MASTER"). No toolbar chrome.

**Sidebar** — 240pt (200–320), collapsible (⌘⌃S):
1. Header: app mark + "xBot"; an `IconButton` for a new chat (⌘N → Home).
2. Search field with a "⌘K" hint; ⌘K focuses it; typing filters chats by title (case- and
   diacritic-insensitive); Escape clears.
3. Nav: **Home**, **Inbox** (count of Inbox chats). Nothing that does not work yet appears.
4. **Projects** — header with a hover "+" (add folder). A project row: folder icon, name, a dot
   while any chat in it runs; it expands to its chats (newest first, at most 5, then "Show all N").
   Chat rows: title; relative time on hover; spinner while running. Context menu: Rename, Delete,
   Show in Finder (project).
5. **Recent** — the 5 most recently updated chats across everything.
6. Footer: found agents as status dots ("● Claude Code ● Codex"), or "No agent found" with
   **Look again**.

Rows: 28pt, 6pt radius, tertiary icon, `hover` on pointer-over, selection = `raised` fill +
semibold. Section headers: caption, secondary, hover-revealed "+".

## 3. Home and the composer

**Home** (launch, ⌘N, the Home row): centered a little above middle — "What should we work on?"
(`hero`), the composer (max 680pt), and four suggestion cards in a row:
- "Plan a change / from an idea" — turns Plan on, focuses the input
- "Explain / this project" — fills "Explain how this project is put together."
- "Find and fix / a bug" — fills "Find the bug: "
- "Write tests / for recent changes" — fills "Write tests for the most recent changes."

Cards: `raised`, hairline, an accent-tinted SF Symbol, two lines (second secondary). Click fills
the composer; nothing sends without the person. Sending from Home creates the chat in the chosen
project, opens it, and the composer glides to its docked place (`matchedGeometryEffect`;
cross-fade under Reduce Motion).

**Composer** (one view; Home and docked):
- **Context strip** — an `inset` band attached to the top of the card: folder icon + project menu
  (Inbox, each project, "Add a folder…"); the git branch in mono when the folder is a repo; at the
  right, the found agents' marks.
- **Input** — up to 10 lines; placeholder by mode: "Describe a task, a bug to fix, an idea to
  try…" / "Describe the change. You'll review the plan first." / "Describe the change. The plan
  runs straight away."
- **Chips** — agent + model in one chip ("● Claude Code · Opus ⌄"); permission ("✎ Can edit ⌄");
  **Plan** toggle chip (accent tint when on; its menu holds "Review plan first").
- **Send** — 30pt circle, `accent` with text, `hover` grey when empty; a stop square while the
  chat runs (⌘. too).
- Card: `raised`, 14pt, hairline, floating shadow; focus turns the border accent at 40%.

The chat's project is fixed once it exists; on Home the strip chooses it.

## 4. Chat, cards, toasts, motion

**Transcript** — a centered 720pt column.
- **Person:** right-aligned, `raised` fill, 14pt radius, `body` text.
- **Agent:** no bubble. A header line "● Claude Code worked for 41s" (agent dot, `caption`
  secondary; the time from the person's message to the reply's end; "working…" with a spinner
  while live). Reply in `reading`. Markdown blocks: headings (`#`, `##`, `###` → title / emphasis),
  bulleted and numbered lists with hanging indents, inline code as `inset` chips, fenced code as an
  `InsetPanel` with `mono` and Copy on hover.
- **Tools** fold into one row: "Read 3 files, ran a command ⌄" (`ToolLabel.summary`), expanding to
  `ToolLine`s; while live, the running tool shows under it with a spinner.
- Hover under a reply: Copy, and the time.
- **Failure:** a `failure`-tinted inline callout with an icon, the reason, and Retry when the turn
  can be repeated.

**Plan cards** become `Card`s:
- Review: title "Review the plan", subtitle "Edit, reorder or remove steps…", meta "6 STEPS";
  steps inside an `InsetPanel`; footer meta "READ-ONLY PLANNING", Cancel (`QuietButton`) and
  **Run plan ⌘↩** (`PrimaryButton`).
- Tasks: title "Tasks", meta "3 OF 7 DONE · 1 FAILED"; progress hairline under the header (accent;
  failure once anything failed); rows with `StatusPill`s where the recording had text states
  ("● ADDED" on added steps); footer meta "RUNNING · 26S" / "FINISHED · 1 FAILED".

**Toasts** — dark capsules, bottom centre, 3 s (5 s with an action): "✓ Plan finished · 9 steps",
"Chat deleted · Undo" (restores the chat and its messages), "xBot couldn't save …". Deleting a chat
no longer asks first; the Undo is the safety. CLAUDE.md's invariant 6 changes to match: deleting a
bot (its computer) is confirmed; deleting a chat is undoable instead.

**Motion** — existing spring tokens; hover is immediate; tabs and rows reposition with
`Motion.reposition`; the composer glide uses `Motion.panel`. Reduce Motion → cross-fades; Reduce
Transparency → solid sidebar.

## Out of scope

Notes, Automations, Settings and the dashboard home (they arrive with their sub-projects and will
use these components); the Chat/Work switch (xBot has one mode).

## Testing

Unit tests for the logic the UI adds:
- `SidebarModel`: projects with their 5 newest chats and the overflow count, Recent (5 newest
  overall), search filtering (case- and diacritic-insensitive), Inbox count.
- "Worked for": duration from the person's message to the reply.
- Markdown blocks: headings, bulleted and numbered lists, fenced code, unterminated fences.
- `ToastCenter`: queueing, expiry, and the delete-undo window restoring chat and messages
  (`Workspace.deleteChat` → `restoreChat`).

Views: offscreen renders of Home, a chat with tools and code, the review and Tasks cards, and the
sidebar, in light and dark, compared with the references; then the person checks the real app.
