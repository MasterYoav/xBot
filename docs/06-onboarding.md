# Onboarding

The single most important surface in the product. Everything xBot claims — that it is local, that it
is easy, that you never touch a terminal — is either proved or disproved in the first four minutes.

## The bar

**A person who has never heard of Docker installs xBot and talks to an agent, having typed only an
API key.**

If they see a container, a port, a shell command, or a log during a successful run, we failed. If
they see one during a *failed* run, we failed harder — that is when they need us most.

## Shape

A single fixed-size window, no resize, no minimise. Steps advance with a spring; the back button is
always live except during work that cannot be undone. There is no progress bar with fake segments —
each step says what it is doing.

```
   1  Welcome            what this is, one screen, no scrolling
   2  System check       silent when it passes
   3  Set up the engine  the long one. Honest about time
   4  Connect a model    the only step that asks for input
   5  Meet your agent    ends inside a real conversation
```

Five steps. Two of them ask nothing. **Exactly one asks for input**, and it is the one where the
user gets something in return.

---

## Step 1 — Welcome

One screen. A short line about what xBot is, three points about what makes it different, one button.

> **Your own AI coworkers.**
>
> Agents that run on your Mac, with their own browser and their own files.
>
> - Bring any model — or run one locally, with nothing leaving your Mac
> - Watch what your agents do, and take over whenever you want
> - Everything stays here. No account, no cloud
>
> [ Get started ]

No account creation. No email. No telemetry consent yet — that comes later, and separately, so it is
a real choice rather than a thing they click past to get in.

**Motion:** content arrives with a 40ms stagger, `bounce: 0`, `duration: 0.4`. Nothing bounces —
nothing was thrown.

---

## Step 2 — System check

Runs on entry, takes under two seconds, and **shows nothing if everything passes** — the window
advances on its own. Apple's *simplicity* principle: do not make the user acknowledge good news.

Checks:

| Check | Fail behaviour |
| --- | --- |
| macOS 14+ | Hard stop, with the version they have |
| Architecture | Informational. Affects runtime choice |
| Free disk ≥ 12 GB | Blocking, with actual free space and a Storage Settings link |
| Physical RAM | 8 GB → a warning about running one agent at a time. 16 GB+ → silent |
| Container runtime present | → the branch below |

### The runtime branch

The only genuinely hard moment in onboarding, because the honest answer is "you need another piece
of software."

**Detected and running** → silent, advance.

**Detected but not running** → "Docker Desktop is installed but not running." One button, **Start
Docker**. The app launches it and waits with a real progress state. No instruction to the user.

**Not detected** → the one screen where we must be straight:

