# Plan mode: review a plan, then watch it run

Date: 2026-10-08 · Status: approved in brainstorming, awaiting spec review

## Intent

**What the user said.** Implement the "loop mode" UX from their screen recording (an "Agent Todos"
prototype, 2026-10-08) exactly, using our agents' plan mode.

**Decided in brainstorming.**

1. A **Plan** chip in the composer turns plan mode on per chat; a **Review plan first** switch
   beside it (on by default) decides whether the plan waits for approval. Plan off = a normal reply.
2. **xBot drives the loop** (approach A): one planning turn that must answer in a JSON schema, then
   one resumed turn per step, each answering in a small schema. Rejected: one long turn reporting
   through an MCP tool (needs the MCP helper now; step grouping inferred), and mirroring the CLIs'
   own to-do lists (neither exposes one when run headless — probed below).
3. "Exactly" means the recording's layout, wording and behaviour, in xBot's design tokens.

**Success.** A person turns Plan on, asks for a change, edits and reorders the proposed steps, runs
them, and watches each step go from pending to running (with its live tool rows) to done or failed,
with the agent adding steps when something fails — all saved, so a relaunch shows the same card.

## What the CLIs do (probed 2026-10-08)

- **Claude Code 2.1.291**, `-p --output-format stream-json`:
  - `--permission-mode plan` investigates read-only. Its own plan goes to `~/.claude/plans/*.md` as
    free-form markdown, and `ExitPlanMode` is not available headless — not parseable into steps.
  - No to-do tool in headless sessions (the init tool list has `Task`, a subagent tool, and no
    `TodoWrite`); asked to track to-dos, it did not.
  - `--json-schema '<schema>'` works with stream-json and plan mode: the final `result` line carries
    the answer as `structured_output`.
- **Codex 0.160.1**, `exec --json`:
  - `--output-schema <file>` works (also on `exec resume`); the answer is the last `agent_message`
    item's text, as JSON. A schema field without a description was misread — every field needs one.
  - OpenAI's strict schemas need `additionalProperties: false` and every property `required`.

## The flow

1. **Planning turn.** With Plan on, sending runs a turn in the chat's folder that is always
   read-only (Claude Code `--permission-mode plan`; Codex `sandbox_mode="read-only"`), with the
   user's message plus an instruction: investigate, change nothing, answer with the plan. Schema:

   ```json
   {"summary": "one sentence: what you will do and why",
    "steps": [{"title": "imperative, 3-8 words, e.g. 'Find where search fetches results'",
               "active": "the same step as an -ing phrase, e.g. 'Finding where search fetches results'"}]}
   ```

   While it investigates, the card shows **Planning…** with the live tool rows.
2. **Review.** With Review plan first on, the plan card waits. Off, it runs at once.
3. **Run.** For each step in order, xBot resumes the CLI session in the chat's own permission mode:
   "Do step N of the plan: ‹title›. The whole plan, for context: ‹numbered list›. Do only this step."
   Schema:

   ```json
   {"outcome": "done | failed",
    "note": "one sentence about what you found or did, shown to the user",
    "add": [{"title": "…", "active": "…"}]}
   ```

   - `done` → the step is checked. `failed` → red ✕ with the note; the loop **continues**.
   - `add` → those steps are inserted right after the current step and marked added; the card says
     "Plan updated · N added" (N counted over the whole run).
   - The note becomes the card's header sentence.
4. **Close.** After the last step, one short resumed turn: "In one or two sentences, tell the user
   what changed." Its text is shown under the card. Footer pill: **Finished**, or
   **Finished · N failed**.
5. **Stop** (⌘.) ends the running step as stopped; later steps stay pending; footer **Stopped**,
   with **Resume**.

## Data

In `XBotCore`, saved inside the transcript as a message part:

```swift
public struct Plan: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case drafting, review, running, finished, stopped }
    public var summary: String
    public var status: Status
    public var note: String          // latest step note; starts as the summary
    public var steps: [PlanStep]
    public var added: Int            // steps the agent added during the run
    public var startedAt: Date?
    public var endedAt: Date?
}

public struct PlanStep: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable { case pending, running, done, failed, stopped }
    public var id: UUID
    public var title: String
    public var active: String        // the -ing label; becomes `title` when the user edits the title
    public var status: Status
    public var note: String?
    public var tools: [ToolPart]
    public var startedAt: Date?
    public var endedAt: Date?
}

case plan(Plan)   // new `Part`
```

- `ToolPart` gains `startedAt` and `endedAt` (optional, so old rows still decode).
- The plan message is saved whenever the plan changes, replacing the previous copy in place
  (`Store.replace(_ message:)`), so a relaunch shows exactly the last state.
- The chat gains `planMode: Bool` and `reviewPlan: Bool` (stored; defaults off / on).

In `XBotBrain`:

