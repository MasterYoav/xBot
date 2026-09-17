# Phase 1 Ship Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove that the current xBot revision ships as a universal, signed, notarized Mac app that completes a real conversation and clean-VM onboarding.

**Architecture:** Keep the existing release path and change only its SwiftPM build command plus a native architecture assertion. Treat signing, live credentials, and the clean VM as explicit human gates; use the existing release workflow, runtime, client, and live tests for evidence instead of adding another harness.

**Tech Stack:** GitHub Actions, SwiftPM, `lipo`, Apple `codesign`/`notarytool`/`stapler`/Gatekeeper, Sparkle 2, Docker, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-17-phase-1-ship-readiness-design.md`

## Global Constraints

- The app supports macOS 14 or later on both Apple Silicon and Intel.
- The shipped artifact is one universal DMG under 40 MB.
- Developer ID signing, hardened runtime, timestamping, notarization, and stapling are required.
- Sparkle uses an HTTPS appcast and EdDSA; private keys never enter the repository or command output.
- Real credentials stay in GitHub Actions or the macOS Keychain and are never committed or pasted into chat.
- Clean-VM onboarding uses no Terminal, Homebrew, Docker, Xcode, or developer tools already installed in the guest.
- Do not add a new release script, test framework, VM framework, or abstraction.

---

### Task 1: Make the Existing Release Build Universal

**Files:**
- Modify: `.github/workflows/mac-release.yml`
- Modify: `scripts/README-packaging.md`

**Interfaces:**
- Consumes: SwiftPM product `XBot` and the existing `.build/release/XBot` compatibility path.
- Produces: a universal `x86_64 arm64` executable at `.build/release/XBot` for `scripts/bundle-mac-app.sh`.

- [ ] **Step 1: Reproduce the missing Intel slice**

Run from the repository root:

```bash
scripts/generate-app-icon.sh
(
  cd apps/mac
  swift build -c release --arch arm64
  ! lipo -verify_arch arm64 x86_64 .build/release/XBot
)
```

Expected: SwiftPM succeeds, then `lipo` reports that `x86_64` is missing. The leading `!` makes the
reproduction command succeed only when the current artifact is not universal.

- [ ] **Step 2: Change the workflow and local packaging instructions**

Replace the release build step in `.github/workflows/mac-release.yml` with:

```yaml
      - name: Release build
        working-directory: apps/mac
        run: |
          swift build -c release --arch arm64 --arch x86_64
          lipo -verify_arch arm64 x86_64 .build/release/XBot
```

Replace packaging step 2 in `scripts/README-packaging.md` with:

```sh
# 2. Universal release binary
cd apps/mac && swift build -c release --arch arm64 --arch x86_64 && cd ../..
```

- [ ] **Step 3: Verify the universal bundle and DMG locally**

Run:

```bash
scripts/generate-app-icon.sh
swift build -c release --arch arm64 --arch x86_64 --package-path apps/mac
lipo -verify_arch arm64 x86_64 apps/mac/.build/release/XBot
scripts/bundle-mac-app.sh
scripts/create-dmg.sh
lipo -verify_arch arm64 x86_64 apps/mac/XBot.app/Contents/MacOS/XBot
hdiutil verify dist/xBot.dmg
```

Expected: every command exits zero and `hdiutil` prints `checksum ... is VALID`.

- [ ] **Step 4: Run the Mac suite**

Run:

```bash
swift test --package-path apps/mac
```

Expected: 235 tests pass with no failures.

- [ ] **Step 5: Commit the universal build**

```bash
git add .github/workflows/mac-release.yml scripts/README-packaging.md
git commit -m "CI: ship one universal Mac app"
```

### Task 2: Prove the Current Unsigned Workflow on GitHub

**Files:**
- No source files.

**Interfaces:**
- Consumes: `mac-release.yml` on `master` and GitHub Actions authentication from `gh`.
- Produces: a passing workflow URL and a downloaded universal unsigned diagnostic artifact.

- [ ] **Step 1: Push the reviewed Phase 1 commits**

Run:

```bash
git status --short
git push origin master
```

Expected: the worktree is clean before the push, and `origin/master` advances to the local Phase 1 commit.

- [ ] **Step 2: Dispatch and watch the current release workflow**

Run:

```bash
phase1_sha="$(git rev-parse HEAD)"
phase1_previous_run_id="$(gh run list -R MasterYoav/xBot --workflow mac-release.yml \
  --event workflow_dispatch --commit "${phase1_sha}" --limit 1 \
  --json databaseId --jq '.[0].databaseId // empty')"
