# CLAUDE.md

Instructions for Claude Code working in this repository. Read this before touching anything.

---

## What this project is

**xBot** is a native macOS app for working with AI agents — for a developer who lives in the
terminal and for someone who has never opened one.

It drives the agent CLIs a person already has and pays for (Claude Code, Codex; more to come) and
puts a native experience around them: projects, chats as tabs, and — being built — notes, bots with
a soul and a memory, a native model loop for people with an API key instead of a CLI, and **a
computer of its own for any bot that needs one**: a Linux VM on Apple's Containerization, with a
shell, files and a browser you can watch and take over.

The design follows [MonoCode](https://github.com/hardbeat920/monocode). xBot 1.x was built on
OpenBot in Docker; that was removed in the redesign.

### The one-sentence constraint

> **A user of xBot never opens a terminal, never edits a text file, and never reads a log to use
> the product.**

If a change would require the user to do any of those three things, it is not finished. Route it
through the app.

### Non-goals

- No hosted/SaaS version. Everything runs on the user's Mac; conversations stay there.
- No services: no Docker, no background daemon, no database server, no listening port.
- No Mac App Store build. See `docs/decisions/0005-distribution-outside-app-store.md`.
- No Windows or Linux client, and no Intel Macs or macOS before 26.
- No model of our own. The user brings a CLI subscription, a key, or Ollama.

---

## Read these before you plan anything

| File | Why |
| --- | --- |
| `docs/decisions/0009-native-harness-redesign.md` | Why the app is what it is now |
| `docs/superpowers/specs/2026-10-06-xbot-redesign-design.md` | The whole design, and the build order |
| `docs/02-architecture.md` | What runs, how a message becomes a reply |
| `docs/05-mac-app.md` | Modules and tests |
| `docs/08-design-system.md` | Tokens, motion, materials — non-negotiable |
| `docs/superpowers/plans/` | The plan for each sub-project, as built |

Docs marked "Describes xBot 1.x" at the top are history until their sub-project rewrites them.
**Read the ADR that covers a task before implementing it.**

---

## Things about the brains you must internalise

### 1. A harness turn is one process, prompt on stdin.

`HarnessBrain` starts the CLI per turn in the chat's folder, writes the prompt to stdin and closes
it, and resumes the CLI's own session id. **Never put the prompt in argv**: one starting with `-` is
read as a flag, and argv has a length limit.

### 2. A turn's stream ends exactly once.

Every `Brain.run` stream ends with one `.done` or `.failed`. A CLI that exits without saying which
has failed, and its stderr is the reason. Cancelling the consumer kills the process.

### 3. Parsers are tested against real output.

CLI stream formats belong to their vendors and change without notice. Fixtures in
`Tests/XBotBrainTests/Fixtures` are recorded from real runs (with personal paths removed). When a
format changes, record a new fixture; do not hand-write one from documentation.

### 4. A GUI app does not have the user's PATH.

`HarnessLocator` reads `PATH` from the login shell (with a timeout and markers, because shell
startup files print things), adds the usual install folders, and strips Claude Code's own
`CLAUDECODE*` variables so a nested `claude` will start.

---

## Repository layout

```
/
├── apps/mac/                 Swift package. The app.
│   ├── Sources/
│   │   ├── XBotApp/          @main, menus, Sparkle, quit handling
│   │   ├── XBotUI/           SwiftUI views and the design system
│   │   ├── XBotCore/         Models, SQLite store, Workspace
│   │   └── XBotBrain/        Brains: harness CLIs, stream parsers, locator (Foundation only)
│   └── Tests/
├── docs/                     Design, ADRs, specs and plans
├── scripts/                  Icon, bundling, signing, DMG, appcast, uninstaller
├── site/                     The website
└── CLAUDE.md
```

---

## Working agreements

### Before you write code

- **Plan first, in writing.** For anything larger than a single file, produce a short plan and get
  it agreed. Use the `superpowers:writing-plans` skill if available.
- **Check the build order in the redesign spec** for which sub-project the task belongs to. Work that
  jumps a sub-project usually means the order was wrong — say so rather than silently reordering.
- **Use `superpowers:brainstorming` before any new feature.** Requirements before implementation.

### While you write code

- **Test-driven where there is logic to test.** The stream parsers, the process runner, the store,
  the workspace, and later the policy gate, the native loop and the machine state machine all have
  real logic — write the test first.
  UI views do not need unit tests.
- **Small, focused changes.** One concern per commit.
- **Comments explain why.** Many in this codebase record a bug that was found the hard way. If you
  disagree with one, change the code and rewrite the comment to explain the new reasoning — do not
  just remove it.

### Before you claim it works

Use `superpowers:verification-before-completion`. Concretely:

```sh
# On a fresh clone the icon must be compiled first: Package.swift declares xBot.icns and Assets.car
# as resources and .gitignore excludes them, so `swift build` fails with "missing inputs" until this
# has run. It needs Xcode 26 — xBot.icon is Icon Composer's format.
scripts/generate-app-icon.sh
# --build-tests, not plain build: `swift build` does NOT compile the test targets, so a change that
# breaks only the tests looks green. This has produced a "verified" claim that measured nothing.
cd apps/mac && swift build --build-tests && swift test
# After a Claude Code or Codex update, or any change to a stream parser: a real turn and a resumed
# turn through each installed CLI. Costs a few tokens on your own subscription.
XBOT_LIVE_HARNESS=1 swift test --filter LiveHarnessTests
```

**Never say "done", "fixed", or "passing" without having run the command and read the output.**

**Local green is not CI green.** Both are worth checking — `gh run list -R MasterYoav/xBot`. Every
CI failure so far has been something that only exists on a fresh checkout: a generated file that
was never committed, a runner image without the right Xcode, a value spliced into a script that
only ever held a well-behaved string locally.

**Swift Testing runs suites in parallel.** Two suites touching one global — `UserDefaults.standard`,
the login Keychain, a `URLProtocol` stub's class-level fixtures — will pass alone and fail together,
roughly one run in three. That has happened three times in this codebase. The fix each time was to
inject the storage rather than serialise the suites, so **run a suspect suite ten times, not once.**

---

## Swift and SwiftUI conventions

- **Swift 6 language mode, strict concurrency.** Actors for anything touching the runtime or the
  network. `@MainActor` on view models.
- **Observation (`@Observable`), not `ObservableObject`.** macOS 26 is the floor.
- **No third-party UI frameworks.** SwiftUI and AppKit interop only. Sparkle is the one exception,
  for updates.
- **Views are dumb.** A view renders state and sends intents. Business logic lives in
  `XBotCore`/`XBotBrain`. If a view has a `URLSession` or a `Process` in it, that is a bug.
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
2. **Keys live in the macOS Keychain.** Never in SQLite, `UserDefaults`, a plist, a file the user
   could open, a log line, an error shown on screen, or a crash report.
3. **The audit trail is append-only** (when it lands with the tool server). Nothing in the app
   deletes an audit row.
4. **A secret's value is never echoed.** Record that it was supplied and its length.
5. **No listening ports.** The tool relay uses a Unix socket (0600), a bot's VM uses vsock.
6. **Destructive actions are confirmed once.** Deleting a chat or a bot (which deletes its
   computer) earns a confirmation; almost nothing else does.
7. **The app degrades honestly.** No CLI installed, a CLI signed out, a folder that moved, a
   library that will not open — say so, in a sentence, with the one button that fixes it. Never an
   empty state that implies everything is fine.
8. **A reply that has started is never lost.** Stop, failure and quit all save what arrived.

---

## Licensing and attribution

- `NOTICE` credits MonoCode (the design) and OpenBot by CopilotKit (xBot 1.x's engine). Keep both.
- The About window carries the same credits with live links; `AboutCreditTests` holds it to that.
- **Naming:** see `docs/decisions/0006-naming-and-trademark.md` before using the name "xBot" or any
  Grok/X-derived asset in shipped code, marketing copy, or icons. There is unresolved trademark risk
  recorded there. Do not resolve it yourself in a commit message.
- **Never commit `sparkle-private.key`.** Whoever holds it can sign updates every install accepts.

---

## When you are stuck or the spec is wrong

Say so. The docs in this repository were written before the code existed and will be wrong in
places. When you find a place where the spec and reality disagree:

1. Stop.
2. Say which document, which section, and what reality is.
3. Propose the change to the document as well as the code.

Do not implement around a wrong spec quietly. A doc that has silently drifted from the code is worse
than no doc.
