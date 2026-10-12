# UI specification

Every screen of the Mac app and of the iPhone and iPad app, as they are built today. The Mac app's
views live in `apps/mac/Sources/XBotUI`; the phone's in `apps/ios/Sources`. **The code is the source
of truth.** Where this document and the code disagree, the code wins, and this document is wrong.

Nothing here is a plan. Features the redesign still owes — a bot's own computer, the native brain,
checkpoints, worktrees, split panes, the Quick Composer, onboarding — are in the
[redesign spec](superpowers/specs/2026-10-06-xbot-redesign-design.md) and the
[roadmap](12-roadmap.md), not here.

Two rules run through every screen:

- **Every empty state is a sentence and, where there is one, an action.** Never "No items".
- **A control revealed on hover is faded, not absent**, so VoiceOver and the keyboard can still
  reach it. Copy buttons on code blocks, the × on tabs and the actions under messages all work this
  way.

---

# The Mac app

## The window

One window (`Window("xBot", id: "main")`), default 1280 × 820, minimum 900 × 600. The title bar
is hidden: content runs to the top edge, the traffic lights float over the sidebar, and the strip
of chat tabs is the title bar row. The window moves only from its drag areas — the empty parts of
the sidebar's title row, the tab strip and the inspector's header.

```
┌──────────────┬───────────────────────────────────────────────┬────────────────┐
│ ● ● ●   ◧  ✎ │  × ☺ Fix login ⌘1 │ ☺ Notes ⌘2 │ +          ◨ │ Explorer +12 −3 │
│ 🔍 Search ⌘K ├───────────────────────────────────────────────┤                │
│ Abilities    │                                               │  Changes       │
│ Notes        │            Home, a chat, or a page            │  or            │
│ Automations  │                                               │  Explorer      │
│ ░ Agents ░░░ │                                               │                │
│ Projects  +  │                                               │  260–420 pt    │
│ Recent       │  ┌─ composer ───────────────────────────┐     │  drag to       │
│ ─────────────│  └──────────────────────────────────────┘     │  resize        │
│ ◉ Your name ⇕│                                               │                │
└──────────────┴───────────────────────────────────────────────┴────────────────┘
  220–340 pt
```

Behind Home and chats sits the wallpaper chosen in Settings › Appearance: full strength on Home,
softer behind a conversation. The Agents page draws its own world instead.

If the library on disk cannot be opened, xBot runs on one in memory and a red strip across the top
of the content says so: *"xBot couldn't open its library, so this session won't be saved."*

### Pages

The content area shows one of these at a time.

| Page | Reached from | Tab strip shown |
| --- | --- | --- |
| Home (a new chat before its first message) | ⌘N, ✎ in the sidebar, + in the tab strip | yes |
| A chat | a tab, the sidebar, ⌘1…⌘9 | yes |
| A file's diff | a changed file in the inspector | yes |
| Profile | the account menu | yes |
| Abilities, Notes, Automations | the sidebar | no |
| Agents | the sidebar's miniature world | no |

Notes and Automations run to the top of the window; the inspector button floats over their
top-right corner.

### The tab strip

Open chats are tabs, in the title bar row.

- Each tab shows the chat's agent face (or a coloured dot for the CLI; a spinner while it works),
  its title, and `⌘1`…`⌘9` for the first nine.
- The selected tab is a soft translucent segment, and only while that chat is what the window
  shows — not under Abilities or Notes.
- **×** appears on hover at the tab's leading edge. It is laid over the tab rather than inside it,
  so closing never also reopens the chat.
- **Drag a tab** along the strip to reorder it. Neighbours slide aside as its middle passes theirs;
  a few points of travel are needed first, so a click still just selects.
- A new chat waiting for its first message is a tab of its own, **New chat**.
- **+** starts a new chat in the current chat's project.
- At the right end, **◨** toggles the inspector (⌥⌘0). With no project in view it is disabled and
  says *"Choose a project to see its files and changes."*
- With the sidebar hidden, the traffic lights sit at the strip's left with a button to show the
  sidebar again (⌃⌘S).

## The sidebar

Top to bottom:

1. **Title row** — hide sidebar (⌃⌘S) and new chat (⌘N).
2. **Search** (⌘K). Filters chats by title, hiding projects with no match; Escape clears it.
3. **Abilities**, **Notes**, **Automations**. Automations shows a spinner while one is running.
4. **Agents** — a miniature of the crew's world (hidden while searching). See below.
5. **Projects**, with **+** to add a folder. With none, an **Add a folder** row. Each project is a
   folder row with a dot while any of its chats is working; click to fold it. Long lists end in
   **Show all N**. Right-click: **New Chat**, **Show in Finder**, **Remove from xBot**.
