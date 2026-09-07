# UI specification

Screen by screen. The interaction model is taken from the Grok Bot reference screenshots; see
[ADR-0006](decisions/0006-naming-and-trademark.md) on where the line sits between borrowing an
interaction model and copying trade dress.

**This document is the product.** Since [ADR-0007](decisions/0007-wrap-openbot-keep-intelligence.md)
the engine is wrapped rather than rebuilt, which makes everything below the actual work rather than
the reward at the end of it. OpenBot already does what the agents do; nobody outside a terminal can
use it. This is that gap, written down.

## What exists today

The app drives a `RuntimeController` and `HTTPEngineClient` in production, and still has
`StubEngineClient` for tests and for UI work without Docker.

| Surface | State |
| --- | --- |
| The rail | Built — selection on pointer-down, ⌘1–⌘9. Working ring, which follows the agent that is answering rather than the one selected. **All three badges wired**: unread when a reply lands out of sight, attention when an agent calls `ask_person` and stops |
| Conversation, header, status pill | Built — streaming, scroll-pinning that releases on scroll-up. Empty states distinguish engine-down, runtime-missing, failed-start, and no-agents |
| Message bubbles | Built — markdown, code blocks with highlighting and a copy button, compact tool-call rows. Images **not yet**. Handover and secret cards: see the note under *Content types* — the engine has no in-band request for either |
| The composer | Built — grow to five lines, ⏎/⇧⏎, disabled-with-reason (Start / Try again / Give it back), optimistic send |
| The right panel | Built — Screen, Activity, Routines, Agent settings (model picker, **What it can reach**, Connection, Handoff grants) |
| Command palette | Built — search, open, create. **`Tab` adds an agent to the current channel** (creates a multi-agent channel). Footer shows both verbs |
| Engine connection | Built — SSE parser, AG-UI decoder, HTTP client, runtime state machine, container adoption. A stopped-but-installed runtime is now **started** rather than reported as missing. Image published to ghcr; the app fetches `manifests/engine-stable.json` for a pinned digest before each pull |
| Design system | Built — tokens, aurora field, frosted glass, Reduce Motion and Reduce Transparency inside tokens |
| Onboarding | **Built (M6 in progress)** — five steps, Colima install-for-me, engine adoption, provider keys, handoff to main window. VM clean-machine validation still open |
| Settings | **In the main window, not a separate scene** — the gear at the foot of the rail, ⌘, and Escape. General, Models, **Agents** (defaults), **Computer** (policy presets + boundaries admin), **Usage** (placeholder), Updates, Advanced |
| Plugins & admin | **Partial** — native grant toggles in agent settings; Plugins admin window (`WKWebView` at `/admin/plugins` with bearer injection). **The audit trail is native** (Settings → Audit), which is ADR-0004's one exception to the webview rule. Credentials, playground and the rest **not embedded** |

## The main window

Three regions. Familiar, because a chat app should be.

```
┌────┬──────────────────────────────────────┬──────────────────────┐
│    │  Agent name          ⟨ Reconnecting ⟩│   ‹  Panel      ⚙ ›› │
│ R  ├──────────────────────────────────────┼──────────────────────┤
│ A  │                                      │                      │
│ I  │            conversation              │  Screen              │
│ L  │                                      │  Activity            │
│    │                                      │  Routines            │
│ 68 │                                      │  Agent settings      │
│ pt │                                      │                      │
│    ├──────────────────────────────────────┤   320–420 pt         │
│    │  ⊕  Message <agent>              🎤  │   resizable          │
└────┴──────────────────────────────────────┴──────────────────────┘
```

**Minimum window 900 × 600.** Below ~1100 the panel collapses to an overlay rather than a column.

---

## The rail

Fixed 68 pt. `Material.bar`. Vertical, top-aligned.

```
   ┌────┐
   │ 🎭 │   selected agent — filled background, radius 12
   ├────┤
   ────────  divider
   │ ✉️ │   agent
   │ ⚫ │   agent · unread dot
   │ 🟢 │   agent · attention badge (needs you)
   │    │
   │ +  │   new agent
   │    │
   │ 👤 │   you — bottom-anchored, opens the account menu
   └────┘
```

### Behaviour

- **Selection is instant.** The fill appears on pointer-down. The conversation may take a frame to
  load; the selection does not wait for it.
- **Reorder by drag**, 1:1 with the cursor, respecting the grab offset. Others displace with
  `Motion.reposition`. Release hands off velocity. Momentum projection picks the landing slot.
- **`⌘1`–`⌘9`** select. Visible in the command palette, as in the reference.
- **Hover** shows name and label in a popover anchored to the item, scaling from the item — not from
  its own centre.
