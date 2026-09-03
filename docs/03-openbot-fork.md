# The OpenBot fork

Read this one carefully. It is the difference between a three-month project and a nine-month one.

**Fork point:** OpenBot `main` @ `257c128`, vendored into `engine/` with `git subtree`, MIT
licensed, © 2026 CopilotKit. Upstream describes itself as *"a template, not a product"* and
*"alpha, and under active development."* Both are accurate and both are relevant.

> **The stance, since [ADR-0007](decisions/0007-wrap-openbot-keep-intelligence.md): we wrap this
> engine, we do not re-engineer it.** Where OpenBot already does something, our job is to surface
> it well. The two sections below were written as *blockers* before anyone had run the code; both
> turned out to be smaller than they read, and neither is on the critical path for v1. They are
> kept because the analysis is still correct and the work is still coming — just not first.

---

## What we get for free

This is why we are forking rather than building. Every item here is weeks-to-months of work that
already exists and is better than a first attempt would be.

**Per-agent computers.** A supervisor that creates one container per agent, each with its own
workspace volume and its own Chromium profile, so logins survive between turns and do not leak
between agents. Optional gVisor (`COMPUTER_RUNTIME=runsc`) underneath.

**The action gateway.** Resolve → decide → **audit** → act. The audit row is written before the
action, not after. A second row lands if a forwarded action fails.

**A policy engine that fails closed.** CEL expressions over `tool.name`, `intent`, `bot.id`,
`actor.id`, `page.url`, `page.host`, `element.*`, `key`, `file.*`, `mcp.*`. Deny rules evaluate
before allow rules. A missing policy permits nothing. A malformed policy stops startup.

**An append-only audit trail.** Nothing in the product deletes a row; retention is the only thing
that shrinks it. Control handovers are audited as first-class events
(`computer.help_requested`, `computer.control_taken`, `computer.control_released`). While a human
holds the browser, agent actions are refused rather than queued.

**Secret handling done correctly.** Secret entry is a separate channel from chat content. The audit
records *that* a secret was requested and its character count — never its value.

**Workload identity.** Optional SPIRE issues each computer an SVID based on supervisor-set
container labels. An agent cannot claim another agent's identity; an unregistered container gets
none.

**AG-UI.** Any agent endpoint, on any framework or hand-written, plugs in. Upstream ships examples
for LangGraph, Mastra, and Pydantic AI. This is what makes "bring your own agent" real for the
developer audience.

**A single-container image.** The root `Dockerfile` builds the whole laptop stack — app, API,
Chromium — onto one port under s6-overlay, with an optional embedded PostgreSQL
(`EMBEDDED_POSTGRES=on`). This is close to exactly what the Mac app wants to run.

**Generative UI, routines, MCP plugins, connected accounts, a component catalogue.** All present.

**Comments that explain security reasoning.** Upstream's source comments record *why* a boundary is
where it is, including at least one case where removing a boundary as "hardening" reintroduced a
vulnerability and the comment now records that. **Do not tidy these away.**

---

## Blocker 1 — the mandatory hosted service

### What is there

`server/src/config.ts`, `runtimeCapabilities()`:

```ts
const missing = Object.entries({
  INTELLIGENCE_API_URL: settings.apiUrl,
  INTELLIGENCE_GATEWAY_WS_URL: settings.gatewayWsUrl,
  INTELLIGENCE_API_KEY: settings.apiKey,
  COPILOTKIT_LICENSE_TOKEN: settings.licenseToken,
}).filter(([, value]) => !value).map(([name]) => name);

if (missing.length > 0) {
  throw new Error(
    `CopilotKit Intelligence is required and is not configured. Missing: ${missing.join(", ")}`,
  );
}
```

`.env.example` is explicit about what this is:

> *CopilotKit Intelligence. Required: the server refuses to start without all four because
> Intelligence owns durable threads and memory and a deployment without it forgets every
> conversation. **There is no degraded mode.***

The defaults point at `api.intelligence.copilotkit.ai` and
`wss://realtime.intelligence.copilotkit.ai`. Getting a key means signing into CopilotKit through
their CLI. Self-hosting Intelligence is an Enterprise feature deployed by Helm chart and explicitly
not self-serve.

### Why this is fatal for xBot

Every part of the promise breaks:

- **"Runs on your Mac."** Conversation history transits and rests on a third party's infrastructure.
- **"No account."** Onboarding would require a CopilotKit sign-in through a Node CLI — a terminal.
- **"Nothing leaves your machine except calls you choose."** Untrue.
- **Business risk.** A consumer app whose core function stops if a third party changes its free tier
  is not a product we can ship.

This is not a criticism of OpenBot. It is a self-hosted enterprise platform where a managed
intelligence layer is a reasonable dependency. It is simply the wrong shape for us.

### The fix

Introduce a **history provider interface** and implement it against the local database.

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
  in-process event emitter where upstream uses the realtime websocket gateway. **This is the xBot
  default and the only one onboarding can produce.**