6. **Recent** — chats outside any project, with **Show all N** / **Show less**.
7. **Account button** — your picture and name, bottom-anchored.

An automation's runs are not listed here; they are on its page. A chat row shows the agent's face
(animated while working). Right-click: **Rename** (in place; Return saves, Escape cancels) and
**Delete Chat**, which deletes at once and shows a toast with **Undo** rather than asking first.

### The agents miniature

The same scenery as the Agents page, scaled to a strip and dimmed, with the crew's faces in one row
over it.

- The header reads **Agents**, plus **N working** when anyone is.
- A face opens that member's latest chat. Its tooltip is the member's name and what they are doing,
  *"Done — tap to read"*, or their role.
- **+** opens the hiring sheet on the Agents page.
- Anywhere else on the strip opens the Agents page.

## Home

A new chat before its first message is the composer on its own, centred. There are no greeting or
suggestion cards; they were taken out.

With no agent CLI found, Home says instead:

> **xBot works through an agent you already have.**
> Install Claude Code or Codex and sign in, then come back. xBot will find it.

with links **Get Claude Code** and **Get Codex**, and **Look again**.

## The composer

One composer, used on Home (where it writes the draft) and docked under a chat.

```
┌──────────────────────────────────────────────────────────────┐
│ 📁 xbot ⌄   ⑂ main                                  ● ● ●     │  context strip
├──────────────────────────────────────────────────────────────┤
│ Describe a task, a bug to fix, an idea to try…               │
│                                                              │
│ ● Claude Code · Opus ⌄  🧠 Medium ⌄  ✎ Can edit ⌄  ▤ Plan   ⬆ │
└──────────────────────────────────────────────────────────────┘
```

- **Context strip** — the project menu (*No project*, each project, *Add a folder…*), the branch,
  and a coloured dot for each installed CLI. The project can be changed only before anything has
  been said in the chat.
- **Text** grows to ten lines. ⏎ sends. A refused send keeps what was typed.
- **Agent chip** — CLI and model, grouped by CLI, each with *Default model*. Locked while a turn
  runs.
- **Effort chip** — opens a card: *Effort · Medium*, a slider from *Faster* to *Smarter* with six
  stops (Low, Medium, High, Extra, Max, Galaxy), the agent's recommended stop marked
  *Recommended*. ← and → move it. At **Galaxy** the track fills with shimmering pixels and the knob
  radiates (still under Reduce Motion). The help reads: *"Galaxy is the most the agent can do:
  Claude Code at max on Opus, Codex at its ultra level."*
- **Permission chip** — **Read only** (eye), **Can edit** (pencil), **Full access** (bolt). For
  Antigravity the menu adds that it can only edit with full access, so "Can edit" runs with full
  access.
- **Plan chip** — click to turn plan mode on or off; its menu holds **Review plan first**. With
  review off the chip reads *Plan · runs at once*. For CLIs that cannot make plans in xBot
  (Antigravity, Copilot) the chip is dimmed with that reason.
- **Send** is ⬆ in the accent; while a turn runs it becomes ■ (⌘.).
- A reason, when sending is blocked, sits beside Send: *"No agent found"*,
  *"Looking for Codex…"*, *"Codex isn't installed on this Mac any more."*

The placeholder changes with the mode: *"Describe a task, a bug to fix, an idea to try…"*;
*"Ask Forge…"* in a crew member's chat; *"Describe the change. You'll review the plan first."* or
*"…The plan runs straight away."* in plan mode.

A file dropped on the composer, or mentioned from the explorer, is added as `@path`.

## A chat

The transcript is centred at reading width, anchored to the bottom, with the composer under it.

**An empty chat with a crew member** shows them standing there with their name and role, and
*"Tell Forge what you need."* — for HeadMaster, *"Big things get planned and shared out to the
crew."*

**Your messages** are right-aligned on a raised fill, selectable. On hover: the time, **Copy
message**, and **Edit and send again**, which opens the bubble in place (Escape cancels). Editing
replaces that turn and everything after it, and a toast offers **Undo**. Not offered while the chat
is busy.

**Replies** are under a header — the member's face or the CLI's dot, then *"Forge is working…"*
live or *"Forge worked for 41s"* when done. The body is:

| Part | Rendering |
| --- | --- |
| Text | Markdown. Code blocks with syntax highlighting and a copy button |
| Shell code block | The same, plus **Run**, which sends it to this chat's terminal (*"Sent to terminal"*) |
| Tools | One folded line — *"Read 3 files, ran a command"* — that opens to every tool with its target, size and time. While live, the running tool shows under the fold |
| Hand-off | A card with the member's face: *"Handed to Forge"* or *"Forge finished"*, a line of the task, and **Open** |
| Notice | A quiet caption line |
| Failure | A red callout with the reason and, on the last reply only, **Retry** |

