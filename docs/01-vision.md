# Vision

## The product in one paragraph

xBot is a native Mac app for working with AI agents, and an iPhone and iPad app for working with
them from anywhere. It drives the agent CLIs people already have and pay for (Claude Code, Codex,
Antigravity, GitHub Copilot) and puts a real Mac experience around them: projects, chats as tabs,
plans you can edit, git, files, notes, a terminal, automations, and a crew of agents organised like
a company, living in a pixel-art world you can watch. Everything runs on your Mac, on your own
subscriptions. Nothing goes through a server of ours, because there isn't one.

## Who it is for

Two people, and the tension between them is the interesting part of the design.

### The developer who lives in the terminal

They already use Claude Code or Codex, often several at once, in several repos. What they want is
not another agent: it's a place to run the ones they have. Tabs instead of terminal windows. A
transcript that folds tool noise into one line. The diff, the branch, the pull request and its
checks beside the chat. Plans they can reorder before a single file is touched. The same work from
their phone when they're away from the desk.

What they need from us: **the CLIs they trust, with everything around them done properly, and
nothing taken away.** Each CLI's own flags, sessions and permissions are used, not reinvented. The
terminal is always one shortcut away.

### The person who has never opened a terminal

They have a Mac and a ChatGPT or Claude subscription, and they've heard agents can do things,
not just write. What they need from us: **a window that behaves like every other window on their
Mac**, plain sentences instead of errors, and agents that feel like people they can hand things to.
The crew, the world and the company structure are for them as much as for anyone: "ask HeadMaster,
and it hands the work to whoever does that" is something everybody understands.

### The design consequence

The same app, at different depths: **the common path first, advanced options exactly one level
deeper.** The default path never mentions a flag, a session id or a sandbox mode. The inspector,
the terminal and Abilities never hide them.

## The promise

> **You never open a terminal. You never edit a configuration file. You never read a log.**

When a design decision is close, the tiebreak is whichever option keeps this promise. In practice:

- When something fails (a CLI signed out, a limit reached, the Mac unreachable from the phone), xBot
  says what happened in a sentence and offers the one action that fixes it.
- Settings are screens, not files. Connectors, plugins and MCP servers are switched in Abilities,
  through the CLIs' own commands, never by editing their config.
- The terminal exists because developers want it, not because anyone needs it.

**Where the promise isn't kept yet.** Today a person needs at least one agent CLI installed and
signed in, and installing one means a terminal. xBot links to them from Home but can't install
them. The native agent loop for API keys and Ollama (below) is what closes this gap.

## What stays on the Mac

Projects, chats, the crew, notes, automations and usage live on the Mac, in one SQLite file and in
the project folders. What leaves it is what you send to the agent you picked: that's a request to
its provider, on your account, as if you'd typed it into the CLI. The phone reaches the Mac directly
on your network, or through your own iCloud with every message sealed by the pairing key.

## What xBot is not

**Not a hosted service.** No xBot account, no server, no subscription to us.

**Not a model provider, and not another agent.** xBot ships no intelligence of its own. The CLIs
are the agents; xBot is the place they work in. This is why it can support all of them honestly:
it has no reason to steer you to one.

**Not a sandbox.** An agent on Full access can do what you can. xBot passes each CLI's own
permission flags and says plainly what each mode allows. A computer of its own for an agent (below)
is where isolation will come from.

**Not a Mac App Store app.** A sandboxed app can't start the CLIs or a shell in your folders. See
[ADR-0005](decisions/0005-distribution-outside-app-store.md).

**Not cross-platform.** The Mac is where the agents run. The iPhone and iPad app is a remote for it,
not a second place to run them. There is no Windows, Linux or Intel Mac version.

## Where it is going

The [redesign spec](superpowers/specs/2026-10-06-xbot-redesign-design.md) set the direction, and
[the roadmap](12-roadmap.md) tracks it:

- **A native agent loop** for people with an API key or Ollama instead of a CLI, so nobody needs a
  terminal to start.
- **A computer of its own for any agent that needs one:** a Linux VM on Apple's Containerization,
  with a shell, files and a browser you can watch live and take over.
- **Agents with a memory** of their own, and habits that run on a schedule.
- **A paid tier**, xBot Pro, as a one-time purchase with a year of updates, verified offline.

## The honest risks

**⚠️ The CLIs' stream formats belong to their vendors and change without notice.** Each CLI has
its own parser, tested against output recorded from real runs, and a live test that runs real
turns. A format change is found by those, not by users, only if someone runs them.

**⚠️ Usage limits are read from the CLIs' own data,** which isn't a public interface either.

**⚠️ The iCloud lane needs a provisioning profile with iCloud** for the Mac app. Development builds
have one; a Developer ID release needs one from the developer portal before the phone works away
from home on a downloaded build.

**⚠️ The name and the visual reference carry trademark risk.** See
[ADR-0006](decisions/0006-naming-and-trademark.md).

## What success looks like

A developer replaces their pile of terminal windows with xBot for a week and doesn't go back. A
person who has never opened a terminal hires a crew, asks HeadMaster for something, and watches it
get handed down and done. Someone leaves home with only their iPhone and keeps working on their
Mac.
