# Launch checklist

Everything between here and a `.dmg` a stranger can download and use.

`docs/12-roadmap.md` says what each milestone means and what is done. This says what to *do*, in
order, with the parts that need a human marked as such. Written after a pass that found and fixed
the things a machine could find alone; what is left is mostly things only an account holder can do.

The ordering is not arbitrary. Step 1 unblocks 2, 3 and 4; step 5 needs a real key; step 6 needs a
clean machine. Doing them out of order mostly means doing them twice.

---

## 1. Apple identity — **needs you**, unblocks everything else

Nothing else in this list can finish first. Until the app is signed, every local build is ad-hoc
signed, its code identity changes on every rebuild, and macOS re-prompts for Keychain access on each
launch — which is also why interactive verification of the app keeps getting blocked mid-session.

1. **Enrol in the Apple Developer Program** (~$99/year, individual is fine). Allow a day or two;
   identity verification is not instant.
2. **Create a Developer ID Application certificate.** Xcode → Settings → Accounts → Manage
   Certificates → **+** → *Developer ID Application*. Not "Apple Development" — that one only signs
   for machines on your team and Gatekeeper will still refuse it on somebody else's Mac.
3. **Export it as `.p12`.** Keychain Access → My Certificates → right-click the *Developer ID
   Application* entry → Export. Set a password; you will need it in step 5. Export the certificate
   **with its private key** — if the disclosure triangle shows no key, you exported the wrong row.
