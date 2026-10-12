# Packaging and updates

How xBot is built, signed, shipped and updated, outside the App Store
([ADR-0005](decisions/0005-distribution-outside-app-store.md)). The step-by-step commands for a local
release are in [`scripts/README-packaging.md`](../scripts/README-packaging.md); what is left before a
public 2.0 is in the [launch checklist](13-launch-checklist.md).

## What ships

| | Channel | State |
| --- | --- | --- |
| **Mac app** | One `.dmg` from GitHub Releases, Developer ID signed, notarized and stapled, updated by Sparkle | The pipeline works: it published xBot 1.0.0 (a pre-release, 29 September 2026, the old Docker app). Nothing of the redesign is released; local builds say `2.0.0-dev` |
| **iPhone and iPad app** | None yet | Installed from Xcode onto your own devices. No TestFlight or App Store build |

The DMG holds three things: `XBot.app`, an alias to Applications, and `Uninstall xBot.command`. The
window is the standard one; the gesture is a drag. There's no runtime, image or model to download
afterwards: xBot drives the agent CLIs already on the Mac (Claude Code, Codex, Antigravity, GitHub
Copilot), and the app is a single Apple-silicon binary with two third-party libraries, Sparkle
(embedded as a framework) and SwiftTerm. xBot 1.0.0's DMG was 8.8 MB.

Requirements: macOS 26 and Apple silicon (`LSMinimumSystemVersion` is 26.0; the release build is
`--arch arm64` only and the workflow checks it with `lipo -verify_arch arm64`).

---

## Building the Mac app

### Locally

```sh
scripts/generate-app-icon.sh                                  # xBot.icon → Assets.car + xBot.icns (Xcode 26)
cd apps/mac && swift build --build-tests && swift test && cd ../..
cd apps/mac && swift build -c release --arch arm64 && cd ../..
XBOT_VERSION=2.0.0-dev scripts/bundle-mac-app.sh              # → apps/mac/XBot.app
scripts/create-dmg.sh                                         # → dist/xBot.dmg
```

`bundle-mac-app.sh` copies the release binary, the compiled icon, `apps/mac/Resources/Info.plist`,
SwiftPM's per-target resource bundles (without them `Bundle.module` traps at launch) and
`Sparkle.framework`, then calls `inject-sparkle-plist.sh`. It stamps the version from two variables:

| Variable | Sets | Notes |
| --- | --- | --- |
| `XBOT_VERSION` | `CFBundleShortVersionString` | Always set from here; without it, `2.0.0-dev` |
| `XBOT_BUILD_NUMBER` | `CFBundleVersion` | Sparkle compares this, so it must rise with every release. CI uses the run number |

Two things a fresh checkout needs that aren't obvious, both found as CI failures:

1. **The icon is a build input.** `Package.swift` declares `Assets.car` and `xBot.icns` as
   resources, `.gitignore` excludes them, and they're compiled from `xBot.icon/`. Until
   `scripts/generate-app-icon.sh` has run, `swift build` fails with "missing inputs". The script
   also writes the alternate app icons (Ink, Rose, Sunset, Plum) for Settings › Appearance.
2. **Xcode 26.** `xBot.icon` is Icon Composer's format and only Xcode 26's `actool` compiles it.
   SwiftTerm compiles a Metal shader, and Xcode 26 ships without the Metal toolchain until it's
   downloaded: `xcodebuild -downloadComponent MetalToolchain`.

### In CI

| Workflow | When | What it does |
| --- | --- | --- |
| `.github/workflows/ci.yml` | Every pull request and push to master | `macos-26`: Metal toolchain, icon, `swift build --build-tests`, `swift test` |
| `.github/workflows/mac-release.yml` ("Mac release") | By hand (`workflow_dispatch`) | Builds, signs, notarizes and, with a version, publishes. Below |
| `.github/workflows/pages.yml` ("Website") | Push to master touching `site/` | Publishes `site/` to GitHub Pages (live at masteryoav.github.io/xBot) |