> **xBot needs a container runtime**
>
> Your agents run in isolated containers so they can't touch the rest of your Mac. That needs one
> free piece of software.
>
> [ Install for me ]  — recommended
> [ I'll install Docker Desktop myself ]
>
> This takes about 5 minutes and around 4 GB.

**"Install for me"** installs the app's bundled choice — see
[ADR-0003](decisions/0003-container-runtime.md) — with a real progress bar and a phase label
("Downloading", "Installing", "Starting"). No terminal appears. It may require an administrator
password, which is a native macOS prompt and is fine.

**The manual path** opens docker.com and leaves the window on a live check that flips to a green
state and a Continue button the moment Docker appears. **The user does not come back and click
"Recheck".** We poll.

**⚠️ This is the highest-risk screen in the product.** It is where a non-technical user is most
likely to quit. It deserves the most iteration and the most user testing. If Apple's Containerization
framework matures enough to remove this screen entirely, that is worth a major version.

---

## Step 3 — Set up the engine

The long one: pulling an image of a few gigabytes over an unknown connection.

**Be honest about time and specific about phase.** A single indeterminate spinner for four minutes is
how you get a force-quit.

```
   Setting up xBot

   ●  Downloading the engine        1.2 GB of 3.4 GB · about 2 minutes left
   ○  Preparing storage
   ○  Starting up

   This is a one-time setup. Later updates are much smaller.

   [ Cancel ]
```

Phases:

1. **Download** — real bytes, real ETA from observed throughput. Resumable.
2. **Prepare storage** — create volumes, initialise Postgres, run migrations, generate secrets into
   the Keychain, negotiate ports.
3. **Start** — bring the engine up, poll `/health` until it answers as xBot.

**"It answers as xBot", not "the port is open."** Upstream's start script learned this the hard way
and Yoav's screenshots show the failure: a Homebrew Postgres already on 5432, xBot talking to the
wrong database, `role "openbot" does not exist`. The health check verifies identity, not liveness.
The app negotiates a free port before starting and never asks the user about it.

**Cancel is real.** It stops the pull, removes partial state, and returns to step 2. A cancel that
leaves a half-configured machine is worse than no cancel.

### When it fails

Every failure gets a sentence, a cause, and a button. Never a stack trace on screen.

| Failure | What we say | Button |
| --- | --- | --- |
| Network drops | "The download was interrupted." | Resume |
| Disk fills mid-pull | "Not enough space — needs 2.1 GB more." | Open Storage Settings |
| Ports occupied | *(nothing — we picked others)* | — |
| Runtime dies | "Docker stopped unexpectedly." | Restart Docker |
| Migration fails | "Couldn't set up the database." | Retry · Reset and try again |
| Anything unclassified | "Something went wrong setting up the engine." | Retry · Copy diagnostics |

**Copy diagnostics** puts a redacted report on the clipboard — versions, state machine history,
last 200 log lines, **no keys, no tokens, no conversation content.** It exists so the user can send
it to us, not so they can read it.

---

## Step 4 — Connect a model

The only step that asks for anything, and the one that returns something immediately.

> **Choose a model**
>
> xBot doesn't include an AI model. Connect one you have a key for, or run one on your Mac for free.
>
>   ○ Anthropic — Claude
>   ○ OpenAI — GPT
>   ○ Google — Gemini
>   ○ xAI — Grok
>   ○ Ollama — runs on your Mac, no key needed        [ Detected · 3 models ]
>
>   [ paste your key here                                              ]
>   Your key is stored in your Mac's Keychain and only sent to <vendor>.
>
>   [ Skip for now ]                                    [ Connect ]

**Details that matter:**

- **The key is validated before Continue enables.** One cheap models-list call. A key that is wrong
  is caught here, not on the user's first message.
- **The sentence about storage is not a disclaimer, it is the product.** Keychain, and only to that
  vendor. Say it where they are typing the key.
- **Ollama appears with live state.** Detected, with a model count → the row is selectable and asks
  for nothing. Not detected → shown greyed with a link. Never an install instruction.
- **Skip is allowed.** Someone evaluating the app should reach the UI. Skipping lands them in the app
  with a persistent, dismissible banner and a disabled composer that says why.
- **Paste is the primary input.** Handle a key with whitespace or a `Bearer ` prefix. Trim it. Do not
  reject on formatting.

---

## Step 5 — Meet your agent

Do not end on a "You're all set!" screen. End **inside the product, with something happening.**

The app creates a first agent — a general assistant with a generated avatar, on the model just
connected — and transitions the onboarding window into the main window with that conversation open
and one message already in it:

> **Hi. I'm your first agent.**
>
> I have a browser and files of my own, and I'll ask before doing anything that matters.
>
> Try me with something like:
> - "Find three well-reviewed ramen places near me and tell me which opens earliest"
> - "Open my calendar and summarise this week"
>
> You can make more agents any time with the **+** in the sidebar.

**Transition, not a jump.** The onboarding window becomes the main window: the panel expands, the
rail slides in from the left, the composer settles into place. Spatially continuous — Apple's
*spatial consistency*, and the moment the app stops being an installer and starts being an app.

---

## What onboarding writes

By the time step 5 completes:

| Where | What |
| --- | --- |
| **Keychain** | Vendor API key · engine bearer token · DB encryption key |
| **UserDefaults** | Onboarding version completed, window state, chosen runtime |
| **Runtime volumes** | `xbot-data` (Postgres) · `xbot-workspace` · `xbot-profiles` |
| **Engine DB** | The first agent, its channel, the first message |

**Nothing is written to a file the user could find and edit.** No `~/.xbot/config.yaml`. No `.env` in
Application Support. The configuration surface is the app.

---

## Re-onboarding

Onboarding is versioned. A user who completed v1 and updates to a build that adds a step sees only
the new step, as a sheet in the main window, not a fresh five-step flow. `OnboardingVersion` is an
integer; the app runs the steps between completed and current.

**Reset** lives in Settings → Advanced, is a two-step confirmation, and is explicit about what it
destroys: conversations, agents, and browser logins. It is the only path in the app that removes the
data volume.

---

## Testing onboarding

The path with the least test coverage and the most consequence. It gets more, not less.

- **Every failure branch has an automated test** with a fake runtime driver: no network, network
  drops at 40%, disk full at 80%, runtime dies during start, migration fails, port occupied by a
  process claiming to be Postgres.
- **The happy path is an XCUITest** on a clean machine image in CI.
- **Manual, before every release, on a genuinely clean Mac** — no Homebrew, no Docker, no developer
  tools. A VM snapshot. This catches the assumptions a developer's machine hides, and it is where
  the 5432 collision would have been caught.
- **Timed.** Record how long a clean install takes on a normal connection. If it grows past ten
  minutes, that is a regression with a bug number.
