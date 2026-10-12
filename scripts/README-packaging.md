# Mac app packaging

The local release flow for the Mac app. Why each step exists, signing, Sparkle and the iPhone app
are in [`docs/11-packaging-and-updates.md`](../docs/11-packaging-and-updates.md); what's left before
a public 2.0 is in [`docs/13-launch-checklist.md`](../docs/13-launch-checklist.md).

Needs Xcode 26 (for `actool` and the Metal toolchain) on an Apple-silicon Mac with macOS 26. Run
from the repository root.

## Build

```sh
scripts/generate-app-icon.sh                                   # xBot.icon → Assets.car + xBot.icns; first, on a fresh clone
cd apps/mac && swift build --build-tests && swift test && cd ../..
cd apps/mac && swift build -c release --arch arm64 && cd ../..  # Apple silicon only
XBOT_VERSION=2.0.0-dev scripts/bundle-mac-app.sh               # → apps/mac/XBot.app (XBOT_BUILD_NUMBER sets CFBundleVersion)
```

Without `XBOT_VERSION` the bundle is stamped with the `VERSION` file (the version the next release
publishes), so pass `2.0.0-dev`-style versions for local installs. If the build stops on SwiftTerm's
Metal shader: `xcodebuild -downloadComponent MetalToolchain`.

## Sign: pick one

```sh
# For this team's own Macs, with iCloud (the phone's away lane). Apple Development identity;
# Xcode makes the profile through the XBotMacSigning helper in apps/ios/project.yml.
scripts/sign-mac-remote.sh

# For anyone else: Developer ID, then notarize and staple the app and the DMG.
# Without the three APPLE_* variables it signs but doesn't notarize. No iCloud entitlement.
export MACOS_SIGNING_IDENTITY="Developer ID Application: …"
export APPLE_ID=… APPLE_TEAM_ID=… APPLE_APP_PASSWORD=…
scripts/sign-mac-app.sh                                         # also rebuilds dist/xBot.dmg
```

For a local install, quit xBot and replace the old copy:
`rm -rf /Applications/XBot.app && ditto apps/mac/XBot.app /Applications/XBot.app`.

## DMG

```sh
scripts/create-dmg.sh      # → dist/xBot.dmg: XBot.app, Applications alias, Uninstall xBot.command
```

`sign-mac-app.sh` runs this itself after signing, so the DMG holds the signed app.

## Sparkle

Inert unless both `XBOT_APPCAST_URL` (HTTPS) and `XBOT_SPARKLE_PUBLIC_KEY` are set when
`bundle-mac-app.sh` runs; `inject-sparkle-plist.sh` then writes `SUFeedURL`, `SUPublicEDKey`,
`SUEnableAutomaticChecks` (true) and `SUAutomaticallyUpdate` (false) into the bundle.

```sh
scripts/generate-sparkle-keys.sh                  # prints the public key; makes a pair only if none exists
SPARKLE_EDDSA_PRIVATE_KEY_FILE=sparkle-private.key \
  scripts/generate-appcast.sh                     # → dist/releases/xBot-<version>.dmg + appcast.xml
```

`SPARKLE_EDDSA_PRIVATE_KEY` (the key itself) works instead of the file. Never commit the key.

## In CI: releasing

**To release, change `VERSION` in a pull request and merge it.** The push to master runs
`.github/workflows/mac-release.yml`, which runs the same steps with the signing secrets, verifies
the DMG the way a stranger's Mac will, and publishes `v<VERSION>` with `xBot.dmg`,
`xBot-<version>.dmg` and `appcast.xml`. A version with a `-` is a pre-release; a version that's
already released is skipped, not rebuilt. Details in
[packaging › Releasing](../docs/11-packaging-and-updates.md#releasing).

```sh
gh workflow run "Mac release" -R MasterYoav/xBot -f build_only=true   # build only → artifact xbot-release
gh workflow run "Mac release" -R MasterYoav/xBot                      # publish VERSION if it isn't yet
git tag v2.0.1 && git push origin v2.0.1                              # publish a tag
```

A Developer ID build has no iCloud entitlement, so a downloaded copy reaches the phone on the same
network only.

## Before a release candidate

Run the clean-machine test in the [launch checklist](../docs/13-launch-checklist.md) (step 7), and
the live suites on the development Mac: `XBOT_LIVE_HARNESS=1 swift test` in `apps/mac`, and
`scripts/e2e_automations.py` with xBot closed.