- **`IntelligenceHistoryProvider`** — the existing behaviour, retained behind a setting. Keeping it
  means our diff against upstream stays reviewable and merges stay possible.

### Scope, as measured

The estimate below said *~64 references across 8 files*. Both numbers are now measured rather than
surveyed, and they disagree with each other in an instructive way.

| Measure | Result |
| --- | --- |
| `grep -i intelligence` over `server/src` | **156 hits across 18 files** |
| Type errors after widening `RuntimeCapabilities` | **5, across 4 files** |
| Lines actually changed to boot without an account | **136, across 4 files** |

The grep number is the one that looks like scope and is not. The compiler number is the real
structural coupling; the rest are comments, identifiers, and calls on an already-injected client.

Three places upstream had already done the work:

- `index.ts` carried the note *"If a second mode is ever added, THIS is the line that has to grow a
  guard, and the routine runner must then be left off `createApp` entirely."*
- `channels/thread-status.ts` is duck-typed on one `getThread` method, not the vendor class.
- `routines/run-turn.ts` exports `IntelligenceLike` and `RunnerLike` — narrow structural types — so
  a local implementation needs no edit to that file at all.

**And `COPILOTKIT_LICENSE_TOKEN` is telemetry, not a licence gate.** `runtime.mjs` stores it and
derives a telemetry id; nothing validates it. The only hard requirement is OpenBot's own throw.

The original survey, for reference:

**~64 references across 8 files.**

| File | Nature of the work |
| --- | --- |
| `server/src/config.ts` | Replace the hard throw with provider selection |
| `server/src/copilot.ts` (~1250 lines) | The bulk. Thread lifecycle inside the CopilotKit runtime |
| `server/src/intelligence-client.ts` (26 lines) | Becomes one implementation of the interface |
| `server/src/channels/routes.ts` | Thread listing and creation |
| `server/src/channels/thread-status.ts` | Live status — websocket gateway → local emitter |
| `server/src/routines/run-turn.ts` | Scheduled turns need a thread |
| `server/src/db/schema/core.ts` | New tables: threads, messages, memory |
| `server/src/app.ts`, `index.ts` | Wiring |

**Estimate: 3–5 focused weeks**, of which `copilot.ts` is most of it. The realtime gateway is the
subtle part — upstream uses a websocket to a hosted service for live thread status, and locally that
becomes an in-process emitter plus SSE to the client. Simpler, but every consumer has to be found.

**Risk if we skip it:** the two promises named in [01-vision.md](01-vision.md) — no account, and
nothing leaving the machine — do not hold, and a third party can affect the product by changing its
free tier. That is a real cost, and v1 accepts it deliberately.

**Do this when the client exists, not before.** The seam is built and the engine has been run
without an account, so this is no longer a gate. Doing it first would mean months before anyone
could judge the product, and it would be built against a *guess* about which methods the native
client needs. The app uses SSE rather than the browser's Phoenix websocket, so that surface is
smaller than the vendor's full client — **measure it before estimating this again.**

---

## Blocker 2 — the model provider is baked in at boot

### What is there

`agent-langgraph/src/index.ts`:

```ts
const PROVIDER = (process.env.BOT_PROVIDER ?? "openai").toLowerCase();
// ...
if (provider === "anthropic") return "claude-sonnet-4-5";
if (provider === "google")    return "gemini-2.5-flash";
// ...
`BOT_PROVIDER=${PROVIDER} is not one this Bot knows. Use openai, anthropic or google.`
```

**Status: replaced.** `buildModel()` now takes a selection resolved per run by
`agent-langgraph/src/models/registry.ts`, and this environment read survives only as the
deployment-wide fallback, evaluated once at boot. An OpenBot deployment that forwards no selection
behaves exactly as it did. See [ADR-0002](decisions/0002-per-bot-model-router.md).

Three consequences:

1. **Process-wide.** Every agent served by that container uses the same provider and model.
2. **Boot-time.** Changing it means editing `.env` and restarting a container.
3. **Three vendors.** No xAI, no Ollama, no Mistral, no OpenRouter, no Bedrock.

Yoav's screenshots show the actual expectation: separate agents named *Orchestrator*, *Grok*,
*Gmail*, *monday*, each with its own settings pane. That is per-agent model selection with a
restart-free change, which is the opposite of what upstream does.

### The fix

A **model router** that resolves provider and model *per request* from the agent record, with keys
read from the credential vault rather than the environment. Full design in
[04-model-providers.md](04-model-providers.md); ADR in
[0002](decisions/0002-per-bot-model-router.md).

### Scope

**Estimate: 2–3 weeks**, in three parts:

1. Schema and API: `model_selection` on the agent record; settings UI to set it. *(small)*
2. The router: resolve → fetch key → construct client → call. *(medium)*
3. Vendor adapters. *(medium, but parallelisable and mostly mechanical)*