gh workflow run mac-release.yml -R MasterYoav/xBot --ref master
phase1_run_id=""
for phase1_attempt in 1 2 3 4 5 6; do
  phase1_candidate_run_id="$(gh run list -R MasterYoav/xBot --workflow mac-release.yml \
    --event workflow_dispatch --commit "${phase1_sha}" --limit 1 \
    --json databaseId --jq '.[0].databaseId // empty')"
  if [[ -n "${phase1_candidate_run_id}" && "${phase1_candidate_run_id}" != "${phase1_previous_run_id}" ]]; then
    phase1_run_id="${phase1_candidate_run_id}"
    break
  fi
  sleep 5
done
test -n "${phase1_run_id}"
gh run watch "${phase1_run_id}" -R MasterYoav/xBot --exit-status
gh run view "${phase1_run_id}" -R MasterYoav/xBot --json url,headSha,conclusion
```

Expected: the workflow concludes `success` on the exact local HEAD revision.

- [ ] **Step 3: Download and inspect the unsigned artifact**

Run in the same shell so `phase1_run_id` is retained:

```bash
phase1_artifacts="$(mktemp -d)"
gh run download "${phase1_run_id}" -R MasterYoav/xBot \
  --name xbot-release --dir "${phase1_artifacts}"
phase1_dmg="$(find "${phase1_artifacts}" -name xBot.dmg -type f -print -quit)"
test -n "${phase1_dmg}"
hdiutil verify "${phase1_dmg}"
phase1_mount="$(mktemp -d)"
hdiutil attach -nobrowse -readonly -mountpoint "${phase1_mount}" "${phase1_dmg}"
lipo -verify_arch arm64 x86_64 "${phase1_mount}/XBot.app/Contents/MacOS/XBot"
hdiutil detach "${phase1_mount}"
```

Expected: the DMG checksum is valid and the app contains both architecture slices. It remains
unsigned by design; this task proves packaging before credentials are introduced.

### Task 3: Supply the Account-Holder Prerequisites

**Files:**
- No repository files.

**Interfaces:**
- Consumes: Apple Developer membership, GitHub repository admin access, and Sparkle's existing `generate_keys` tool.
- Produces: a Developer ID Application certificate and the release-secret names consumed by `mac-release.yml`.

- [ ] **Step 1: Create and verify the correct Apple identity**

In Xcode, open **Settings → Accounts → Manage Certificates**, create **Developer ID Application**,
then run:

```bash
security find-identity -v -p codesigning | rg 'Developer ID Application'
```

Expected: exactly the intended Developer ID Application identity appears. Apple Development and
Apple Distribution identities do not satisfy this check.

- [ ] **Step 2: Export the certificate with its private key**

In Keychain Access, export the Developer ID Application certificate and its nested private key as a
password-protected `.p12`. Keep the file outside the repository. Verify the export locally:

```bash
phase1_secrets_dir="$(mktemp -d)"
phase1_p12="${phase1_secrets_dir}/certificate.p12"
printf 'Export the certificate to: %s\n' "${phase1_p12}"
test -s "${phase1_p12}"
openssl pkcs12 -in "${phase1_p12}" -info -noout
```

Expected: OpenSSL prompts for the export password and reports a certificate bag plus a shrouded key
bag. Do not commit the `.p12` or its password.

- [ ] **Step 3: Generate and export the Sparkle signing key once**

Run outside the repository for the exported private file:

```bash
apps/mac/.build/artifacts/sparkle/Sparkle/bin/generate_keys
phase1_sparkle_key="$(mktemp)"
apps/mac/.build/artifacts/sparkle/Sparkle/bin/generate_keys -x "${phase1_sparkle_key}"
test -s "${phase1_sparkle_key}"
apps/mac/.build/artifacts/sparkle/Sparkle/bin/generate_keys -p
```

Expected: Sparkle prints the public key; the private export exists only at the temporary path and is
backed up in the account holder's password manager before that file is removed.

- [ ] **Step 4: Add the existing release secrets without exposing values**

Use GitHub **Settings → Secrets and variables → Actions** to add the values named below:

```text
MACOS_SIGNING_IDENTITY
MACOS_CERTIFICATE_P12
MACOS_CERTIFICATE_PASSWORD
APPLE_ID
APPLE_TEAM_ID
APPLE_APP_PASSWORD
SPARKLE_EDDSA_PRIVATE_KEY
XBOT_SPARKLE_PUBLIC_KEY
XBOT_APPCAST_URL
XBOT_RELEASE_DOWNLOAD_PREFIX
```

`MACOS_CERTIFICATE_P12` is the base64 content of the `.p12`; the Sparkle public key is the output of
`generate_keys -p`; the private key is the exact content exported by `generate_keys -x`.

Verify names only:

```bash
gh secret list -R MasterYoav/xBot --json name --jq '.[].name' | sort
```

Expected: every required name except optional `XBOT_RELEASE_DOWNLOAD_PREFIX` appears. Values remain unreadable.

After GitHub confirms both private values were saved, remove the temporary exports:

```bash
rm "${phase1_p12}" "${phase1_sparkle_key}"
rmdir "${phase1_secrets_dir}"
```

### Task 4: Produce and Independently Verify the Signed Release

**Files:**
- No source files.

**Interfaces:**
- Consumes: the universal release workflow and all Task 3 secrets.
- Produces: a signed/notarized/stapled universal DMG and a signed Sparkle appcast.

- [ ] **Step 1: Dispatch the signed release**

Run:

```bash
phase1_signed_sha="$(git rev-parse HEAD)"
phase1_previous_signed_run_id="$(gh run list -R MasterYoav/xBot --workflow mac-release.yml \
  --event workflow_dispatch --commit "${phase1_signed_sha}" --limit 1 \
  --json databaseId --jq '.[0].databaseId // empty')"
