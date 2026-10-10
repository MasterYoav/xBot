# In-app terminal

Status: approved in conversation, 2026-10-10.

## What

Each chat (a "session") has one terminal window: real shells, one per tab, in the chat's folder
(its project, else the Inbox), floating over the right side of the chat. A toggle in the chat's
bottom-right corner shows it; pressing again hides it (⌃` does the same, and so does − in the
window). Hiding doesn't stop anything: the shells keep running, and showing the window again brings
back the same tabs with their scrollback. Switching chats shows each chat's own window.

Revised 2026-10-10: one window with tabs replaced several free-floating windows.

- **Tabs** look and behave like the main tab bar: the selected one a soft segment, × on hover,
  **+** after the last for a new tab (selected), drag a tab along the strip to reorder. Closing
  the selected tab selects the one after it (else before). Typing `exit` closes its tab. The last
  tab closing closes the window.
- **Moving**: drag the empty end of the tab strip. **Resizing**: the left, right and bottom edges
  and both bottom corners (the pointer shows the resize arrows). The window stays where its strip
  can be grabbed again.
- Deleting a chat ends its shells. Quitting xBot ends them all.
- Ending a shell sends it SIGHUP, as closing a Terminal window does: interactive shells ignore the
  SIGTERM SwiftTerm sends, and on SIGHUP the shell hangs up its own jobs too. A tab that has ended
  never starts a shell again, even if it is drawn once more on its way out.
- A tab's title follows its shell's (the end of the folder path, or the running program).
- The Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`) is needed to build, since
  SwiftTerm compiles a shader; CI downloads it.

## How

- **SwiftTerm** (MIT, Miguel de Icaza) is the emulator: `LocalProcessTerminalView` runs the
  person's login shell (`$SHELL -l`, from the password database) on a pty, with
  `TERM=xterm-256color`. It is the second third-party exception after Sparkle, approved
  2026-10-10, because a terminal that can't run vim, htop or the agents' own TUIs isn't one.
  Pinned to the 1.20 series.
- `XBotCore.TerminalDeck` holds the layout: per chat, one panel (its tabs in order, the selected
  one, its offset and size) and whether it's shown. Tested without a window.
- `XBotUI` keeps one `LocalProcessTerminalView` per tab for the tab's whole life, so hiding,
  switching tabs and re-showing never restart a shell. The process lives in SwiftTerm's view; that
  is the one place a view owns a process, and the deck tells it when to end.
- Colours follow the app's palette; the font is SF Mono at the reading size.

## Tests

The deck: first toggle opens a window with one tab and shows it; second hides and keeps the tabs;
new tabs go last and are selected; closing selects a neighbour and the last closes the window;
reordering; moves and resizes kept within limits; a deleted chat's tabs ended; chats don't see each
other's terminals; the workspace opens tabs in the chat's folder.