On hover under a reply: **Copy reply** and the time. **Stop** (⌘.) keeps whatever had arrived.

### Plan mode

With plan mode on, the agent first plans read-only, then each step runs as its own turn.

1. **Planning…** (*Read-only*) — what it is reading, live, or *"Looking around the project"*.
2. **Review the plan** — *"Here's my plan. Change anything you like, then run it."* Each step is an
   editable line. ⌥↑/⌥↓ move a step, Return goes to the next (or adds one), Delete on an empty step
   removes it, × on hover removes it, **Add step** appends. The meta line counts steps or says
   *"Add a step to run."* Footer: **Cancel** and **Run plan** (⌘↩). With review off this card is
   skipped.
3. **Tasks** — *"On it. I'll keep this list updated as I go."* A progress bar (red if anything
   failed), *"3 of 7 done · 1 failed"*, the agent's latest note, and the steps. Pending steps are
   dashed circles (the next one solid), the running step shows its live tools and active wording,
   done steps are struck through, failed steps show their note. Steps the agent added mid-run sit
   on a soft panel with an **Added** pill while the plan runs. Three or more finished steps above
   the running one fold into *"N completed"*. Each finished step opens to its tools. The footer
   shows *Running*, *Finished · 2 added* or *Stopped*, the elapsed time, and hide/show steps.
4. **The closing sentence** — the agent's summary, under the card.

Under the latest plan, above the composer, a status pill reads *Finished*, *Finished · 1 failed*
or *Stopped*; a stopped plan has **Resume**. A planning turn that produced no steps shows **No
plan** with the reason and **Try again**. A cancelled plan leaves *"Plan cancelled"*. When a plan
finishes, a toast says *"Plan finished · N steps"*.

## The inspector: files and changes

A column on the right for the project in view (the open chat's, or the draft's). ⌥⌘0 or ◨ toggles
it; drag its left hairline to resize between 260 and 420 pt. Its header has two segments,
**Explorer** and the change totals themselves, **+372 −33**, which is the Changes tab.

If git is missing: *"Git isn't installed on this Mac."* with **Install Command Line Tools**, which
opens Apple's own installer.

### Changes

- **Header** — *Changes*, the branch, ↓behind ↑ahead, a spinner while busy, and a ⋯ menu with
  **Fetch Now** and **Open on GitHub**. A quiet fetch also runs every five minutes while the column
  is open.