gh workflow run mac-release.yml -R MasterYoav/xBot --ref master
phase1_signed_run_id=""
for phase1_signed_attempt in 1 2 3 4 5 6; do
  phase1_candidate_signed_run_id="$(gh run list -R MasterYoav/xBot --workflow mac-release.yml \
    --event workflow_dispatch --commit "${phase1_signed_sha}" --limit 1 \
    --json databaseId --jq '.[0].databaseId // empty')"
  if [[ -n "${phase1_candidate_signed_run_id}" && "${phase1_candidate_signed_run_id}" != "${phase1_previous_signed_run_id}" ]]; then
    phase1_signed_run_id="${phase1_candidate_signed_run_id}"
    break
  fi
  sleep 5
done
test -n "${phase1_signed_run_id}"
gh run watch "${phase1_signed_run_id}" -R MasterYoav/xBot --exit-status
gh run view "${phase1_signed_run_id}" -R MasterYoav/xBot --log \
  | rg 'Import the signing certificate|Sign, notarize|Generate Sparkle appcast|Signed, notarized and stapled'
```

Expected: certificate import, signing/notarization, and appcast generation all run rather than skip.

- [ ] **Step 2: Download and mount the signed artifact**

```bash
phase1_signed_artifacts="$(mktemp -d)"
gh run download "${phase1_signed_run_id}" -R MasterYoav/xBot \
  --name xbot-release --dir "${phase1_signed_artifacts}"
