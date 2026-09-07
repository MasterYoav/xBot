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
| M2 | Model router | **Proven live against a real vendor** (see below). Registry + `openai-compatible` adapter, per-run resolution, selection stored on the agent, forwarded, and read back, Settings → Models, custom providers, **Ollama host-gateway routing**. **Not yet done:** the same run through `copilot.ts` rather than straight at the agent, a second real vendor, usage accounting |
| M3 | Engine runs headless | **Done.** Image published to ghcr on every push to master; manifest pinned and fetched by the app at start |
| M4 | Mac app skeleton | **Done.** Rail, conversation, composer, panel, palette, design system, runtime driver |
| M5 | Connected | **Client done.** `scripts/verify-m5-handoff.sh` smoke check; model picker fallback from connected providers |
| M6 | Onboarding | **In progress.** Five steps built, install-for-me, adoption, handoff transition, failure branches, runtime choice persistence; VM testing still open |
| M7 | Ship v1.0 | **In progress (unsigned).** Settings tabs (Agents, Computer, Usage) wired; Sparkle scaffold + appcast scripts done; CI secrets + publish still open |

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

### Where it actually got to

The path is complete and every part of it is unit-tested; **none of it has answered a real vendor.**
That last step is the milestone's own done-criterion and it has not been run.

| Piece | Where |
| --- | --- |
| Provider registry, resolution, error classification | `engine/agent-langgraph/src/models/registry.ts` |
| Wire type + parser, shared across the boundary | `engine/shared/model-selection.ts` |
| The seam that was `BOT_PROVIDER` | `buildModel()` in `engine/agent-langgraph/src/index.ts` |
| Selection stored and forwarded | `configuration.modelSelection` → `forwardedProps.xbotModel` in `engine/server/src/copilot.ts` |
| Settings → Models, custom providers | `apps/mac/Sources/XBotCore/ModelSettingsState.swift` |

Two bugs found on the way, both silent and both shipped: the engine dropped `modelSelection`
entirely, and the client sent a display name under the wrong key on a partial PATCH that the
engine's PUT-shaped parser rejected with a 400 — so **every** agent edit failed while the app
reported success.

### The live smoke, and what it actually showed

Run against `agent-langgraph` with a real Anthropic key, one process, no restarts between requests:

| Check | Result |
| --- | --- |
| No selection — deployment fallback | answered |
| Selection naming a different model | answered |
| Selection naming a **bogus** model | `RUN_ERROR` 404 from the vendor |
| `openai-compatible` adapter, same process | answered |
| Switched back to the native adapter | answered |
| Custom provider with no base URL | "A custom provider needs the address of its endpoint." |
| Unknown provider | "bedrock is not a provider this engine knows. Use one of: …" |

**The third row is the one that proves it.** A bogus model in the selection reaching the vendor as a
404 means the selection's model is what gets sent — if it were being ignored the run would have
answered on `BOT_MODEL` and looked fine. That is precisely how this path failed three times already:
parsed but dropped, sent under the wrong key, stored but never read back. Each looked identical from
outside.

**What it did not show.** The run went straight at the agent's `/ag-ui`, so `copilot.ts` forwarding
`xbotModel` off the stored agent record is still only unit-tested. And one vendor key exists on this
machine, so "two agents on different providers" was met as two *adapters* — the native Anthropic one
and `openai-compatible` — rather than two vendors.

An end-to-end conversation through the server needs Intelligence credentials:
`runtimeCapabilities()` takes all four `INTELLIGENCE_*` variables or none, and none selects
`LocalIntelligence`, which is a spike that throws (ADR-0007).

**Still open:** native OpenAI/Google adapters (compatible mode covers them for now), usage
accounting, and the two gaps above.

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
and `/health` answers correctly. **Met.** `.github/workflows/engine-image.yml` builds and pushes to
`ghcr.io/masteryoav/xbot-engine` on every push to master, and `scripts/generate-engine-manifest.sh`
emits a manifest pinning the pushed digest rather than a tag — a tag can be moved.

