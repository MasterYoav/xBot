# Roadmap

Milestones, ordered by risk rather than by visible progress. The riskiest work is first because
finding out it does not work in month one is cheap and finding out in month five is not.

Durations assume roughly one focused person plus Claude Code. They are estimates, not commitments,
and the ones marked ⚠️ have the widest error bars.

> **Re-ordered by [ADR-0007](decisions/0007-wrap-openbot-keep-intelligence.md).** The original plan
> put M1 — replacing Intelligence — in front of everything as "the gate". Having run the engine,
> that turned out to be neither the riskiest work nor a gate: the seam took 136 lines and the
> engine boots without an account. The real risk was always the part nobody had started, which is
> the app. **M1 is deferred past v1; the client moves to the front.**
>
> Ordering is now: engine running → client → connected → onboarding → ship.

## Status

| | Milestone | State |
| --- | --- | --- |
| M0 | Groundwork | **Done.** Engine vendored, CI, Swift package, dev database |
| M1 | Local history provider | **Deferred past v1.** Seam built and verified; see ADR-0007 |
| M2 | Model router | Not started |
| M3 | Engine runs headless | Partly — the app composes environment, allocates ports, and can `docker run`; **image not published** (dev build: `scripts/build-engine-image.sh`) |
| M4 | Mac app skeleton | **Done.** Rail, conversation, composer, panel, palette, design system, runtime driver |
| M5 | Connected | **Client done, live container blocked on M3.** HTTP client, runtime swap, create agent, send/stream, take/release control, tool-call rows, honest engine-down states |
| M6 | Onboarding | Not started |
| M7 | Ship v1.0 | Not started |

---

## M0 — Groundwork

**~1 week**

Set up so the rest can move.

- Fork OpenBot into `engine/`, preserving upstream layout. `NOTICE` and licence in place.
- Repo skeleton: `apps/mac/` Swift package with the six targets, `docs/`, `scripts/`.
- CI: engine (`format:check`, `lint`, `typecheck`, `test`) and Swift (`build`, `test`).
- Get upstream running locally *as upstream* — with a CopilotKit key — so we have a working baseline
  to break things against. **Do not skip this.** Debugging our fork without ever having seen the
  original work is a bad position.
- Apple Developer account, Developer ID certificate, notarization credentials in CI.

**Done when:** upstream runs on the machine; both CI pipelines are green on an empty Swift package.

---

## M1 — The local history provider ⚠️ — **DEFERRED PAST v1**

**3–5 weeks, and no longer first.** See
[ADR-0007](decisions/0007-wrap-openbot-keep-intelligence.md) for why, and
[ADR-0001](decisions/0001-local-history-provider.md) for the design, which still stands.

**What is already done:** `RuntimeCapabilities` has both modes, the three call sites are guarded,
and `history/local-intelligence.ts` enumerates what a local provider must answer. The engine has
been booted and driven with no `INTELLIGENCE_*` variables set at all.

**What is not:** the provider itself — threads, messages, pgvector recall, and the in-process
emitter that replaces the hosted realtime gateway.

**Before estimating this again, measure.** The native client uses SSE, not the browser's Phoenix
websocket, so the method surface it actually reaches is smaller than the vendor client's. That
measurement does not exist until M5 is connected, which is the real reason this comes later.

The rest of this section is the original plan, unchanged and still correct.

- `HistoryProvider` interface.
- Schema: threads, messages, memory (pgvector).
- `LocalHistoryProvider`: Postgres for threads and messages, pgvector for recall, an in-process
  emitter where upstream uses the hosted realtime websocket.
- `IntelligenceHistoryProvider` retained behind a setting, so the diff stays reviewable.
- Rework `runtimeCapabilities()` from a hard throw to provider selection.
- Rework `copilot.ts` — the bulk of the work — plus the six other call sites.
- Tests: thread lifecycle, message ordering, memory recall, concurrent turns, restart durability.

**Done when:** the engine starts and runs a full conversation with **no `INTELLIGENCE_*` variables
set at all**, and history survives a container restart.

**If this takes more than 6 weeks, stop and re-plan.** It would mean the coupling is deeper than the
64 references suggested, and the alternatives — vendoring differently, or a much thinner engine —
need to be back on the table.

---

## M2 — The model router

**2–3 weeks. Parallelisable with M3.**

See [ADR-0002](decisions/0002-per-bot-model-router.md) and
[04-model-providers.md](04-model-providers.md).

- Provider registry and `ModelProvider` interface.
- **`openai-compatible` adapter first.** It alone unlocks xAI, Ollama, OpenRouter, Groq, Together,
  LM Studio, and any corporate gateway.
- `model_selection` on the agent record; resolution order agent → workspace default → error.
- Keys from the credential vault, **not the environment**. Remove the `BOT_PROVIDER` read from the
  request path.
- Native Anthropic, OpenAI, Google adapters.
- Ollama detection via `/api/tags`.
- Error classification: no key / bad key / rate limited / model not found / no tool support.

**Done when:** two agents in the same engine, on different providers, both answer correctly, and
switching one from a dropdown takes effect on the next message with no restart.

---

## M3 — The engine runs headless

**2–3 weeks. Parallelisable with M2.**

Everything needed for the app to own the engine.

- Single-container image with `EMBEDDED_POSTGRES=on`, built from upstream's `Dockerfile`.
- Local bearer token auth on top of single-user mode.
- Configuration surface: settings → environment block. The `.env` file stops being a user-facing
  thing.
- Port negotiation.
- A `/health` response that identifies itself as xBot, with versions and schema version.
- The upstream `.env` → xBot settings mapping table, filled in and committed.

