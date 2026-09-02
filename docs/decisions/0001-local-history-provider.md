# ADR-0001 — Replace the mandatory hosted history service with a local provider

**Status:** Accepted
**Date:** 2026-09
**Supersedes:** nothing
**Related:** [03-openbot-fork.md](../03-openbot-fork.md), [12-roadmap.md](../12-roadmap.md) M1

---

## Context

OpenBot's server refuses to start without CopilotKit Intelligence, a hosted service. From
`server/src/config.ts`:

```ts
if (missing.length > 0) {
  throw new Error(
    `CopilotKit Intelligence is required and is not configured. Missing: ${missing.join(", ")}`,
  );
}
```

Four values are required together: `INTELLIGENCE_API_URL`, `INTELLIGENCE_GATEWAY_WS_URL`,
`INTELLIGENCE_API_KEY`, `COPILOTKIT_LICENSE_TOKEN`. The defaults point at
`api.intelligence.copilotkit.ai` and `wss://realtime.intelligence.copilotkit.ai`.

Upstream's `.env.example` is explicit:

> *Intelligence owns durable threads and memory and a deployment without it forgets every
> conversation. **There is no degraded mode.***

And on self-hosting it:

> *Running Intelligence on your own infrastructure is an Enterprise Intelligence Platform feature
> deployed by Helm chart, and is not self-serve.*

Getting a key requires signing in through the CopilotKit CLI (`npx copilotkit@latest login`).

For an enterprise platform this is a reasonable dependency. For xBot it breaks four things at once:

1. **"Runs on your Mac"** — conversation history transits and rests on a third party.
2. **"No account"** — onboarding would require a CopilotKit sign-in through a Node CLI, i.e. a
   terminal, which violates the product's central promise.
3. **"Nothing leaves your machine except calls you choose"** — untrue.
4. **Business risk** — a consumer app whose core function stops if a third party changes its free
   tier is not shippable.

## Options considered

### A. Ship with Intelligence as-is

Onboarding provisions a CopilotKit account behind the scenes.

**Rejected.** It is not local, and the privacy claim — the reason to choose xBot over a hosted
assistant — evaporates. It also makes our product's availability a function of someone else's
pricing page.

### B. Self-host Intelligence alongside the engine

Run it in the same container stack.

**Rejected.** Explicitly an Enterprise feature, Helm-deployed, not self-serve. Not licensed for what
we would be doing, and not a thing we could ship inside a consumer DMG.

### C. Local provider behind an interface ✅

Introduce a `HistoryProvider` interface. Implement it against the local database. Keep the
Intelligence implementation behind a setting.

### D. Rip out the abstraction entirely and write threads directly against Postgres

Simpler code, no interface indirection.

**Rejected**, and this is the interesting one. It would produce a smaller diff *today* and a much
larger one every month afterwards, because every upstream change touching `copilot.ts` would collide
with our rewrite. The interface is not there for elegance — it is there so the merge boundary is one
seam rather than a hundred edits.

## Decision

**Option C.**

```ts
interface HistoryProvider {
  createThread(input: NewThread): Promise<Thread>;
  getThread(id: ThreadId): Promise<Thread | null>;
  listThreads(query: ThreadQuery): Promise<Page<ThreadSummary>>;
  appendMessages(id: ThreadId, messages: Message[]): Promise<void>;
  streamThread(id: ThreadId): AsyncIterable<ThreadEvent>;

  recall(query: MemoryQuery): Promise<MemoryHit[]>;
  remember(fact: MemoryWrite): Promise<void>;
}
```

Two implementations:

- **`LocalHistoryProvider`** — PostgreSQL for threads and messages, pgvector for memory, an
  in-process `EventEmitter` where upstream uses the hosted realtime websocket. **The xBot default,
  and the only one onboarding can produce.**
- **`IntelligenceHistoryProvider`** — the existing behaviour, retained behind a setting so our diff
  stays reviewable and upstream merges stay possible.

`runtimeCapabilities()` changes from a hard throw to provider selection, defaulting to local.

## Consequences

### Good

- The promise becomes true. No account, no cloud, no third-party dependency in the critical path.
- pgvector is already in the stack — upstream uses `pgvector/pgvector:pg17` — so memory needs no new
  infrastructure.
- The interface makes an offline test double trivial, which every test in the engine benefits from.
- Retaining the Intelligence implementation keeps a path open if a user or a future deployment wants
  it.

### Bad

- **The largest single piece of engineering in the fork.** 3–5 weeks, ~64 references across 8 files,
  most of it inside `copilot.ts` (~1250 lines).
- **We own thread and memory correctness now.** Ordering, concurrency, durability across restarts,
  and recall quality are ours. Intelligence presumably has had these bugs found already.
- **Merge risk.** `copilot.ts` is the file most likely to change upstream and the one we have changed
  most. Every merge is a careful review.
- **Memory quality is unknown.** Intelligence's recall is presumably tuned. A naive pgvector
  cosine-similarity implementation is a starting point, not a match, and we will need to iterate on
  chunking, embedding choice, and ranking.

### The realtime gateway is the subtle part

Upstream uses a websocket to a hosted service for live thread status — which conversations are busy,
what is streaming where. Locally this becomes an in-process emitter plus SSE to the client. Simpler
in principle. The work is finding every consumer, because they are not all obvious from a grep for
"intelligence": `channels/thread-status.ts` is the visible one, and `routines/run-turn.ts` is the one
that gets missed.

## Verification

**Done when the engine starts and runs a full conversation with no `INTELLIGENCE_*` variables set at
all, and history survives a container restart.**

Tests required before this is considered complete:

- Thread lifecycle: create, append, list, read after restart.
- Message ordering under concurrent turns in different channels.
- Memory: write, recall, relevance ordering.
- The Intelligence implementation still passes the same suite, so the interface is honest.

## Review trigger

**If this exceeds 6 weeks, stop and re-plan.** It would mean the coupling is deeper than 64
references suggested, and the alternatives — a thinner engine, or vendoring differently — need to be
back on the table before more is sunk into it.