The iPhone app and its UI tests aren't built in CI.

**Mac release**, in order: Metal toolchain → icon → `swift test` → release build (arm64, checked
with `lipo`) → `bundle-mac-app.sh` (with the Sparkle keys) → `create-dmg.sh` (unsigned, so a run with
no secrets still produces a DMG) → import the certificate into a throwaway keychain →
`sign-mac-app.sh` → `generate-appcast.sh` → upload the `xbot-release` artifact. With a `version`
input it then mounts the DMG and checks what a stranger's Mac will check (`spctl` says *Notarized
Developer ID*, both staples validate, the appcast carries an `edSignature`, the version matches), and
creates the GitHub release `v<version>` with three assets: `xBot.dmg`, `xBot-<version>.dmg` and
`appcast.xml`. The `prerelease` box marks it a pre-release; otherwise it's marked latest.

```sh
gh workflow run "Mac release" -R MasterYoav/xBot                      # build only, artifact
gh workflow run "Mac release" -R MasterYoav/xBot -f version=2.0.0     # build and publish
```

**Secrets** (Settings › Secrets and variables › Actions). All nine are set on the repository; each
optional step no-ops when its secret is absent.

| Secret | Purpose |
| --- | --- |
| `MACOS_SIGNING_IDENTITY` | Developer ID Application identity, e.g. `Developer ID Application: Name (TEAMID)` |
| `MACOS_CERTIFICATE_P12` | The certificate and its private key, base64 of a `.p12` export |
| `MACOS_CERTIFICATE_PASSWORD` | The password set when exporting that `.p12` |
| `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | Notarization (`notarytool`; an app-specific password) |
| `XBOT_APPCAST_URL` | Feed URL for build-only runs. A run with a version uses `releases/latest/download/appcast.xml` instead |
| `XBOT_SPARKLE_PUBLIC_KEY` | EdDSA public key baked into the bundle |
| `SPARKLE_EDDSA_PRIVATE_KEY` | Signs the update archive and the appcast |
| `XBOT_RELEASE_DOWNLOAD_PREFIX` | Optional (not set): enclosure prefix for build-only runs. A run with a version points at its own release |

**Naming an identity doesn't make one exist.** `codesign` looks the identity up in the keychain
search list, and a fresh runner's keychain holds no certificates. Without `MACOS_CERTIFICATE_P12`
the sign step fails with "The specified item could not be found in the keychain", which reads like
a wrong identity string and is a missing certificate.

---

## Signing

There are two ways to sign the Mac app, and they differ in one thing that matters: iCloud.

| | Developer ID (`scripts/sign-mac-app.sh`) | Apple Development (`scripts/sign-mac-remote.sh`) |
| --- | --- | --- |
| Used by | `mac-release.yml`; anyone with the Developer ID certificate | Local installs on the team's own Macs |
| Runs on | Any Mac, after notarization | Only Macs registered to the team |
| Hardened runtime | Yes | Yes |
| Notarized and stapled | Yes, the app and then the DMG | No |
| Entitlements | None | iCloud (CloudKit, `iCloud.dev.xbot`) and push, from an Xcode-managed profile |
| The phone's iCloud lane | **Doesn't work**: the Mac falls back to the local lane | Works |

### Developer ID

`sign-mac-app.sh` reads `MACOS_SIGNING_IDENTITY` and exits quietly without it. It signs
`Sparkle.framework` first, then the app (`--options runtime --timestamp`), and verifies. With the
three notarization variables it then:

1. zips and notarizes **the app**, and staples it — the person drags the app out of the DMG, and an
   unstapled app fails to open on a Mac that's offline at first launch;
2. rebuilds the DMG, so it contains the signed, stapled app (it used to sign only the wrapper,
   around an unsigned app);
3. signs, notarizes and staples the DMG;
4. runs `spctl --assess --type execute` on the app.

`create-dmg.sh` also signs `Uninstall xBot.command` with the same identity, but only when the
identity is actually in a keychain. A `.command` keeps its signature in extended attributes, which
the copy and the disk image preserve; unsigned, it arrives quarantined and macOS refuses it.

### Apple Development, with iCloud

iCloud and push are restricted entitlements: macOS only honours them with a provisioning profile
for the bundle id. The Mac app is built with SwiftPM, which can't ask Xcode for one, so
`apps/ios/project.yml` has a helper target, **`XBotMacSigning`**: a one-window macOS app with the
Mac's bundle id `dev.xbot.app`, team `N6883L5366`, and the same iCloud container and push
entitlements. It's never shipped. `sign-mac-remote.sh`:

1. runs `xcodegen generate` and builds `XBotMacSigning` with `-allowProvisioningUpdates`, so Xcode's
   automatic signing makes (or reuses) the profile;
2. copies the helper's `embedded.provisionprofile` into `XBot.app`;
3. reads the helper's signing identity (the `Apple Development` one) and its entitlements, minus
   `get-task-allow`;
4. re-signs Sparkle and the app with that identity and those entitlements, hardened runtime, and
   verifies.

```sh
scripts/sign-mac-remote.sh                    # signs apps/mac/XBot.app
scripts/sign-mac-remote.sh /path/to/XBot.app  # or another bundle
```

The helper's DerivedData goes to `XBOT_SIGN_DERIVED_DATA`, or `apps/ios/DerivedData/sign` (git-ignored)
if unset. The installed app on the development Mac is signed this way: `Apple Development`, team
`N6883L5366`, with `aps-environment` `development`, CloudKit and `iCloud.dev.xbot`.

### A Developer ID release with iCloud

Not set up. It needs, from the account holder:

- a **Developer ID provisioning profile** for `dev.xbot.app` that includes iCloud (CloudKit,
  `iCloud.dev.xbot`) and push;
- the **CloudKit schema deployed to Production** in the CloudKit Console: the development profile
  uses CloudKit's development environment, where the mailbox's `Batch` record type was created on
  first use, and a distributed build uses production;
- and a change to `sign-mac-app.sh`, which today passes no `--entitlements` and embeds no profile.

Until then a Developer ID build is fine everywhere except the away lane: the phone pairs and works
on the same network, and doesn't reach the Mac through iCloud. The [checklist](13-launch-checklist.md)
has the steps.

### Entitlements and the sandbox

The Mac app isn't sandboxed and asks for nothing beyond iCloud and push. It can't be sandboxed: it
starts the agent CLIs as child processes with the person's login-shell `PATH`, reads their
sessions and usage data under the home folder, opens real shells for the terminal, works in any
project folder, and installs a LaunchAgent for automations. That's the reason it isn't on the Mac
App Store.

`Info.plist` carries the usage strings macOS shows when an automation or agent first controls
another app (`NSAppleEventsUsageDescription`) or reads calendars and reminders, and the copyright
line "Copyright © 2026 xBot contributors. MIT.", the holder named in `LICENSE`.

The iPhone app's entitlements (`apps/ios/XBotMobile.entitlements`) are CloudKit with
`iCloud.dev.xbot` and `aps-environment` `development`.

---

## Updates

**Sparkle 2**, linked through SwiftPM (`from: "2.6.0"`), started by `SparkleAppUpdateController`.

**Inert until configured.** The updater starts only when the bundle's `Info.plist` has both
`SUFeedURL` and `SUPublicEDKey`. A plain `swift run` or an unconfigured bundle has neither, and
**xBot › Check for Updates…** says "Updates aren't set up in this build" (`AppUpdateGate`).

**The keys come from the signed bundle only.** `scripts/inject-sparkle-plist.sh` writes, when
`XBOT_APPCAST_URL` and `XBOT_SPARKLE_PUBLIC_KEY` are both set:

| Key | Value |
| --- | --- |
| `SUFeedURL` | The appcast URL |
| `SUPublicEDKey` | The EdDSA public key |
| `SUEnableAutomaticChecks` | `true` (Sparkle checks once a day by default) |
| `SUAutomaticallyUpdate` | `false`: it asks before installing |

They sit inside the code-signed bundle, where they can't change without breaking the signature. The
environment is honoured in debug builds only (`AppUpdateTrust`), and the feed must be HTTPS: an
update channel is a code-execution channel, and the appcast also carries the version and the
download URL, which is enough to stage a downgrade.

**The feed.** A release run sets `SUFeedURL` to
`https://github.com/MasterYoav/xBot/releases/latest/download/appcast.xml`. GitHub redirects that to
the newest release **that isn't a pre-release**, so each release's appcast only describes itself.
Today the only release, 1.0.0, is a pre-release, so that URL answers 404 and installed 1.0.0 apps
find nothing. A 2.0 published as a pre-release wouldn't be found either; publish it as a full
release. Because 2.0's appcast carries `minimumSystemVersion` 26.0, a 1.0.0 install on an older
macOS won't be offered it.

