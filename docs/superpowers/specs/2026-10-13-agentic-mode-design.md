# Agentic Mode: talk to your crew, and they run your Mac

Status: approved in conversation, 2026-10-13. xBot's biggest feature yet.

## What the person asked for

"xBot's whole idea must be totally controllable with the agents. Give the iOS app a big twist:
Agentic Mode. The current app is Developer Mode; add a settings toggle to switch to Agentic Mode.
In Agentic Mode the UI is very simple: a Grok/WhatsApp/Telegram chatting UX where you talk to your
agents and control the whole xBot infrastructure (your whole Mac; anything a human user can do) by
talking to them. Check out Google's Harness2 for ideas. It must be super light on resources and flow
like a dream."

Decided with the person (Jev's picks first, each confirmed):

1. **Shape**: a chat list like WhatsApp/Telegram, one thread per crew member, HeadMaster pinned on
   top as "do anything". Voice dictation, photos to send, rich reply cards (Mac screenshots,
   approvals, progress). Developer Mode stays one toggle away in Settings.
2. **Control**: xBot runs its own **MCP server**, attached to every agentic turn: xBot tools
   (projects, chats, crew, automations, notes, settings, worlds) plus **Mac control** (screenshot,
   read the screen through Accessibility, click, type, keys, open apps and URLs). Risky actions ask
   the person on the phone with an approval card.
3. **Permissions**: Accessibility and Screen Recording, granted once, in both the onboarding's
   permission step (with the floating guide) and on first use of Agentic Mode.
4. **From Harness2: experience.** After each task the agent writes evidence-backed lessons
   ("when X → do Y", with confidence) into its own memory, used on later turns; the person sees
   and edits them on the Mac.
5. **Approvals** for destructive or outward actions only: deleting files, sending messages or
   email, purchases, quitting apps, git push, changing system settings. Everything else just
   happens.

## Harness2, and what we take

[Harness²](https://github.com/google-research/harness2) (Google Cloud AI Research, Apache-2.0)
treats a *harness* as the editable system around a model: system prompt, guardrails, memory, tool
guidance, subagents, skills, scripts, plugins. It improves harnesses by recursion at two levels:
per task, *Propose–Probe–Compose* (propose edits, probe them on the same task, compose from the
behavioural contrasts); and across tasks, an *improvement harness* that keeps evidence-supported
lessons (`cue → lesson`, confidence) for future tasks.

xBot already has most components per agent: instructions (system prompt), the crew and hand-offs
(subagents), abilities (skills, plugins, MCP). Agentic Mode adds:

- **Tool guidance**: the xbot MCP tools, each with a precise description.
- **Guardrails**: the approval rules, always on.
- **Memory, as experience**: the harnessing-level recursion, kept cheap. One reflection per task,
  done by the agent at the end of its own turn (a tool call, no extra turn), never a second model
  run. Probes (N parallel attempts) are left out: they multiply cost.

## The two modes (iPhone)

Settings › **Mode**: **Developer** (today's app, the default after an update) or **Agentic**.
Stored on the phone (`UserDefaults` `mode`). Switching is instant; both read the same
`RemoteClient`. In Agentic Mode the tab bar, Places and every Developer screen are gone.

### Agentic Mode screens

**Chats** (the only root screen), like Telegram:

- Top: the Mac's name and a status dot (same Wi-Fi / through iCloud / offline), a ⚙ that opens
  Settings (with the Mode switch).
- **HeadMaster pinned** first, labelled "Ask me anything", then every crew member with their pixel
  face (the shared avatar, static, no world), last message preview, time, an unread dot, and
  "typing…" while a turn runs.
- Search field on pull-down. **+** hires someone (the existing Suggested agents sheet).

**A thread** with one agent:

- Bubbles: yours on the right in the accent colour, theirs on the left. Markdown, code blocks.
- While the agent works: a **typing indicator**, then a single compact **activity line** that
  updates in place ("Opening Safari…", "Reading the screen…", "Running swift test…") and collapses
  into "Did 7 things ›" when the reply lands (tap to see them).
- **Cards** in the flow:
  - **Screenshot**: a Mac screenshot the agent took, as a rounded thumbnail; tap for full screen
    with pinch zoom.
  - **Approval**: "Forge wants to delete 3 files in ~/Projects/old" with **Allow** and
    **Don't allow**; after an answer it shows the answer and who gave it. The phone app gets no
    background time, so an approval waits up to 10 minutes for an answer, then counts as Don't
    allow, and the agent is told.
  - **Hand-off**: "Handed to Forge: build the login page", tapping opens Forge's thread.
  - **Done** notes from teammates.
  - **Lesson learnt**: "Learnt: when Xcode asks to trust a package, choose Trust and Enable" (small,
    quiet; tap to edit or forget on the Mac).
- Composer: a growing text field, **mic** (on-device dictation with `SFSpeechRecognizer`, live
  transcript into the field, tap again to stop), **photo** (PhotosPicker; sent as a downscaled JPEG
  ≤ 1600 px, saved on the Mac in the thread's folder and referenced in the prompt), **send**.
  Long-press a message: Copy, Retry (theirs), Edit and resend (yours).
- No pixel world, no animations beyond the system's (bubble insertion, typing dots), so it stays
  light.

### Threads on the Mac

A **thread** is one chat per agent, flagged `chats.thread = 1` (schema v7; the Jev branch's v7
becomes v8 when it lands). Created on first message, kept forever, continued with the CLI's
session; when a session can't be resumed (too long, CLI changed) a new chat continues the thread
with a short summary preamble. Thread chats run in **Full access** with the xbot tools attached and
work in xBot's Inbox folder unless the person names a project. They're listed on the Mac too, under
the agent, like any chat, so everything stays visible on the Mac.

## The xbot MCP server (Mac)

`XBot --mcp` (the same binary, headless, stdio MCP) is started by the CLI. It connects to the
running app over a Unix socket (`~/Library/Application Support/xBot/xbot.sock`, mode 0600, the
socket CLAUDE.md invariant 5 already allows), passing a per-turn token from its environment, and
forwards each tool call; the app answers. If xBot isn't running, every tool says so.

Per-turn attachment (the token names the chat and agent, so tools know who is asking):

| CLI | How |
| --- | --- |
| Claude Code | `--mcp-config <json>` (temporary file) and `--allowedTools mcp__xbot__*` |
| Codex | `-c mcp_servers.xbot.command=…` / `.args` / `.env` |
| Copilot | `--additional-mcp-config <json>` |
| Antigravity | no per-run flag: `agy mcp add xbot …` once, when Agentic Mode is first used (with consent, reversible from Settings › AI) |

Attached to thread turns, and (Settings › AI › "xBot tools in every chat", off by default) to any
turn.

### Tools

xBot (all through `Workspace`, the same methods the UI calls):

- `xbot_projects`, `xbot_add_project(path)`, `xbot_chats(project?)`, `xbot_start_chat(agent, project?, message)`,
  `xbot_read_chat(id)`;
- `xbot_crew`, `xbot_hire(name, role, instructions?)`, `xbot_hand_off(to, task)`;
- `xbot_automations`, `xbot_save_automation(…)`, `xbot_run_automation(id)`;
- `xbot_notes(project)`, `xbot_write_note(project, name, text)`;
- `xbot_settings`, `xbot_set_world(name)`, `xbot_set_appearance(…)`;
- `xbot_remember(cue, lesson, confidence, evidence)`, `xbot_lessons()` (experience, below);
- `xbot_ask(question, options?)`: ask the person something in the thread and wait.

Mac control:

- `mac_screenshot(display? | app?)`: ScreenCaptureKit, a JPEG ≤ 1600 px, returned to the agent as
  an image and posted to the thread as a screenshot card;
- `mac_ui(app?)`: the frontmost (or named) app's Accessibility tree, trimmed to visible elements
  with role, title, value and frame (for "click the Send button" without coordinates);
- `mac_click(x, y | element)`, `mac_type(text)`, `mac_keys(combo)` (CGEvent), `mac_scroll(dx, dy)`;
- `mac_open(app | url | path)`, `mac_apps()` (running apps), `mac_quit(app)`.

### Approvals (guardrails)

A tool call is classified before it runs (`RiskRules`, pure and tested):

- **Needs approval**: `mac_quit`; deleting (an `xbot_*` delete, or a shell command the hook sees
  with `rm`, `trash`, `git clean`, `git reset --hard`…); sending (Mail, Messages, `osascript` that
  sends; `mac_keys` of ⌘↩ in Mail/Messages); git push; purchases (Return/click in a window whose
  title says checkout, buy, pay, order); System Settings changes (`mac_*` while System Settings is
  frontmost, `defaults write` outside xBot's own domain, `sudo`).
- Everything else runs.

An approval goes to the phone (card in the thread) if one is attached, else to a Mac alert. The
call blocks until answered or 10 minutes (then refused). The agent is told the outcome.

Claude Code's own shell and file tools are routed through the same rules by a **PreToolUse hook**
passed per turn with `--settings` (the hook runs `XBot --hook`, which asks the app over the socket).
Codex, Copilot and Antigravity have no per-run hook: their shell commands are covered only by their
instructions ("before anything destructive or outward, call `xbot_ask`") and their own permission
mode. The docs say so.

### Permissions

Accessibility (for `mac_ui`, clicks, keys) and Screen Recording (for screenshots). Both only in
System Settings, so they use the onboarding's floating guide: the files step gains these two rows,
and the first agentic thread turn without them shows a card on the phone ("Allow xBot to see and
use your Mac: on the Mac, a guide is open") while the Mac opens the guide. Live detection:
`AXIsProcessTrusted()` and `CGPreflightScreenCaptureAccess()`.

## Experience (Harness2's harnessing-level recursion)

- Per agent, `~/Library/Application Support/xBot/Experience/<agent-id>.md`: a list of lessons, each
  `cue`, `lesson`, `confidence` (low/medium/high), `evidence` (one line), `learnt` date, `uses`.
- Agentic turns' instructions end with: "When you finish a task, if you learnt something general
  that would help next time (not task-specific facts), call `xbot_remember` once with the cue, the
  lesson, your confidence and the evidence." 
- On every turn of that agent, the top lessons (by confidence then recency, at most 12 or ~1,500
  characters) are added to its instructions under "What you've learnt". `uses` counts how often a
  lesson was included.
- Duplicate cues replace the older lesson. Low-confidence lessons older than 30 days unused are
  dropped.
- On the Mac: the agent editor gains **Experience** (list, edit, forget, "Forget everything").

## Performance budget

| State | Phone | Mac |
| --- | --- | --- |
| Agentic Mode, idle in the list | no timers beyond the link's; no animation | as today |
| A thread open, agent working | typing dots (system), one activity line updated ≤ 4×/s | MCP server process per turn: < 15 MB, idle between calls |
| Screenshot | one JPEG ≤ 1600 px, ≤ 400 KB, sent once; thumbnails decoded lazily | ScreenCaptureKit single frame, no stream |

Messages render in a `LazyVStack`; images are decoded at thumbnail size; the transcript keeps the
last 200 messages in memory and pages older ones on scroll.

## Wire (XBotRemote)

- `RemoteChat.thread: Bool?`; `RemotePart.image(RemoteImage)` (`id`, `jpeg: Data?`, `width`,
  `height`, `caption`), `RemotePart.approval(RemoteApproval)` (`id`, `agent`, `summary`, `detail`,
  `risk`, `state`: pending/allowed/refused/expired, `answeredBy`), `RemotePart.lesson(String)`,
  `RemotePart.activity([String])`.
- Client: `threadSend(requestID, memberID, text, images: [Data])`, `answerApproval(requestID, id,
  allow)`, `threads(requestID)`.
- Host: `.approval(chatID, RemoteApproval)` pushes, `.permissions(accessibility, screen)`.
- Old phones ignore unknown parts; the phone shows an unknown part as nothing.

## Tests

- `RiskRules`: every rule, both ways (a `git status` runs, `git push` asks; `rm -rf` asks; Mail
  ⌘↩ asks; typing in TextEdit runs).
- MCP: the stdio server's JSON-RPC (initialize, tools/list, tools/call, errors) against a fake app
  socket; the socket's token check; every xbot tool against a scripted workspace; approvals
  (allowed, refused, timed out, no phone → Mac alert path stubbed).
- Mac control: the AX tree trimming and CGEvent construction behind protocols (no real clicks in
  tests); screenshot downscaling.
- CLI attachment: each CLI's arguments with the tools attached.
- Experience: store round trip, dedupe by cue, selection and trimming, decay, injection into
  instructions.
- Wire round trips for every new message and part; `RemoteHost+Agentic` (threads, send with an
  image saved to the folder, approval relay).
- Phone: a live XCUITest switches to Agentic Mode, sends HeadMaster a message that makes it take a
  screenshot (`mac_screenshot`), sees the screenshot card and the reply; an approval round trip
  with a scripted risky call.