**A useful shortcut for the first cut:** xAI, Ollama, OpenRouter, Groq, and Together all speak an
OpenAI-compatible API. Setting `BOT_PROVIDER=openai` with a per-agent `baseURL` covers all of them
through one adapter. That gets the demo working in days. It is not the end state — token accounting
and native tool-calling shapes differ enough that first-class adapters are worth having — but it
means Grok and Ollama can work in the app long before the router is finished.

**Risk if we skip it:** the product is a single-model app with a misleading settings screen.

---

## The rest of the divergence

Smaller, but each one is real work.

### Auth becomes one local user

Upstream supports Google, Microsoft, Okta, and registered SAML/OIDC providers, plus
`OPENBOT_SINGLE_USER=true` which admits every request as one administrator.

Single-user mode is what xBot wants and it already exists — but its warning applies:
*"while it is set, every visitor is an administrator."* On a laptop with loopback-only ports, the
practical exposure is another process on the same Mac. That is not nothing.

**xBot:** keep single-user mode, add a bearer token generated on first run and held in the macOS
Keychain, required on every request. The app has it; nothing else on the machine does. Sign-in stays
in the codebase and unreachable, so upstream merges stay clean.

### Configuration moves from a file to the app

Upstream's configuration surface is `.env` — well over a hundred documented settings. Our promise
forbids the user ever seeing it.

**xBot:** the app owns configuration. Settings are stored in the app's own store, rendered to an
environment block, and handed to the container at start. The user sees a settings pane. The `.env`
file becomes an implementation detail generated at runtime and never opened by hand.

**Consequence:** every new upstream `.env` setting is a decision — expose it, default it, or ignore
it. `docs/07-container-runtime.md` holds the mapping table, and it must stay current or the fork
rots.

### The React app becomes admin-only

Upstream ships a React/Vite app on `:3010` with ~30 routes: the conversation surface, agents,
routines, skills, settings, and a substantial admin section (audit, boundaries, computers,
credentials, identity providers, people, playground, plugins, components).

**xBot:** the product surface — conversation, agents, settings, onboarding, live screen — is native
SwiftUI. The admin surface is rendered in an embedded `WKWebView` in v1, because those screens are
dense, rarely opened, and already built. See
[ADR-0004](decisions/0004-native-vs-webview.md).

In the single-container image the API already serves the built web assets on the same origin, so
this costs nothing extra to run.

### The tenant package becomes app defaults

Upstream configures agents through YAML in a tenant package (`TENANT_PACKAGE_DIR`, shipping an
example `fintech` package with three coworkers).

**xBot:** a compiled-in default package with a small set of starter agents, and agent creation goes
through the app's UI writing to the database. The YAML path stays for the developer audience, exposed
as "Import agents from a package" in Advanced.

### Ports get negotiated

Upstream picks 3001, 3010, 4100, 4200, 4201, 4500, 5432, documents them, and expects you to fix
collisions by editing `.env`. On a developer's Mac, 5432 is very often a Homebrew Postgres already —
this exact failure appears in Yoav's own screenshots, where OpenBot connected to the wrong database
and the error was `role "openbot" does not exist`.

**xBot:** the app probes, allocates from a private range, records the choice, and never mentions it
unless the user opens Advanced.

---

## Merging from upstream

Upstream is alpha and moving fast. A fork that stops merging becomes an unmaintained copy of a
security-sensitive codebase within a year.

**Strategy: minimise surface, isolate ours.**

- Keep upstream's directory layout in `engine/`. Do not reorganise. A moved file is a permanent
  merge conflict.
- New xBot code goes in **new files** wherever possible. `history/local-provider.ts` and
  `models/router.ts` do not conflict; edits scattered through `copilot.ts` do.
- Where an upstream file must change, prefer **one seam** — swap a construction for an injected
  interface — over threading conditionals through it.
- Every upstream merge is a review, not a pull. Security-relevant diffs get read line by line.
- Record every merge in `CHANGELOG.md` under `From upstream`, with the upstream range.

**Merge cadence: monthly**, plus immediately for anything upstream flags as a security fix.

---

## Effort summary

| Work | Estimate | Blocking? |
| --- | --- | --- |
| Local history provider (ADR-0001) | 3–5 weeks | **No, since ADR-0007.** Seam built; deferred past v1 |
| Model router (ADR-0002) | 2–3 weeks | **Yes — the product is single-model without it** |
| Vendor adapters beyond OpenAI-compatible | 1–2 weeks | No — compatible mode covers most |
| Local-token auth | 3–4 days | **Done** — `EngineTokenStore`, bearer on loopback |
| Config surface → app settings | 1–2 weeks | **Done** — `EngineEnvironment` + [`env-mapping.md`](env-mapping.md) |
| Port negotiation + runtime driver | 1–2 weeks | **Done** — `DockerDriver`, adoption, `RuntimeController` |
| Admin webview embedding | 3–4 days | **Partially done** — plugins admin webview ships; other admin surfaces still open |
| **Engine total** | **~9–14 weeks** | |

The Mac client is estimated separately in [12-roadmap.md](12-roadmap.md). The two streams can run in
parallel after M1, because the app develops against a stub API.