**Keys.** `scripts/generate-sparkle-keys.sh` finds Sparkle's own `generate_keys` in the SwiftPM
artifacts (build once first), prints the public key, and only generates a pair if none exists, so it
never replaces the key shipped builds trust. The private key lives in the login Keychain. **Losing it
strands every installed copy**: an app can't verify an update signed by a key it has never seen.
`scripts/generate-appcast.sh` copies `dist/xBot.dmg` to `dist/releases/xBot-<version>.dmg` (no
space: GitHub renames spaces in asset names to dots) and runs `generate_appcast` with the private
key from `SPARKLE_EDDSA_PRIVATE_KEY` or `SPARKLE_EDDSA_PRIVATE_KEY_FILE`.

**Never mid-turn.** At launch the app binds the updater to its turns
(`bindUpdateBlockingActivity`) and starts its daily check (`scheduleAutomaticCheckIfDue`, looked at
again every hour while the app stays open). While any turn is running, background checks, Sparkle's
own included, are skipped, and the relaunch that installs an update waits until none is
(`UpdateInstallDeferral`), so an update never cuts off a reply. **Check for Updates…** looks even
mid-turn; it's the install that waits. Sparkle still asks before it installs.

**Not built in 2.0:** there's no update settings page and no beta channel.

---

## Versioning

