# Mac app packaging (M7)

Local release flow until CI signing credentials exist. See `docs/11-packaging-and-updates.md`.

```sh
# 1. Official icon (Icon Composer → Assets.car + xBot.icns)
scripts/generate-app-icon.sh

# 2. Release binary
cd apps/mac && swift build -c release && cd ../..

# 3. .app bundle
scripts/bundle-mac-app.sh

# 4. DMG (unsigned stub)
scripts/create-dmg.sh

# 5. Run against real engine
cd apps/mac && XBOT_USE_RUNTIME=1 .build/release/XBot
```

Engine image (pulled during onboarding, not bundled in the DMG):

```sh
scripts/build-engine-image.sh          # tags xbot/engine:1 locally
scripts/check-engine-health.sh         # probes /health
scripts/generate-engine-manifest.sh    # manifest JSON for updates pipeline
```

## M6 manual test (clean VM)

Before each release candidate, on a snapshot with **no Homebrew, no Docker, no dev tools**:

1. Install from DMG → drag to Applications → launch
2. Complete all five onboarding steps with only an API key typed
3. Send one message, confirm streaming reply
4. Open panel → Screen, confirm screenshot poll
5. Take control → release control
6. Copy diagnostics from a forced failure — confirm no keys in clipboard

# Sparkle updates

Sparkle 2 is linked through SwiftPM (`Package.swift`). It stays **inert** until a release
`Info.plist` includes `SUFeedURL` and `SUPublicEDKey` (EdDSA public key from
`generate_keys` / `generate_appcast`).

Release Info.plist keys (injected at CI pack time, not committed with secrets):

```xml
<key>SUFeedURL</key>
<string>https://releases.example.com/xbot/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>base64-public-key</string>
<key>SUEnableAutomaticChecks</key>
<true/>
<key>SUAutomaticallyUpdate</key>
<false/>
```

`scripts/bundle-mac-app.sh` embeds `Sparkle.framework` when present. Settings → Updates exposes
**Check for app update**; checks are deferred while a turn is streaming.

When CI has signing credentials:

```sh
export MACOS_SIGNING_IDENTITY="Developer ID Application: …"
export APPLE_ID=…
export APPLE_TEAM_ID=…
export APPLE_APP_PASSWORD=…
scripts/sign-mac-app.sh
```

Until appcast + EdDSA key exist in CI, ship via signed DMG only.

