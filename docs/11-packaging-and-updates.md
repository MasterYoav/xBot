# Packaging and updates

Delivering a native Mac app that manages a container runtime, outside the App Store.

## What ships

**One `.dmg`.** Universal binary, Developer ID signed, notarized, stapled.

The window is the standard one: the app icon on the left, an arrow, the Applications folder alias on
the right. No background artwork with instructions on it, no "read me" file, no bundled installers.
The gesture is a drag and everyone already knows it.

**Size target: under 40 MB.** The app is a client. The engine image is pulled at first run, and this
is deliberate — bundling gigabytes of container image into a DMG makes the download hostile and the
update story impossible.

**What is *not* in the DMG:**

- The engine image (pulled during onboarding)
- A container runtime (installed during onboarding if absent — see [ADR-0003](decisions/0003-container-runtime.md))
- Any model

---

## Signing

| Setting | Value |
| --- | --- |
| Identity | Developer ID Application |
| Hardened runtime | On |
| Library validation | On |
| Timestamp | On |
| Notarization | Required |
| Stapling | Required |

### Entitlements

Deliberately short. Every entitlement is a claim we have to defend.

```xml
<key>com.apple.security.app-sandbox</key>            <false/>
<key>com.apple.security.network.client</key>         <true/>
<key>com.apple.security.cs.allow-jit</key>           <false/>
<key>com.apple.security.cs.disable-library-validation</key> <false/>
```

**Unsandboxed, and why.** The app drives a container runtime: it launches processes, talks to a Unix
socket, and manages an external application's lifecycle. None of that is possible in a sandbox. This
is the single reason we are not on the Mac App Store — see
[ADR-0005](decisions/0005-distribution-outside-app-store.md).

**Say so publicly.** The download page explains, in a sentence, that xBot is not sandboxed because it
manages containers on your behalf, and that it is signed and notarized by Apple. A security-conscious
user *will* check, and should find an explanation rather than a surprise.

### Notarization

Every build, including betas. `notarytool` in CI, stapled before the DMG is published. An unstapled
app fails to open on a machine that is offline at first launch, which is exactly the kind of bug that
generates support mail from people who cannot describe it.

---

## Build pipeline (today)

Unsigned local releases are scripted; signing runs when CI secrets are set (M7). Step-by-step:
[`scripts/README-packaging.md`](../scripts/README-packaging.md).

| Script | Purpose |
| --- | --- |
| `scripts/generate-app-icon.sh` | `xBot.icon` → `Assets.car` + `xBot.icns` via `actool` |
| `scripts/bundle-mac-app.sh` | Wrap `swift build -c release` binary in `XBot.app` |
| `scripts/create-dmg.sh` | Unsigned DMG with Applications alias |
| `scripts/build-engine-image.sh` | Local dev image `xbot/engine:1` |
| `scripts/generate-engine-manifest.sh` | Pinned digest manifest for updates |
| `scripts/sign-mac-app.sh` | Developer ID sign + optional notarization when env vars are set |
| `scripts/inject-sparkle-plist.sh` | Injects `SUFeedURL` / `SUPublicEDKey` from CI env at bundle time |
| `scripts/generate-appcast.sh` | Builds `dist/releases/appcast.xml` from a signed DMG + EdDSA key |
| `scripts/build-engine-manifest.py` | Assembles that JSON from environment values |
| `scripts/read-health-field.py` | Reads one field from a `/health` response |
| `scripts/verify-m5-handoff.sh` | Smoke check against a live engine |

CI: `.github/workflows/mac-release.yml` builds, optionally signs/notarizes, generates a Sparkle
appcast when EdDSA secrets are set, and uploads `dist/xBot.dmg` plus `dist/releases/`; signing and
appcast steps no-op when their secrets are absent. `.github/workflows/engine-image.yml` builds the
engine image, **pushes it to `ghcr.io/masteryoav/xbot-engine`**, and uploads a manifest pinning the
pushed digest.

**`mac-release` CI secrets** (all optional until publish):

| Secret | Purpose |
| --- | --- |
| `MACOS_SIGNING_IDENTITY` | Developer ID Application identity |
| `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | Notarization |
| `XBOT_APPCAST_URL` | Sparkle feed URL injected into the bundled app |
| `XBOT_SPARKLE_PUBLIC_KEY` | EdDSA public key for update verification |
| `SPARKLE_EDDSA_PRIVATE_KEY` | Signs update archives and the appcast |
| `XBOT_RELEASE_DOWNLOAD_PREFIX` | Optional CDN prefix for enclosure URLs |

### Two ordering rules in CI that are not obvious

Both were live failures, and both are the kind that only appear on a fresh checkout:

1. **The icon is a build input, not a packaging step.** `Package.swift` declares `xBot.icns` and
   `Assets.car` as bundled resources and `.gitignore` excludes them, because they are compiled from
   `xBot.icon/`. So `swift build` fails on a clean clone with "missing inputs" until
   `scripts/generate-app-icon.sh` has run. It runs **first** in both workflows.
2. **The Mac jobs need `macos-26`.** `xBot.icon` is Icon Composer's format and only Xcode 26's
   `actool` compiles it. On `macos-15` the step runs, reports "actool did not produce Assets.car",
   and the build then fails on the missing resources.

---

## CI (target)

```yaml
build:
  - scripts/generate-app-icon.sh
  - cd apps/mac && swift build -c release --arch arm64 --arch x86_64   # universal (target)
  - cd apps/mac && swift test

sign:
  - codesign --deep --force --options runtime --timestamp
  - codesign --verify --deep --strict --verbose=2