- **Right-click** → Rename, Duplicate, Reset computer, Hide, Delete.

### The three badges

| Badge | Meaning |
| --- | --- |
| Dot (accent) | Unread messages |
| Ring (amber, pulsing slowly) | Working — a turn is in flight |
| Filled badge (attention) | **Blocked on you.** Needs a handover, a secret, or a decision |

The third is the important one and gets the strongest treatment, plus a dock badge and a
notification. An agent waiting for a human that nobody notices is the failure mode that makes the
whole product feel unreliable.

**All three are wired.** The ring follows `workingAgentID`, the dot follows `unreadAgents` — a turn
keeps running when the selection moves, so a reply can finish where nobody is looking — and the
attention badge follows `questionsForYou`.

**What lights the attention badge** is the engine's own escalation tool,
`server/src/agents/escalation.ts`. A Bot that needs judgement can guess, hand sideways to another
Bot, or ask the person; `ask_person` is the third, and calling it *ends the Bot's turn*. So an
outstanding call is exactly "blocked on you". The question comes from the call's arguments rather
than its result — the result is a sentence written for the model ("Ask it in your own words now"),
while the arguments carry what was actually asked. Answering in the composer clears it.

Blocked outranks working in the rail. An agent that has stopped to ask something is the state a
person most needs to see, so a working ring never covers it.

The tool's *name* is the contract, and upstream's renderer matches on it too
(`app/src/lib/copilot/escalation-tool.tsx`) — a rename there is a rename here.

**On the cards this document used to promise here:** `ask_person` reads as a compact tool row plus
the agent's own prose, and that is the whole of it — the engine has one escalation tool and it takes
a question, not a credential. See *Content types* below for why the secret card is not coming.

---

## The conversation

### Header

Agent avatar, name, and — centred, floating over the content — the **status pill**.

```
       ⟨  ◌  Reconnecting  ⟩
```

`Material.ultraThin`, capsule, a shadow that separates it from text beneath. It **materialises**:
blur radius and scale animate together on enter, so it reads as a surface arriving rather than an
opacity ramp. It is not part of the layout — content scrolls under it.

States: `Reconnecting` · `Starting up` · `Updating` · `Model not connected`. **When everything is
fine there is no pill.** Do not confirm good news.

### Messages

From the reference: incoming bubbles are light neutral fill, left-aligned, `Radius.large`. Outgoing
are near-black with white text, right-aligned, same radius. Both cap at ~70% of the conversation
width.

Content types:

| Type | Rendering |
| --- | --- |
| Text | Markdown. Code blocks with syntax highlighting and a copy button |
| Image | Inline, tappable to a full-size window. Both directions — the reference shows the user attaching an image and the agent returning one |
| Tool call | A compact inline row: what it did, its target, its result. Expandable |
| Handover request | Not in the transcript. **Take control** lives on the Screen panel, next to the browser it hands over — which is where a person is looking when they decide to take it |
| Secret request | **There is none, deliberately.** See below |
| Generated UI | Sandboxed `WKWebView`, no same-origin access. Fixed height, expandable |
| Error | Inline, with a retry action |

**Why there is no secret card.** This document originally specified "a card with a secure field,
never a normal message", and the instinct behind it is right: a secret typed into the composer goes
into the transcript, and for v1 the transcript rests on CopilotKit Intelligence (ADR-0007). But the
engine has no tool with which a Bot asks for one, and adding one would be re-engineering upstream
rather than surfacing it — CLAUDE.md's first rule about the engine.

It does not need one, because upstream already answers this better than a card would. The mechanism
is the **browser takeover**: the person takes control and types the password into the real login
form themselves. `server/src/computer/routes.ts` is explicit that this is the point — the takeover is
the audited event, and what the person typed during it is deliberately unrecorded, "because the
reason a takeover exists is to let them enter the thing nothing else should keep."

A card would have been strictly worse: it puts the secret through our process, our transcript and our
memory on the way to the same field. The takeover never lets it leave the browser. So the secure
field stays where it already is — in the page — and the app's job is to make handing over easy,
which is the button on the Screen panel.

**Streaming.** Tokens append without re-laying-out the message. The scroll pins to the bottom while
the user is at the bottom, and **releases the moment they scroll up** — with a "jump to latest"
affordance. Yanking someone back to the bottom mid-read is the single most-hated behaviour in chat
UIs.

**Hover actions** appear on the bubble: `…` (more), forward, react. Instant on hover, no delay.
Visible in the reference on both incoming and outgoing bubbles.

### The composer

```
  ┌──────────────────────────────────────────────────┐
  │  ⊕   Message Orchestrator                    🎤  │
  └──────────────────────────────────────────────────┘
```

