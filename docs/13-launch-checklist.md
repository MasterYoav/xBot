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

1. Generate the EdDSA key pair with Sparkle's tool (`generate_keys` from the Sparkle release
   archive). It writes the private key to your login Keychain and prints the public key.
2. Add two more secrets: `SPARKLE_EDDSA_PRIVATE_KEY` (the private key) and `XBOT_SPARKLE_PUBLIC_KEY`
   (the public one, which gets baked into the bundle).
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

## 5. End-to-end conversation — **needs a CopilotKit key**

ADR-0007 keeps CopilotKit Intelligence for v1. Without a key the engine boots into local mode, whose
history client throws past wiring, so no conversation can complete. The app now says so rather than
failing silently, and the key can be pasted, replaced or revoked in Settings → Models → Conversation
history.

1. Get a key from CopilotKit.
2. Paste it in Settings → Models, or during onboarding.
3. Start the engine and hold a real conversation with an agent: send a message, get a reply, let it
   call a tool, and confirm the reply survives a restart of the app.

That last part is the actual test. The transcript living on their infrastructure is precisely what
this key buys, so a reply that does not survive a restart means it is not working.

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

## 7. The website

The last item in M7 and the only one with no code in this repository. It needs the download, the
security explanation, and — per ADR-0007 — the fact that conversation history is stored by
CopilotKit, said plainly rather than buried. The README already carries that wording; reuse it
rather than writing a second version that can drift.

---

## What is already verified, so you do not redo it

From a shell holding no credentials:

- `manifests/engine-stable.json` at `raw.githubusercontent.com` answers 200.
- The digest it names resolves at ghcr on an anonymous pull token — a stranger's first Start can pull
  the engine.
- The manifest bundled into the app is byte-identical to the published one, so a first run with the
  network blocked still starts from a real pin.
- Every outbound URL the app can show a person answers 200.

Plus: the Swift suite and the engine suite are green in CI, the latter against a real database.

---

## Two things worth doing but not blocking

- **A second pair of eyes on the security posture** before the website goes up. The invariants in
  `CLAUDE.md` are the checklist; the audit trail, the loopback bindings, and the Keychain rules are
  the three that would hurt most to have wrong in public.
- **Decide the trademark question** in `docs/decisions/0006-naming-and-trademark.md`. It is recorded
  as unresolved and it is cheaper to answer before a public launch than after.
