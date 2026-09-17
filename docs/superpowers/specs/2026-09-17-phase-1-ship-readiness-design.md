# Phase 1: Ship Readiness

**Date:** 17 September 2026  
**Status:** Approved design; awaiting written-spec review

## Goal

Produce authoritative evidence that xBot can be distributed and used by a new Mac user:

1. the release artifact is universal, Developer ID signed, notarized, and stapled;
2. a real conversation reaches CopilotKit Intelligence and two model vendors, uses the agent's
   computer, and survives an app restart; and
3. a clean macOS 14+ VM completes onboarding without a terminal, Homebrew, Docker, or developer
   tools already installed.

Phase 1 does not publish the website or perform the final security review. Those are Phases 2 and
3, after the release path has exercised the product we will actually ship.

## Current Evidence

- `swift test` passes all 235 Mac tests locally.
- The existing scripts produce a valid compressed DMG whose checksum verifies.
- The current release workflow builds only the runner's native `arm64` architecture, while
  `docs/05-mac-app.md` and `docs/11-packaging-and-updates.md` require one universal app for Apple
  Silicon and Intel Macs.
- `swift build -c release --arch arm64 --arch x86_64` succeeds locally. The app executable and all
  embedded Sparkle executables are universal after the existing bundle script runs.
- The most recent successful release workflow predates the certificate-import change in commit
  `b35dea4`, so that change has not run in CI.
- This Mac has Apple Development and Apple Distribution identities, but no Developer ID Application
  identity. The GitHub repository has no release secrets configured.
- No clean-VM application or image was found on this Mac. Model and Intelligence credentials may be
  stored in the app's Keychain and are intentionally not inspected by this design.

## Release Artifact

Change the existing `Release build` step in `.github/workflows/mac-release.yml` to use SwiftPM's
native universal build:

```sh
swift build -c release --arch arm64 --arch x86_64
lipo -verify_arch arm64 x86_64 .build/release/XBot
```

No new build script or architecture matrix is needed. The current bundle, DMG, signing,
notarization, Sparkle, and artifact-upload steps remain the single release path.

Trigger the workflow without secrets first. The job must pass and its downloaded DMG must contain
an `x86_64 arm64` app executable. This proves the new command on GitHub's macOS 26 runner before
credentials complicate diagnosis.

## Signing, Notarization, and Updates

The account holder supplies the existing workflow's documented secrets:

- `MACOS_SIGNING_IDENTITY`
- `MACOS_CERTIFICATE_P12`
- `MACOS_CERTIFICATE_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_PASSWORD`
- `SPARKLE_EDDSA_PRIVATE_KEY`
- `XBOT_SPARKLE_PUBLIC_KEY`
- `XBOT_APPCAST_URL`
- optionally `XBOT_RELEASE_DOWNLOAD_PREFIX`

Secrets remain in GitHub Actions or the macOS Keychain; they are never added to the repository,
printed, or passed through chat. A missing or invalid secret should fail the relevant release step,
not produce an artifact that is described as signed or update-capable.

After the signed workflow run, download the artifact and verify the app and DMG independently:

```sh
codesign --verify --deep --strict --verbose=2 XBot.app
spctl -a -vvv -t execute XBot.app
xcrun stapler validate XBot.app
xcrun stapler validate xBot.dmg
lipo -verify_arch arm64 x86_64 XBot.app/Contents/MacOS/XBot
```

Acceptance requires Gatekeeper to report an accepted, notarized Developer ID build and Sparkle keys
to be present in the signed app's `Info.plist`. An unsigned fallback artifact remains useful for CI
diagnosis but cannot close Phase 1.

## Real Conversation

Use a throwaway engine and the production runtime path. Store keys through xBot's existing UI so
the test covers Keychain-to-vault synchronization rather than bypassing it with process variables.

The run must prove, in order:

1. a CopilotKit-backed conversation returns a real model response;
2. a browser tool call appears in Activity and the live screen;
3. take control, release control, and a help/secret request complete;
4. after quitting and reopening xBot, the transcript remains and contains no duplicated messages;
5. a remembered fact from an earlier turn is available in a later turn; and
6. a second agent answers through a second real model vendor, with a deliberately nonexistent model
   producing that vendor's named error rather than silently falling back.

Run `LiveEngineTests` against the same throwaway engine as supporting evidence. The manual app flow
is still required because the suite does not prove the native UI, Keychain prompts, restart, or
human handoff experience.

No credentials, prompts containing secrets, or raw engine logs are committed as evidence. Record
only timestamps, versions, vendor names, pass/fail results, and redacted failure messages.

## Clean-VM Onboarding

Use a fresh macOS 14+ VM with no xBot state, Docker, Homebrew, Xcode, or command-line developer tools.
Install only from the signed DMG produced above. The tester must not use Terminal, edit a file, or
read a log.

Record whether the user can:

1. open the app without a Gatekeeper warning;
2. understand the CopilotKit conversation-storage disclosure before entering a key;
3. install the offered container runtime from the app;
4. see honest download and startup progress;
5. connect conversation and model credentials;
6. create an agent and complete the real-conversation checks; and
7. quit and relaunch without losing onboarding or conversation state.

Record elapsed time and every point where the tester needs help. A product defect found here is
fixed and the clean-VM run is repeated from a fresh snapshot. Setup instructions are not an
acceptable substitute for a product fix when the app promises no terminal.

## Error Handling

- Universal-build or architecture verification failure stops CI before packaging.
- Signing, notarization, stapling, Gatekeeper, or Sparkle verification failure blocks the release.
- Conversation failure is classified at the failing boundary: Intelligence, model vendor, engine,
  computer, Keychain, or client persistence.
- VM failures retain redacted diagnostics and exact reproduction steps, then restart from a clean
  snapshot after the fix.
- Human-gated missing credentials are reported as prerequisites, never worked around with mock
  evidence.

## Expected Changes

- `.github/workflows/mac-release.yml`: build and assert a universal executable.
- `docs/13-launch-checklist.md`: record completed evidence and any remaining human gate after the
  checks run.
- Product or test files only when a release, conversation, or onboarding check exposes a verified
  defect. No speculative refactor is part of Phase 1.

## Completion Evidence

Phase 1 is complete only when all of the following exist:

- a passing current-revision release workflow;
- a downloaded universal signed/notarized/stapled DMG with independent verification output;
- a recorded real-conversation run covering Intelligence, computer use, handoff, persistence,
  memory, and a second vendor;
- a recorded clean-VM onboarding run from the signed DMG; and
- a clean repository with the Mac test suite and every targeted regression test passing.
