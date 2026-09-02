# Vision

## The product in one paragraph

xBot is a native macOS app for creating, managing, and talking to AI agents that run on your own
machine. Each agent gets a real computer of its own — a browser with its own logins, its own files,
its own shell — and only the tools you grant it. You watch it work, take the wheel when it reaches
something it should not do alone, and hand it back. Every model provider is supported through your
own API keys, including models running locally. You install it by dragging an icon into
Applications.

## Who it is for

Two audiences, and the tension between them is the interesting part of the design.

### The person who does not have a terminal

They have a Mac. They have heard that AI can "do things for you" and have found that in practice it
mostly writes text. They want an assistant that can actually open a browser, log into their airline
account, and check something — without them handing an API key to a company they have never heard
of, and without a subscription that reads their email on someone else's server.

What they need from us: **an install that is a drag, a first run that asks four questions, and a
chat window that behaves the way every other chat window on their Mac behaves.**

### The developer who lives in the terminal

They could clone OpenBot and run `scripts/start.sh`. Some of them have. What they do not want is to
own the operational surface of a Postgres instance, a supervisor, a browser container, and a
`.env` file with thirty settings in it, forever, on their laptop, in order to have a useful agent.

What they need from us: **the same product, plus escape hatches.** A visible container status.
A "reveal in Finder" for the workspace. An `xbot` CLI that talks to the same local API. Bring your
own agent endpoint. The ability to point it at Ollama and never make an outbound request.

### The design consequence

These two audiences want the same app with different depth. That is Apple's *simplicity* principle,
not minimalism: **the common path first, advanced options exactly one level deeper.** The default
path never mentions containers. The Advanced section never hides them.

## The promise

> **You never open a terminal. You never edit a text file. You never read a log.**

This is the product. Everything else in this repository is in service of it. When a design decision
is close, the tiebreak is whichever option keeps this promise intact.

### What the promise does not cover in v1

An earlier version of this document also promised *"no account"* and *"nothing leaves your machine
except the calls you choose."* **Neither holds in v1**, and they are corrected here rather than
quietly reinterpreted. See [ADR-0007](decisions/0007-wrap-openbot-keep-intelligence.md).

v1 runs on CopilotKit Intelligence for durable threads and memory, which means:

- **Onboarding asks for a CopilotKit key**, entered in the app. No terminal, no CLI — the central
  promise survives — but it is an account, and calling it anything else would be dishonest.
- **Conversation history transits and rests on CopilotKit's infrastructure.** Model calls were
  always outbound. This is different in kind, because it is the transcript rather than the request.

**Onboarding says this in one sentence, before the user types a key.** Not in a privacy policy,
not afterwards. An app that sells local control cannot be vague about the part that is not local.

The engine already boots without it — the seam is built and measured — so this is a v1 sequencing
decision, not a permanent shape. Everything else on this page is unchanged: the agents, their
computers, their browsers, their files, and the model keys are all yours and all local.

Concretely, that means the app owns:

- Detecting whether a container runtime is present, and installing or guiding installation if not.
- Pulling and updating images.
- Starting, stopping, and health-checking the engine.
- Generating and storing every secret the engine needs.
- Migrating the database.
- Surfacing failures as a sentence and a button, not a stack trace.

When something breaks — and it will, because Docker will be mid-update, or the port will be taken,
or the disk will be full — the app says what happened in one sentence and offers the action that
fixes it. The log exists, and there is a "Copy diagnostics" button for when the user wants to send
it to us. They are never asked to read it.

## What xBot is not

**Not a hosted service.** There is no xbot.com you sign into, no xBot account, and no subscription
to us. The engine, the agents, the browsers and the files are on your Mac. In v1 the conversation
transcript is the exception, and it is named as one above.

**Not a model provider.** xBot ships no intelligence of its own. You supply keys, or you run
Ollama and supply nothing. This is what makes "every AI" honest rather than a marketing line — we
have no incentive to steer you.

**Not a Mac App Store app.** An App Store app is sandboxed and cannot manage a container runtime.
See [ADR-0005](decisions/0005-distribution-outside-app-store.md).

**Not cross-platform in v1.** The engine is portable — it is containers. The client is deeply
macOS. A Windows or Linux client is a separate project that would reuse the engine and share
nothing else.

**Not a coding agent.** Claude Code, Cursor, and their peers own that shape and own it well. xBot's
agents have a shell because a computer without one is a toy, not because we are competing there.

## Why this can work

Three things are true at once, which is unusual.

**The engine is already good and already MIT.** OpenBot has per-agent container isolation, an action
gateway that resolves-decides-audits-then-acts, a policy engine that fails closed, SPIFFE workload
identity, and an audit trail designed by someone who has been on the wrong end of an incident
review. Building that from scratch is a year. It is available under a licence that lets us fork it.

**The consumer shape has been demonstrated.** Grok Bot showed that agents-as-contacts-in-a-chat-app
is legible to people who do not care about agents. A rail of avatars, a conversation, and a panel
showing what the thing is currently looking at. Nobody needs that explained.

**Nobody has done both.** The self-hosted agent platforms are developer templates. The consumer
agent apps are locked to one vendor's model and one company's servers. The gap is a native app that
is genuinely local and genuinely model-agnostic.

## The honest risks

Recorded here rather than discovered in month four.

**⚠️ The engine has a cloud dependency we are living with in v1.** OpenBot's server refuses to
start without CopilotKit Intelligence unless the seam described in
[ADR-0007](decisions/0007-wrap-openbot-keep-intelligence.md) is used. It is built and the engine
has been run without an account — but v1 ships on Intelligence, so a third party can change its
free tier and affect the product. The seam is what keeps that from being fatal rather than
inconvenient. [ADR-0001](decisions/0001-local-history-provider.md) remains the end state.

**⚠️ Container runtimes on macOS are a licensing and UX minefield.** Docker Desktop requires a paid
licence above a company-size threshold, is a large install, and is not something we can bundle.
Apple's own Containerization framework is the obvious long-term answer and is young. See
[ADR-0003](decisions/0003-container-runtime.md).

**⚠️ Resource cost is real.** Postgres, a Chromium per agent, and the engine will want several
gigabytes of RAM. On an 8 GB Mac with three agents this is a bad experience. The app must be honest
about this at onboarding and must cap concurrent browsers.

**⚠️ The name and the visual reference carry trademark risk.** See
[ADR-0006](decisions/0006-naming-and-trademark.md).

**⚠️ We inherit upstream's security posture and upstream's velocity.** OpenBot is alpha and moving.
Every merge from upstream is a review, not a pull. A fork that stops merging becomes an unmaintained
copy of a security-sensitive codebase within a year.

## What success looks like

**Milestone-level:** a non-technical person installs xBot, adds their keys, and has an agent book a
restaurant in a browser they can watch — with no instruction beyond what is on screen.

**The thing being tested is the app, not the engine.** OpenBot already does the hard part; nobody
outside this repository can currently use it. Success is that the distance between those two
sentences is closed by a window, an installer, and a first run.

**Product-level:** a developer chooses xBot over running OpenBot directly, because the operational
surface is not worth owning and the escape hatches are all still there.