- **State** — one pill and one sentence: *Up to date* ("Nothing to commit. In step with
  origin/main."), *Changes*, *To push*, *To pull*, *Diverged* ("Pull before you push…"),
  *Conflict*, or *Local* ("This branch isn't on a remote yet.") with **Publish Branch**.
- **Pull request** (through `gh`) — *PR #42 · open*, its review state, and a checks pill
  (*Passing*, *Failing*, *Running*). Click opens it.
- **Problems** from git, in red monospace, dismissable.
- **Commit box** — *Message (⌘↩ to commit)*, **Commit**, and **Sync Changes ↓n ↑n** (or **Publish
  Branch** with no upstream).
- **Merge needed** — *"Your branch and the remote both have new commits. They need merging before
  you can push."* with **Ask the agent to merge**, which sends a merge request to the open chat or
  puts it in Home's composer. Conflicts are explained here, never resolved here.
- **Changed files** — icon, name, folder, and the git letter (M/R amber, A/U green, D/C red;
  deleted names struck through). On hover: **Stage**/**Unstage** and **Discard Changes**, which asks
  first (*"This can't be undone."*). Click opens the diff.

**The diff** replaces the content area: the path and letter on top, a unified diff with both
sides' line numbers, additions and removals tinted, hunks on an inset band. *"No changes to show."*
when empty. × or Escape closes it.

### Explorer

The project's files as a tree that loads folders as they open. Names are coloured by their git
letter; ignored files are dimmed and italic; deleted files stay listed, struck through.

- Header buttons: **New File**, **New Folder** (created beside the selection with a free name, then
  renamed in place), **Collapse All**, **Filter** (by name, among folders already read; Escape
  closes).
- Click a file to preview it with Quick Look; double-click opens it in its app. Files can be
  dragged out, or onto the composer.
- Right-click: **Mention in Chat**, **Reveal in Finder**, **Copy Path**, **Rename**, **Move to
  Trash** (with a toast).

## The terminal

Each chat has its own terminal window, floating over the chat's right side. The **terminal button**
at the chat's bottom-right shows or hides it (⌃`) and counts its tabs. **Run** on a shell code
block sends the command there.

- The window has a tab strip like the main one: a tab per shell, titled with the end of the shell's
  path (or *Terminal N*), × on hover (*"Close tab (ends its shell)"*), drag to reorder, **+** for
  another shell, **–** to hide.
- The empty part of the strip moves the window; the left, right and bottom edges and bottom corners
  resize it (minimum 340 × 200). It is kept where its strip can still be grabbed.
- A shell that exits on its own closes its tab.
- Shells are real login shells, drawn by SwiftTerm.

## Abilities

*"Connectors, plugins, skills and MCP servers your agents can use."* Everything here is read from,
and changed through, Claude Code's and Codex's own CLIs.

- **Tabs**: Connectors, Plugins, Skills, MCPs, each with a count (a spinner while loading), and a
  search field for the current tab.
- **Rows**: icon, title, source, summary, and the agent that uses it. At the end, a switch where
  the CLI allows turning it on and off; otherwise a status pill (*Connected*, *Sign in*, *Failed*,
  *Pending*), *On*/*Off*, or a lock with the reason. A ⋯ menu on hover offers **Show in Finder**
  and **Remove…**, which says what removal means (a skill's folder goes to the Trash; a plugin is
  uninstalled by its CLI; a server is forgotten).
- **Browse** opens the plugin marketplaces: filter by agent (All, Claude Code, Codex), search, and
  **Install**. Over 300 results asks you to search.
- **Add** ▾ — **MCP Server…** (name; connects by Command or URL; which agents to add it to),
  **Skill Folder…** for a chosen agent, **Plugin from a Marketplace…**.
- Connectors are claude.ai's; the tab links to **Manage connectors on claude.ai**.
- If one of the two CLIs is missing: *"Codex isn't installed, so its abilities aren't shown."*

Empty tabs: *"No claude.ai connectors yet…"* with **Open claude.ai**; *"No plugins installed."*
with **Browse plugins**; *"No skills yet."*; *"No MCP servers yet."* with **Add an MCP server**.

## Notes

A project's ideas and release notes, as Markdown files in `<project>/notes/`.

- **Left**: a project menu, **New note**, the notes newest first with their age, and the footer
  *"In xbot/notes — part of the project, so agents can read them."* Right-click a note: **Show in
  Finder**, **Delete**.
- **Right**: **Edit** / **Preview** (rendered Markdown), *Editing…* or *Saved*, and delete. A note
  saves 0.7 s after typing stops and on leaving. Deleting shows a toast with **Undo**.
- The folder is re-read every three seconds, so a note an agent writes appears.

With no project: *"Notes belong to a project."* and **Add a project**. With no note selected:
*"Ideas, plans, the next release notes — in whatever shape they're in."* and **New note**.

## Automations

A trigger, then steps in plain words, carried out by an agent with full access.

- **Left**: the list (a clock for scheduled ones, a spinner while running, *off* when switched off),
  **+**, and at the foot **Run when xBot is closed**. Off (the default), *"Scheduled automations run
  while xBot is open."* On installs a background helper: *"A small background helper checks every
  minute and runs what's due."*
- **Editor**:
  - The name, an on/off switch, ⋯ › **Delete…** (*"Its past runs stay as chats."*) and **Run now**.
  - The agent/model chip, the project chip, a warning label **Full access**, and *Next: …* when
    scheduled.
  - **WHEN** — *When I press Run now*, *Every hour* at a minute (five-minute steps), *Every day*,
    *Every weekday* or *Every week* (a weekday) at a time.
  - **STEPS** — numbered cards, each an app's icon and a field with a hint for that app (*"e.g. Find
    unread mail from today and summarise it"*). Drag to reorder; × on hover removes. A dashed drop
    zone at the end: *"Drag an app or connector here for the first step"*.
  - **RUNS** — the last twenty, each a chat: running, *Failed*, or *Open*.
- **Right**: the palette — **APPS** (Mail, Calendar, Reminders, Notes, Messages, Contacts, Finder,
  Safari, Music, Photos, Maps, Shortcuts, Terminal, Web, Anything) and **CONNECTORS** (the enabled
  connectors and MCP servers from Abilities; *"None yet. Add them in Abilities."*). Drag a tile
  into the steps, or click to add it at the end.

Empty: *"Automate anything you do on your Mac"* and **New automation**.

## Agents

The crew, as a company, in a living pixel world.

**Header**: *"Your crew, as a company: HeadMaster on top, each team under its manager. Click
someone to open their chat."* Then a **World** menu (Village, Sky Realm, Underwater Kingdom,
Moonbase, Enchanted Forest), **Organise**, and **Hire**.