- **Mac app:** semantic versioning. `CFBundleShortVersionString` is the marketing version, set from
  `XBOT_VERSION`; `CFBundleVersion` is a build number that only rises, from `XBOT_BUILD_NUMBER` (the
  release workflow's run number). Without `XBOT_VERSION`, `bundle-mac-app.sh` stamps `2.0.0-dev`,
  which is also what the committed `apps/mac/Resources/Info.plist` says; its `CFBundleVersion` is
  `1` until `XBOT_BUILD_NUMBER` sets it.
- **iPhone app:** `MARKETING_VERSION` `2.0.0`, `CURRENT_PROJECT_VERSION` `1` in
  `apps/ios/project.yml`.
- **The wire** between them has its own version (`Wire.version`, now 1); see
  [iPhone and iPad](14-iphone-and-ipad.md#the-protocol).
- **Storage:** the SQLite store's schema version is 6; the store migrates forward on open.

---

## The iPhone and iPad app

The Xcode project is generated by XcodeGen from `apps/ios/project.yml` and has three targets:

| Target | What it is |
| --- | --- |
| `XBotMobile` | The app: iOS 26, iPhone and iPad, bundle id `dev.xbot.mobile`, product name xBot. Links `XBotRemote`, `XBotWorld` and `XBotMarkdown` from `apps/mac/Package.swift`, and SwiftTerm |
| `XBotMobileUITests` | The 18 live UI tests in `UITests/LiveRemoteUITests.swift` |
| `XBotMacSigning` | The Mac signing helper above. Not shipped |

```sh
cd apps/ios && xcodegen generate && cd ../..        # after adding or removing files
xcodebuild -project apps/ios/XBotMobile.xcodeproj -scheme XBotMobile \
  -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation build
```

On a device (registered to the team, unlocked):

```sh
xcodebuild -project apps/ios/XBotMobile.xcodeproj -scheme XBotMobile \
  -destination 'generic/platform=iOS' -derivedDataPath DerivedData/ios \
  -allowProvisioningUpdates -skipPackagePluginValidation build
xcrun devicectl list devices
xcrun devicectl device install app --device <name or id> \
  DerivedData/ios/Build/Products/Debug-iphoneos/xBot.app
```

`-skipPackagePluginValidation` is needed on every `xcodebuild` call because SwiftTerm ships a build
plugin. Signing is automatic with team `N6883L5366`; to build with another account, change
`DEVELOPMENT_TEAM` in `project.yml` (and the bundle ids, which belong to that team). `DerivedData/` is
git-ignored.

There's no distribution channel. TestFlight would need an App Store Connect record for
`dev.xbot.mobile`, `aps-environment` `production`, and the same CloudKit production schema as the
Mac; that's a decision on the [checklist](13-launch-checklist.md).

---

## First run from the DMG

1. Download `xBot.dmg`, open it, drag xBot to Applications, eject.
2. Open xBot. **Gatekeeper checks the notarization ticket**; because the app is stapled, this works
   offline and shows no warning.
3. Home. With no agent CLI installed it says "xBot works through an agent you already have", with
   links to get Claude Code, Codex, Antigravity and GitHub Copilot. There's no onboarding flow in the redesigned app yet
   ([06-onboarding.md](06-onboarding.md) describes today's first run).

Step 2 is the one that goes wrong. An unsigned or unstapled build shows "xBot cannot be opened
because the developer cannot be verified", and a non-technical person stops there. Check every
release on a Mac that has never seen it:

```sh
spctl --assess --type execute --verbose /Applications/XBot.app
xcrun stapler validate /Applications/XBot.app
```

---

## Uninstall

There's no uninstall button in the redesigned app. Dragging `XBot.app` to the Trash removes the
app; what it stored stays until removed:

| Where | What |
| --- | --- |
| `~/Library/Application Support/xBot/` | `xbot.sqlite` (projects, chats, agents, automations) and `history.sqlite` (a rebuildable index) |
| Preferences, domain `dev.xbot.app` | Settings and appearance |
| Keychain, service `dev.xbot.remote.pairing` | Pairing keys for paired phones |
| `~/Library/LaunchAgents/dev.xbot.automations.plist` | Only if **Run when xBot is closed** is on. It starts `XBot --automations-tick` every minute |
| Each project's `notes/` folder | Notes. These belong to the project and stay |

**Turn off Run when xBot is closed before deleting the app.** That boots the LaunchAgent out and
deletes its plist. Left behind, launchd keeps trying to start a binary that's gone (the uninstaller
below removes it too).

**`Uninstall xBot.command`** (in the DMG, from `scripts/uninstall-xbot.command`) asks you to type
`remove`, refuses while xBot is running, and then:

- removes xBot 1.x's Docker container `xbot-engine` and volumes `xbot-data`, `xbot-workspace`,
  `xbot-profiles`, when Docker (or the Colima xBot 1.x installed) is available. It leaves Docker and
  Colima themselves alone;
- unloads the automations LaunchAgent (`launchctl bootout gui/<uid>/dev.xbot.automations`) and
  deletes `~/Library/LaunchAgents/dev.xbot.automations.plist`;
- deletes every Keychain item of the pairing service `dev.xbot.remote.pairing` (one per paired
  device), and xBot 1.x's (`dev.xbot.provider-key`, `dev.xbot.engine-token`,
  `dev.xbot.key-encryption-key`, `dev.xbot.intelligence-key`, `dev.xbot.copilotkit-license`), each by
  service name, never a wildcard sweep;
- deletes `~/Library/Application Support/xBot` and the `dev.xbot.app` preferences.

Nothing on the phone is touched: delete the iPhone app as usual, and remove the device in
the Mac's Settings › Devices first if the Mac is staying.