- `TurnRequest` gains `schema: String?` (a JSON Schema document) and `planning: Bool`.
- `HarnessKind.arguments` adds `--json-schema <schema>` (Claude) or `--output-schema <file>`
  (Codex; the schema is written to a temporary file per turn), and for `planning` forces the
  read-only flags whatever `mode` says.
- New event `.structured(String)` — the JSON text of the final answer: Claude's
  `result.structured_output` re-encoded, or Codex's last `agent_message` when the request had a
  schema. With a schema, Codex's final message is *not* also shown as reply text.

## UI

Matched to the recording, in xBot tokens.

**Composer.** A **Plan** chip (`list.bullet.clipboard`) beside agent / model / permission. When on,
a **Review plan first** switch appears next to it. Disabled while a plan is running.

**Plan card (review).**
- "Here's my plan. Change anything you like, then run it."
- **Review the plan** / caption: "Edit, reorder or remove steps before the agent starts. Move a step
  with ⌥↑ and ⌥↓."
- Numbered rows: grey number, a borderless text field; the focused row gets a soft highlight and an
  ✕ on the right. ⏎ moves to the next row; ⌫ on an empty row removes it; ⌥↑ / ⌥↓ move the focused
  row.
- **+ Add step** adds an empty row and focuses it.
- Footer under a divider: "N steps" left; **Cancel** and a filled **Run plan ⌘↩** right. Cancel
  marks the plan stopped and leaves the user's message. With no steps, Run is disabled and the
  footer says "Add a step to run."

**Tasks card (running and after).**
- "On it. I'll keep this list updated as I go."
- Header: **Tasks** "3 of 7 done" (+ " · 1 failed"); total elapsed time right; a chevron collapses
  the card.
- A thin progress bar, done / total: accent colour, failure colour once anything failed. Spring.
- The note line in secondary text.
- Rows:
  - pending: dashed circle, grey title; the next pending step has a solid outline circle.
  - running: spinner; the `active` label in the accent colour; its live tool rows indented below
    (icon, verb, mono target, spinner); elapsed time; chevron.
  - done: filled check; struck-through grey title; duration; chevron. Expanded: a summary line
    ("Read 4 files, searched the web once, listed a folder"), which expands to each tool with its
    size ("64 lines", "6 results", "18 items", "+39") and duration ("1.4s").
  - failed: red ✕; title; the note in red below.
  - stopped: a hollow stop glyph; title; "Stopped" below.
- While running, three or more finished steps above the running one collapse into one
  "✓ 3 completed ⌄" row. When the plan is not running, all rows show.
- "Plan updated · N added" under the list when N > 0.
- Closing sentence below the card as normal reply text; a footer pill above the composer:
  **Finished** / **Finished · N failed** / **Stopped** (+ **Resume**).

**Motion.** Row status changes `Motion.quick`; progress bar `Motion.standard`; Reduce Motion
cross-fades, via the existing `motion(_:value:)`.

**Tool sizes and summary.**
- Size from the result text: line count for reads; entries for listings (`ls`, Glob, LS); result
  count for searches (Grep, WebSearch); `+N` lines for files written or edited.
- Summary verbs from tool names per CLI — Claude: Read, Write, Edit, Bash, Grep, Glob, WebSearch,
  WebFetch; Codex: Shell, Edit. Anything else counts as "used N tools".

## Errors and edge cases

- **No usable plan** (no structured answer, bad JSON, zero steps): the card says "The agent didn't
  return a plan." with its text reply, and **Try again**. Never an empty card.
- **A step's turn fails** (`.failed` from the brain: crash, signed out, usage limit): that step is
  failed with the CLI's reason and the loop **stops** — footer **Stopped · 1 failed**, **Resume**
  retries from that step. Distinct from the agent's own `outcome: failed`, which continues.
- **A step answers without a structured result:** treated as `done` with no note if the turn
  succeeded (the work happened; the format slipped).
- **Runaway additions:** at most 20 added steps per plan; past that, further `add`s are ignored and
  the note says "Stopped adding steps at 20."
- **Quit mid-plan:** the running step is saved as stopped; the plan as stopped; Resume on relaunch.
- **Agent switch** is disabled while a plan runs. Editing is review-only.

## Testing

TDD:
- Arguments for planning and step turns on both CLIs; `.structured` parsing from recorded
  fixtures (Claude `structured_output`, Codex last `agent_message`), including the Codex final
  message not doubling as reply text.
- The plan runner on a scripted brain: order and resume; failed outcome continues; brain failure
  stops; additions inserted after the current step and counted; the cap; stop and resume; editing a
  title replaces its active label; no-plan and bad-JSON paths; persistence of each change.
- Tool size and summary helpers.
- Opt-in live test (`XBOT_LIVE_HARNESS=1`): a real two-step plan through each installed CLI.

Views: no unit tests; offscreen renders of review, running, failed-and-added, and finished states,
compared by eye with the recording's frames.

## Out of scope

Plans for the native brain (it arrives later and will speak the same schemas); editing a plan while
it runs; parallel steps.