- **Grows to five lines**, then scrolls. `Radius.xlarge`.
- **`⊕`** — attach files, attach an image, insert a skill.
- **`🎤`** — push-to-talk dictation, using the system speech recogniser. Filled circle when active.
- **`⏎` sends. `⇧⏎` newline.** Not configurable. Every chat app on this machine works this way.
- **Disabled with a reason, inline.** "Connect a model to start" with a Settings link. Never a toast,
  never a silent no-op.
- **Sending is optimistic.** The bubble appears immediately with a sending state. Failure turns it
  into a retryable state — the text is never lost.

---

## The right panel

Parallel and non-blocking: translucent, offset, **no scrim**. It sits beside the conversation rather
than over it, which is why the reference shows both at once. Collapses with `»`; enters and exits to
the right, always.

### Screen

The live view of the agent's browser. A polled screenshot endpoint — cadence adapts: fast while a
turn runs, slow when idle, **stopped when the panel is not visible**.

- **Aspect-preserving, letterboxed.** Never stretched.
- **Take control** overlays the frame. While a human holds it, agent actions are *refused, not
  queued* — upstream's behaviour, and correct. The panel says so.
- **Empty state:** a monitor glyph and "*Agent*'s screen", as in the reference. Not "No data."
- **Detach to its own window** for real work. `WindowGroup`, one per agent.

### Activity

What the agent did away from the browser: every command with its output and exit code, every file
read, write, and listing. Newest first. Monospaced.

**Say what this is.** Upstream is precise and we should be too: Activity is held in the client for
the open conversation and is gone on reload. It is a window, not a record. **The record is the audit
trail** — server-side, survives restarts, and is what an investigation reads. A footer links to it.

A saved file contributes its path and size, never its contents. An agent may be saving something it
was told in confidence.

**What is built.** Entries come from the turn's own stream — every `TOOL_CALL_START` becomes one —
rather than from a fetch, which is what "held for the open conversation" means in practice. So a
call carries the tool's name and, for now, an `ActivityEntry.Kind.tool` rather than a command's exit
code or a page's URL: `TOOL_CALL_ARGS` arrives separately, keyed by tool-call id rather than by
message, and inventing `command(exitCode: 0)` to fill the richer shape would claim a call succeeded
when nothing said so. Pairing the arguments back to their call is what turns these into the command,
file and page rows described above.

### Routines

Recurring scheduled tasks. Empty state, from the reference:

> Routines are recurring tasks this Bot runs on a schedule.
>
> [ Create Routine ]

Each routine: name, schedule in plain language ("Weekdays at 9:00"), last run and its outcome,
enable toggle.

### Agent settings

Editing is **in place**, saved on blur. No Save button, no dialog.

```
              ┌─────────┐
              │  avatar │      ← click opens the picker
              └─────────┘

   Name         [ Orchestrator                    ]
   Label        [ Orchestrate and use the other…  ]
   Description  [                                 ]
                [ What this Bot is for            ]

   Model        [ Claude Sonnet 4.5             ⌄ ]
                Anthropic · vision · tools

   Notifications                              ( ●  )
   Get notified when this Bot finishes or needs input

   What it can reach                          ⌄
   Connection                                 ⌄
   Handoff grants                             ⌄

   Duplicate · Reset computer · Delete
```

The **Model** row is the xBot addition and the reason the router exists. It shows the current model,
its provider, and its capabilities. Choosing takes effect on the next message.

### The avatar picker

From the reference: a popover with four tabs and a two-part grid.

```
  ┌──────────────────────────────────────────┐
  │  Bot    Generate    Upload        Reset  │
  ├──────────────────────────────────────────┤
  │   ⬤   ⬬   ▢   ▭                          │
  │   ▲   ⬢   ☁   ◗                          │   shapes
  │                                          │
  │   ●  ●  ●  ●  ●  ●                       │   colours
  │   ●  ●  ●  ●  ●                          │
  └──────────────────────────────────────────┘
```

- **Bot** — the shape + colour grid. Generated locally as an SVG. No network.
- **Generate** — an image from the connected model, if it supports images. **Greyed with a reason if
  not**, rather than failing on click.
- **Upload** — a file, cropped to a square.
- **Reset** — back to the generated default.

Scales from the avatar it was opened from, not from its own centre.

---

## The command palette

`⌘K`, or clicking `+` in the rail. From the reference:

```
  To: | Search or create Bots
  ┌───────────────────────────────────────────────┐
  │  +   Create new Bot                    ⌘ 1    │
  │  ✉️   Gmail                             ⌘ 2    │
  │  🎭  Orchestrator                      ⌘ 3    │
  │  ⚫  Grok                              ⌘ 4    │
  │  🟢  monday                            ⌘ 5    │
  ├───────────────────────────────────────────────┤
  │                          Tab add    ⏎ open    │
  └───────────────────────────────────────────────┘
```

