#!/usr/bin/env python3
"""Live end-to-end test of Automations, through the real path.

Seeds a sandbox library (never the person's own) with one automation per app — plus one per
agent — all due now, then has launchd start the installed xBot headless (`--automations-tick`),
exactly as "Run when xBot is closed" does. Each step's effect is checked from outside xBot
(osascript, files), then a second tick checks nothing runs twice. Everything it creates in
Reminders, Notes, Calendar and Safari is removed afterwards.

  scripts/e2e_automations.py [--agent codex] [--only reminders,notes] [--keep]

xBot must be closed (the helper leaves runs to an open app). macOS asks once per app whether
xBot may control it: answer Allow for the apps to pass.
"""
import argparse, json, os, plistlib, shutil, sqlite3, subprocess, sys, tempfile, time, uuid

APP = "/Applications/XBot.app/Contents/MacOS/XBot"
LABEL = "dev.xbot.e2e"
REF = 978307200  # 2001-01-01, Foundation's reference date


def sh(cmd, timeout=120):
    r = subprocess.run(cmd, shell=isinstance(cmd, str), capture_output=True, text=True, timeout=timeout)
    return r.stdout.strip(), r.returncode


def osa(script, timeout=60):
    try:
        out, code = sh(["osascript", "-e", script], timeout)
    except subprocess.TimeoutExpired:
        return None
    return out if code == 0 else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--agent", default="codex")
    ap.add_argument("--only", default="")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--clean-marker", default="", help="also delete reminders left by an earlier run's marker")
    ap.add_argument("--timeout", type=int, default=1500)
    args = ap.parse_args()

    if sh(["pgrep", "-f", "/Applications/XBot.app/Contents/MacOS/XBot$"])[1] == 0:
        sys.exit("Quit xBot first: the helper leaves runs to an open app.")

    mark = "xbot-e2e-" + time.strftime("%H%M%S")
    work = tempfile.mkdtemp(prefix="xbot-e2e-", dir=os.path.expanduser("~/.hermes/cache/scratch"))
    home = os.path.join(work, "home")
    out = os.path.join(work, "out")
    os.makedirs(out)
    finder_dir = os.path.join(out, mark + "-finder")
    support = os.path.join(home, "Library/Application Support/xBot")
    os.makedirs(support)
    print(f"marker {mark}\nwork   {work}")

    # name, app, step text, check() -> (ok, detail)
    def file(name):
        p = os.path.join(out, name)
        return open(p).read().strip() if os.path.exists(p) else None

    def is_int(name):
        v = file(name)
        return (v is not None and v.split()[0].isdigit(), v)

    shortcuts_now = sh("shortcuts list | wc -l")[0].strip()
    cases = [
        ("reminders", "reminders", f'Create a reminder titled "{mark} reminder" in the default Reminders list.',
         lambda: (verified.get("reminders", "0") not in ("0", ""), verified.get("reminders"))),
        ("notes", "notes", f'Create a note titled "{mark} note" whose body says hello from xBot.',
         lambda: ((osa(f'tell application "Notes" to count (notes whose name is "{mark} note")') or "0") != "0",
                  osa(f'tell application "Notes" to count (notes whose name is "{mark} note")'))),
        ("calendar", "calendar", f'Create an event titled "{mark} event" tomorrow from 10:00 to 10:30 in any calendar you can write to.',
         lambda: (bool(calendar_count(mark)), calendar_count(mark))),
        ("finder", "finder", f'Using Finder, make a new folder at the POSIX path {finder_dir}.',
         lambda: (os.path.isdir(finder_dir), finder_dir)),
        ("contacts", "contacts", f'Count the people in Contacts and write only the number to {out}/contacts.txt.',
         lambda: is_int("contacts.txt")),
        ("mail", "mail", f'Count the messages in the Mail inbox without opening or changing any, and write only the number to {out}/mail.txt.',
         lambda: is_int("mail.txt")),
        ("messages", "messages", f'Count the chats in Messages, without sending anything, and write only the number to {out}/messages.txt.',
         lambda: is_int("messages.txt")),
        ("music", "music", f"Write Music's player state (playing, paused or stopped) to {out}/music.txt.",
         lambda: ((file("music.txt") or "").lower().strip(". ") in ("playing", "paused", "stopped"), file("music.txt"))),
        ("photos", "photos", f'Count the albums in Photos and write only the number to {out}/photos.txt.',
         lambda: is_int("photos.txt")),
        ("safari", "safari", f'In Safari open https://example.com in a new tab, write the page title to {out}/safari.txt, then close that tab.',
         lambda: ("Example Domain" in (file("safari.txt") or ""), file("safari.txt"))),
        ("shortcuts", "shortcuts", f'Write how many shortcuts I have (only the number) to {out}/shortcuts.txt.',
         lambda: ((file("shortcuts.txt") or "").split()[:1] == [shortcuts_now], f'{file("shortcuts.txt")} (actual {shortcuts_now})')),
        ("maps", "maps", f'Open Maps showing Tel Aviv, then write the word opened to {out}/maps.txt.',
         lambda: (file("maps.txt") == "opened", file("maps.txt"))),
        ("web", "web", f'Fetch https://example.com and write its page title to {out}/web.txt.',
         lambda: ("Example Domain" in (file("web.txt") or ""), file("web.txt"))),
        ("terminal", "terminal", f'Run uname -s and write its output to {out}/terminal.txt.',
         lambda: (file("terminal.txt") == "Darwin", file("terminal.txt"))),
        ("anything", "anything", f'Write the word banana to {out}/anything.txt.',
         lambda: (file("anything.txt") == "banana", file("anything.txt"))),
    ]
    for agent in ("antigravity", "copilot"):
        cases.append((f"agent-{agent}", "terminal", f"Write the word {agent} to {out}/{agent}.txt.",
                      lambda a=agent: (file(f"{a}.txt") == a, file(f"{a}.txt"))))
    # A connector step: passes only if the run really called that MCP server's tools.
    cases.append(("connector-node_repl", "connector:node_repl",
                  f"Use the node_repl tools (not the shell) to evaluate 6*7 in JavaScript, then write only the result to {out}/connector.txt.",
                  lambda: (file("connector.txt") == "42" and "node_repl" in tools_used.get("connector-node_repl", ""),
                           f'{file("connector.txt")}, tools: {tools_used.get("connector-node_repl", "")[:120]}')))
    # Claude Code, and its claude.ai connectors (read-only).
    cases.append(("agent-claude", "terminal", f"Write the word claude to {out}/claude.txt.",
                  lambda: (file("claude.txt") == "claude", file("claude.txt"))))
    cases.append(("connector-gmail", "connector:Gmail",
                  f"Using the Gmail connector's tools (not Mail.app, not the shell), search for my most recent email thread, "
                  f"without sending, changing or archiving anything, and write only the word found to {out}/gmail.txt.",
                  lambda: (file("gmail.txt") == "found" and "mcp__claude_ai_Gmail__" in tools_used.get("connector-gmail", ""),
                           f'{file("gmail.txt")}, gmail tools used: {"mcp__claude_ai_Gmail__" in tools_used.get("connector-gmail", "")}')))
    cases.append(("connector-claude-docs", "connector:Claude Docs",
                  f"Call the Claude Docs connector's guide tool (read only, change nothing), "
                  f"then write only the word documented to {out}/docs.txt.",
                  lambda: (file("docs.txt") == "documented" and "mcp__claude_ai_Claude_Docs__" in tools_used.get("connector-claude-docs", ""),
                           f'{file("docs.txt")}, tools: {sorted(set(__import__("re").findall(r"mcp__[A-Za-z_]+?__", tools_used.get("connector-claude-docs", ""))))}')))
    cases.append(("connector-supabase", "connector:Supabase",
                  f"Using the Supabase connector's tools, list my organizations or projects (read only, change nothing), "
                  f"then write only the number of projects to {out}/supabase.txt.",
                  lambda: ((file("supabase.txt") or "x").isdigit() and "mcp__claude_ai_Supabase__" in tools_used.get("connector-supabase", ""),
                           file("supabase.txt"))))
    tools_used = {}
    # Two steps in order: the second needs the first.
    cases.append(("two-steps", "terminal", None, lambda: (file("order.txt") == "one two", file("order.txt"))))

    only = set(filter(None, args.only.split(",")))
    if only:
        cases = [c for c in cases if c[0] in only]

    db = sqlite3.connect(os.path.join(support, "xbot.sqlite"))
    db.executescript("""
        CREATE TABLE automations (id TEXT PRIMARY KEY, name TEXT NOT NULL, trigger TEXT, steps TEXT NOT NULL,
          harness TEXT NOT NULL, model TEXT, effort TEXT, project_id TEXT, enabled INTEGER NOT NULL DEFAULT 1,
          last_run_at REAL, sort_index INTEGER NOT NULL DEFAULT 0, created_at REAL NOT NULL);
    """)
    # Daily at an hour ago, made two days ago: due now, and not again until tomorrow — so a second
    # tick that runs anything is a double run.
    created = time.time() - REF - 2 * 86400
    hour_ago = time.localtime(time.time() - 3600)
    trigger = json.dumps({"daily": {"hour": hour_ago.tm_hour, "minute": hour_ago.tm_min}})
    ids = {}
    for i, (name, app, text, _) in enumerate(cases):
        harness = (name.split("-", 1)[1] if name.startswith("agent-")
                   else "claude" if name in ("connector-gmail", "connector-claude-docs", "connector-supabase") else args.agent)
        if name == "two-steps":
            steps = [{"id": str(uuid.uuid4()).upper(), "app": "terminal", "text": f"Write the word one to {out}/order.txt."},
                     {"id": str(uuid.uuid4()).upper(), "app": "anything", "text": f"Append a space and the word two to the single line in {out}/order.txt, so it reads: one two"}]
        else:
            steps = [{"id": str(uuid.uuid4()).upper(), "app": app, "text": text}]
        aid = str(uuid.uuid4()).upper()
        ids[name] = aid
        db.execute("INSERT INTO automations VALUES (?,?,?,?,?,?,?,?,1,NULL,?,?)",
                   (aid, f"E2E {name}", trigger, json.dumps(steps), harness, None, None, None, i, created))
    db.commit()
    db.close()
    # Let xBot finish the schema (v5) on first open: it creates its other tables then.

    plist = os.path.expanduser(f"~/Library/LaunchAgents/{LABEL}.plist")
    with open(plist, "wb") as f:
        plistlib.dump({"Label": LABEL, "ProgramArguments": [APP, "--automations-tick"], "RunAtLoad": True,
                       "EnvironmentVariables": {"CFFIXED_USER_HOME": home},
                       "StandardOutPath": os.path.join(work, "tick.log"), "StandardErrorPath": os.path.join(work, "tick.log")}, f)
    uid = os.getuid()
    sh(["launchctl", "bootout", f"gui/{uid}/{LABEL}"])
    started = time.time()
    _, code = sh(["launchctl", "bootstrap", f"gui/{uid}", plist])
    print(f"tick started by launchd (bootstrap exit {code}); waiting…")

    def state():
        out_, _ = sh(["launchctl", "print", f"gui/{uid}/{LABEL}"])
        return "state = running" in out_
    time.sleep(5)
    while state() and time.time() - started < args.timeout:
        time.sleep(5)
    print(f"tick finished after {int(time.time() - started)} s")

    verified = {}
    checks = {c[0]: c[3] for c in cases}

    def grade(name):
        db = sqlite3.connect(os.path.join(support, "xbot.sqlite"))
        aid = ids[name]
        runs = db.execute("SELECT id FROM chats WHERE automation_id = ?", (aid,)).fetchall()
        last = db.execute("SELECT last_run_at FROM automations WHERE id = ?", (aid,)).fetchone()[0]
        reply, failure = "", None
        if runs:
            for (parts,) in db.execute("SELECT parts FROM messages WHERE chat_id = ? AND role = 'assistant' ORDER BY rowid", (runs[0][0],)):
                for p in json.loads(parts):
                    if "failure" in p: failure = str(p["failure"])
                    if "tool" in p: tools_used[name] = tools_used.get(name, "") + json.dumps(p["tool"]) + " "
                    if "text" in p: reply += str(p["text"].get("_0", p["text"]) if isinstance(p["text"], dict) else p["text"])
        db.close()
        try:
            ok, detail = checks[name]()
        except Exception as e:
            ok, detail = False, repr(e)
        return (len(runs) == 1 and last is not None and failure is None and ok, len(runs), failure, detail, reply[-160:])

    results = [(c[0], *grade(c[0])) for c in cases]

    # Second tick: nothing is due any more.
    before = count_runs(support)
    sh(["launchctl", "kickstart", "-k", f"gui/{uid}/{LABEL}"])
    time.sleep(8)
    while state():
        time.sleep(2)
    again = count_runs(support) - before

    # Through xBot, which has the permissions: count what it made in Reminders, then delete it.
    if any(c[0] == "reminders" for c in cases):
        db = sqlite3.connect(os.path.join(support, "xbot.sqlite"))
        steps = [{"id": str(uuid.uuid4()).upper(), "app": "reminders",
                  "text": f'Count the reminders, in every list, whose name is exactly "{mark} reminder", and write only that number to {out}/verify-reminders.txt. Then delete those reminders.' + (f' Also delete any reminders named exactly "{args.clean_marker} reminder".' if args.clean_marker else '')}]
        db.execute("INSERT INTO automations VALUES (?,?,?,?,?,?,?,?,1,NULL,99,?)",
                   (str(uuid.uuid4()).upper(), "E2E verify", trigger, json.dumps(steps), args.agent, None, None, None, created))
        db.commit(); db.close()
        sh(["launchctl", "kickstart", "-k", f"gui/{uid}/{LABEL}"])
        time.sleep(8)
        while state():
            time.sleep(2)
        verified["reminders"] = file("verify-reminders.txt") or ""
        results = [(r[0], *grade(r[0])) if r[0] == "reminders" else r for r in results]

    sh(["launchctl", "bootout", f"gui/{uid}/{LABEL}"])
    os.remove(plist)

    sys.stdout.flush()
    width = max(len(r[0]) for r in results)
    for name, ok, runs, failure, detail, reply in results:
        print(f"{'PASS' if ok else 'FAIL'}  {name:<{width}}  runs={runs}  {('failure: ' + failure) if failure else ''}  got: {detail!r}")
        if not ok and reply:
            print(f"      reply: …{reply!r}")
    print(f"{'PASS' if again == 0 else 'FAIL'}  second tick ran {again} more")

    if not args.keep:
        ran = {c[0] for c in cases}
        if "notes" in ran: osa(f'tell application "Notes" to delete (notes whose name is "{mark} note")')
        if "calendar" in ran:
            osa(f'tell application "Calendar" to repeat with c in calendars\ntry\ndelete (events of c whose summary is "{mark} event")\nend try\nend repeat', 120)
        print("cleaned up what it made, named", mark)
    passed = sum(r[1] for r in results) + (again == 0)
    print(f"\n{passed}/{len(results) + 1} passed")
    sys.exit(0 if passed == len(results) + 1 else 1)


def calendar_count(mark):
    v = osa(f'set n to 0\ntell application "Calendar"\nrepeat with c in calendars\ntry\nset n to n + (count (events of c whose summary is "{mark} event"))\nend try\nend repeat\nend tell\nreturn n', 120)
    return int(v) if v and v.isdigit() and int(v) > 0 else 0


def count_runs(support):
    db = sqlite3.connect(os.path.join(support, "xbot.sqlite"))
    n = db.execute("SELECT count(*) FROM chats WHERE automation_id IS NOT NULL").fetchone()[0]
    db.close()
    return n


if __name__ == "__main__":
    main()
