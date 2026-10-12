<div align="center">

<img src="assets/banner.png" alt="xBot" width="100%">

<h3><b>A crew of AI agents on your Mac, run from anywhere</b></h3>

Projects, chats, notes and a whole company of agents, built around the agent CLIs you already pay
for: Claude Code, Codex, Antigravity and GitHub Copilot.
Everything stays on your Mac. Your iPhone and iPad drive it over your network, or through your own
iCloud when you're away.

<a href="https://github.com/MasterYoav/xBot/releases/latest/download/xBot.dmg"><img src="https://img.shields.io/badge/Download_for_Mac-xBot.dmg-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Download xBot for Mac"></a>

macOS 26 · Apple silicon · [All releases](https://github.com/MasterYoav/xBot/releases)

[![CI](https://github.com/MasterYoav/xBot/actions/workflows/ci.yml/badge.svg)](https://github.com/MasterYoav/xBot/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/Swift-F54A2A?logo=swift&logoColor=white)](https://www.swift.org)
[![Xcode](https://img.shields.io/badge/Xcode-007ACC?logo=Xcode&logoColor=white)](https://developer.apple.com/xcode/)
[![macOS](https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=F0F0F0)](https://www.apple.com/macos/)
[![iOS](https://img.shields.io/badge/iOS-000000?&logo=apple&logoColor=white)](docs/14-iphone-and-ipad.md)
[![iCloud](https://img.shields.io/badge/iCloud-3693F3?logo=icloud&logoColor=fff)](docs/10-security.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

</div>

---

## What it is

xBot is a native Mac app for working with AI agents. Add any folder as a project and talk to an
agent about it in chats that sit as tabs in the title bar. Replies stream in as they're written,
each tool the agent uses folds into one line, and a Plan mode has the agent propose steps you can
edit before it runs them one by one. Beside the chat, the inspector shows the project's git
changes (commit, sync, pull requests and their checks) and its files. Each chat has its own
terminal window. Notes live as Markdown in the project folder, and Automations run agent steps on
a schedule, even while xBot is closed.

The agents are a **crew**: personas with a name, a role, instructions and a pixel-art look, each
working through one of your CLIs. They're organised like a company. HeadMaster is the CEO and
reports to you; a CTO or CFO reports to HeadMaster; engineers report to the CTO, and so on. You
decide who reports to whom, and xBot suggests what most companies do. Managers hand work to their
team, and finished work reports back up. On the Agents page the crew lives in a little
MapleStory-style world (a village, a sky realm, an underwater kingdom, a moonbase or an enchanted
forest) where they stroll, sit down at a desk to work and say what they're doing.

Underneath, there are no services. xBot starts the CLI for one turn at a time in the project's
folder, feeds it the prompt and reads its stream; the CLI's own sign-in, subscription and
permissions are used. Projects, chats and the crew are kept in one SQLite file on the Mac. The
**iPhone and iPad app** is a remote for that Mac: pair it with a QR code, and it reaches the Mac
directly on the same network or, away from home, through your own iCloud, with everything sealed
by the pairing key. It has the Mac's features (chats, projects and files, notes, automations, the
crew and their world, abilities, a real terminal, your profile and usage) in a Liquid Glass
interface.

You never open a terminal to use it. You never edit a configuration file. You never read a log.

## Download

**[Download xBot for Mac](https://github.com/MasterYoav/xBot/releases/latest/download/xBot.dmg)**
(`xBot.dmg`, always the newest release), or pick a version on the
[releases page](https://github.com/MasterYoav/xBot/releases). Open the disk image and drag xBot to
Applications. It's signed with Developer ID and notarized by Apple, so it opens without a warning,
and it updates itself (it asks first).

You need macOS 26 on Apple silicon and at least one agent CLI installed and signed in: Claude Code,
Codex, Antigravity or GitHub Copilot.

One limit for now: the downloaded build reaches your iPhone or iPad **on the same network only**. The
away-from-home lane through iCloud needs an iCloud entitlement that the released build doesn't carry
yet ([packaging](docs/11-packaging-and-updates.md#a-developer-id-release-with-icloud)). Built from
source and signed for your own team, it has both.

## Why it exists

xBot 1.0 ran [**OpenBot**](https://github.com/CopilotKit/openbot)'s agent platform in Docker on
the Mac. It worked, and it was heavy: a container runtime to install, an image to pull, a database
to migrate, and an agent loop that duplicated the ones people already pay for.

[**MonoCode**](https://github.com/hardbeat920/monocode) showed a lighter shape: a desktop app that
drives the agent CLIs people already have and puts projects, chat tabs, notes and personas around
them. xBot was rebuilt in that shape, natively in Swift
([ADR-0009](docs/decisions/0009-native-harness-redesign.md)), and went further: a crew organised
as a company, a world to watch them in, and a phone that runs it all from anywhere.

## Status

**xBot 2.0 is published from CI on every version bump**: changing [`VERSION`](VERSION) on master
builds, signs, notarizes and releases the `.dmg` ([how](docs/11-packaging-and-updates.md#releasing)).
The redesigned Mac app, the iPhone and iPad app and the company org chart are all on master, each
built test-first and verified live against a real Mac and a real iPhone. There are 443 package
tests, plus 18 live phone tests that run against a debug Mac. The iPhone and iPad app has no
download yet: it's installed from Xcode.

Not built yet: a native agent loop for API keys and Ollama, and a computer of its own for an agent
(a Linux VM on Apple's Containerization). [1.0.0](https://github.com/MasterYoav/xBot/releases/tag/v1.0.0)
was the old Docker app.

Start at [`docs/README.md`](docs/README.md). What's done and what's next is in
[`docs/12-roadmap.md`](docs/12-roadmap.md).

### Run the apps locally

```sh
scripts/generate-app-icon.sh                              # once per clone: compile xBot.icon (needs Xcode 26)
cd apps/mac && swift run                                  # the Mac app, debug build
cd apps/mac && swift build --build-tests && swift test    # 443 tests; plain `swift build` skips the test targets
XBOT_LIVE_HARNESS=1 swift test --filter LiveHarnessTests  # opt-in: real turns against the CLIs you have
cd apps/ios && xcodegen generate                          # the iPhone/iPad project, from project.yml
xcodebuild -project apps/ios/XBotMobile.xcodeproj -scheme XBotMobile \
  -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation build   # build for the simulator
```

Requires macOS 26 on Apple silicon and Xcode 26, plus at least one agent CLI installed and signed
in (Claude Code, Codex, Antigravity's `agy` or GitHub Copilot's `copilot`); xBot finds them on
your login shell's `PATH`. `swift build` fails with "missing inputs" until `generate-app-icon.sh`
has run. The phone's away-from-home lane needs the Mac app signed with the iCloud entitlement: see
[packaging](docs/11-packaging-and-updates.md). Running the iPhone app on a device needs your own
Apple Developer team in `apps/ios/project.yml`.

## Documentation

| | |
| --- | --- |
| [Documentation index](docs/README.md) | Reading order, conventions and every spec |
| [Vision](docs/01-vision.md) | What xBot is, for whom, and what it is not |
| [Architecture](docs/02-architecture.md) | What runs, how a message becomes a reply, storage, the remote |
| [Agents and providers](docs/04-model-providers.md) | The four agent CLIs: how each is run, models, reasoning, usage |
| [The Mac app](docs/05-mac-app.md) | Modules, ownership and tests |
| [First run](docs/06-onboarding.md) | What happens the first time, on the Mac and the phone |
| [Design system](docs/08-design-system.md) | Tokens, motion, materials, worlds, the phone's look |
| [UI specification](docs/09-ui-spec.md) | Every screen of the Mac app and the iPhone/iPad app |
| [Security](docs/10-security.md) | What xBot can do on your Mac, keys, pairing, the remote lanes |
| [Packaging and updates](docs/11-packaging-and-updates.md) | Building, signing, Sparkle, installing on a device |
| [Roadmap](docs/12-roadmap.md) | What's done, what's open, what's next |
| [Launch checklist](docs/13-launch-checklist.md) | What is left before a public 2.0, in order |
| [The iPhone and iPad app](docs/14-iphone-and-ipad.md) | The remote: lanes, pairing, protocol, features, tests |
| [Decisions](docs/decisions/) | ADRs 0001–0009. 0009 supersedes the 1.x engine decisions |
| [Design specs](docs/superpowers/specs/) | One spec per sub-project, from the redesign onward |
| [Plans](docs/superpowers/plans/) | Step-by-step plans for the larger sub-projects |
| [Changelog](CHANGELOG.md) | What changed since 1.0.0 |

## Built with

App updates use [Sparkle](https://sparkle-project.org) (MIT), and the terminals use
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT). The design follows
[MonoCode](https://github.com/hardbeat920/monocode) (MIT); xBot contains none of its code. xBot 1.x
was built on [OpenBot](https://github.com/CopilotKit/openbot) by [CopilotKit](https://copilotkit.ai)
(MIT); no OpenBot code ships any more. See [`NOTICE`](NOTICE).

xBot is not affiliated with, endorsed by, or sponsored by MonoCode, CopilotKit, Anthropic, OpenAI,
Google, GitHub, xAI or any other model provider. Their product names identify the tools you can
connect.

## Licence

MIT. See [`LICENSE`](LICENSE).