phase1_signed_dmg="$(find "${phase1_signed_artifacts}" -name xBot.dmg -type f -print -quit)"
phase1_signed_mount="$(mktemp -d)"
hdiutil verify "${phase1_signed_dmg}"
hdiutil attach -nobrowse -readonly -mountpoint "${phase1_signed_mount}" "${phase1_signed_dmg}"
phase1_signed_app="${phase1_signed_mount}/XBot.app"
```

Expected: the DMG checksum verifies and `XBot.app` is mounted read-only.

- [ ] **Step 3: Verify trust, notarization, architecture, and Sparkle metadata**

```bash
codesign --verify --deep --strict --verbose=2 "${phase1_signed_app}"
spctl -a -vvv -t execute "${phase1_signed_app}"
xcrun stapler validate "${phase1_signed_app}"
xcrun stapler validate "${phase1_signed_dmg}"
lipo -verify_arch arm64 x86_64 "${phase1_signed_app}/Contents/MacOS/XBot"
phase1_feed_url="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "${phase1_signed_app}/Contents/Info.plist")"
phase1_public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${phase1_signed_app}/Contents/Info.plist")"
[[ "${phase1_feed_url}" == https://* ]]
test -n "${phase1_public_key}"
phase1_appcast="${phase1_signed_artifacts}/releases/appcast.xml"
test -f "${phase1_appcast}"
rg -q 'sparkle:edSignature=' "${phase1_appcast}"
! rg -q 'url="http://' "${phase1_appcast}"
hdiutil detach "${phase1_signed_mount}"
```

Expected: `codesign` succeeds; Gatekeeper says `accepted` and `Notarized Developer ID`; stapler
validates both app and DMG; both architectures and non-empty Sparkle keys are present; an appcast exists.

### Task 5: Prove the Real Engine and Conversation Path

**Files:**
- Modify after evidence: `docs/13-launch-checklist.md`

**Interfaces:**
- Consumes: the existing production runtime path, CopilotKit key, Anthropic key, and a second real vendor key.
- Produces: automated live-suite output plus a manual native-app record covering persistence, memory, computer use, and handoff.

- [ ] **Step 1: Start the production runtime from the signed app**

Install the signed app in `/Applications`, open it, enter only the CopilotKit credential through
onboarding or Settings, and press **Start**. Do not add a real Anthropic key until after Step 2: the
live suite deliberately writes and revokes invalid Anthropic keys in the throwaway engine vault.
Then run:

```bash
scripts/check-engine-health.sh
scripts/verify-m5-handoff.sh
```

Expected: both scripts identify a healthy xBot engine and reachable authenticated agents API.

- [ ] **Step 2: Run the automated client against the same throwaway engine**

```bash
phase1_engine_port="$(docker port xbot-engine | awk -F: '/->/ {print $NF; exit}')"
phase1_token_file="$(mktemp)"
security find-generic-password -s dev.xbot.engine-token -a default -w > "${phase1_token_file}"
XBOT_LIVE_ENGINE_URL="http://127.0.0.1:${phase1_engine_port}" \
XBOT_LIVE_ENGINE_TOKEN_FILE="${phase1_token_file}" \
XBOT_LIVE_ENGINE_HAS_INTELLIGENCE=1 \
swift test --package-path apps/mac --filter 'LiveEngineTests|LiveComputerToolsTests'
rm "${phase1_token_file}"
```

Expected: health, REST shapes, vault round-trip, vendor rejection, browser/files/shell, help, and
control tests pass. The temporary token file is removed immediately after the suite.

- [ ] **Step 3: Complete the native conversation checklist**

Connect the real Anthropic and second-vendor keys through Settings after the live suite finishes.
Then, in the signed app:

1. Create an Anthropic-backed agent and send a message; require a streamed model response.
2. Ask it to open `https://example.com`; require `computer_navigate` in Activity and the page in Screen.
3. Take control, release it, then ask the agent to request help; require the composer ask and continuation.
4. Tell the agent `The launch word is heliotrope`; two turns later ask for the launch word; require `heliotrope`.
5. Quit and reopen xBot; require the transcript above exactly once with no duplicated messages.
6. Create an agent using the second real vendor and require a successful answer.
7. Select a deliberately nonexistent model for that vendor and require the vendor's named error, not fallback output.

Expected: all seven checks pass. Record only app version, engine version, timestamp, vendor names,
and redacted pass/fail outcomes.

- [ ] **Step 4: Record the live evidence**

Update the end-to-end conversation section in `docs/13-launch-checklist.md` with the date, workflow
revision, app/engine versions, the two vendor names, and each check's result. Do not include keys,
prompts containing secrets, bearer tokens, or raw logs.

Run and commit:

```bash
git diff --check
git add docs/13-launch-checklist.md
git commit -m "Docs: record the live conversation check"
```

### Task 6: Complete Clean-VM Onboarding

**Files:**
- Modify after evidence: `docs/13-launch-checklist.md`

**Interfaces:**
- Consumes: a fresh macOS 14+ VM snapshot and the signed DMG from Task 4.
- Produces: a dated clean-install record with timings and no unresolved onboarding defects.

- [ ] **Step 1: Prepare a genuinely clean guest**

Create or revert a macOS 14+ VM snapshot that has no xBot state, Homebrew, Docker, Xcode, or command-line
developer tools. Copy only the signed DMG into the guest. Do not open Terminal in the guest.

Expected: the guest represents a new non-developer Mac user; host tooling does not count as guest tooling.

- [ ] **Step 2: Run the clean onboarding checklist**

Using only the xBot UI:

1. Drag xBot to Applications and launch it; require no Gatekeeper warning.
2. Confirm the CopilotKit storage disclosure appears before the key field.
3. Complete all five onboarding steps and let xBot install its offered container runtime.
4. Record runtime download time, engine pull time, and time to the first usable composer.
5. Create an agent and repeat Task 5's message, browser, take/release, help, and persistence checks.
6. Force one recoverable failure by disconnecting the guest network during an engine pull; require a plain-language retry action, then reconnect and recover.
7. Copy diagnostics; require no API key, bearer token, encryption key, or credential value in the clipboard.

Expected: the tester never needs Terminal, a config file, or a log. Every failure has a sentence and
an actionable button. A failed check stops this task; diagnose it with `superpowers:systematic-debugging`,
add the smallest regression check that reproduces it, fix it, rebuild the signed DMG, and restart from
the clean snapshot.

- [ ] **Step 3: Record and commit clean-VM evidence**

Update the clean-VM section of `docs/13-launch-checklist.md` with the date, macOS version,
architecture, signed workflow revision, timings, and redacted outcomes. Then run:

```bash
git diff --check
git add docs/13-launch-checklist.md
git commit -m "Docs: record clean-VM onboarding"
```

### Task 7: Close Phase 1 Against Its Evidence

**Files:**
- Modify: `docs/12-roadmap.md`
- Modify: `docs/13-launch-checklist.md`

**Interfaces:**
- Consumes: successful artifacts and records from Tasks 2 through 6.
- Produces: an accurate Phase 1 status and a clean handoff into the website phase.

- [ ] **Step 1: Audit every Phase 1 acceptance item**

Confirm the repository contains dated evidence for:

```text
universal unsigned workflow
Developer ID signed + notarized + stapled app and DMG
Sparkle public key + HTTPS feed + signed appcast
CopilotKit conversation
computer Activity + Screen
take/release/help
restart persistence without duplicates
memory across turns
second real model vendor and named invalid-model error
clean-VM onboarding and recovery timing
redacted diagnostics
```

Expected: no item relies only on a unit test, intention, or an older revision.

- [ ] **Step 2: Update milestone status without overstating it**

Mark M2's second-vendor item, M6's clean-VM item, and the applicable M7 signing/conversation items
complete in `docs/12-roadmap.md` and `docs/13-launch-checklist.md`. Leave website and Phase 3 hardening
open because they are not part of this plan.

- [ ] **Step 3: Run final Phase 1 verification**

```bash
swift test --package-path apps/mac
git diff --check
git status --short
```

Expected: 235 tests pass, the diff is clean, and only the intended roadmap/checklist edits remain.

- [ ] **Step 4: Commit Phase 1 closure**

```bash
git add docs/12-roadmap.md docs/13-launch-checklist.md
git commit -m "Docs: close ship-readiness validation"
```
