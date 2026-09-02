# CLAUDE.md

Instructions for Claude Code working in this repository. Read this before touching anything.

---

## What this project is

**xBot** is a native macOS application that gives anyone — a developer who lives in the terminal
and someone who has never opened one — a way to create, manage, and talk to AI agents that run
entirely on their own Mac.

It is two things fused:

1. **An engine**, forked from [OpenBot](https://github.com/CopilotKit/openbot) (MIT, CopilotKit).
   Agents, per-agent containerised computers, a browser each agent drives, an action-policy
   gateway, an append-only audit trail.
2. **A native SwiftUI client**, which owns the entire user-facing experience: onboarding, the
   container lifecycle, the chat surface, settings, and updates.

### The one-sentence constraint

> **A user of xBot never opens a terminal, never edits a text file, and never reads a log to use
> the product.**

If a change you are making would require the user to do any of those three things, it is not
finished. Route it through the app.

### Non-goals

- No hosted/SaaS version of xBot. The app, the engine, the agents and their browsers run on the
  user's machine. **In v1 the conversation transcript is the exception** — it lives in CopilotKit
  Intelligence, and onboarding says so before the user types a key. See ADR-0007.
- No Mac App Store build. See `docs/decisions/0005-distribution-outside-app-store.md`.
- No Windows or Linux client in v1. The engine is portable; the client is not.
- No model of our own. xBot supplies no intelligence — the user brings keys or runs Ollama.

---

## Read these before you plan anything

Documentation lives in `docs/`. Read in this order the first time:

| File | Why |
| --- | --- |
| `docs/01-vision.md` | What we are building and for whom |
| `docs/02-architecture.md` | The whole system, service by service |
| `docs/03-openbot-fork.md` | What we inherit, what we change, what is broken for our purposes |
| `docs/04-model-providers.md` | The provider router — the biggest engine change |
| `docs/05-mac-app.md` | Swift target layout, module boundaries |
| `docs/06-onboarding.md` | First-run flow, screen by screen |
| `docs/07-container-runtime.md` | How the app drives Docker/container without the user knowing |
| `docs/08-design-system.md` | Tokens, motion, materials — non-negotiable |
| `docs/09-ui-spec.md` | Screen-by-screen spec |
| `docs/10-security.md` | Keychain, secrets, what never gets logged |
| `docs/11-packaging-and-updates.md` | DMG, signing, notarization, Sparkle |
| `docs/12-roadmap.md` | Milestones and what "done" means for each |
| `docs/decisions/` | ADRs. Every one is load-bearing. Read them. |

**Do not start an implementation task without reading the ADR that covers it.** The ADRs record
decisions that look wrong out of context and are right in context. Reversing one silently will cost
a week.

---

## Three things about the engine you must internalise

These shape most of the work. All are documented at length in `docs/03-openbot-fork.md`; the
summary is here because getting them wrong is expensive.

### 0. We wrap OpenBot. We do not re-engineer it.

**This is the most important line in this file.** Where the engine already does something, your job
is to surface it well. Before writing anything into `engine/`, check whether upstream already does
it — it usually does, and better than a first attempt would.

- ADR: `docs/decisions/0007-wrap-openbot-keep-intelligence.md`
- The value we add is the native client. The engine is driven, not rewritten.
- New xBot code goes in **new files**. A moved or heavily edited upstream file is a permanent merge
  conflict.

### 1. v1 runs on CopilotKit Intelligence, and the seam to leave it is already built.

OpenBot's `runtimeCapabilities()` in `server/src/config.ts` used to **throw on startup** unless all
four of `INTELLIGENCE_API_URL`, `INTELLIGENCE_GATEWAY_WS_URL`, `INTELLIGENCE_API_KEY` and
`COPILOTKIT_LICENSE_TOKEN` were set. It now selects a mode: all four means Intelligence, **none**
means local history, and a partial set still throws — for upstream's original reason, that somebody
who set two of four intended Intelligence and got it wrong.

**v1 sets all four.** The local mode exists, boots, and serves, but `LocalIntelligence` is a spike
that records which methods are reached and throws; it is not a provider yet.

- ADRs: `docs/decisions/0007-...` (the decision), `docs/decisions/0001-...` (the eventual design)
- Measured scope: `grep` says 156 references across 18 files; the **compiler** says 5 across 4.
  Trust the compiler. Widen the `RuntimeCapabilities` union and let it tell you.
- `COPILOTKIT_LICENSE_TOKEN` is telemetry only. The runtime validates nothing.
- **Never add a new direct call to the Intelligence client.** Go through the seam.

### 2. The model provider is a process-wide environment variable. We are making it per-agent.

Upstream reads `BOT_PROVIDER` once at process start in `agent-langgraph/src/index.ts`, supports
exactly `openai | anthropic | google`, and requires a container restart to change. Our users pick a
model per agent, from a settings pane, and expect it to take effect on the next message.

- ADR: `docs/decisions/0002-per-bot-model-router.md`
- **Never read a provider or model name from `process.env` in request-handling code.** Resolve it
  from the agent record via the model router.

---

## Repository layout

```
/
├── apps/
│   └── mac/                  Swift package + Xcode project. The native client.
│       ├── Sources/
│       │   ├── XBotApp/          @main, window/scene, app lifecycle
│       │   ├── XBotUI/           SwiftUI views, design system, components
│       │   ├── XBotCore/         Models, state, persistence
│       │   ├── XBotEngine/       API client, SSE/AG-UI stream, screen polling
│       │   ├── XBotRuntime/      Container runtime driver, health, image pulls
│       │   └── XBotOnboarding/   First-run flow
│       └── Tests/
├── engine/                   The OpenBot fork. Upstream layout preserved.
│   ├── server/
│   ├── app/                  Upstream React app. Kept for admin surfaces only.
│   ├── agent-bot/
│   ├── agent-runtime/        (was agent-langgraph) multi-provider agent
│   ├── agent-computer/
│   ├── supervisor/
│   └── docker-compose.yml
├── docs/
├── scripts/
├── CLAUDE.md
└── README.md
```

---

## Working agreements

### Before you write code

- **Plan first, in writing.** For anything larger than a single file, produce a short plan and get
  it agreed. Use the `superpowers:writing-plans` skill if available.
- **Check `docs/12-roadmap.md`** for which milestone the task belongs to. Work that jumps a
  milestone usually means the milestone was wrong — say so rather than silently reordering.
- **Use `superpowers:brainstorming` before any new feature.** Requirements before implementation.

### While you write code

- **Test-driven where there is logic to test.** The model router, the policy evaluation, the
  container state machine, and the credential store all have real logic — write the test first.
  UI views do not need unit tests; their behaviour is covered by snapshot and interaction tests.
- **Small, focused changes.** One concern per commit.
- **Preserve upstream comments in `engine/`.** OpenBot's source comments explain *why* a security
  boundary is where it is. Deleting one to tidy up has, upstream, previously reintroduced a
  vulnerability. If you disagree with a comment, change the code and rewrite the comment to explain
  the new reasoning — do not just remove it.
- **Match upstream conventions inside `engine/`**, our own inside `apps/mac/`. Do not import Swift
  house style into TypeScript or vice versa.

### Before you claim it works

Use `superpowers:verification-before-completion`. Concretely:

```sh
# Engine. The suite needs a real pgvector database; dev-db.sh starts one on 55432,
# because a Homebrew Postgres usually already owns 5432 and the engine then connects
# to the wrong database. Use test:ci, not test — it enforces a test-count floor, so an
# import-time failure that skips a whole file cannot pass as green.
eval "$(scripts/dev-db.sh)"
cd engine && bun run format:check && bun run lint && bun run typecheck && bun run test:ci

# Mac app
cd apps/mac && swift build && swift test
xcodebuild -scheme XBot -destination 'platform=macOS' test   # from M4, once the Xcode target exists
```

**Never say "done", "fixed", or "passing" without having run the command and read the output.**

---

## Swift and SwiftUI conventions

- **Swift 6 language mode, strict concurrency.** Actors for anything touching the runtime or the
  network. `@MainActor` on view models.
- **Observation (`@Observable`), not `ObservableObject`.** macOS 14+ is the floor.
- **No third-party UI frameworks.** SwiftUI and AppKit interop only. Sparkle is the one exception,
  for updates.
- **Views are dumb.** A view renders state and sends intents. Business logic lives in
  `XBotCore`/`XBotEngine`. If a view has a `URLSession` in it, that is a bug.
- **Every string the user reads goes through `String(localized:)`.** Even in v1 when English is
  the only language. Retrofitting localisation is miserable.
- **Design tokens only.** Never a raw hex value, a raw point size, or a raw duration in a view.
  Everything comes from `XBotUI/DesignSystem`. See `docs/08-design-system.md`.

### Motion is not optional polish

`docs/08-design-system.md` is derived from Apple's *Designing Fluid Interfaces*. The rules that get
violated most often, so check yourself against them:

- **Feedback on pointer-down, never on release.**
- **Every animation is interruptible.** Springs, not fixed-duration curves, for anything the user
  can touch. SwiftUI: `.spring(duration:bounce:)`, never `.easeInOut(duration:)` on a gesture path.
- **Default `bounce: 0`.** Add bounce only when a flick or drag preceded the motion.
- **Enter and exit along the same path.** A panel that slides in from the right dismisses right.
- **Honour `accessibilityReduceMotion` and `accessibilityReduceTransparency`** in the component,
  not at the call site.

---

## The things that must never regress

Treat these as invariants. A change that breaks one is wrong even if it passes CI.

1. **No terminal, ever.** No user-facing instruction anywhere in the product says "run", "open
   Terminal", "edit", or "paste this".
2. **Keys live in the macOS Keychain.** Never in `UserDefaults`, never in a plist, never in a file
   the user could open, never in a log line, never in an error message shown on screen, never in a
   crash report.
3. **The audit trail is append-only.** Nothing in the app deletes an audit row. Retention is a
   server setting.
4. **A secret's value is never echoed.** Upstream records that a secret was supplied and its
   character count. Keep that.
5. **The container's ports stay on loopback.** `127.0.0.1` bindings only. The agent's browser holds
   real logins.
6. **Destructive actions are confirmed once, and are undoable where possible.** Deleting an agent
   deletes its container and its browser profile — that is not undoable, so it is the rare case that
   earns a confirmation dialog. Almost nothing else does.
7. **The app degrades honestly.** If the engine is down, say so and offer the one button that fixes
   it. Never show an empty state that implies everything is fine.

---

## Licensing and attribution

The engine is a fork of OpenBot, **MIT licensed, © 2026 CopilotKit**.

- `engine/LICENSE` stays. Do not remove or rewrite the copyright line.
- `NOTICE` at the repo root credits OpenBot and CopilotKit. Keep it current.
- The About window credits OpenBot with a link. This is a requirement, not a courtesy.
- When you pull upstream changes, record them in `CHANGELOG.md` under a `From upstream` heading so
  the divergence stays legible.

**Naming:** see `docs/decisions/0006-naming-and-trademark.md` before using the name "xBot" or any
Grok/X-derived asset in shipped code, marketing copy, or icons. There is unresolved trademark risk
recorded there. Do not resolve it yourself in a commit message.

---

## When you are stuck or the spec is wrong

Say so. The docs in this repository were written before the code existed and will be wrong in
places. When you find a place where the spec and reality disagree:

1. Stop.
2. Say which document, which section, and what reality is.
3. Propose the change to the document as well as the code.

Do not implement around a wrong spec quietly. A doc that has silently drifted from the code is worse
than no doc.
