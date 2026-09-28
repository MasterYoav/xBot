<div align="center">

<img src="assets/banner.png" alt="xBot" width="100%">

<h3><b>Your own AI coworkers, on your own Mac</b></h3>

Create agents, give them a computer, watch them work, and take the wheel when you want to.
Bring any model: OpenAI, Anthropic, Google, xAI, or a model running locally through Ollama.
Your agents, their files, their browsers and your conversations stay on this Mac.

*Not released yet: there is no signed download. Build it from source below, and see the
[launch checklist](docs/13-launch-checklist.md) for what stands between here and a `.dmg`.*

[![CI](https://github.com/MasterYoav/xBot/actions/workflows/ci.yml/badge.svg)](https://github.com/MasterYoav/xBot/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/Swift-F54A2A?logo=swift&logoColor=white)](https://www.swift.org)
[![macOS](https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=F0F0F0)](https://www.apple.com/macos/)
[![Xcode](https://img.shields.io/badge/Xcode-007ACC?logo=Xcode&logoColor=white)](https://developer.apple.com/xcode/)
[![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=fff)](docs/07-container-runtime.md)
[![Ollama](https://img.shields.io/badge/Ollama-fff?logo=ollama&logoColor=000)](docs/04-model-providers.md)

</div>

---

## What it is

xBot is a native macOS app. You download a `.dmg`, drag it to Applications, and open it. Five
onboarding steps take you from there to your first agent: a system check, installing the container
runtime for you if you have none, starting the engine, connecting a model, and meeting the agent.

Behind the app, a full agent platform runs in a container on your Mac: each agent gets its own
computer with its own browser, its own files, and only the tools you grant it. Every action an agent
takes is decided against a policy before it happens and recorded in an append-only audit trail
after. Model keys live in the macOS Keychain, and the engine's ports are bound to loopback only.
Conversations are kept by the engine itself, in its own database, with no CopilotKit account
([ADR-0008](docs/decisions/0008-local-thread-runner.md)).

You never open a terminal. You never edit a configuration file. You never read a log.

## Why it exists

Two good things existed separately.

[**OpenBot**](https://github.com/CopilotKit/openbot) is a serious, well-built, self-hosted agent
platform, with per-agent isolation, an action gateway and a real audit trail. It is also a developer
template: you clone a repository, copy an `.env`, fill in credentials, and run a shell script.

**Grok Bot** showed what the consumer shape of this looks like: a chat app with a rail of agents,
a live view of what each one is doing, and settings you can actually find.

xBot is the fusion: OpenBot's engine, wrapped rather than rewritten
([ADR-0007](docs/decisions/0007-wrap-openbot-keep-intelligence.md)), a native Mac experience, and no
lock-in to any single model vendor.

## Status

**In development.** The native client ships the rail, conversation, composer, panel, command
palette, onboarding, in-window settings (General, Models, Agents, Computer, Usage, Audit, Updates,
Advanced), per-agent settings (model picker, plugin reach, handoff grants) and the plugins admin
webview, all wired to the real engine. On start the app pulls the multi-arch engine image pinned by
digest in [`manifests/engine-stable.json`](manifests/engine-stable.json).

What has been proven against a real engine: the model router answered a real vendor (Anthropic)
with per-run model selection, a deployment fallback and an `openai-compatible` endpoint in one
process. On 27 September a throwaway engine with no CopilotKit key held a three-turn conversation
with a local Ollama model, drove its browser through the client-tool loop, remembered across turns,
and kept every conversation intact through a restart.

Still open: a second live vendor, one intermittent fault seen only under the full live suite, a
clean-VM first run, and Developer ID signing, notarization, Sparkle keys and the first published
release. Those last items need an account holder.

Start at [`docs/README.md`](docs/README.md). The milestone table is in
[`docs/12-roadmap.md`](docs/12-roadmap.md), and what is left, in order, is in
[`docs/13-launch-checklist.md`](docs/13-launch-checklist.md).

### Run the Mac app locally

```sh
scripts/generate-app-icon.sh                    # compile xBot.icon → Assets.car + xBot.icns (fresh clones; needs Xcode 26)
cd apps/mac && swift run                        # debug: stub engine, full UI, no Docker
cd apps/mac && XBOT_USE_RUNTIME=1 swift run     # debug: real runtime path; press Start in the UI
cd apps/mac && swift build --build-tests        # compile the test targets too; plain `swift build` skips them
cd apps/mac && swift test                       # 328 Swift tests; the live-engine suites skip without an engine
scripts/build-engine-image.sh                   # dev: build xbot/engine:1 for the runtime path
scripts/check-engine-health.sh                  # dev: read-only /health check once the engine is up
eval "$(scripts/dev-db.sh)"                     # dev: pgvector database on port 55432 for the engine tests
cd engine && bun run test:ci                    # engine tests, with a test-count floor
scripts/bundle-mac-app.sh                       # wrap the release binary in XBot.app (after swift build -c release)
```

Requires macOS 14 or later and Xcode 26: the app icon is Icon Composer's format, and
`Package.swift` expects the compiled icon, so `swift build` fails with "missing inputs" until
`generate-app-icon.sh` has run. Release builds always use the runtime path and pull
`ghcr.io/masteryoav/xbot-engine@sha256:…`; for local development build `xbot/engine:1` or set
`XBOT_ENGINE_IMAGE=xbot/engine:1`. The bearer token and encryption key are generated on first run
and held in the Keychain. The first Start can take up to about two minutes while Postgres
initializes. If a start fails mid-boot, `docker rm -f xbot-engine` clears the container for a clean
retry; the data volume is kept. Unsigned local builds are ad-hoc signed, so macOS may ask for
Keychain access again after each rebuild.

## Documentation

| | |
| --- | --- |
| [Documentation index](docs/README.md) | Reading order and conventions |
| [Vision](docs/01-vision.md) | What we are building, for whom, and what we are not building |
| [Architecture](docs/02-architecture.md) | Services, ports, data flow |
| [The OpenBot fork](docs/03-openbot-fork.md) | What we inherit and what we have to change |
| [Model providers](docs/04-model-providers.md) | Per-agent model selection across every vendor |
| [The Mac app](docs/05-mac-app.md) | Swift target layout and module boundaries |
| [Onboarding](docs/06-onboarding.md) | The first-run flow, screen by screen |
| [Container runtime](docs/07-container-runtime.md) | Driving containers without the user knowing |
| [Design system](docs/08-design-system.md) | Tokens, type, motion, materials |
| [UI specification](docs/09-ui-spec.md) | Every screen |
| [Security](docs/10-security.md) | Keys, secrets, isolation, what never gets written down |
| [Packaging](docs/11-packaging-and-updates.md) | Signing, notarization, updates |
| [Roadmap](docs/12-roadmap.md) | Milestones |
| [Launch checklist](docs/13-launch-checklist.md) | What is left between here and a download, in order |
| [Engine environment mapping](docs/env-mapping.md) | App settings → container env vars |
| [Decisions](docs/decisions/) | ADRs 0001–0008. Read these before disagreeing with anything above |
| [Plan: computer client tools](docs/plans/computer-client-tools.md) | Giving agents their browser, files and shell through the Mac client |
| [Plan: managed Bot and model keys](docs/plans/managed-bot-and-model-keys.md) | A Bot in the engine image, and model keys that reach it |
| [Phase 1: ship readiness](docs/superpowers/specs/2026-09-17-phase-1-ship-readiness-design.md) | The evidence needed before a stranger can install xBot |

## Built on OpenBot

xBot's engine is a fork of [OpenBot](https://github.com/CopilotKit/openbot) by
[CopilotKit](https://copilotkit.ai), used under the MIT licence. Copyright © 2026 CopilotKit.
See [`NOTICE`](NOTICE) and [`engine/LICENSE`](engine/LICENSE). App updates use
[Sparkle](https://sparkle-project.org), also MIT-licensed.

xBot is not affiliated with, endorsed by, or sponsored by CopilotKit, xAI, X Corp., or any model
provider.

## Licence

MIT.
