# ADR-0008 — A durable local thread runner, narrower than ADR-0001's HistoryProvider

> **Superseded by [ADR-0009](0009-native-harness-redesign.md)** — conversations live in the app's SQLite store. Kept as history.

**Status:** Accepted
**Date:** 2026-09
**Supersedes:** nothing. **Partially resolves** [ADR-0001](0001-local-history-provider.md) — the
"conversation persists with no account" half of it. Recall/memory (pgvector) is still that ADR's,
unimplemented.
**Related:** [ADR-0007](0007-wrap-openbot-keep-intelligence.md), [03-openbot-fork.md](../03-openbot-fork.md)

---

## Context

ADR-0007 kept CopilotKit Intelligence for v1 on the reasoning that the engine's local-mode seam was
already built and cheap to leave unimplemented — `history/local-intelligence.ts` is a spike that
records which methods are reached and throws on all of them. Building it out to ADR-0001's full
design (a `HistoryProvider` interface, `LocalHistoryProvider` backed by Postgres and pgvector, an
in-process realtime emitter, ~64 references across 8 files, 3–5 weeks) was deliberately deferred
past v1.

No CopilotKit account is available in this environment. Shipping "a fully working app" against that
constraint means either the app cannot hold a conversation at all, or local mode has to actually
work — not ADR-0001's full scope, but enough of it that a conversation survives.

**The measurement ADR-0007 asked for, done:** the native Mac client's only path to the engine is
`HTTPEngineClient.stream()`, a `POST /api/copilotkit/agent/:id/run` with
`Accept: text/event-stream`. It never opens Intelligence's realtime websocket. `@copilotkit/runtime`
already has a second runtime class for exactly this shape — `CopilotSseRuntime`, which needs no
`intelligence` client and defaults to its own `InMemoryAgentRunner` — and that runner already
implements `run`, `connect`, `isRunning`, `listThreads`, `getThreadMessages`, `getThreadEvents`,
`getThreadState`, and `clearThreads` against a process-global map. It is not durable — an in-memory
map does not survive a container restart — but it is otherwise the whole surface the client needs.

## Decision

**Wrap the vendor's own SSE runner rather than building ADR-0001's `HistoryProvider` interface.**

`LocalThreadRunner` (`engine/server/src/history/local-thread-runner.ts`) extends
`InMemoryAgentRunner`:

- `run()` behaves exactly as the vendor's does, and additionally persists the kept messages to a new
  `local_threads` table (`threadId` primary key, `agentId`, `messages` jsonb, timestamps) once a run
  completes or errors. Writes are serialized per-runner so a fast second turn cannot land before a
  first one's write.
- `hydrate()` reads every row back into the in-memory map at boot, so a restart's `getThreadMessages`
  answers as if the map had never been cleared.
- `localRoutineIntelligence(runner)` adapts it to the narrow `IntelligenceLike` structural interface
  `routines/run-turn.ts` already defines, so a routine's headless turn reads the same durable history
  a person's conversation does, including a lock (`ɵacquireThreadLock`) that throws when the runner
  says the thread is already running.

`copilot.ts` picks this up as a second branch, keyed on whether `mountCopilotRuntime()` was given
an `intelligence` client or a `localRunner`: local mode builds `CopilotRuntime` with `runner:
localRunner` instead of `intelligence:`, answers `history()` from `localRunner.getThreadMessages()`,
and uses a `localThreadLock` (`runner.isRunning()`) in place of Intelligence's own lock object.
`index.ts` wires a `LocalThreadRunner` and hydrates it whenever `runtimeCapabilities()` selects local
mode, and hands it to both the routine runner and Bot-to-Bot handoff delivery, which previously went
"dark" in local mode per the old comment on that branch.

**Guarded to single-user.** SSE mode has no `identifyUser`, so there is no per-person scoping —
`mountCopilotRuntime()` throws if local mode is selected without `config.singleUser`. This is fine
for xBot: `OPENBOT_SINGLE_USER=true` is already how `EngineEnvironment.compose` configures every
container.

**The Mac app stops offering to connect Intelligence at all.** There is no UI path left that
collects a CopilotKit key: onboarding's model step names only what still leaves the Mac (the chosen
model), `EngineBootstrap.environmentFactory` never passes `intelligence` to
`EngineEnvironment.Inputs`, and Settings has no "Conversation history" section. The engine's
dual-mode support and `EngineEnvironment.Intelligence` stay — a deployment could still configure
Intelligence by hand — but nothing in the shipped client can produce that configuration.

## Consequences

### What this buys

ADR-0001's "Done when" criterion — a full conversation with no `INTELLIGENCE_*` variables set,
surviving a container restart — is met, without its 3–5 week estimate or its `HistoryProvider`
interface. The vendor's own reducer (`@ag-ui/client`) is what decides which messages are new; xBot's
code only decides what those messages become on disk. That is a much smaller merge surface than
rewriting `copilot.ts` against a hand-rolled interface would have been — consistent with "wrap
OpenBot, do not re-engineer it."

Two client-side bugs surfaced and were fixed while wiring this: the thread-history GET used the
query-string route form (`?threadId=`), which the vendor's router matches as `threads/list` rather
than `threads/:id/messages`; and `WireMessage.init(row:)` only parsed AG-UI's nested tool-call shape,
silently dropping every historical tool call the flat local-mode row shape actually sends. Both were
pre-existing and would have surfaced against Intelligence too, once anyone had a key to find them
with.

### What this does not buy

**No memory or recall.** ADR-0001's pgvector-backed `recall`/`remember` is not part of this — a
`LocalThreadRunner` conversation remembers everything sent in it (the whole thread goes to the model
every run, same as Intelligence mode), but there is no semantic search over past conversations. That
gap is exactly ADR-0001's remaining scope, and it stays open.

**No cross-user or hosted-realtime story.** `runnerConnection()` throws in local mode — there is no
platform websocket to reach — and `identifyUser` is not supported, both fine only because xBot is
single-user per container.

**A `local_threads` row is not the audit trail.** It is durable storage for what a run needs to
answer the next one, not the append-only record invariant 3 protects. The two are unrelated and
neither substitutes for the other.

### When we revisit

- If xBot ever needs multiple people sharing one engine, this seam does not extend to that — it
  would need `identifyUser` support the vendor's SSE mode does not have, at which point Intelligence
  or a real `HistoryProvider` is back on the table.
- If recall/memory becomes a feature request, ADR-0001's pgvector design is still the plan for it;
  `LocalThreadRunner` and a `HistoryProvider`'s memory half are not mutually exclusive.

## Alternatives considered

**Build ADR-0001 in full.** Rejected for now, on the same sequencing grounds ADR-0007 used: the
memory/recall half is real work with no measurement behind it yet, and a working conversation was
the blocking requirement, not tuned recall.

**Wait for a CopilotKit key and ship Intelligence as designed.** Rejected as the only path: a
"fully working app" should not depend on a credential nobody asked for and this environment does not
have. ADR-0007's own seam — local mode, deferred but built — existed precisely so this would not be
a blocker.

**Hand-roll a `HistoryProvider` against Postgres directly, skipping the vendor's runner.** Rejected:
the vendor's `InMemoryAgentRunner` already implements the exact surface `CopilotSseRuntime` calls and
already handles run bookkeeping (`isRunning`, thread event queues) correctly; duplicating it to fit a
new interface would be re-engineering the part upstream already does well, for no capability this
project currently needs.