**The world** draws the org chart as tiers by rank, with no lines: HeadMaster on top, each
manager's team on the tier below, centred under them, each person with a slot of their own. In the
Village everyone has a grassy ledge with a desk, strolls on it and sits at the desk to work; in the
other worlds each rides a mount over their slot (a golden cloud, a sea turtle…) with a floating
screen when working. Speech bubbles say what someone is doing, *"Done! ✓"*, or now and then
something idle. Click someone to open their latest chat; right-click for **New chat with …** and
**Edit …**.

**Organise** puts everyone where their role suggests: executives (CTO, CFO, CMO, CPO, COO, VP,
Head of, Director) under HeadMaster; leads under their department's executive; everyone else under
their department's lead or executive; product falls back to engineering; anyone unmatched under
HeadMaster.

**Below the world**: **Working now** (who, what, for how long; *"Nobody's working right now."*),
**Just finished** (*"Finished — open to read"*; *"Nothing new for you."*), **Activity** (replies
from the crew over 14 days, as bars), and **Crew** (face, name, *Founder* for HeadMaster, role,
CLI, ✎ and **Talk**).

**The editor** (a sheet, for hiring and editing):

- Left, a character creator: the avatar on a little stage (click to make them walk), a ‹ › stepper
  for each of seven parts — Skin, Hair, Hair colour, Eyes, Outfit, Outfit colour, Accessory — and
  **Randomize**.
- Right: **Name**, **Role** (*"One line: what they do"*), **Role instructions** (sent on every
  turn), **Brain** (the CLI) and **Model**, **Home project** (*"The one in view"* or a project), and
  **Reports to**, which lists everyone except the member and their own team, marking the
  suggestion *(suggested)*. A new hire's manager follows the suggestion as the role is typed.
- For HeadMaster, instead of Reports to: *"HeadMaster founded this place and runs it for you: it
  reports to you, hands work to the crew, and can't be let go."*
- Footer: **Let go…** (not for HeadMaster), **Cancel**, **Hire** / **Save**. Letting someone go
  moves their team up to their manager, keeps their chats, and shows a toast with **Undo**.

The founding crew is HeadMaster, Forge (builder), Hawk (reviewer) and Quill (scribe).

## Profile

Opened from the account menu. Your picture, name and `@username`, with **Edit** at the top right
(a sheet: **Choose Picture…**, Name). The Mac account's name and picture are the defaults.

Built from the agents' own history on this Mac, re-read at launch and hourly:

- A strip of five: **Lifetime tokens**, **Peak tokens**, **Longest task**, **Longest streak**,
  **Current streak**.
- **Showcase** — the top three projects by tokens.
- **Token activity** — a heatmap, *Daily* / *Weekly* / *Cumulative*.
- **Top tools** — up to nine, with use counts on hover.
- **Insights** — most used reasoning, most used agent, plan mode runs, skills explored, total
  skills used.
- *"No Copilot history found."* for each CLI with none.

While indexing: *"Reading your history…"*.

## The account menu

The account button opens a small card:

- Your picture and name, and the plans the agents report (*"Claude Max · ChatGPT Plus"*, or
  *"Claude Code · Codex"* when none have).
- **Usage remaining** (folds): for Claude Code and Codex, the **5h** and **Weekly** windows — what
  is left and when it resets — and when it was last updated. Before any data: *"Run a turn to see
  Claude Code's usage."* / *"No Codex usage yet."* Read from the CLIs' own output and logs; no
  password or token is read.
- **Profile** and **Settings** (⌘,).

## Settings

A separate Settings window (⌘,), with five tabs.

