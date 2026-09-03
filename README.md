<div align="center">

# xBot

**Your own AI coworkers, on your own Mac.**

Create agents, give them a computer, watch them work, and take the wheel when you want to.
Bring any model — OpenAI, Anthropic, Google, xAI, or a model running locally through Ollama.
Nothing leaves your machine except the calls you choose to make.

</div>

---

## What it is

xBot is a native macOS app. You download a `.dmg`, drag it to Applications, and open it. It walks
you through everything else.

Behind the app, a full agent platform runs in containers on your Mac: each agent gets its own
computer with its own browser, its own files, and only the tools you grant it. Every action an agent
takes is decided against a policy before it happens and recorded after.

You never open a terminal. You never edit a configuration file. You never read a log.

## Why it exists

Two good things existed separately.

[**OpenBot**](https://github.com/CopilotKit/openbot) is a serious, well-built, self-hosted agent
platform — per-agent isolation, an action gateway, a real audit trail. It is also a developer
template: you clone a repository, copy an `.env`, fill in credentials, and run a shell script.

**Grok Bot** showed what the consumer shape of this looks like — a chat app with a rail of agents,
a live view of what each one is doing, and settings you can actually find.

xBot is the fusion: OpenBot's engine, a native Mac experience, and no lock-in to any single model
vendor.

## Status

**In development.** The native Mac client ships rail, conversation, composer, panel, command palette,
onboarding (five steps), agent settings (model picker, plugins reach, handoff grants), plugins admin
webview, and a settings skeleton — all wired to `RuntimeController` and `HTTPEngineClient` when the
engine is running. A published engine image (M3) is still required before a non-developer install path
works end to end.

Start at [`docs/README.md`](docs/README.md). The current milestone table is in
[`docs/12-roadmap.md`](docs/12-roadmap.md).

### Run the Mac app locally

```sh
cd apps/mac && swift run          # debug: stub engine, full UI, no Docker
cd apps/mac && XBOT_USE_RUNTIME=1 swift run   # debug: real runtime path — Start in the UI
cd apps/mac && swift test         # 99 unit tests (SwiftPM)
scripts/build-engine-image.sh     # dev: build xbot/engine:1 for the runtime path
scripts/check-engine-health.sh    # dev: read-only /health check once the engine is up
scripts/generate-app-icon.sh      # compile xBot.icon → Assets.car + xBot.icns
scripts/bundle-mac-app.sh          # wrap release binary in XBot.app (after swift build -c release)
```

Release builds always use the runtime path. The runtime path needs a local `xbot/engine:1` image
(built above) until M3 publishes a pinned digest manifest. Bearer token and encryption key are
generated on first run and held in the Keychain. First Start can take up to ~2 minutes while
Postgres initializes. If a start fails mid-boot, `docker rm -f xbot-engine` clears the container
for a clean retry (volumes are kept).

## Documentation

| | |
| --- | --- |
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
| [Engine environment mapping](docs/env-mapping.md) | App settings → container env vars |
| [Decisions](docs/decisions/) | ADRs — read these before disagreeing with anything above |

## Built on OpenBot

xBot's engine is a fork of [OpenBot](https://github.com/CopilotKit/openbot) by
[CopilotKit](https://copilotkit.ai), used under the MIT licence. Copyright © 2026 CopilotKit.
See [`NOTICE`](NOTICE).

## Licence

MIT.
