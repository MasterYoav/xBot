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
| M1 | Local history provider | **Conversation half done, ahead of v1.1.** See ADR-0008: a durable `LocalThreadRunner` ships in place of Intelligence, with no CopilotKit account needed. Memory/recall (pgvector) is still ADR-0001's, deferred to v1.1 |
| M2 | Model router | **Proven live against a real vendor** (see below). Registry + `openai-compatible` adapter, per-run resolution, selection stored on the agent, forwarded, and read back, Settings → Models, custom providers, **Ollama host-gateway routing**. **The `copilot.ts` hop is now covered by a test that drives the real client and asserts on the posted body** (`server/tests/copilot-model-selection.test.ts`). **Not yet done:** a second real vendor |
| M3 | Engine runs headless | **Done.** Image published to ghcr on every push to master; manifest pinned and fetched by the app at start |
| M4 | Mac app skeleton | **Done.** Rail, conversation, composer, panel, palette, design system, runtime driver |
| M5 | Connected | **Client done, and now driven against a real engine.** The engine image had no Bot and no model key ever reached it, so no agent could be created and no run could authenticate — fixed, see `docs/plans/managed-bot-and-model-keys.md`. `Tests/XBotEngineTests/LiveEngineTests.swift` exercises the real client against a throwaway engine. **No longer blocked on a CopilotKit key** — ADR-0008's `LocalThreadRunner` is what the client actually talks to; the `XBOT_LIVE_ENGINE_HAS_INTELLIGENCE=1` branch of that suite now only exercises the Intelligence path for a deployment that opts into it by hand |
| M6 | Onboarding | **In progress.** Five steps built, install-for-me, adoption, handoff transition, failure branches, runtime choice persistence; VM testing still open |
| M7 | Ship v1.0 | **In progress (unsigned).** Settings tabs (Agents, Computer, Usage) wired; the CopilotKit section is gone rather than finished — ADR-0008 means there is no key to replace or revoke. About window credits OpenBot; Sparkle scaffold + appcast scripts done. First-run supply chain verified anonymously. Signing certificates, CI secrets and publish still open — all remaining items need a person |

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

## M1 — The local history provider — **conversation half done; recall deferred to v1.1**

See [ADR-0008](decisions/0008-local-thread-runner.md) for what shipped, and
[ADR-0001](decisions/0001-local-history-provider.md) for the fuller design that is still v1.1's.

The measurement ADR-0007 asked for before re-estimating this — what the native client's SSE-only
usage actually needs, versus the vendor client's full surface — is now done: `LocalThreadRunner`
wraps the vendor's own `InMemoryAgentRunner`, adding durability (a `local_threads` Postgres table)
and hydration on restart. No `HistoryProvider` interface was built; `copilot.ts` branches on
`intelligence` vs. `localRunner` instead. This is smaller than the original plan below because it
skips the part that plan called "the bulk of the work" — a rework of `copilot.ts` against a new
interface — by wrapping the vendor's runner in place.

**Done, per ADR-0001's own criterion:** the engine starts and runs a full conversation with no
`INTELLIGENCE_*` variables set at all, and history survives a container restart. The Mac app has no
UI path left to connect a CopilotKit key at all.

**Still not done, and now explicitly v1.1's scope (see below):** pgvector recall/memory, and the
in-process realtime emitter for a hosted-gateway-shaped consumer — `LocalThreadRunner` has no
`identifyUser` and is guarded to `config.singleUser`, which is what xBot ships anyway.

The original plan, for the part still open:

- Schema: memory (pgvector).
- Recall/remember, tuned for chunking, embedding choice, and ranking.
- Tests: memory recall, relevance ordering.

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

An end-to-end conversation through the server no longer needs Intelligence credentials: with none
of the `INTELLIGENCE_*` variables set, `copilot.ts` runs on `LocalThreadRunner` (ADR-0008). That run
through the server is launch checklist item 5. Its engine half was run on 27 September against a
local Ollama model, and found three faults on this hop that every conversation hit; all three are
fixed and recorded there.

