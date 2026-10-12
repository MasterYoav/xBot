# Launch checklist

Everything between here and a public xBot 2.0: a signed `.dmg` a stranger can download, open and
use, with updates that work.

The [roadmap](12-roadmap.md) says what's built. This says what to *do*, in order. Steps marked
**needs you** can only be done by the account holder (the Apple Developer account, the GitHub
repository's settings, the Sparkle key). The rest is work in the repository. How the pieces work is
in [packaging and updates](11-packaging-and-updates.md).

The order matters: the PRs have to be on master before anything is built from it, the iCloud
decision changes what gets signed, and the clean-machine run tests the build you're about to publish.

---

## Already done, so you don't redo it

- **The release pipeline has shipped once.** "Mac release" run 36527990203 (29 September 2026)
  built, signed with Developer ID, notarized and stapled the app and the DMG, passed its own
  `spctl`/`stapler` checks, generated an EdDSA-signed appcast, and published **xBot 1.0.0** (a
  pre-release; the old Docker app). So the Developer ID certificate, its `.p12` and the notarization
  credentials worked, at least on that day.
- **All nine release secrets are set**: `MACOS_SIGNING_IDENTITY`, `MACOS_CERTIFICATE_P12`,
  `MACOS_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`,
  `XBOT_APPCAST_URL`, `XBOT_SPARKLE_PUBLIC_KEY`, `SPARKLE_EDDSA_PRIVATE_KEY`.
  (`XBOT_RELEASE_DOWNLOAD_PREFIX` is optional and not needed.)
- **Sparkle keys exist**, and 1.0.0 was built with the public key baked in.
- **GitHub Pages is on** (source: GitHub Actions) and the site answers at
  masteryoav.github.io/xBot.
- **CI is green** on every open PR in the stack (`swift build --build-tests && swift test` on
  `macos-26`; 443 tests).
- **The redesign runs signed with iCloud on a real Mac**: the installed app is signed by
  `scripts/sign-mac-remote.sh` (Apple Development, Xcode-managed profile with CloudKit and push), and
  an iPhone 15 Pro paired with it by QR, chatted over Wi-Fi, and got a new chat answered through
  iCloud with Wi-Fi off.
- **Measured on the installed release build** (11 October 2026): 0.01% CPU, 63 MB, with a phone
  paired and xBot in the background.

---

## 1. Merge the open PRs — **needs you**

In this order, each after its CI passes:

1. **#30** — motion gate (animations pause while xBot isn't in view). Based on master.
2. **#31 → #42** — the iPhone and iPad app and the org chart. #31 is based on master; each later PR
   is based on the one before it (#32 on #31's branch, and so on up to #42 on #41's). Merge them
   one at a time, bottom up, so each diff stays reviewable; after each merge, retarget the next PR at
   master if GitHub hasn't.
3. **The documentation refresh** (`docs-refresh`), which is stacked on #42.

Then pull master and run the suite once more locally:

```sh
scripts/generate-app-icon.sh
cd apps/mac && swift build --build-tests && swift test
```

---

## 2. Check the Apple side still holds — **needs you**

The secrets were set on 18 and 29 September. Before relying on them:

- The **Developer ID Application** certificate is still valid (Keychain Access, or
  `security find-identity -v -p codesigning | grep "Developer ID Application"` on the Mac you
  exported it from).
- The **app-specific password** behind `APPLE_APP_PASSWORD` hasn't been revoked
  (appleid.apple.com › Sign-In and Security › App-Specific Passwords).
- The **Apple Developer Program membership** is current.

The build-only run in step 6 proves all three at once; this step is so a failure there isn't a
surprise.

---

## 3. Sparkle keys — **needs you**

The keys exist; this is about not losing them. Losing the private key strands every installed copy,
because an app can't verify an update signed by a key it has never seen.

1. On the Mac that generated them, run `scripts/generate-sparkle-keys.sh` (after one
   `cd apps/mac && swift build -c release`). It prints the public key and changes nothing.
2. Confirm it's the key in `XBOT_SPARKLE_PUBLIC_KEY`. GitHub won't show a secret back, so compare
   with your own record of what you set, or with `SUPublicEDKey` inside the 1.0.0 app.
3. **Back the private key up** somewhere you'll still have in two years. Export it with
   `apps/mac/.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private.key`, store it,
   and delete the file (`sparkle-private.key` is git-ignored, but don't leave it lying around).

---

## 4. Decide about the iCloud lane — **needs you**

A Developer ID build today carries **no entitlements**, so the phone can pair and work on the same
network but can't reach the Mac through iCloud; the Mac falls back to the local lane. Pick one:

**A. Ship 2.0 with the local lane only.** Nothing to do here; say so in the release notes and on the
website ("same Wi-Fi for now").

**B. Ship the away lane too.** Then:

1. In the Apple Developer portal (Certificates, Identifiers & Profiles), make sure the App ID
   `dev.xbot.app` has iCloud (CloudKit, container `iCloud.dev.xbot`) and Push Notifications.
   The development profile already uses both, so they should be on.
2. Create a **Developer ID provisioning profile** for `dev.xbot.app` with those capabilities, and
   download it.
3. In the **CloudKit Console**, deploy the schema of `iCloud.dev.xbot` from Development to
   **Production**. The `Batch` record type exists only in development, where it was created on first
   use; a distributed build uses production.
4. Make the profile available to CI (for example as another base64 secret) and change
   `scripts/sign-mac-app.sh` to embed it as `Contents/embedded.provisionprofile` and sign the app
   with an entitlements file: CloudKit, `iCloud.dev.xbot`, `aps-environment` `production`, and the
   production CloudKit environment. This is code; it isn't written.
5. Verify on a Mac that isn't registered to the team: pair a phone, turn its Wi-Fi off, and get a
   reply through iCloud.

---

## 5. Fix what ships stale

Work in the repository, before anything is published:

- **The website.** `site/index.html` still describes the Docker engine, OpenBot and the 1.x
  uninstaller. Rewrite it for 2.0 (what xBot does now, that it needs an agent CLI, that it isn't
  sandboxed and why, the phone app's status, uninstall). Pushing to master republishes it.

---

## 6. A build-only release run

```sh
gh workflow run "Mac release" -R MasterYoav/xBot
gh run watch -R MasterYoav/xBot
gh run download -R MasterYoav/xBot -n xbot-release
```

No version means nothing is published. Open the downloaded `xBot.dmg` and check:

```sh
spctl -a -vvv -t execute /Volumes/xBot/XBot.app   # → accepted, "Notarized Developer ID"
xcrun stapler validate /Volumes/xBot/XBot.app     # → "The validate action worked!"
codesign -d --entitlements :- /Volumes/xBot/XBot.app   # empty for A; iCloud and push for B
```

If `spctl` says *accepted* but not *Notarized Developer ID*, notarization was skipped or failed:
read the `notarytool` output in the job log.

---

## 7. Clean-machine run — **needs a Mac that has never seen xBot**

The one test that can't be faked from the development Mac. Apple silicon, macOS 26, no Xcode, no
Homebrew, no xBot data, no agent CLI yet.

1. Install from the step 6 DMG. It opens with no Gatekeeper warning.
2. Home says "xBot works through an agent you already have". Follow one of its links, install Claude
   Code (or Codex, Antigravity or GitHub Copilot) and sign in. xBot finds it without a restart or a terminal hint (Settings › Agents).
3. Add a project folder, start a chat, get a streamed reply with tool rows; stop one mid-reply (⌘.);
   run a plan; open the terminal; edit a note.
4. Turn on **Run when xBot is closed** for an automation, quit xBot, and see it run. Turn it off and
   check `~/Library/LaunchAgents/dev.xbot.automations.plist` is gone.
5. Pair a phone from Settings › Devices (installed from Xcode). Same Wi-Fi works; with option B,
   iCloud works too.
6. Quit, drag xBot to the Trash, run `Uninstall xBot.command` from the DMG, and check nothing of
   xBot is left (the table in [packaging](11-packaging-and-updates.md#uninstall)).
7. Time the whole thing, and write down every place you reached for something the app should have
   done. There's no onboarding flow yet (the [roadmap](12-roadmap.md) has it after the native
   brain), so this run is what shows how much one is needed.

The live suites are worth a run on the development Mac at the same time:
`XBOT_LIVE_HARNESS=1 swift test` in `apps/mac`, `scripts/e2e_automations.py` (xBot closed), and
the 18 phone UI tests in `apps/ios/UITests/LiveRemoteUITests.swift` against a debug Mac build.

---

## 8. Publish 2.0.0 — **needs you**

```sh
gh workflow run "Mac release" -R MasterYoav/xBot -f version=2.0.0
```

Leave **prerelease** unticked. Sparkle's feed is `releases/latest/download/appcast.xml`, which
GitHub resolves only to the newest release that isn't a pre-release. Today that URL is a 404,
because the only release, 1.0.0, is a pre-release.

Publishing 2.0.0 as a full release also means **every 1.0.0 install on macOS 26 will be offered
2.0**: same bundle id, same key, and its feed starts answering. Decide whether that's wanted. Those
people's Docker container and volumes stay behind; `Uninstall xBot.command` in the DMG is how they
remove them.

Afterwards:

```sh
curl -sIL https://github.com/MasterYoav/xBot/releases/latest/download/appcast.xml | grep -i '^HTTP'
```

ends in `200`, and **xBot › Check for Updates…** in the installed 2.0.0 says it's up to date.

---

## 9. Prove an update — **after the next release**

An update channel isn't verified until an update has gone through it. Publish 2.0.1 the same way
and check that 2.0.0 offers it, asks before installing, installs and relaunches as 2.0.1. Do it once
with a long turn running too: the relaunch should wait until the turn ends.

---

## 10. The phone app: TestFlight or not — **needs you**

Today the iPhone and iPad app is installed from Xcode onto the team's own devices. To let anyone
else use it:

1. An App Store Connect record for `dev.xbot.mobile`, and an App Store distribution profile with
   iCloud and push.
2. `aps-environment` `production`, and the CloudKit production schema from step 4.B (TestFlight
   builds use production).
3. A privacy description for what it asks for: the local network (Bonjour `_xbot._tcp`) and the
   camera (scanning the pairing code).
4. An upload with `xcodebuild archive` (still with `-skipPackagePluginValidation`), then TestFlight
   review.

Without option B in step 4, a TestFlight phone only works on the same network as the Mac.

---

## Worth doing, not blocking

- **A second look at the security posture** before the website goes up: the
  [security doc](10-security.md), the TLS-PSK pairing, and what the agents may do under each
  permission mode.
- **The name.** [ADR-0006](decisions/0006-naming-and-trademark.md) is still unresolved, and it's
  cheaper to answer before a public launch than after.