**Shipped:** `EngineImageResolver` fetches `manifests/engine-stable.json` before each start, with
bundled fallback and a dev override via `XBOT_ENGINE_IMAGE`. Local `xbot/engine:1` remains the
fallback when nothing else resolves.

---

## M4 — The Mac app skeleton

**3–4 weeks. Can start during M1 against the stub.**

- Swift package, six targets, strict concurrency clean.
- `XBotRuntime`: driver protocol, `DockerDriver`, `FakeDriver`, the full state machine.
- `XBotEngine`: REST client, **SSE parser**, screen polling, `StubEngineClient`.
- `XBotCore`: `AppState` and the stores.
- `XBotUI/DesignSystem`: every token from [08](08-design-system.md).
- The main window: rail, conversation, composer, panel — working against the stub.
- Design system tokens from [08](08-design-system.md).

**Done when:** the app runs against `StubEngineClient` and looks and feels right, with no engine
present. **Met.**

---

## M5 — Connected

**2 weeks**

The two halves meet. As of this writing the **client half is in**: the app owns `RuntimeController`,
swaps `UnavailableEngineClient` for `HTTPEngineClient` when the runtime reports `.running`, creates
agents from the palette, streams turns, and takes/releases the browser. A dev-built `xbot/engine:1`
(`scripts/build-engine-image.sh`) unblocks local testing; production builds pull the pinned ghcr
digest from `manifests/engine-stable.json`.

**Still to close this milestone against a live container:**

- App drives a real engine end to end (dev image + `XBOT_USE_RUNTIME=1`; first boot ~2 min for Postgres).
- Live streaming into the conversation (client ready; needs a running engine).
- Live screen from the polled screenshot endpoint (client ready; needs a computer).
- Handover: take control, release control (client ready; needs a computer).
- Agent creation and settings, including the model picker and **plugins reach / handoff grants**
  (creation is in; engine-side model routing waits on M2).
- Activity panel — **fills from the stream.** Every tool call the agent makes becomes an entry, so
  it works against a live engine and not only the stub. It used to reach the message bubble and
  nowhere else, and `activity(for:)` returns an empty list on HTTP by design, so the panel promised
  "commands, files, and pages will show up here" and nothing could deliver it.
- Plugins admin webview + native grant toggles (partial — other admin surfaces still open).

**Done when:** create an agent in the app, send a message, watch it browse, take control, hand it
back — all native. `scripts/verify-m5-handoff.sh` covers the smoke path against a running engine.

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

- DMG, signing, notarization, stapling. Verified on a clean machine. **Unsigned DMG + bundle scripts
  exist locally and in `mac-release` CI; signing runs when secrets are set.**
- Sparkle with EdDSA. **Appcast generation scripted (`generate-appcast.sh`); publish + CI secrets
  still open.**
- Engine update flow including rollback, and the migration-rollback decision. **Done** — the dump,
  per docs/11's recommendation: taken before the new image can migrate, restored on rollback.
- Uninstall, complete.
- Admin surfaces embedded (webview). **Plugins admin ships; the audit trail is native rather than
  embedded, per ADR-0004's exception; credentials, playground, etc. still open.**
- Settings: General, Models, Agents, Computer, Advanced, Updates. **Built** — all seven panes, in the
  main window rather than a separate scene.
- The honest v1 limitations stated in the UI: shared browser, shared workspace. **Done** — Settings →
  Computer, in the wording docs/10-security.md specifies.
- Website with the download and the security explanation.

**Done when:** someone who has never seen the project installs from the website and uses it, without
help.

### The Intelligence wiring — resolved

**Was:** the app passed no `intelligence`, so the engine booted into local mode, whose client throws
past wiring. It shipped a mode in which a conversation cannot work, and the first screen promised
"Everything stays here. No account, no cloud" — both of the things ADR-0007 says do not hold in v1.

**Now:** ADR-0007 is Accepted and it decided this already; the code had simply never followed.

