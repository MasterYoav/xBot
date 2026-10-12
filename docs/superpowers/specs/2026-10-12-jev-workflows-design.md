# Jev in xBot: the AI settings, and Jev workflows

Status: approved in conversation, 2026-10-12.

## What the person asked for

1. Settings: the **Agents** tab becomes **AI**, and takes a **TypeSafe Jev API key**.
2. **Jev workflows**: the person defines workflows that mix their LLM agents with Jev, so Jev's
   fast, cheap decisions raise quality and lower cost. Next to the Jev key, a **toggle** turns the
   Jev Workflows feature on and off.
3. (Separate, see [packaging](../../11-packaging-and-updates.md)) CI publishes `xBot.dmg` to GitHub
   Releases whenever the version is bumped; the first release is 2.0.0.

Decided with the person: a Workflows page where a workflow is built from **agent steps** and **Jev
decision steps** that gate, route and branch between them; Jev can also **pick the cheapest capable
agent, model and effort** for a step, and for a chat. Workflows run like automations (Run now, or
on a schedule).

## Jev

Jev is TypeSafe AI's "System One" model. It never writes text: given a **state** and a map of
typed **questions**, it answers each with calibrated probabilities, in roughly 70–500 ms, at
$0.042 per million input tokens (output is free).

```
POST https://api.typesafe.ai/v1/systemone
Authorization: Bearer <key>
{ "model": "jev-latest", "state": "…",
  "questions": { "name": { "type": "noul" | "choice" | "score", "instructions": "…", "criteria": … } } }
→ { "model": "jev-1.13.0", "answers": { "name": { "type": "choice", "choice": "a",
      "probabilities": {…}, "confidence": 0.9 } … }, "usage": { "input_tokens": …, "output_tokens": … } }
```

- **noul**: yes/no; `criteria` optional `{"true": "…", "false": "…"}`; answer `noul` = P(yes).
- **choice**: one of up to 255 options; `criteria` = `{key: description}`; answer `choice`,
  `probabilities`, `confidence`.
- **score**: an ordered rubric of 2–10 levels, lowest first; `criteria` = `[level…]`; answer `score`
  (can land between levels), `legend`, `probabilities`, `confidence`.
- Errors: 401 key, 422 validation, 429 rate limit, 529 overloaded.

`JevClient` lives in `XBotBrain` (Foundation only). Its transport is injected (a closure taking a
`URLRequest`), never a class-level `URLProtocol` stub, so tests can't collide (CLAUDE.md). Fixtures
come from a real response.

## 1. Settings › AI

The **Agents** tab is renamed **AI** (icon unchanged). Above the CLIs it already lists:

- **TypeSafe Jev**: a secure field for the API key, kept **only in the Keychain** (service
  `dev.xbot.jev`); the app shows that a key is saved and its length, never its value. **Check**
  sends one tiny noul question and says "Jev answered in 120 ms." or the error in a sentence (bad
  key, rate limited, offline). **Remove** deletes it. A link: "Get a key at console.typesafe.ai".
- **Model**: `jev-latest` (default) or a pinned version, as text.
- **Jev Workflows** toggle (off by default). Off: no Workflows page, no Jev choice in chats, nothing
  calls Jev. On without a key: the toggle stays on, and Workflows says the key is missing, with a
  button to Settings › AI.

## 2. Jev workflows

### A workflow

- A **name**, a **trigger** (Run now, or a schedule: the automations' `AutomationSchedule`), a
  **project** (else the Inbox folder), on/off.
- **Steps**, in order. Each has an id and a title. Two kinds:
  - **Agent step**: a prompt in plain words for an LLM agent. Its **brain** is either a fixed CLI
    and model and effort, or **Jev picks** (below). Permission: Read only, Can edit or Full access
    (default Can edit). Its reply is the step's **output**.
  - **Jev step**: one question to Jev about the run so far. Its **state** is the workflow's input
    plus every earlier step's output (each under its step title), newest last, trimmed from the
    oldest end to fit Jev's context.
    - **Yes/no gate**: a question and a threshold (default 0.5). Yes → continue (or go to a step);
      no → go to a step, or **stop**.
    - **Route**: a question and options; each option goes to a step (or stops).
    - **Score**: a question and 2–10 ordered levels; each level goes to a step (or continues).
  - "Go to" may only point forward, or to a step at most a set number of times (a loop guard: each
    step runs at most 5 times per run), so a run always ends.
- An optional **input**: text given when running it by hand ("Run with…"), else empty.

### Jev picks

For an agent step set to **Jev picks**, before the step runs xBot asks Jev, in one call:

- **choice** `brain`: the options are every installed CLI and model, each described plainly (its
  strength and its relative cost: e.g. "Claude Code · Opus — strongest, most expensive", "Codex ·
  mini — quick edits, cheapest");
- **score** `effort`: Low, Medium, High, Max for the step's prompt.

It runs the step on the choice, at that effort. The run shows "Jev chose Codex · gpt-5-mini, low
effort (0.82)". The same pick is offered in chats: in the composer's agent menu, **Let Jev choose**
(only while Jev Workflows is on), deciding per message from the message itself.

If Jev can't be reached, a gate fails **closed** (stops, saying why), a route or score stops, and a
Jev-picks step falls back to the workflow's default brain. Never a silent guess.

### Running

A run is a chat tagged with the workflow (`chats.workflow_id`), like an automation run: each agent
step is a turn in it (so the CLI session carries context from step to step), and each Jev step adds
a notice: "Gate: Is the build failing? — yes (0.91) → Fix it". The run's chat is its history.
Claimed in the database before it starts, so a run is never doubled. Scheduled workflows run while
xBot is open, and through the automations helper while it's closed, if that's on.

### Storage

Schema v7: table `workflows` (id, name, trigger JSON, steps JSON, project_id, enabled, last_run_at,
created_at, sort_index) and column `chats.workflow_id`.

### Where it shows

- Sidebar: **Workflows** under Automations, only while the toggle is on.
- The Workflows page: the list, an editor (steps added from a palette, dragged to reorder; a Jev
  step's branches as pickers), Run now, Run with…, runs.
- The phone: Workflows in Places, listed with Run now, while the Mac has the feature on.

## Tests

- `JevClient`: request body and headers for each type; parsing each answer type (fixture recorded
  from a real call); 401/422/429/529 as sentences; timeouts.
- Workflow engine with a scripted brain and a scripted Jev: gates (yes, no, threshold, stop), routes,
  scores, go-to, the loop guard, Jev unreachable (fail closed, fallback brain), Jev picks reaching
  the turn, state assembly and trimming, run chat notices, claims, schedules.
- Store round trip and v6 → v7 migration.
- Settings: the key reaches only the Keychain; the toggle hides the page.
- Live, opt-in: `XBOT_LIVE_JEV=1` with a key in the Keychain runs one real call of each type.