| Tab | Contents |
| --- | --- |
| **General** | **Default agent** (*Most recent* or a CLI), **Default reasoning** (*The agent's default* or a level), **Default permission** |
| **Appearance** | Appearance (Dark / Light / Match System); Wallpaper; App icon; Font |
| **Agents** | For each CLI: **Found at** (path, *Looking…* or *Not installed*), **Signed in**, **Plan**, and 5-hour and weekly usage left where known; **Look Again** |
| **Devices** | Pair an iPhone or iPad, the paired devices, and the stay-awake note |
| **About** | Icon, version and build, credits |

**Wallpaper** tiles: **Sunset**, **Desktop** (the current desktop picture), **Choose…** (a picture
of your own), **Randomize…** and **None**. Randomize opens a sheet in which an agent draws a
text-art wallpaper: Kind (Still / Animated), Agent and model (Claude Code or Codex), Reasoning, and
an optional Idea; **Generate**, then **Another one** or **Use as wallpaper**, with *"The prompt
xBot wrote"* to read.

**App icon**: Ink, Rose, Sunset, Plum. **Font**: *System (SF Pro)* or any installed family; code
and file names stay in SF Mono.

**Signed in** reads *Yes*/*No* for Claude Code, *Yes*/*Not seen yet* for Codex, and *Checked on
the first turn* for Antigravity and Copilot.

**Devices**: *"Keep working from your iPhone or iPad: your chats live, and the agents still run
here. On the same Wi-Fi it connects directly; away, through your iCloud."* **Pair an iPhone or
iPad…** opens a QR code (*"Open xBot on it and scan this code."*, *"The code pairs one device. Keep
it to yourself: it's the key to this Mac."*), which turns into *"Paired. You can close this."*
Each paired device shows *Connected · same network*, *Connected · through iCloud*, *Last seen …*
or *Not connected yet*, with **Remove**. A note says the Mac stays awake while a device is
connected or an agent is working (with the lid closed on battery it still sleeps); an iCloud
problem shows under it.

## Menus

Beyond the standard ones: **About xBot**, **Check for Updates…** (Sparkle; inert until a release
feed is configured), **File › New Chat** and **Close Tab**, **View › Files and Changes**,
**Window › Tab 1…9**, **Edit › Search Chats**, **Help › xBot Documentation**.

## Toasts and motion

Toasts are short notes at the bottom of the window, some with **Undo**. Every looping animation —
the worlds, faces, Galaxy, animated wallpapers — pauses while xBot is not the active app; Reduce
Motion stills the worlds, text-art wallpapers and Galaxy.

## Keyboard shortcuts

| Keys | Does |
| --- | --- |
| ⌘N | New chat |
| ⌘W | Close the current tab |
| ⌘1 … ⌘9 | Go to tab 1 … 9 |
| ⌘K | Search chats (Escape clears) |
| ⌃⌘S | Show or hide the sidebar |
| ⌥⌘0 | Show or hide files and changes |
| ⏎ | Send |
| ⌘. | Stop the running turn |
| ⌃` | Show or hide this chat's terminal |
| ← → | Move the effort slider (when it has focus) |
| ⌘↩ | Run plan (on a plan in review); commit (in the commit box) |
| ⌥↑ ⌥↓ | Move a plan step |
| ⏎ / ⌫ | Next plan step / remove an empty step |
| Escape | Cancel an edit; close a diff; close the explorer's filter |
| ⌘, | Settings |

---

# The iPhone and iPad app

A remote for the Mac. The agents run on the Mac; the phone shows its projects, chats, crew, notes,
automations and abilities, and acts on them through the Mac. It connects directly on the same
network and through iCloud elsewhere; how that works is in [14-iphone-and-ipad.md](14-iphone-and-ipad.md).
The look is Liquid Glass over calm charcoal cards, rounded type and one accent colour.

## Pairing

Until paired, the app shows one screen:

> **Your Mac, in your pocket**
> Keep working with your agents from here. They still run on your Mac; this is the remote.

then three steps — open xBot › Settings › Devices on the Mac, click **Pair an iPhone or iPad**,
scan the code — and **Scan the code**, which opens the camera with a framing square and
**Cancel**. A wrong code says *"That isn't an xBot pairing code."* Opening an `xbot://pair` link
pairs too.

## The tab bar

**Home**, **Chats**, **Agents**, **Projects** and **Search**, along the bottom. The bar folds away
as you scroll down. Each tab keeps its own navigation; a chat pushed from any tab hides the bar.

## Home

- **Toolbar**: the Mac's name with a status dot, opening a menu headed by the connection state with
  **Settings** and **Add a project…**; **+** (new chat, ⌘N) and ⚙ Settings.
- **The plan board** — every connected plan at a glance, in each provider's colours. One to four
  plans are concentric open rings, outermost first, each with a glowing tip; five or more share one
  arc in segments. The middle shows the tightest plan's percentage *left on Claude*. The legend
  gives each plan's 5-hour and weekly windows and when they reset. Tap opens Profile. With no usage
  yet, a single arc counts *chats today*. Pull to refresh.
- **A sentence**: *"Claude has 62% of its 5-hour limit left."* (or *"12 chats on Studio."*), then
  *"Everyone's free."*, *"Forge is working."* or *"3 agents are working."*
- **Working** and **Today** tiles (tap for Agents or Chats).
- **Working now** — up to four running chats with what each is doing.
- **Recent** — the latest four chats.
- **Places** — round glass buttons for **Notes**, **Automations**, **Abilities**, **Terminal** and
  **Profile**, each opening full screen with a zoom from its button, and × to close.

The page glows in the accent from the top.

## Chats

Every chat, newest first: loose chats under **Recent**, then a section per project. A row shows the
chat's mark (the agent's initial in its colour, or a spinner), title, *"Forge · Claude Code"* or
*"… is working…"*, and its age.

- Swipe left to **Delete** (at once); swipe right to **Rename**. Long-press: **Rename**, **Delete**
  (asks first: *"It's deleted on your Mac too. You can undo right after."*).
- After a delete, a banner at the bottom offers **Undo** for six seconds.
- **+** (⌘N) opens **New chat**: the first message (*"Ask anything…"*), Project, Agent, Model,
  Permissions and **Plan first**; **Send** (⌘↩).
- Empty: *"No chats yet"*, or *"Connecting"* with the link state while not connected.

**Search** finds chats by title across all projects: *"Search your chats"* until you type.

## A chat

- **Title** with a subtitle of member · agent · project. ⋯ menu: **Rename**, **Ask again**, **Copy
  chat**, **Delete**.
- **Your messages** are accent bubbles. Long-press: **Copy**, **Edit and resend** (a sheet).
- **Replies**: Markdown, with fenced code in its own scrolling box; tool rows (spinner, ✓ or ✗,
  label, target, size); notes from the agent folded into *"2 notes from the agent"*; failures in
  red; *"Thinking…"* before the first word. Long-press: **Copy**, **Share**. After a failed reply,
  **Try again**.
- **Plans** are a card: *Making a plan…*, *Plan ready*, *Running the plan*, *Plan done* or *Plan
  stopped*, the steps with their state, and in review **Cancel** and **Run plan**. Steps are not
  edited on the phone.
- **The composer** sits at the bottom in glass. Above the field, the same chips as on the Mac:
  agent · model, permission, reasoning (*The agent's default* or the levels the model offers) and
  **Plan** (dimmed for CLIs that can't plan). Chips are locked while a turn runs. The field reads
  *"Message Forge"*, or the reason when the chat can't take a message. **Send** (⌘↩) becomes
  **Stop** (Escape) while running. A failed send puts the text back.

## Agents

The same pixel world as the Mac (the shared `XBotWorld` library), drawn compact and filling the
whole page, with the bars kept dark over it.

- **The world menu** (top left) picks the world; the choice is the Mac's, and changing it on either
  side changes both.
- **Crew actions** (top right): **Hire someone** and **Organise like a company**.
- **The world**: tap someone for their page; long-press for a new chat or edit.
- **Crew cards** in a row under it: face, name (a crown for HeadMaster), role, and *Working · …*,
  *Done* or *Free*. Long-press: **Message**, **Edit**, **Let go**.
- **Suggested agents** — thirteen ready-made members not yet on the crew (Nova the CTO, Penny the
  CFO, Scout the researcher, Sentry the security reviewer and others; `SuggestedAgents.swift`), two
  to a row. Each card has a look, a role, a pitch and **Hire**, which hires in one tap under the
  suggested manager. Tapping the card opens the editor first.
- Letting someone go shows *"Forge left"* with **Undo**.

**A member's page**: their sprite, role, status and **Message Forge**; **In the company** (*Reports
to*, *You* for HeadMaster; *Team*); **Works on** (agent, home project); their instructions; their
chats; and **Let Forge go** (*"Their chats stay. You can undo right after."*). **Edit** in the
toolbar.

**The editor** (sheet): **Look** — the sprite drawn by the Mac, a stepper for each part, and
shuffle; **Who** — name, role, instructions; **Reports to** with *(suggested)*, and the footer
*"When they finish work their manager gave them, the manager's chat hears about it. HeadMaster
reports to you."*; **Works on** — agent, model, home project. **Hire** / **Save**.

**Talking to someone** opens a half-height sheet, *"What should Forge do?"*, and **Send** opens the
new chat.

## Projects

Each project is a card with its chat count and folder, and a spinner while a chat in it is working.
Long-press: **New chat here**. **+** adds a project by browsing the Mac's folders (*"Add “xbot” as
a project"*). Empty: *"No projects yet"* and **Add a project…**.

**A project** has **Files** and **Changes**, and a ⋯ menu: **New chat here**, **Terminal here**,
**Copy path on the Mac**, **Remove from xBot** (*"Its chats are removed too. The folder and its
files stay on the Mac."*).

- **Files** — folders and files with git letters. Swipe for **Trash** and **Rename**; long-press
  for **Mention in a new chat**, **Copy path**, **Rename**, **Move to Trash**. **New** › **New
  File** / **New Folder**.
- **Changes** — the branch and +/− totals, a sync line, the merge warning with **Ask the agent to
  merge**, problems, the pull request with its checks, **Publish Branch** or **Sync Changes**, and
  **Fetch**. A commit field with **Commit staged** or **Commit all**. Changed files: swipe right
  to **Stage**/**Unstage**, left to **Discard**; long-press adds **Mention in a new chat**. A file
  opens its diff.

**A file** opens with line numbers. Text files have **Edit** / **Save**; the ⋯ menu has **Mention
in a new chat**, **Copy text**, **Wrap lines**, and for Markdown **Show as code**. Over the size
limit: *"Showing the first N KB of … Too big to edit here."* Binary: *"Not a text file"*.

**Markdown files open as a document** — headings, lists, checklists, quotes and code — edited in
place: tap a block to change it. The keyboard bar has a block style menu (Text, Title, Heading,
Subheading, Bulleted list, Numbered list, Checklist, Quote), **Bold**, **Italic**,
**Strikethrough**, **Code** and **Done**. Return makes the next list item or paragraph; Return on
an empty item ends the list. Leaving a block saves it, written back as Markdown, with untouched
blocks exactly as they were in the file. Checkboxes tick with a tap.

Saving sends what the phone last read with the new text; if the file changed on the Mac since,
the Mac refuses: *"It changed on the Mac since you opened it. Open it again to see the new
version."* A good save shows *"Saved on the Mac"*.

## Places

Full-screen pages from Home, each closed with ×.

- **Notes** — a project picker, the project's notes, swipe to delete (with Undo), **+**. A note
  is plain text with *"Title on the first line…"*; it saves 1.2 s after typing stops, and its file
  follows the first line. Empty: *"No notes yet"*; with no projects, *"Notes live in a project.
  Add one first."*
- **Automations** — **Run while xBot is closed** at the top, then each automation with its
  schedule in words (*"Weekdays at 09:00 · next tomorrow"*, *Off*, *Running now…*) and a warning
  when its last run failed. Swipe right to **Run now**, left to **Delete**; long-press adds
  **Turn on/off**. The editor: name and **On**; **When** (When I run it, Every hour, Every day,
  Weekdays, Once a week); **Steps** from the same apps and connectors as the Mac (*"Steps run in
  order, by an agent with full access on your Mac."*); **Agent**, Model, Reasoning, **Works in**;
  **Runs**; **Save** and **Run now**.
- **Abilities** — Connectors, Plugins, Skills, MCPs as a segmented picker, with search. Switches
  where allowed, status otherwise (*Connected*, *Needs sign-in*, *Failed*, *Checking*); swipe to
  **Remove**. **+**: **Browse plugins**, **Add an MCP server** (a command or an address, for which
  agents), **Manage connectors on claude.ai**.
- **Terminal** — a real login shell on the Mac in a project's folder or home, drawn by SwiftTerm.
  The menu picks the **Folder** and starts a **New shell**. When it exits: *"The shell ended."* and
  **Start a new one**.
- **Profile** — lifetime tokens, best day, day streak, longest; a 26-week activity grid; tokens and
  tasks per agent and *plans run*; **Plan usage** per provider with what is left and when it
  resets; top projects, tools and skills. With no history: *"No agent history yet"*.

## Settings

A sheet from Home's ⚙ or the Mac menu.

| Section | Contents |
| --- | --- |
| *(top)* | **Mac** — its name, and the link state. *"The agents run on your Mac. Keep it on and awake; while this device is connected, xBot keeps it from sleeping."* |
| **Appearance** | *Match the device*, *Light*, *Dark* |
| **Accent colour** | Eight swatches — Orchid, Violet, Blue, Teal, Green, Amber, Coral, Graphite — and **Custom colour**. *"Used for buttons, highlights and Home's glow."* |
| **Files** | **Show .md files as code** — opens Markdown as text instead of a document (each file can still switch from its menu) |
| — | **Unpair this device** (*"To use xBot here again, pair it from the Mac's Settings › Devices."*) |

## iPad

The same app. The tab bar becomes a sidebar (`sidebarAdaptable`), and pages keep to a readable
width: Home and Projects 700 pt, chats 760 pt, pairing 520 pt. ⌘N, ⌘↩ and Escape work from a
hardware keyboard as on the phone.

## Connection

The link shows as a dot and a line wherever the Mac's name appears:

| State | Dot | Line |
| --- | --- | --- |
| Searching | orange | *Looking for Studio…* |
| Same network | green | *Studio · same Wi-Fi* |
| Through iCloud | green | *Studio · through iCloud* |
| Unreachable | red | the reason, e.g. *"Your Mac isn't on this network, and iCloud is off on this device."* |
| Not paired | red | *Not paired* |

The app connects when it comes to the foreground and lets go in the background. Sending is
disabled while not connected. When the Mac refuses something, an alert titled **Your Mac said no**
gives its reason; a request with no answer says *"Your Mac didn't answer."*