- `EngineBootstrap` passes all four `INTELLIGENCE_*`, from `IntelligenceCredentialStore`.
- The two URLs are constants; the licence token is generated per install, because ADR-0007 measured
  that nothing validates it and upstream's way of getting one is a terminal command; the API key is
  pasted at onboarding beside the model key.
- Onboarding says where conversations are kept **before** a key is typed, which is the placement the
  ADR specifies, and the Welcome bullet no longer claims otherwise. Both strings are asserted by
  tests, because the claim is the feature.
- Without the key the composer says so — `ComposerBlock.noConversationStore` — rather than letting a
  turn fail against an engine that otherwise looks healthy.

**Still open, and the reason this is not finished:** nothing has driven a conversation end to end
against an engine in Intelligence mode. That needs a CopilotKit key on the machine running it. Every
engine test sets the four variables, so the suite covers the mode; the app's own path to it has
never been exercised.

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

### v1.3 — The audit viewer, finished

**The viewer itself shipped in v1** — ADR-0004 requires it before v1.0 ("a native audit viewer
exists before v1.0 ships") and this roadmap had quietly moved it here, which is the kind of silent
ADR reversal CLAUDE.md warns costs a week. v1 has Settings → Audit: newest first, filter by event
type, paged.

What is left for v1.3 is the rest of that entry: filter by agent and by decision rather than by
event string, a date range, and export.

### v1.4 — Multi-agent channels

Several agents in one conversation, with handoff grants between them. The *Orchestrator* agent in the
reference screenshots is exactly this shape. **Basic support exists:** the command palette's `Tab`
verb creates a multi-agent channel; handoff grant toggles live in agent settings. What remains is
the full multi-agent composer UX (who you are addressing, turn routing polish) and richer channel
management.

### v1.5 — The CLI

`xbot` talking to the same local API. Send a message, list agents, tail activity, start and stop the
engine. This is the developer audience's version of the promise: the GUI is not the only way in.

### v1.6 — Skills and MCP, natively

Upstream has plugins and MCP. v1 ships native **grant toggles** and catalogue browsing in agent
settings, plus the full plugins manager in an admin webview. v1.6 is the rest natively: one-click MCP
install, connected-account management, and the remaining admin surfaces without a webview seam.

### Later, unordered

- **Bring your own agent, natively.** Register an AG-UI endpoint from the app. The engine already
  does this; it is a UI surface.
- **iOS companion.** Read conversations, approve handovers, get notifications. The Mac stays the
  engine; the phone is a remote. The reference's "Get Grok Bot for iOS" row suggests users will
  expect it.
- **Local model management.** Detect and surface MLX or llama.cpp alongside Ollama.
- **Shared agents.** Export an agent as a file another xBot user can import. Not a marketplace — a
  file.
- **Import agents you already have.** Bring in the agents, projects and custom instructions a person
  has already built elsewhere — Claude, Gemini, Copilot, ChatGPT — and from an `AGENT.md` /
  `CLAUDE.md` file on disk. The file case is the one to build first and the one that should ship
  alone if the others stall: it needs no vendor account, no OAuth, and no API that can be withdrawn,
  and a repository's own agent file is the format this audience already writes. The account
  importers are each a separate integration with a separate export format, so they are worth
  ordering by whichever has a real export endpoint rather than a scrape. **Open question:** what an
  imported agent inherits — a system prompt maps cleanly onto `roleDescription`, but tools, grants
  and memory do not, and an import that silently drops the tools an agent had is an agent that
  quietly stops working. Better to state what did not come across than to import it halfway.

---

## Explicitly not planned

Recorded so they do not get re-proposed every quarter.

- **A hosted version.** It would be a different product and would break the promise.
- **Windows or Linux clients.** The engine is portable; the client is not. A separate project.
- **Our own model.** We supply none. That is what makes "every AI" credible.
- **A plugin marketplace.** MCP is the ecosystem. We do not need a second one.
- **Team or multi-user features.** OpenBot already does this well and it is upstream's territory, not
  ours. A user who needs it should run OpenBot.
