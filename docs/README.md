# xBot documentation

Written before the code, so that the code has something to be measured against. Where a document
and the implementation disagree, one of them is wrong and it is worth finding out which — see the
last section of [`CLAUDE.md`](../CLAUDE.md).

## Reading order

xBot was redesigned in October 2026: a native app that drives the agent CLIs people already have,
with no Docker and no services. Read [ADR-0009](decisions/0009-native-harness-redesign.md), then the
[redesign spec](superpowers/specs/2026-10-06-xbot-redesign-design.md), then:

1. **[Architecture](02-architecture.md)** — what runs, and how a message becomes a reply.
2. **[The Mac app](05-mac-app.md)** — modules, ownership, tests.
3. **[Design system](08-design-system.md)** — tokens, typography, motion, materials. Derived from
   Apple's *Designing Fluid Interfaces*. Still current.

The rest describe xBot 1.x and say so at the top. Each is rewritten in the sub-project that
touches it: [vision](01-vision.md), [model providers](04-model-providers.md),
[onboarding](06-onboarding.md), [UI specification](09-ui-spec.md), [security](10-security.md),
[packaging and updates](11-packaging-and-updates.md), [roadmap](12-roadmap.md),
[launch checklist](13-launch-checklist.md).

## Decisions

Architecture Decision Records. Each one exists because the decision looks wrong without its context.

| # | Decision |
| --- | --- |
| [0001](decisions/0001-local-history-provider.md) | Replace the mandatory hosted history service with a local provider |
| [0002](decisions/0002-per-bot-model-router.md) | Resolve the model per agent at request time, not per process at boot |
| [0003](decisions/0003-container-runtime.md) | Which container runtime the app drives, and how it hedges |
| [0004](decisions/0004-native-vs-webview.md) | Native SwiftUI for the product surface, embedded web for admin |
| [0005](decisions/0005-distribution-outside-app-store.md) | Developer ID and a DMG, not the Mac App Store |
| [0006](decisions/0006-naming-and-trademark.md) | Open questions about the name and the visual reference |
| [0007](decisions/0007-wrap-openbot-keep-intelligence.md) | **Wrap OpenBot rather than re-engineer it, and keep Intelligence for v1.** Defers 0001 and re-orders the roadmap — read it before 01 or 03 |
| [0008](decisions/0008-local-thread-runner.md) | **Conversations kept locally** by a durable wrapper around the vendor's SSE runner. Supersedes 0007's "keep Intelligence" for v1 |
| [0009](decisions/0009-native-harness-redesign.md) | **A native app that drives the agents people already have.** No Docker, no services; a bot's computer is an Apple Containerization VM. Supersedes 0001, 0002, 0003, 0007, 0008 |

## Conventions in these documents

- **"A harness"** is an agent CLI the person has installed and signed in to (Claude Code, Codex),
  which xBot drives on their subscription.
- **"A brain"** is whatever answers a turn: a harness, or later the native loop.
- **"A bot"** is a persona with a soul, a memory and optionally a computer (sub-project 3 onward).
- **"The computer"** is a bot's own Linux VM. Kept from 1.x, because it is a good word.
- A line marked **⚠️** is a known risk with no settled answer yet.