Fuzzy search over name, label, and description. **`Tab` adds an agent to the current channel; `⏎`
opens it** — the two-verb model in the reference, and the entry point to multi-agent channels. The
footer states both, because a keyboard affordance nobody knows about does not exist.

---

## Settings

**In the main window, not a `Settings` scene.** A list on the left and the pane on the right, the
shape macOS System Settings uses and the one the rail already establishes here. Opened by the gear
at the foot of the rail, by ⌘,, and closed by Escape or the back chevron.

A separate floating panel was tried first and removed: it put settings somewhere a person had to go
and find, and it hid the rail — so which agent was selected stopped being visible while its model
was being changed.

**Shipped today:** General, Models, **Agents** (default model + description; shared preamble deferred), **Computer** (auto-review + preset deny rules + boundaries admin webview), **Usage** (honest placeholder — engine accounting still open), Updates (Sparkle scaffold + engine install with health rollback), Advanced (Plugins, uninstall).

| Tab | Contents |
| --- | --- |
| **General** | Account (local), appearance, language, microphone, timezone, launch at login |
| **Models** | Providers, keys, Ollama detection, default model. See [04](04-model-providers.md) |
| **Agents** | Defaults for new agents, the shared instruction preamble |
| **Computer** | What agents may reach. Policy rules in plain language, with an advanced editor |
| **Usage** | Tokens and estimated cost, per agent and per provider. **No percentage meter** — see [04](04-model-providers.md) |
| **Advanced** | Engine state, ports, volumes, resource limits, admin surfaces, diagnostics, reset |
| **Updates** | App and engine versions, channel, check now, install when a newer digest is published (blocked while a turn is streaming) |

### General

Mirrors the reference's structure — Account, Appearance, System, Bot — because it is a sensible
structure.

The **Account** row shows the local user, not a signed-in identity. It is a name and an avatar for
message attribution, stored locally. There is no sign-in and no Sign Out. Where the reference has
Sign Out, we have nothing, and that absence is the product.

**Auto-review** carries over as the policy switch, and its copy should be exact:

> **Auto-review**
> xBot checks each action before it runs and asks you first when needed. Add rules to customise what
> agents can do automatically.

### Computer

Where policy becomes legible to a non-technical person. The engine's policy is CEL; the settings
screen is a rule list in plain language:

```
   Always ask before…
     ▸ Buying anything or entering payment details
     ▸ Sending an email or a message
     ▸ Deleting files
     ▸ Signing in to a new site

   Never allow…
     ▸ Visiting these sites          [ + ]

   [ Advanced: edit rules directly ]
```

The advanced editor is the raw policy with the dry-run tool upstream provides.

---

## Admin surfaces

Audit, boundaries, computers, credentials, people, plugins, components, playground. Per
[ADR-0004](decisions/0004-native-vs-webview.md), dense operational tools open in a dedicated window
from Settings → Advanced, not inside the main window.

**What ships today:**

| Surface | How |
| --- | --- |
| **Plugins (full manager)** | `WKWebView` at the engine's `/admin/plugins` — OAuth setup, catalogue, per-tool config |
| **Plugin grants (per agent)** | Native — **What it can reach** and **Handoff grants** in the panel's Agent settings |
| Everything else in the table above | **Not embedded yet** — same webview pattern when added |

The webview injects the loopback bearer token at document start so the upstream React admin can call
`/api` without a sign-in flow. The token never appears in page-visible UI.

**They are labelled as advanced and they look it.** No attempt to make a dense operational tool feel
like the chat app.

**Exception: the audit trail gets a native view before v1.0.** It is the product's central trust
claim. A user who wants to know what their agent did should not meet a webview at that moment.

---

## Empty and error states

Every empty state is a sentence and an action. Never "No items."

| Situation | What we show |
| --- | --- |
| No agents | "Create your first agent" + a button. Not "No agents." |
| Engine stopped | "The engine isn't running" + **Start**. Not an empty list |
| No model connected | "Connect a model to start" + **Open Settings**. Composer disabled with this reason |
| Agent has never browsed | The monitor glyph + "*Agent*'s screen" |
| No routines | The reference's sentence + **Create Routine** |
| Turn failed | The reason, inline, + **Retry** |
| Provider rejected the key | "Anthropic didn't accept this key" + **Update key** |
| Rate limited | "Anthropic is rate-limiting you. Try again in about a minute." |

**Never show an empty state that implies emptiness when the real cause is that something is down.**
This is the single most common way an app quietly lies to its user.
