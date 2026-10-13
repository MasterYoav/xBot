# xBot documentation

These documents describe xBot as it is built: the native Mac app, its crew of agents and the
iPhone/iPad remote. Where a document and the code disagree, one of them is wrong and it is worth
finding out which. The code wins until the document is fixed.

## Reading order

1. **[ADR-0009](decisions/0009-native-harness-redesign.md)**: why xBot is a native app that
   drives the agent CLIs people already have, with no services.
2. **[Vision](01-vision.md)**: what it is, for whom, and what it is not.
3. **[Architecture](02-architecture.md)**: what runs, how a message becomes a reply, storage,
   agents and hand-offs, automations and the remote.
4. **[The Mac app](05-mac-app.md)**: modules, ownership and tests.
5. **[The iPhone and iPad app](14-iphone-and-ipad.md)**: the remote, its two lanes and its tests.
6. **[Design system](08-design-system.md)**: tokens, motion, materials. Non-negotiable.

Then, as needed:

| Document | What it covers |
| --- | --- |
| [Agents and providers](04-model-providers.md) | Claude Code, Codex, Antigravity and GitHub Copilot: how each turn is run, models, reasoning, plan mode, usage limits |
| [First run](06-onboarding.md) | The welcome tour (agents installed in the app, file access, the phone), and pairing a phone |
| [UI specification](09-ui-spec.md) | Every screen of both apps, and the keyboard shortcuts |
| [Security](10-security.md) | What xBot can do on the Mac, what it stores and where, pairing, the remote lanes |
| [Packaging and updates](11-packaging-and-updates.md) | Building, signing, Sparkle, installing the phone app |
| [Roadmap](12-roadmap.md) | What's done, what's open, what's next |
| [Launch checklist](13-launch-checklist.md) | What is left before a public 2.0, in order |

## Decisions

Architecture Decision Records. Each one exists because the decision looks wrong without its
context. 0001–0003, 0007 and 0008 describe the 1.x engine and are superseded; they stay as history.

| # | Decision | Status |
| --- | --- | --- |
| [0001](decisions/0001-local-history-provider.md) | Replace the mandatory hosted history service with a local provider | Superseded by 0009 |
| [0002](decisions/0002-per-bot-model-router.md) | Resolve the model per agent at request time | Superseded by 0009 |
| [0003](decisions/0003-container-runtime.md) | Which container runtime the app drives | Superseded by 0009 |
| [0004](decisions/0004-native-vs-webview.md) | Native SwiftUI for the product surface | Accepted; 0009 removed the embedded web admin |
| [0005](decisions/0005-distribution-outside-app-store.md) | Developer ID and a DMG, not the Mac App Store | Accepted (the Mac app) |
| [0006](decisions/0006-naming-and-trademark.md) | The name and the visual reference | ⚠️ Open |
| [0007](decisions/0007-wrap-openbot-keep-intelligence.md) | Wrap OpenBot rather than re-engineer it | Superseded by 0009 |
| [0008](decisions/0008-local-thread-runner.md) | Conversations kept locally by the engine | Superseded by 0009 |
| [0009](decisions/0009-native-harness-redesign.md) | **A native app that drives the agents people already have** | Accepted |

## Design specs

One per sub-project, written before it was built. They record what was decided and why; where a
later change replaced part of one, the newer spec says so.

| Spec | What | State |
| --- | --- | --- |
| [Redesign](superpowers/specs/2026-10-06-xbot-redesign-design.md) | The whole 2.0 design and its build order | Step 1 built; see the [roadmap](12-roadmap.md) |
| [Plan mode](superpowers/specs/2026-10-08-plan-mode-design.md) | Propose steps, edit them, run them one by one | Merged |
| [Premium UI](superpowers/specs/2026-10-08-premium-ui-design.md) | The look: surfaces, sidebar, tabs, Home, replies | Merged |
| [Workspace panels](superpowers/specs/2026-10-08-workspace-panels-design.md) | The inspector (Changes, Explorer), account menu, profile | Merged |
| [Abilities and notes](superpowers/specs/2026-10-10-abilities-and-notes-design.md) | Connectors, plugins, skills, MCPs; project notes | Merged (#23) |
| [Agents workplace](superpowers/specs/2026-10-10-agents-workplace-design.md) | The crew, HeadMaster's hand-offs, the pixel world | Merged (#24) |
| [Agents sidebar world](superpowers/specs/2026-10-10-agents-sidebar-world-design.md) | The sidebar's miniature of the world | Merged |
| [In-app terminal](superpowers/specs/2026-10-10-in-app-terminal-design.md) | A terminal window per chat; Run on code blocks | Merged (#25) |
| [ASCII wallpaper](superpowers/specs/2026-10-10-ascii-wallpaper-design.md) | Agent-drawn text-art wallpapers | Merged (#26) |
| [Agent worlds](superpowers/specs/2026-10-10-agent-worlds-design.md) | The five worlds | Merged (#27) |
| [More providers](superpowers/specs/2026-10-11-more-providers-design.md) | Antigravity and GitHub Copilot | Merged (#28) |
| [Automations](superpowers/specs/2026-10-11-automations-design.md) | Scheduled agent steps, also while xBot is closed | Merged (#29) |
| [Mobile remote](superpowers/specs/2026-10-11-mobile-remote-design.md) | The iPhone/iPad app, its lanes, protocol and redesign | Open PRs #31–#42 |
| [Phase 1 ship readiness](superpowers/specs/2026-09-17-phase-1-ship-readiness-design.md) | 1.x: evidence before a stranger installs | History (1.x) |

The step-by-step plans for the larger sub-projects are in [`superpowers/plans/`](superpowers/plans/).
[`plans/`](plans/) holds two 1.x engine plans, kept as history.

## Conventions in these documents

- **"An agent CLI"** (or harness) is a command-line agent the person has installed and signed in
  to: Claude Code, Codex, Antigravity or GitHub Copilot. xBot drives it on their subscription.
- **"An agent"** or **"a crew member"** is a persona in xBot: a name, a role, instructions, a look
  and a manager, working through one of those CLIs. **HeadMaster** is the founding agent, the
  company's CEO; it reports to the person.
- **"The world"** is the Agents page's pixel-art scene; **"a setting"** is one of its five worlds.
- **"The remote"** is the iPhone/iPad app; **"a lane"** is how it reaches the Mac (local or iCloud).
- **"The computer"** is an agent's own Linux VM. Planned, not built.
- A line marked **⚠️** is a known risk with no settled answer yet.
