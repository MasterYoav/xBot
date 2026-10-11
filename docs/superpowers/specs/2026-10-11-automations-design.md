# Automations (replacing the Inbox)

Status: approved in conversation, 2026-10-11.

## What changes in the sidebar

The **Inbox** row and its list are gone. **Automations** takes its place. Chats without a project
keep working exactly as before (they still run in xBot's Inbox folder); they're listed under
**Recent**, which now holds all of them, newest first, five at a time with "Show all". Chats an
automation ran stay out of the sidebar: they're the automation's run history.

## An automation

- **Trigger**: *Run now* only, or a **schedule**: hourly (at :mm), daily, weekdays, or weekly
  (day, time). The person asked for Run now; schedules were added because "run while xBot is
  closed" means nothing without them.
- **Steps**, dragged in from a palette and reordered by dragging, each written in plain words:
  - Apple apps installed by default: Mail, Calendar, Reminders, Notes, Messages, Contacts,
    Finder, Safari, Music, Photos, Maps, Shortcuts, plus Terminal (shell) and Web;
  - the person's **connectors** (claude.ai: Gmail, GitHub, …) and MCP servers, from Abilities;
  - "Anything" (no app named: the agent decides).
- **Agent**, model and reasoning (default Claude Code, which carries the connectors). Runs with
  **full access**: an automation can do anything the person can, which is the point; the editor
  says so.
- Optional project folder to work in (else xBot's Inbox folder).

## Running

xBot compiles the steps into one turn (`AutomationPrompt`): the steps in order, each with its app,
and how to reach that app from a shell: `osascript` (AppleScript/JXA) for Mail, Calendar,
Reminders, Notes, Messages, Contacts, Music, Photos, Safari, Finder; `shortcuts run`; `open`; the
connector's MCP tools. "Don't stop to ask; do it, then report what you did." The run is a chat
tagged with the automation (`chats.automation_id`, schema v5), shown in its history, opened like
any chat.

A run is **claimed** in the database before it starts (compare-and-set on `last_run_at`), so the
app and the background helper never both run the same one. A run already going isn't started again.

macOS asks once per app ("xBot wants to control Mail"): `NSAppleEventsUsageDescription` is in
Info.plist.

## Running while xBot is closed

Off by default: scheduled automations run while xBot is open. A toggle on the Automations page,
**Run when xBot is closed**, installs a LaunchAgent (`~/Library/LaunchAgents/dev.xbot.automations.plist`)
that starts xBot's own binary headless (`XBot --automations-tick`) every minute; it runs what's
due and quits, and does nothing while the app itself is open. Turning the toggle off unloads and
removes it.

## Tests

Schedules (next run for each kind, edges: past times, weekdays over a weekend, hourly rollover);
the prompt (order, apps, how-to lines only for apps used, connectors); store round trip and
migration; running creates a tagged chat with full access and the compiled prompt; claiming
prevents a double run; due-ness; the sidebar's Recent and exclusion of runs; the LaunchAgent plist.