notarize:
  - xcrun notarytool submit --wait
  - xcrun stapler staple XBot.app
  - xcrun stapler validate XBot.app

package:
  - scripts/bundle-mac-app.sh
  - scripts/create-dmg.sh
  - codesign the DMG
  - notarize + staple the DMG

publish:
  - generate Sparkle appcast with EdDSA signature
  - upload DMG + appcast
```

**Certificates and the notary key live in CI secrets, never in the repository.** Rotate on a
schedule and on any team change.

---

## Updating the app

**Sparkle 2**, the standard for Developer ID Mac apps.

| Setting | Value |
| --- | --- |
| Appcast | HTTPS, certificate-pinned |
| Signature | **EdDSA. Required.** |
| Delta updates | On |
| Automatic check | Daily |
| Automatic download | On |
| Automatic install | **Off** — prompt |

**An update channel is a code-execution channel.** EdDSA verification is not optional and the private
key does not live anywhere a build machine can be compromised into revealing it.

**Never interrupt.** Sparkle does not prompt while a turn is streaming or an agent is mid-task. The
prompt waits for an idle moment or for the next launch. An update dialog that appears over a running
agent will be dismissed, and dismissed updates do not get installed.

**Channels:** `stable` and `beta`, selectable in Settings → Updates. Beta users get a visible badge
so bug reports arrive labelled.

---

## Updating the engine

Independent from the app, because they have different cadences: the engine changes with upstream
merges, the app changes with our own work.

### The manifest

Served over HTTPS with pinning:

```json
{
  "channel": "stable",
  "version": "0.4.2",
  "image": "ghcr.io/<org>/xbot-engine@sha256:…",
  "size": 3_412_889_600,
  "minimumAppVersion": "1.2.0",
  "migration": {
    "schemaVersion": 14,
    "backwardCompatibleWith": 13
  },
  "releaseNotes": "https://…"
}
```

**`minimumAppVersion`** stops a stale app from starting an engine whose API it does not speak.
**`backwardCompatibleWith`** is what makes rollback possible.

### The sequence

1. **Check** — daily, and on launch.
2. **Pull in the background**, resumable, never blocking use of the running engine.
3. **Prompt at a natural moment.** Not mid-conversation.
4. **Stop** the old container gracefully. `stop_grace_period` matters here — Chromium needs time to
   flush its profile after `SIGTERM`, or the agent's logins are damaged.
5. **Start** the new container **against the same volumes.**
6. **Migrate**, inside the container, on start.
7. **Health check** — answers as xBot, not just a 200.
8. **On failure: roll back** to the previous digest, same volumes, and tell the user what happened.

**Keep the previous image until the new one has been healthy for a full session.** Disk is cheaper
than an engine that will not start.

### The migration hazard

⚠️ **The one that will bite.** Step 8 is impossible if a forward migration produced a schema the old
image cannot read.

Two options, and one must be chosen **before the first schema change reaches a user**:

- **Backward-compatible migrations for one version.** Additive only; a column is added in version N
  and only read in N+1. Disciplined, and the discipline has to hold across upstream merges too —
  which is the hard part, because upstream is not writing migrations with our rollback in mind.
- **Pre-migration dump.** Before a migration that is not backward-compatible, `pg_dump` to a file
  outside the volume. Rollback restores it. Costs disk and time; robust against upstream doing
  whatever it likes.

**Recommendation: the dump.** We do not control upstream's migrations and pretending we do is how a
user loses their audit trail.

---

## First-run experience from the DMG

The path the user actually walks:

1. Download `xBot-1.0.0.dmg`
2. Double-click → the DMG mounts → the window opens
3. Drag xBot to Applications
4. Eject, open Applications, double-click xBot
5. **Gatekeeper checks the notarization ticket** — because we stapled, this works offline and shows
   no scary dialog
6. Onboarding opens

**Step 5 is the one that goes wrong.** An unsigned or unstapled build produces "xBot cannot be opened
because the developer cannot be verified," and a non-technical user stops there permanently. Verify
on a clean machine, every release:

```sh
spctl --assess --type execute --verbose /Applications/xBot.app
xcrun stapler validate /Applications/xBot.app
```

Both must pass on a Mac that has never seen the app before.

---

## Uninstall

**Uninstalling must be complete and must be easy.** An app that leaves gigabytes of container volumes
behind after being dragged to the Trash is a bad citizen, and a container-managing app that does it
is a bad citizen with a reputation problem.

**Settings → Advanced → Uninstall xBot** does the whole thing, in order, with confirmation:

1. Stop the engine
2. Remove the containers
3. Remove the volumes — **named explicitly**: "your conversations, your agents, and their browser
   logins"
4. Remove Keychain items
5. Remove `UserDefaults`
6. Offer to move the app to the Trash

**Does not remove the container runtime**, because the user may have installed it for something else.
It says so.

**Also ship a standalone uninstaller script** in the DMG for the user who already dragged the app to
the Trash and then found the volumes. ⚠️ Yes, this is a terminal — it is the one place the no-terminal
promise yields, because the alternative is orphaned data with no way to remove it. It is documented
on the website, not in the app.

---

## Versioning

**The app** uses semantic versioning. `CFBundleShortVersionString` is the marketing version;
`CFBundleVersion` is a monotonic build number.

**The engine** carries its own version and its own schema version.

**Settings → Updates shows both**, plus the upstream OpenBot commit the engine was built from. That
last one is for the developer audience and for us — when a bug report arrives, knowing which upstream
revision is underneath saves an hour.
