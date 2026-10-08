# Workspace panels: Git and Explorer, the account menu, usage, profile and settings

Date: 2026-10-08 · Status: approved in brainstorming, awaiting spec review

## Intent

**What the user said.**
1. Get rid of the grey bar at the top of the app.
2. A profile picture button at the bottom of the sidebar opening a small menu like ChatGPT's:
   Profile (a page copied from ChatGPT's profile page), Usage (collapsed / expanded, auto-updating
   from the connected AI accounts), Settings, Log out.
3. A right-side sidebar per project: the git state (up to date, needs pulling / pushing / merging,
   PR waiting) with a git interface, and a file explorer — after MonoCode's Explorer and Changes
   panels, without its Sessions tab.
4. xBot's account should be the person's **Apple ID**, syncing across their Apple devices through
   iCloud — "if that is possible we have to make it happen".

**Decided in brainstorming.**
- **Order:** these panels now; Apple ID + iCloud sync next, as its own spec. It needs the user to
  create an iCloud container and a Developer ID provisioning profile with iCloud and Sign in with
  Apple in the Apple Developer portal, which only they can do. **Log out** belongs to that work and
  does not appear before it (xBot shows no control that does nothing).
- **Git panel:** status plus everyday actions — commit, sync (pull fast-forward, then push),
  stage / unstage / discard a file, PR state through `gh` when installed. Conflicts are explained,
  not resolved in-app. AI-written commit messages are a later addition.
- **Profile data:** all the person's agent history — Claude Code's and Codex's own local logs plus
  xBot's chats — indexed incrementally in the background. Nothing leaves the Mac.
- **Identity until Apple ID:** the macOS account's full name and picture (both readable from the
  local directory service without a permission prompt).

## 1. The top bar

The tab strip has no background. The backdrop (or the window colour) runs up behind the tabs. The
selected tab is a soft translucent segment (`Palette.hover` over the backdrop, `Palette.raised` at
70% where there is none); the others are text; no hairline. The right end of the tab row holds
the inspector toggle (⌥⌘0).

## 2. The right sidebar

A native `.inspector` column, 300pt (260–420), toggled by the tab-row button or ⌥⌘0, remembered.
Present when the open chat — or Home's draft — has a project; otherwise the toggle is disabled with
the help text "Choose a project to see its files and changes." Header: two tabs, **Explorer** and
the change totals (**+372 −33**, which opens **Changes**); green / red numbers, mono.

### Changes

- **Header:** "Changes", then the branch (`arrow.triangle.branch`) with `↓behind` `↑ahead`, and a
  ⋯ menu: Fetch now, Open on GitHub (when the remote is GitHub).
- **State line** — one `StatusPill` and a sentence:

  | State | Pill | Sentence |
  | --- | --- | --- |
  | clean, even with upstream | success "UP TO DATE" | "Nothing to commit. In step with origin/master." |
  | local changes | accent "CHANGES" | "15 files changed." |
  | ahead | running "TO PUSH" | "3 commits to push." |
  | behind | warning "TO PULL" | "1 commit to pull." |
  | ahead and behind | warning "DIVERGED" | "Pull before you push: 1 to pull, 2 to push." |
  | conflicts | failure "CONFLICT" | "Merge conflict in 2 files." |
  | no upstream | neutral "LOCAL" | "This branch isn't on a remote yet." + **Publish** |
  | not a repo | neutral "NO GIT" | "This folder isn't a git repository." |

- **Pull request** (when `gh` is on PATH and authenticated): "PR #15 · open" with review state
  (review requested / approved / changes requested) and checks (passing / failing / running),
  linking to the PR. Absent `gh` → the row is absent, not an error.
- **Commit:** a message field ("Message (⌘↩ to commit)") and **Commit** (stages all when nothing is
  staged). **Sync Changes ↓1 ↑2**: `git pull --ff-only`, then `git push`; if the pull cannot
  fast-forward, the state becomes DIVERGED and the panel offers **Ask the agent to merge**, which
  sends that request to the chat.
- **Changed files:** status icon, name, dimmed directory, a letter (M amber, A/U green, D red, C
  conflict red). Hover: Stage / Unstage, Discard (confirmed once — not undoable). Click: the diff
  opens in the main area as a read-only view (unified diff, +/− tinted, line numbers).
- **Freshness:** a file-system watcher on the project re-reads status (debounced 300 ms); a quiet
  `git fetch` every 5 minutes while the panel is visible; Fetch now on demand.

Git runs as `/usr/bin/git` (or the first `git` on the login PATH) with the project as working
directory; status from `git status --porcelain=v2 --branch -z`, totals from
`git diff --numstat HEAD`. No git library.

### Explorer

- Header: the project name in mono caps with a chevron; icon buttons New File, New Folder,
  Collapse All, Filter.
- Tree: folders first, then files, by name; folders load when expanded. Rows: disclosure, icon,
  name. Icons by kind — folders `.git` / `.github` / `docs` / `apps` / `assets` / `scripts` / `site`
  get their own symbol and tint; files by extension (Swift, Markdown, JSON, YAML, images, keys,
  licence, `.gitignore`), else a plain document.