4. **Create an app-specific password** for notarization at
   [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords.
   Your Apple ID password will not work; `notarytool` refuses it.
5. **Find your Team ID** — Apple Developer → Membership. Ten characters.

**Verify before moving on**, on this Mac:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

One line, with a hash. No line means step 2 or 3 did not take.

---

## 2. Set the CI secrets

Repository → Settings → Secrets and variables → Actions.

| Secret | Where it comes from |
| --- | --- |
| `MACOS_SIGNING_IDENTITY` | The full string from `find-identity`, e.g. `Developer ID Application: Your Name (AB12CD34EF)` |
| `MACOS_CERTIFICATE_P12` | `base64 -i cert.p12 \| pbcopy` — the export from step 1.3 |
| `MACOS_CERTIFICATE_PASSWORD` | The password you set when exporting it |
| `APPLE_ID` | The Apple ID email on the developer account |
| `APPLE_TEAM_ID` | From step 1.5 |
| `APPLE_APP_PASSWORD` | The app-specific password from step 1.4 |

The workflow no-ops every signing step when these are absent, so a run with none of them still
produces an unsigned DMG. That is deliberate — it keeps the pipeline exercised.

**Why `MACOS_CERTIFICATE_P12` exists:** `codesign` looks the identity up in the keychain search list,
and a runner's keychain is empty. Naming an identity does not make one exist. Without the `.p12` the
sign step fails with *"The specified item could not be found in the keychain"*, which reads like a
wrong identity string and is a missing certificate.

---

## 3. Sparkle keys — **needs you**

Updates are dead until this exists, and it cannot be retrofitted: an app shipped without the public
key baked in can never verify an update, so v1.0 users would be stranded on v1.0 forever.

1. Run `scripts/generate-sparkle-keys.sh`. It writes the private key to your login Keychain and
   prints the public key. There is nothing to download — Sparkle's own `generate_keys` is already in
   the SwiftPM artifacts, and the script only finds it. Running it twice is safe: it prints the
   existing public key rather than replacing a key your shipped builds were signed against.
2. Add two more secrets: `SPARKLE_EDDSA_PRIVATE_KEY` and `XBOT_SPARKLE_PUBLIC_KEY` (the public one,
   which gets baked into the bundle). The private key is in the Keychain, not on disk, so export it
   first — `apps/mac/.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private.key` —
   paste the file's contents into the secret, and then delete the file. That export is the key
   itself: anything holding it can sign an update your users' apps will install.
3. Decide where the appcast lives and set `XBOT_APPCAST_URL` to it. GitHub Releases plus a raw file
   in the repo is enough to start; `XBOT_RELEASE_DOWNLOAD_PREFIX` is optional and only needed if the
   DMG is served from somewhere other than the appcast's own host.

**Back the private key up somewhere you will still have in two years.** Losing it means the same
stranding as never having had it.

---

## 4. First signed release

```bash
gh workflow run "Mac release" -R MasterYoav/xBot
```

Then download the artifact and check the two things that actually matter:

```bash
spctl -a -vvv -t install /Volumes/xBot/XBot.app   # → "accepted", "Notarized Developer ID"
xcrun stapler validate /Volumes/xBot/XBot.app     # → "The validate action worked!"
```

If `spctl` says *accepted* but not *notarized*, notarization was skipped or failed — check the
notarytool output in the job log rather than shipping it. A signed-but-unnotarized app still shows
the "cannot be opened" dialog on a stranger's Mac, which is the whole failure this step exists to
prevent.

---

## 5. End-to-end conversation — **no CopilotKit key needed**

ADR-0007 kept CopilotKit Intelligence for v1; [ADR-0008](decisions/0008-local-thread-runner.md)
changed that. No key was available to build or verify against, so the engine's local-mode seam was
built out instead — `LocalThreadRunner`, a durable wrapper around the vendor's own SSE runner. The
app has no field anywhere to paste an Intelligence key; conversations are kept by the engine itself.

1. Start the engine and hold a real conversation with an agent: send a message, get a reply, let it
   call a tool, and confirm the reply survives a restart of the app.

That last part is the actual test. `LocalThreadRunner` persisting to Postgres and hydrating on boot
is precisely what this buys, so a reply that does not survive a restart means it is not working.

Three more things only this conversation can prove, all built on 14 September against a stubbed
engine (`docs/plans/computer-client-tools.md`):

- **Memory, within one conversation.** Tell the agent something, then ask about it two messages
  later. Each run carries the whole conversation; before, every agent forgot everything between
  messages. (Recall *across* separate conversations is pgvector work ADR-0001 still owns, not this.)
- **Its computer.** Ask it to open a page and say what is on it. The Activity panel should show
  `computer_navigate` and the screen should show the page. Then check the conversation after an app
  restart has no duplicated messages — the tool-call loop resends messages the thread already holds,
  and relies on their ids matching.
- **The asks.** Ask it to sign in somewhere. "Needs you" or a masked field should appear above the
  composer, and the agent should carry on once you answer.

**There is an automated version of the engine half.** `apps/mac/Tests/XBotEngineTests/LiveEngineTests.swift`
drives the real client against a running engine — point it at a throwaway one, since it creates
agents. **It has now been run** (27 September), against an engine built from the working tree and a
local Ollama (`qwen2.5:7b`): set `XBOT_LIVE_OLLAMA_MODEL` and `LiveConversationTests` holds a real
three-turn conversation — it answers, drives `computer_navigate` through the client-tool loop and
reports the page, remembers a codeword two turns later, and leaves each message in the thread once.
Restarting that engine left every conversation's message count unchanged. What remains for a person
is the app half: the same conversation typed into the window, and the asks.

That first run found three engine faults, each of which failed every conversation:

- **The managed Bot could not be dialled.** `createAgentFetch` refused `127.0.0.1:4201`, the
  address the image itself gives the Bot, so every run through the server ended in "This deployment
  will not dial…". The Bot's configured host is now added to the allowed hosts
  (`server/src/agents/managed-agent-host.ts`), and only that host and port.
- **A keyless `openai-compatible` endpoint was refused locally.** OpenAI's client falls back to
  `OPENAI_API_KEY` when handed no key, so every Ollama run failed with "Missing credentials". It now
  gets a placeholder the endpoint ignores (`agent-langgraph/src/models/build.ts`).
- **Every Anthropic run was refused.** The server's standing role message arrived after the Bot's
  guidance, and Anthropic accepts a system message only first. All system texts are now merged, in
  order, into one leading message (`agent-langgraph/src/history.ts`).

**One open finding.** On a freshly started engine, roughly one full live run in six had a turn come
back empty, or a request go unanswered, while all nine live tests ran at once. The engine logged
"Thread already running" or, once, "No agents are registered", both of which should be impossible
there. It was never seen with the conversation suite alone (5 of 5 fresh engines), nor with a
logging proxy in the path (12 of 12). A leftover process, a database lock, identity, idle
keep-alive and split request writes were each checked and ruled out. Worth one more look before
launch, starting from the app under ordinary use rather than nine tests at once.

**Two more, found starting the app on this Mac's own engine** (27 September), both leaving the
container unhealthy with nothing on its port and no way back short of deleting the data:

- **Any recreate of the container lost the database password.** The app mounts `xbot-data` at
  `/var/lib/postgresql/data`; the password file lives one level up, so it went with the container
  while the cluster kept the password. Every environment change recreates the container. Reproduced
  on the old image with a clean stop and recreate; `postgres-init.sh` now sets a new password when a
  cluster has none beside it, which also heals an install already in this state.
- **`migrate` raced Postgres after an unclean stop.** It started before crash recovery finished and
  failed on `57P03`; 3 of 3 SIGKILL-and-start rounds broke the old image, 0 of 3 the fixed one.
  `migrate.sh` now waits for `pg_isready`, up to 60s.

**Also close the last M2 item here:** point one agent at a second real vendor — Anthropic is already
proven, so use OpenAI or Google — and confirm the reply comes from the vendor you picked. A model
name the vendor does not have should come back as a named error, not a silent fall back to somebody
else's model.

---

## 6. Clean-VM run — **needs a machine that has never seen this project**

The one test that cannot be faked from here. Everything in the app assumes a first run; this Mac has
not had one in months.

On a fresh macOS VM with no Docker, no Xcode, and no Homebrew:

1. Install from the DMG. It should open without a Gatekeeper warning — if it does not, step 4 is not
   finished.
2. Walk onboarding without touching a terminal, editing a file, or reading a log. That is invariant 1
   and this is the only place it gets tested honestly.
3. Let it install the container runtime, pull the engine, and reach a conversation.
4. Time it. The engine image is 4.5 GB and the first Start is the longest wait in the product; the
   progress figure now shows in Settings and onboarding, but if the wait is unreasonable on a normal
   connection that is a finding, not a fact of life.

Write down anywhere you reached for something the app should have done for you. Those are the M6
bugs, and they are only visible on the first run.

---

## 7. The website — **built; needs Pages turned on**

`site/index.html` is the page: one file, no build step. It carries the download (pointing at
`releases/latest`), the security explanation, the uninstall instructions — per docs/11 the standalone
uninstaller is documented here and not in the app — and, per [ADR-0008](decisions/0008-local-thread-runner.md),
the fact that conversation history is kept by the engine on this Mac, in the README's wording rather
than a second version that can drift.

`.github/workflows/pages.yml` publishes it on every push to master that touches `site/`. **It needs
you once:** repository → Settings → Pages → Source: **GitHub Actions**. Until then the workflow fails
at the deploy step. The download link is only useful once step 4 has published a release.

---

## What is already verified, so you do not redo it

From a shell holding no credentials:

- `manifests/engine-stable.json` at `raw.githubusercontent.com` answers 200.
- The digest it names resolves at ghcr on an anonymous pull token — a stranger's first Start can pull
  the engine.
- The manifest bundled into the app is byte-identical to the published one, so a first run with the
  network blocked still starts from a real pin.
- Every outbound URL the app can show a person answers 200.
- On 18 September, a throwaway engine built from master (with the model hop lifted into
  `models/build.ts`) came up healthy on loopback, refused an unauthenticated request with a 401, and
  passed all eight live client tests: health, read endpoints, the vault, agent and conversation
  round-trip, browser, files, shell, and the asks. That run predates ADR-0008; the conversation store
  now needs re-running against `LocalThreadRunner` rather than a CopilotKit key — see item 5.
- On 27 September, it was: a throwaway engine in local mode with no CopilotKit key held a real
  conversation with a local Ollama model, used its computer through the client-tool loop, remembered
  across turns, and kept every conversation intact through a restart. Item 5 has the details and
  the one open finding.
- The pinned engine is one multi-arch image (linux/amd64 and linux/arm64). On 14 September an Apple
  Silicon Mac pulled it anonymously, got arm64, was healthy in about ten seconds on a port other than
  3001, and passed the live suite: browser, files, shell, and a help request handed back. Before that
  the image was amd64 only, and every Apple Silicon Mac ran the engine under emulation.

Plus: the Swift suite and the engine suite are green in CI, the latter against a real database.

---

## Two things worth doing but not blocking

- **A second pair of eyes on the security posture** before the website goes up. The invariants in
  `CLAUDE.md` are the checklist; the audit trail, the loopback bindings, and the Keychain rules are
  the three that would hurt most to have wrong in public.
- **Decide the trademark question** in `docs/decisions/0006-naming-and-trademark.md`. It is recorded
  as unresolved and it is cheaper to answer before a public launch than after.