**Done when:** `docker run` with generated environment and three volumes brings up a working engine,
and `/health` answers correctly.

---

## M4 — The Mac app skeleton

**3–4 weeks. Can start during M1 against the stub.**

- Swift package, six targets, strict concurrency clean.
- `XBotRuntime`: driver protocol, `DockerDriver`, `FakeDriver`, the full state machine.
- `XBotEngine`: REST client, **SSE parser**, screen polling, `StubEngineClient`.
- `XBotCore`: `AppState` and the stores.
- `XBotUI/DesignSystem`: every token from [08](08-design-system.md).
- The main window: rail, conversation, composer, panel — working against the stub.
- Snapshot test harness, light and dark, default and accessibility text sizes.

**Done when:** the app runs against `StubEngineClient` and looks and feels right, with no engine
present.

---

## M5 — Connected

**2 weeks**

The two halves meet. As of this writing the **client half is in**: the app owns `RuntimeController`,
swaps `UnavailableEngineClient` for `HTTPEngineClient` when the runtime reports `.running`, creates
agents from the palette, streams turns, and takes/releases the browser. What is not in is a
published `xbot/engine` image — without it Start walks the real state machine and stops at a
sentence-bearing `.failed`, which is correct rather than a fake success.

**Still to close this milestone against a live container:**

- App drives a real engine end to end (needs M3's image).
- Live streaming into the conversation (client ready; needs a running engine).
- Live screen from the polled screenshot endpoint (client ready; needs a computer).
- Handover: take control, release control (client ready; needs a computer).
- Agent creation and settings, including the model picker (creation is in; picker has no real model list until M2).
- Activity panel (stub fixtures; live activity still empty on HTTP).

**Done when:** create an agent in the app, send a message, watch it browse, take control, hand it
back — all native. That last mile is M3, not more Swift.

---

## M6 — Onboarding

**3 weeks. Do not compress this one.**

See [06-onboarding.md](06-onboarding.md). It is the surface where the entire product promise is
proved or disproved, and it is the one most often given a week and shipped broken.

- All five steps.
- Runtime detection, install, and the manual path with live polling.
- Image pull with real progress and resume.
- **Every failure branch**, each with a sentence and a button.
- Diagnostics with tested redaction.
- Onboarding versioning.

**Done when:** a clean VM with no Homebrew, no Docker, and no developer tools goes from DMG to a
working conversation, with the tester typing only an API key. **Tested by someone who did not build
it.**

---

## M7 — Ship v1.0

**2–3 weeks**

- DMG, signing, notarization, stapling. Verified on a clean machine.
- Sparkle with EdDSA. Appcast published.
- Engine update flow including rollback, and **the migration-rollback decision made and implemented**.
- Uninstall, complete.
- Admin surfaces embedded (webview).
- Settings: General, Models, Agents, Computer, Advanced, Updates.
- The honest v1 limitations stated in the UI: shared browser, shared workspace.
- Website with the download and the security explanation.

**Done when:** someone who has never seen the project installs from the website and uses it, without
help.

---

## Total to v1.0

**~10–14 weeks** with M1 deferred, down from ~18–24. Call it **three to four months** for one
focused person.

The number that moves it most is now M6 (⚠️ if the runtime install path proves fragile across macOS
versions and Docker states). With M1 off the critical path, onboarding is the widest error bar in
the project — and it is the one that decides whether a non-technical person can use this at all.

---

## After v1.0

Ordered by value, not by ease.

### v1.1 — Local history (ADR-0001)

The deferred gate, done with a measurement behind it instead of an estimate. This is what makes
"no account" and "nothing leaves your machine" true, and until it lands both are stated as
limitations in onboarding and in the UI.

### v1.2 — Per-agent computers

The upstream compose topology with the supervisor: one container, one workspace, one browser profile
per agent. **This is the fix for the honest limitation v1 ships with**, and it is the highest-value
thing after launch. gVisor where the host supports it.

### v1.3 — Native audit viewer

The product's central trust claim should not be a webview. Filter by agent, by decision, by date.
Export.

### v1.4 — Multi-agent channels

The `Tab` verb in the command palette already implies this and the engine already supports channels.
Several agents in one conversation, with handoff grants between them. The *Orchestrator* agent in the
reference screenshots is exactly this shape.

### v1.5 — The CLI

`xbot` talking to the same local API. Send a message, list agents, tail activity, start and stop the
engine. This is the developer audience's version of the promise: the GUI is not the only way in.

### v1.6 — Skills and MCP, natively

Upstream has plugins and MCP. Expose them in native settings rather than the admin webview, including
one-click MCP server install.

### Later, unordered

- **Bring your own agent, natively.** Register an AG-UI endpoint from the app. The engine already
  does this; it is a UI surface.
- **iOS companion.** Read conversations, approve handovers, get notifications. The Mac stays the
  engine; the phone is a remote. The reference's "Get Grok Bot for iOS" row suggests users will
  expect it.
- **Local model management.** Detect and surface MLX or llama.cpp alongside Ollama.
- **Shared agents.** Export an agent as a file another xBot user can import. Not a marketplace — a
  file.

---

## Explicitly not planned

Recorded so they do not get re-proposed every quarter.

- **A hosted version.** It would be a different product and would break the promise.
- **Windows or Linux clients.** The engine is portable; the client is not. A separate project.
- **Our own model.** We supply none. That is what makes "every AI" credible.
- **A plugin marketplace.** MCP is the ecosystem. We do not need a second one.
- **Team or multi-user features.** OpenBot already does this well and it is upstream's territory, not
  ours. A user who needs it should run OpenBot.