- Ignored paths (`git check-ignore --stdin`) are dimmed and italic. Git colours names: modified
  amber, added green, deleted red struck through; a folder takes the strongest colour inside it.
- Click: Quick Look. Double-click: open in the default app. Context menu: Reveal in Finder, Copy
  Path, Rename, Move to Trash (recoverable — no confirmation), Mention in Chat (inserts
  `@relative/path` into the composer). Dragging a file onto the composer does the same.
- The same watcher keeps the tree current.

## 3. The account menu

The sidebar footer becomes a button: the person's picture (28pt circle) and name. It opens a
popover card (`Palette.raised`, 16pt radius, floating shadow):

- **Header:** picture, name; below it the plan the agents report (Claude Code's from
  `~/.claude.json` → `oauthAccount`, e.g. "Claude Max"), else "Claude Code · Codex".
- **Usage remaining** with a chevron; expanded, per agent:
  - "Claude Code" — `5h  97%  12:42 AM` and `Weekly  99%  Oct 15` (remaining = 100 − used; the time
    is when the window resets).
  - "Codex" — the same.
  - "Updated 2 min ago" in tertiary text.
  - **Sources:** Claude Code's `rate_limit_event` in every turn's stream (`unifiedWindows.five_hour`
    and `seven_day`: utilization, resetsAt), stored in the library so it survives relaunch. Codex's
    newest session log (`~/.codex/sessions/**/rollout-*.jsonl`, last `token_count.rate_limits`:
    primary 300-minute and secondary 10080-minute windows), read when the menu opens and every
    minute while it is open. No credentials are read.
- **Profile**, **Settings ⌘,**.

## 4. The profile page

Opens in the main area (like Home; a sidebar row is not needed — the menu opens it). Copied from
ChatGPT's profile layout, in xBot's tokens:

- Top-right: **Edit** (name and picture, stored in the library; the macOS ones are defaults).
- Centre: 96pt round picture, name (title), `@username` (macOS short name), tertiary.
- **Stats strip** — one card, five columns separated by hairlines, value over label:
  Lifetime tokens · Peak tokens (best day) · Longest task · Longest streak · Current streak.
- **Showcase** — the three most active projects as cards (name, tokens, last active).
- **Token activity** — a 53-week × 7-day grid of rounded squares, month labels below, a segmented
  **Daily / Weekly / Cumulative** control at the right of the title; shades of the Claude clay
  colour by quantile; empty days `Palette.inset`.
- **Top tools** — up to nine rounded-square tiles with the most-used tools' and skills' symbols,
  count on hover.
- **Insights** — rows, label left, value right: Most used reasoning ("Medium · 37%"), Most used
  agent, Plan mode runs, Skills explored (distinct), Total skills used.
- A "?" by Lifetime tokens: "Input, output and cached tokens, as your agents count them."

### The indexer

A background actor reads the logs into the library:

- **Claude Code** (`~/.claude/projects/*/*.jsonl`): `assistant` lines — `timestamp`, `effort`,
  `message.usage` (input + output + cache creation + cache read), `tool_use` names (and the `Skill`
  tool's skill name); `user` lines start a task, the last assistant line before the next user line
  ends it.
- **Codex** (`~/.codex/sessions/**/rollout-*.jsonl`): `turn_context` (model, effort, cwd),
  `event_msg/token_count` (`info.last_token_usage` per turn), `event_msg/task_complete`
  (`duration_ms`).
- Aggregates per day and agent: tokens, tasks, longest task, tool counts, skill counts, effort
  counts, active projects (by `cwd`). Per file it stores the byte offset read, so later passes read
  only new lines. A pass runs at launch, when the profile opens, and hourly.

## 5. Settings

A native `Settings` scene (⌘,), three tabs:
- **General:** Background (on / off), default agent, default effort, default permission.
- **Agents:** per agent — found at (path), signed in (yes / no), plan, usage; **Look Again**.
- **About:** version, credits (the About panel's text).

## Errors and edge cases

- No `git`: the Changes tab says "Git isn't installed on this Mac." with **Install Command Line
  Tools** (`xcode-select --install` through `Process` — Apple's own installer dialog, not a
  terminal).
- A git command fails: its stderr in a red callout in the panel; the panel keeps working.
- Huge repositories: status is debounced; the Explorer never walks a tree it was not asked to open.
- Missing or unreadable logs: the profile shows what it has and says "No Codex history found" per
  missing source.
- Usage unknown yet (no Claude turn since install): "Run a turn to see Claude Code's usage."

## Testing

TDD: `git status --porcelain=v2` parsing (branch, ahead/behind, renames, conflicts, untracked)
from recorded output; the state table; commit / stage / discard / sync against temporary
repositories with a local bare remote; the rate-limit parsers (Claude stream line, Codex rollout
line) and remaining / reset formatting; the indexer on fixture logs (daily totals, tasks, streaks,
incremental offsets); the profile maths (peak, streaks, heatmap buckets, quantiles). Views:
offscreen renders compared with the references; the real-window snapshot for the top bar.

## Next

Apple ID account and iCloud sync — its own spec, once the container and provisioning profile
exist.
