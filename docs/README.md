# xBot documentation

Written before the code, so that the code has something to be measured against. Where a document
and the implementation disagree, one of them is wrong and it is worth finding out which — see the
last section of [`CLAUDE.md`](../CLAUDE.md).

## Reading order

Read 01 → 03 in order. They establish the problem, the shape of the answer, and the two hard
constraints everything else works around. After that, read by area.

### Foundations

1. **[Vision](01-vision.md)** — the product, the user, the promise, the non-goals.
2. **[Architecture](02-architecture.md)** — every service, every port, how a message becomes an
   action.
3. **[The OpenBot fork](03-openbot-fork.md)** — what we inherit for free, what is actively wrong
   for our purposes, and how much work each fix is. **The most important document here.**

### Engine

4. **[Model providers](04-model-providers.md)** — the router that turns a process-wide environment
   variable into per-agent choice, and how each vendor plugs in.
7. **[Container runtime](07-container-runtime.md)** — Docker, Colima, or Apple's Containerization
   framework, and the state machine the app drives it with.
10. **[Security](10-security.md)** — the Keychain, the credential vault, isolation, and the
    things that must never be written to disk.

### Client

5. **[The Mac app](05-mac-app.md)** — Swift packages, module boundaries, state ownership.
6. **[Onboarding](06-onboarding.md)** — first run, screen by screen, including every failure.
8. **[Design system](08-design-system.md)** — tokens, typography, motion, materials. Derived from
   Apple's *Designing Fluid Interfaces* and the eight design principles.
9. **[UI specification](09-ui-spec.md)** — the rail, the conversation, the panel, settings.

### Delivery

11. **[Packaging and updates](11-packaging-and-updates.md)** — DMG, Developer ID, notarization,
    Sparkle.
12. **[Roadmap](12-roadmap.md)** — milestones, and what "done" means for each.

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

## Conventions in these documents

- **"The engine"** is the forked OpenBot stack running in containers.
- **"The app"** is the native macOS client.
- **"An agent"** is what upstream calls a *coworker* or a *Bot*. We use *agent* in code and
  documentation. The user-facing word is decided in [09-ui-spec.md](09-ui-spec.md).
- **"The computer"** is the container holding one agent's browser, files, and shell. Upstream's
  term; kept, because it is a good one.
- A line marked **⚠️** is a known risk with no settled answer yet.
