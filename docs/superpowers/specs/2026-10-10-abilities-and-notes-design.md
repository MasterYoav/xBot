# Abilities and Notes, in place of Home

Date: 2026-10-10 · Status: approved in conversation, being built

## Intent

**What the user said.** Home is useless: replace it with **Abilities** — Connectors, Plugins,
Skills and MCPs, managed the way the reference (Claude's *Plugins* page) does, working seamlessly —
and add **Notes**: markdown notes per project, "your next release notes", in whatever style ideas
arrive in.

**Decided.**
- ⌘N and "+" open a blank new-chat tab: the composer, no suggestion cards.
- Abilities covers **both** Claude Code and Codex; every row carries its agent's mark, and every
  action goes to that agent's own CLI.
- View, enable/disable and remove now, plus **Browse** (marketplace plugins) and **Add** (an MCP
  server, a skill folder).
- Notes live **in the project folder**, `notes/*.md`, so they are in git and agents read them.

## Sidebar

`Home` becomes **Abilities** (`square.stack.3d.up`), followed by **Notes** (`note.text`), then Inbox,
Projects, Recent as before. Each opens a page in the content column, like Profile.

## Abilities

Header: "Abilities", "Connectors, plugins, skills and MCP servers your agents can use", and on the
right **Browse** (plugins tab) and **Add** (a menu: MCP server…, Skill folder…). Below: four segments
with counts — Connectors · Plugins · Skills · MCPs — and a search field. Rows: a mark (the item's
icon when it has one, else an SF Symbol on a tile), name, a dimmed source (marketplace, scope, plugin
it comes from), a one-line description, the agent's dot, and on the right the toggle or a status.
Hover: ⋯ menu — Remove (confirmed once: it uninstalls), Show in Finder.

### Where each comes from, and what can be done

| | Claude Code | Codex |
| --- | --- | --- |
| Plugins | `claude plugin list --json` · enable/disable/uninstall/install via `claude plugin` | `codex plugin list --json` · toggle = `[plugins."id"] enabled` in `~/.codex/config.toml` · `codex plugin add/remove` |
| MCPs | `~/.claude.json` `mcpServers` (user) and the open project's · remove via `claude mcp remove -s` · add via `claude mcp add -s user` · no global off switch in Claude Code, so no toggle (said in the row's help) | `codex mcp list --json` · toggle = `[mcp_servers.name] enabled` · `codex mcp add/remove` |
| Skills | `~/.claude/skills/*/SKILL.md` (removable: to the Trash) and plugin skills (read-only, labelled with the plugin) | `~/.codex/skills/*/SKILL.md` · toggle = `[[skills.config]]` `enabled` for its path |
| Connectors | claude.ai account connectors from `claude mcp list` (names starting "claude.ai "), with Connected / Needs sign-in / Failed · managed on claude.ai: **Manage** opens claude.ai's connector settings | none |

Reads run concurrently when the page opens and after every action; the connector health check is
slow (it connects to each server), so it fills in last and its tab shows a spinner until then.
A CLI that is not installed contributes nothing and the page says which is missing, with no error.
A failed action shows the CLI's own sentence in a toast and the toggle snaps back.

Only servers with their own `[mcp_servers.x]` table in Codex's config get a switch: a server that comes
with a plugin has none, and a table holding only `enabled` stops Codex from starting ("invalid
transport" — found by testing on a real config). Every Codex edit is followed by `codex mcp list`;
if Codex cannot load the result, the file is put back exactly as it was.

**Never** rewrite a vendor's whole config file: the Codex edits change one `enabled` line in one
table (or append that table), leaving every other byte as it was.

### Browse

A sheet listing marketplace plugins from both CLIs (`--available --json`), searchable, each with
**Install** (or "Installed"). Installs run `claude plugin install <id> -s user` /
`codex plugin add <id>`.

### Add

- **MCP server…**: name; agent (Claude Code, Codex, or both); *Command* (command + arguments) or
  *URL* (HTTP). Runs `claude mcp add -s user …` / `codex mcp add …`.
- **Skill folder…**: a folder with a `SKILL.md`, copied into `~/.claude/skills` or
  `~/.codex/skills`.

## Notes

The project in context (the open chat's, else a picker of projects). Left: the notes in
`<project>/notes/`, newest first, **New note**. Right: the note — an editor (plain text, markdown
syntax, SF Mono off: the person's font) with **Edit / Preview**; preview uses the same markdown
renderer as replies. Saved as you type (debounced, and on leaving). A new note starts empty; its
title is its first line, and the file is renamed to that title, slugged (`v2-1-release-notes.md`),
whenever the title changes. Delete moves the file to the Trash with Undo
in the toast. A note changed on disk (an agent edited it) reloads when it is not being edited.

## Testing

Parsers are tested against JSON recorded from these CLIs on this Mac, personal paths removed. The
Codex TOML edits, the skill frontmatter reader, the notes store and the workspace actions are unit
tested with a scripted command runner. Views are checked by driving the running app.
