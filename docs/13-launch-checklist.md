# Launch checklist

Everything between here and a public xBot 2.0: a signed `.dmg` a stranger can download, open and
use, with updates that work.

The [roadmap](12-roadmap.md) says what's built. This says what to *do*, in order. Steps marked
**needs you** can only be done by the account holder (the Apple Developer account, the GitHub
repository's settings, the Sparkle key). The rest is work in the repository. How the pieces work is
in [packaging and updates](11-packaging-and-updates.md).

The order matters: the iCloud decision changes what gets signed, and the clean-machine run tests
the build you're about to publish. **Publishing is automatic**: `VERSION` already says `2.0.0` on the
release branch (`release-on-version`), and merging that PR into master publishes xBot 2.0.0 as the
latest release. So do steps 2–7 *before* merging it.

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
- **CI is green** on master (`swift build --build-tests && swift test` on `macos-26`; 443 tests).
- **Releases are automated.** "Mac release" publishes `v<VERSION>` when `VERSION` changes on master,
  refuses to publish without the signing secrets, and skips a version that's already out
  ([packaging › Releasing](11-packaging-and-updates.md#releasing)).
- **The website is rewritten for 2.0**, with **Download for Mac** pointing at
  `releases/latest/download/xBot.dmg` (live once 2.0.0 is published).
- **The redesign runs signed with iCloud on a real Mac**: the installed app is signed by
  `scripts/sign-mac-remote.sh` (Apple Development, Xcode-managed profile with CloudKit and push), and
  an iPhone 15 Pro paired with it by QR, chatted over Wi-Fi, and got a new chat answered through
  iCloud with Wi-Fi off.
- **Measured on the installed release build** (11 October 2026): 0.01% CPU, 63 MB, with a phone
  paired and xBot in the background.

---

## 1. Merge the open PRs — done

The motion gate (#30's change) and #31–#44 (the iPhone and iPad app, the org chart, the documentation
refresh and its fixes) are on master. Before releasing, pull master and run the suite once more locally:

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
surprise. If one has lapsed, the release run after the merge fails at signing or notarization and
publishes nothing; fix the secret and re-run it.

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

**A. Ship 2.0 with the local lane only.** Nothing to do here. The README and the website already say
the downloaded build reaches the phone on the same network only; add a line to the 2.0.0 release
notes once it's published (`gh release edit v2.0.0 --notes-file …`).

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

## 5. Fix what ships stale — done

The website (`site/index.html`) describes 2.0 and offers **Download for Mac**. It republishes on the
same merge that publishes the release, so the button and the DMG arrive together.

---

## 6. A build-only release run

Run it on the release branch, before merging: a manual run on any branch but master never publishes.

```sh
gh workflow run "Mac release" -R MasterYoav/xBot --ref release-on-version -f build_only=true
gh run watch -R MasterYoav/xBot
gh run download -R MasterYoav/xBot -n xbot-release
```

It builds the release exactly, stamped 2.0.0, but uploads an artifact instead of publishing. Open
the downloaded `xBot.dmg` and check:

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

**Merge the release PR** (branch `release-on-version`, `VERSION` = `2.0.0`). The push to master runs
"Mac release", which checks the secrets, builds, signs, notarizes, verifies, and publishes **v2.0.0**
as a full release marked latest, with `xBot.dmg`, `xBot-2.0.0.dmg` and `appcast.xml`. A full release
matters: Sparkle's feed and the Download button use `releases/latest/download/…`, which GitHub
resolves only to the newest release that isn't a pre-release. Today those URLs are a 404, because
the only release, 1.0.0, is a pre-release.

If the run fails, nothing is published; fix the cause and re-run it (or
`gh workflow run "Mac release" -R MasterYoav/xBot` on master).

Publishing 2.0.0 also means **every 1.0.0 install on macOS 26 will be offered 2.0**: same bundle id,
same key, a higher build number, and its feed starts answering. Decide whether that's wanted
*before* merging. Those people's Docker container and volumes stay behind; `Uninstall xBot.command`
in the DMG is how they remove them.

Afterwards:

```sh
gh run watch -R MasterYoav/xBot
curl -sIL https://github.com/MasterYoav/xBot/releases/latest/download/appcast.xml | grep -i '^HTTP'
curl -sIL https://github.com/MasterYoav/xBot/releases/latest/download/xBot.dmg | grep -i '^HTTP'
```

Both end in `200`, and **xBot › Check for Updates…** in the installed 2.0.0 says it's up to date.

---

## 9. Prove an update — **after the next release**

An update channel isn't verified until an update has gone through it. Publish 2.0.1 the same way
(a PR that sets `VERSION` to `2.0.1`, merged) and check that 2.0.0 offers it, asks before installing, installs and relaunches as 2.0.1. Do it once
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
