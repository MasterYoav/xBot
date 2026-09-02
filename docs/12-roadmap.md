# Roadmap

Milestones, ordered by risk rather than by visible progress. The riskiest work is first because
finding out it does not work in month one is cheap and finding out in month five is not.

Durations assume roughly one focused person plus Claude Code. They are estimates, not commitments,
and the ones marked ⚠️ have the widest error bars.

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

## M1 — The local history provider ⚠️

**3–5 weeks. The gate.**

Nothing ships without this. It is also the highest-uncertainty work in the project, which is why it
is first. See [ADR-0001](decisions/0001-local-history-provider.md).

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

The two halves meet.

- App drives a real engine end to end.
- Live streaming into the conversation.
- Live screen from the polled screenshot endpoint.
- Handover: take control, release control.
- Agent creation and settings, including the model picker.
- Activity panel.

**Done when:** create an agent in the app, send a message, watch it browse, take control, hand it
back — all native.

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

**~18–24 weeks**, with M2/M3 and M4 overlapping. Call it **five to six months** for one focused
person.

The two numbers that move it most are M1 (⚠️ if the Intelligence coupling is worse than it reads) and
M6 (⚠️ if the runtime install path proves fragile across macOS versions and Docker states).

---

## After v1.0

Ordered by value, not by ease.

### v1.1 — Per-agent computers

The upstream compose topology with the supervisor: one container, one workspace, one browser profile
per agent. **This is the fix for the honest limitation v1 ships with**, and it is the highest-value
thing after launch. gVisor where the host supports it.

### v1.2 — Native audit viewer

The product's central trust claim should not be a webview. Filter by agent, by decision, by date.
Export.

### v1.3 — Multi-agent channels

The `Tab` verb in the command palette already implies this and the engine already supports channels.
Several agents in one conversation, with handoff grants between them. The *Orchestrator* agent in the
reference screenshots is exactly this shape.

### v1.4 — The CLI

`xbot` talking to the same local API. Send a message, list agents, tail activity, start and stop the
engine. This is the developer audience's version of the promise: the GUI is not the only way in.

### v1.5 — Skills and MCP, natively

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
