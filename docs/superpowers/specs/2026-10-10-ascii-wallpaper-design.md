# Wallpaper randomizer: text art drawn by an agent

Status: approved in conversation, 2026-10-10.

Settings › Appearance › Wallpaper gains **Randomize…**. It opens a sheet where the person picks:

- **Kind**: still or animated;
- **Agent** and **model** (any installed CLI; "Default model" is the CLI's own);
- **Reasoning** (the same effort levels as chats);
- an optional **idea**. Empty: xBot picks a subject.

xBot writes the prompt (`AsciiWallpaperPrompt`): a subject, a random style, the exact size
(96 × 28), where to put the subject (the wallpaper fades out towards the bottom), and for an
animation a loop of 8–12 frames with a random kind of motion. The prompt is shown under the
preview ("The prompt xBot wrote").

The agent answers to a JSON schema (`AsciiArt.schema`: title, ink, fps, frames), read-only, in
the Inbox folder, with no tools. `AsciiArt.parse` cleans the answer so it always draws: tabs and
control characters go, blank edges go, frames are padded to one size, fps is kept to 1–12, a still
keeps one frame. **Generate / Another one** draws; **Use as wallpaper** saves it as
`wallpaper-ascii.json` in xBot's folder and selects it (`Appearance.Wallpaper.ascii`).

The backdrop draws it in SF Mono, sized to fill the window's width, in the agent's chosen ink (six
inks, each with a light-mode and a dark-mode shade), with the same fade as a picture, frames played
at its fps. Reduce Motion shows the first frame.

## Found on the way: CLI output was being read on a shared, blocking queue

The first real run failed: Claude Code's answer (a ~47 KB result line) never arrived.
`FileHandle.bytes` does its blocking reads on one serial queue for the whole process, and xBot read
each CLI's stderr that way, so stdout stopped being read once its buffer needed refilling, the pipe
filled up, and the CLI stalled or its last line was lost. Every pipe is now read on a thread of its
own (`PipeReader`). The earlier "a clean exit without a result ends the turn" workaround was hiding
this; it's removed, so a CLI that really stops early is reported again.

## Tests

Parsing (padding, a still, cleaning, limits, inks, nothing drawn, a recorded real answer); the
prompt (xBot's subject, the person's idea, loops, variety); generation (model, effort, read-only,
schema, the prompt returned; failures reported); saving and restoring the wallpaper; a big
structured answer through `HarnessBrain` (the test that hung before the fix).