**Still open:** a second live vendor. The three native adapters are built and each is covered by a
test asserting which client a selection gets (`agent-langgraph/tests/models-build.test.ts`). Usage accounting is done — the agent sums `usage_metadata` across a turn and emits
`CUSTOM`/`xbot.usage` before `RUN_FINISHED`, and Settings → Usage shows it per agent.

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
- Plugins admin webview + native grant toggles. Other admin surfaces via **Engine admin…** (same webview).

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
- Uninstall, complete. **Done** — Settings → Advanced removes the container, volumes, Keychain items,
  preferences and the pre-upgrade dump (which it used to leave behind); `Uninstall xBot.command` ships
  in the DMG for somebody who already trashed the app.
- Admin surfaces embedded (webview). **Plugins admin ships; the audit trail is native rather than
  embedded, per ADR-0004's exception; every other surface opens in the same window at `/admin`, whose own sidebar reaches credentials,
  computers, playground and the rest.**
- Settings: General, Models, Agents, Computer, Advanced, Updates. **Built** — all seven panes, in the
  main window rather than a separate scene.
- The honest v1 limitations stated in the UI: shared browser, shared workspace. **Done** — Settings →
  Computer, in the wording docs/10-security.md specifies.
- Website with the download and the security explanation. **Built** — `site/index.html`, published by
  `.github/workflows/pages.yml`; enabling Pages is a one-time repository setting.

**The first-run supply chain is verified anonymously**, which is the part of "installs from the
website and uses it" that does not need a person. From a shell holding no credentials: the manifest
at `raw.githubusercontent.com/MasterYoav/xBot/master/manifests/engine-stable.json` answers 200, the
digest it names resolves at ghcr with an anonymous pull token, the repository is public, and the
bundled fallback in `XBotApp/Resources` is byte-identical to the published manifest — so a first run
with the network blocked still starts from a real pin rather than a placeholder. Every outbound URL
the app can show a person (OpenBot, Ollama, the docs) answers 200. CopilotKit is no longer one of
them — ADR-0008 means the app has nothing to link to there.

**The ordered version of all this is [13-launch-checklist.md](13-launch-checklist.md).** What still
needs a person, and cannot be done from here:

1. ~~A Developer ID certificate and notarization credentials, plus the CI secrets to use them.~~
   Done 29 September: xBot 1.0.0 shipped signed and notarized from `mac-release.yml`, and Gatekeeper
   accepts the downloaded DMG and app as "Notarized Developer ID".
2. A clean-VM run of onboarding end to end.
3. A second live vendor key, to close the last M2 item.

**Done when:** someone who has never seen the project installs from the website and uses it, without
help.

### The Intelligence wiring — resolved differently than planned

**Was:** the app passed no `intelligence`, so the engine booted into local mode, whose client throws
past wiring. It shipped a mode in which a conversation cannot work, and the first screen promised
"Everything stays here. No account, no cloud" — both of the things ADR-0007 said do not hold in v1.

**Now, per [ADR-0008](decisions/0008-local-thread-runner.md):** rather than wiring the app up to pass
a CopilotKit key — the fix this section originally planned — local mode was built out instead, since
no such key was available to build or verify against. The app has **no UI path left to connect one
at all**: no field in onboarding, no section in Settings, no `intelligence` ever passed to
`EngineEnvironment.Inputs`.

- `LocalThreadRunner` gives the engine durable local history with no account, satisfying ADR-0001's
  "no `INTELLIGENCE_*` variables, survives a restart" criterion.
- Onboarding says where conversations are kept **before** a model key is typed, and both the Welcome
  bullet and the model step's copy are asserted by tests, because the claim is the feature.
- The composer no longer has a "no conversation store" block at all — a running engine can always
  keep a conversation now, so the only thing left for it to be missing is a model.

**What is still open:** memory/recall (ADR-0001's pgvector half) and an actual Intelligence
end-to-end run, which nothing here needs but a future deployment configuring Intelligence by hand
still could.

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

### v1.1 — Recall and memory (the rest of ADR-0001)

[ADR-0008](decisions/0008-local-thread-runner.md) already made "no account" and "conversation
persists on this Mac" true in v1. What is left of ADR-0001 is the part `LocalThreadRunner`
deliberately does not do: pgvector-backed recall across conversations, tuned rather than a first
pass. Until it lands, an agent remembers everything sent within one conversation and nothing across
separate ones — which is also upstream's own behaviour without Intelligence's memory feature turned
on, not a regression xBot introduced.

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
