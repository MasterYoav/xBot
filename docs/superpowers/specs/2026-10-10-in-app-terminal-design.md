# In-app terminal

Status: approved in conversation, 2026-10-10.

## What

Each chat (a "session") has its own terminal windows: real shells, in the chat's folder (its
project, else the Inbox), floating over the right side of the chat. They are moved by dragging their
title bar and resized from their bottom-left corner. A toggle in the chat's bottom-right corner shows them;
pressing it again hides them (⌃` does the same). Hiding doesn't stop anything: the shells keep
running, and showing them again brings back the same windows with their scrollback. Switching tabs
shows each chat's own windows.

- The first show opens one terminal. **+** in a window's title bar opens another, a little down
  and to the left of the last, so none hides another completely.
- **×** closes a window and ends its shell; typing `exit` does the same. When the last closes, the
  chat's terminals are hidden.
- Clicking a window brings it to the front.
- Deleting a chat ends its shells. Quitting xBot ends them all.
- Ending a shell sends it SIGHUP, as closing a Terminal window does: interactive shells ignore the
  SIGTERM SwiftTerm sends, and on SIGHUP the shell hangs up its own jobs too (verified: a running
  `sleep 600` went with its window). A window that has ended never starts a shell again, even if
  it is drawn once more on its way out (it did, and left an orphan shell, before this rule).
- The Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`) is needed to build, since
  SwiftTerm compiles a shader; CI downloads it.
- Each window's title follows the shell's (the folder, or the running program).

## How

- **SwiftTerm** (MIT, Miguel de Icaza) is the emulator: `LocalProcessTerminalView` runs the
  person's login shell (`$SHELL -l`, from the password database) on a pty, with
  `TERM=xterm-256color`. It is the second third-party exception after Sparkle, approved
  2026-10-10, because a terminal that can't run vim, htop or the agents' own TUIs isn't one.
  Pinned to the 1.20 series.
- `XBotCore.TerminalDeck` holds the layout: per chat, the windows (back to front), their offsets
  and sizes, and whether they're shown. Tested without a window.
- `XBotUI` keeps one `LocalProcessTerminalView` per window for the window's whole life, so hiding,
  switching tabs and re-showing never restart a shell. The process lives in SwiftTerm's view; that
  is the one place a view owns a process, and the deck tells it when to end.
- Colours follow the app's palette; the font is SF Mono at the reading size.

## Tests

The deck: first toggle opens one and shows; second hides and keeps them; + cascades; close ends
and the last close hides; raise reorders; moves and resizes are kept within limits; a deleted chat's
windows are closed and reported for teardown; chats don't see each other's windows.
