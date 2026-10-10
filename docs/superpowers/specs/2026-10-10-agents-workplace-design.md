# Agents: a workplace, not a tab

Status: approved in conversation, 2026-10-10. Inspiration: Colony's Agents (faces that blink, a
featured member in the sidebar, a dashboard of what the crew is doing), made far more alive.

## What an agent is

A persona over one of the installed CLIs. It has:

- **identity**: a name and a one-line role ("Builds features end to end");
- **an avatar**: an original pixel-art chibi in the MapleStory Classic manner (big head, small
  body), made in a character creator: skin, hair style, hair colour, eyes, outfit, outfit colour,
  accessory. Nexon's sprites are not used; every pixel is drawn by xBot;
- **role instructions**: how it works, sent with every turn as a system prompt
  (`claude --append-system-prompt`, `codex exec -c developer_instructions=…`; both verified on
  this Mac to take effect);
- **a brain**: Claude Code or Codex, and a model (nil: the CLI's default);
- **a home project** (optional): where its chats start.

Talking to an agent opens a chat tagged with it (`chats.agent_id`). The chat uses the agent's
brain, and each turn carries its identity, the crew, and its instructions.

Stored in the `agents` table (schema v4, which also adds `chats.agent_id`). The avatar is a small
JSON value in a column, so new avatar parts never need a migration.

## The crew

xBot founds the world with four agents, seeded once (a defaults flag), all editable:

| | Role |
|---|---|
| **HeadMaster** | The founding father and orchestrator. Takes the big asks, plans them, and hands parts to the crew. Responsible and creative. Cannot be deleted (it can be renamed and restyled). |
| **Forge** | Builder: implements features end to end, tests first. |
| **Hawk** | Reviewer: reads changes for bugs, risks and missing tests; does not edit. |
| **Quill** | Scribe: keeps the project's `notes/` — ideas and the next release notes. |

People hire more with **Hire** (the same editor, empty, a random avatar).

### Hand-offs

HeadMaster's instructions list the crew (name, role) and one way to give work:

    ```handoff
    to: Forge
    task: Add a dark-mode toggle to Settings…
    ```

When a HeadMaster turn ends, each `handoff` block naming a crew member starts a chat for that
member, in HeadMaster's project, with the task as its first message (prefixed "From HeadMaster:").
HeadMaster's reply gains a line per hand-off ("Handed to Forge"). Only HeadMaster's blocks are
acted on, and only at the end of a turn, so nobody can loop work back and forth. A name that is not
in the crew is reported in the reply, not guessed.

## Alive

- Faces **blink** on their own clocks, **bob** while idle, and **walk** with a stepping cycle.
- An agent's **status** comes from its chats: *Working* (a turn running; the speech bubble shows
  the tool it is using or the start of what it is writing), *Done* (finished in the last 10 minutes,
  not yet looked at), *Idle*.
- The **workplace**: a MapleStory-like 2D map across the top of the Agents page — sky by time of
  day, drifting clouds, grass and dirt tiles, a desk per agent. Idle agents wander, pause, turn;
  working agents walk to their desk, sit and type, with a bubble of what they're doing. Click one
  to open it. Reduce Motion: they stand still (blinks stay, like Colony).

## The Agents page

1. The workplace scene.
2. Cards: **Working now** (who, what, for how long), **Just finished** (open the chat),
   **Activity** (turns per day, 14 days, from agent chats), **Crew** (each member: avatar, role,
   brain, *Talk*, *Edit*).

## Sidebar

Below Notes, an **Agents** section: a featured member in a pill (animated face, name, status;
whoever is working, else whoever just finished, else HeadMaster) over a row of the others' faces,
each with a status dot. A face opens a chat with that agent; the header opens the page; + hires.

## Editor

A sheet: on the left the avatar creator — a large animated preview on a little platform, a row per
part with ‹ › arrows, and **Randomize**; on the right name, role, instructions, brain and model,
home project. Delete (not for HeadMaster) with Undo.

## Tests

Store round-trip and migration; the seeded crew (once only); turn requests carry the
instructions (both CLIs' argument shapes); the identity preamble lists the crew; hand-off parsing
(several, unknown name, non-HeadMaster ignored) and the chats it starts; status derivation; avatar
JSON round-trip and tolerance of unknown parts; the walker's state machine (wander, go to desk).
