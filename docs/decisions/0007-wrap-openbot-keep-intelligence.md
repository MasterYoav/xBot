# ADR-0007 — Wrap OpenBot rather than re-engineer it, and keep Intelligence for v1

**Status:** Accepted
**Date:** 2026-09
**Supersedes:** nothing. **Defers** [ADR-0001](0001-local-history-provider.md) — it stays accepted
and stays unimplemented.
**Related:** [01-vision.md](../01-vision.md), [03-openbot-fork.md](../03-openbot-fork.md),
[12-roadmap.md](../12-roadmap.md)

---

## Context

The original plan read the fork as two large engineering problems — a mandatory hosted history
service and a boot-time model provider — and put the first of them, ADR-0001, in front of
everything else as "the gate". Nothing was to ship until threads and memory were re-implemented
locally: 3–5 weeks, the widest error bars in the project, with a tripwire to stop and re-plan at
six.

That plan was written before anyone had run the code. Having run it, three of its premises are
wrong, and one of them is wrong in a way that changes what the project is.

### The engine boots and serves without a CopilotKit account

Measured, not inferred. Adding a second `mode` to `RuntimeCapabilities` and guarding three call
sites — 136 lines across four files — produces an engine that starts, listens, and answers:

```
/health                → {"status":"ok"}
/api/agents            → the tenant package's agents
/api/channels  POST    → a channel, with a thread id
/api/copilotkit/info   → agents listed, streaming + tools + interrupts
```

Two Intelligence methods are reached during that, both wiring-time URL getters.

### The coupling is far smaller than a grep suggests

`grep -i intelligence` over `server/src` returns **156 hits across 18 files**, which reads as an
enormous surface. Widening the `RuntimeCapabilities` union and letting the compiler enumerate the
real dependency returns **5 errors across 4 files**. The rest are comments, identifiers, and calls
on a client that is already injected.

Upstream had also done much of the work already, and said so in comments:

- `index.ts` carried the note *"If a second mode is ever added, THIS is the line that has to grow
  a guard, and the routine runner must then be left off `createApp` entirely."* That is exactly
  the change, written down before we arrived.
- `channels/thread-status.ts` is duck-typed on a single `getThread` method rather than the vendor
  class, so any implementation satisfies it.
- `routines/run-turn.ts` exports `IntelligenceLike` and `RunnerLike` — two narrow structural
  types — so a local implementation slots in without editing the file at all.

### `COPILOTKIT_LICENSE_TOKEN` is not a licence gate

`runtime.mjs` stores it and derives a telemetry id from it. Nothing validates it. The hard
requirement is OpenBot's own `config.ts` throw and nothing else.

### What that leaves

The engine is not the hard part, and it never was. Everything the product actually sells — per-agent
containers, the action gateway, the fail-closed policy engine, the append-only audit trail, secret
handling, workload identity, AG-UI, generative UI, routines, MCP plugins, connected accounts — is
already built, already good, and already MIT. Re-engineering the one part of it that touches a
hosted service, before a single user has seen a window, is the most expensive way to start.

What does not exist is the thing the product *is*: a native Mac app that makes any of it usable by
somebody who has never opened a terminal.

## Decision

**Wrap OpenBot. Do not re-engineer it.**

1. **Use the engine's features rather than rebuilding them.** Where OpenBot already does something,
   the app's job is to surface it well, not to own it. New xBot code goes in new files; the engine
   is driven, not rewritten.
2. **Keep CopilotKit Intelligence for v1.** Threads and memory stay hosted for now. The app ships
   with an Intelligence key configured at onboarding alongside the model key.
3. **Keep the local-mode seam in place, unimplemented.** `RuntimeCapabilities` keeps both modes,
   the three guards stay, and `history/local-intelligence.ts` records which methods a local
   provider would have to answer. It costs 136 lines to keep and makes ADR-0001 a later decision
   rather than a rewrite.
4. **The Mac client is the project.** Onboarding, the container lifecycle, the conversation, the
   panel, the design system, packaging.

## Consequences

### What this buys

The riskiest, longest, least visible work leaves the critical path. The v1 estimate drops from
~18–24 weeks to something closer to a client project, and the first thing built is the first thing
a user sees.

It also means the product inherits upstream's roadmap. Features landing in OpenBot are features
xBot can surface, at the cost of a merge review rather than an implementation.

### What this costs, stated plainly

**Two promises in [01-vision.md](../01-vision.md) do not hold in v1, and the vision document has
been changed rather than quietly reinterpreted.**

- **"No account."** Onboarding needs a CopilotKit key. It can be entered in the app rather than
  through a CLI, so the *no terminal* promise survives — but "no account" does not.
- **"Nothing leaves your machine except the calls you choose."** Conversation history and memory
  transit and rest on CopilotKit's infrastructure. Model calls were always outbound; this is
  different in kind, because it is the transcript rather than the request.

**This must be stated in the product, not just here.** Onboarding says where conversations are
stored, in one sentence, before the user types a key — not in a privacy policy, and not after.
An app whose pitch is local control must not be vague about the part that is not local.

**The business risk in ADR-0001 is real and is accepted, not solved.** A third party can change
its free tier. The seam is what keeps that from being fatal.

### When we revisit

Any of these reopens ADR-0001:

- CopilotKit changes Intelligence pricing or availability in a way that affects a consumer app.
- Onboarding testing shows the account step is where non-technical users stop.
- The native client's own usage shows which Intelligence methods it actually needs — it uses SSE
  rather than the browser's Phoenix websocket, so the surface a local provider must answer is
  smaller than the vendor's full client. **Measure this before estimating the work again.**

## Alternatives considered

**Implement ADR-0001 first, as planned.** Rejected on sequencing, not on merit. It remains the
right end state; doing it before the client exists means months before anyone can judge whether the
product is any good, and it would be built against a guess about which methods the native client
needs rather than a measurement.

**Fork the vendor package.** Rejected. `@copilotkit/runtime` is where the coupling lives, and
forking it turns every upstream release into a merge instead of a version bump — the exact trap
[03-openbot-fork.md](../03-openbot-fork.md) is written to avoid.

**Ship with no durable history at all.** Rejected outright. A conversation that forgets is not a
product, and upstream is right that there is no useful degraded mode.
