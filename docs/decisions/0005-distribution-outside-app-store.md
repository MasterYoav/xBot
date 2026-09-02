# ADR-0005 — Developer ID and a DMG, not the Mac App Store

**Status:** Accepted
**Date:** 2026-09
**Related:** [11-packaging-and-updates.md](../11-packaging-and-updates.md), [10-security.md](../10-security.md)

---

## Context

Two ways to ship a Mac app.

**Mac App Store.** Discovery, a trusted install, automatic updates, and Apple's payment
infrastructure. Requires the App Sandbox, review, and compliance with the App Store Review
Guidelines.

**Developer ID.** Signed, notarized, distributed as a DMG from a website. No sandbox requirement, no
review, and updates are the developer's problem.

## The constraint

**A sandboxed app cannot manage a container runtime.**

xBot must:

- Launch and terminate external applications (Docker Desktop, Colima)
- Talk to a Unix domain socket owned by another process (`/var/run/docker.sock`)
- Execute CLI binaries and read their output
- Install software into its own Application Support directory and run it
- Manage container volumes on the host filesystem

The App Sandbox prohibits all of these. There is no entitlement for "drive a container runtime," and
there is not going to be one.

Separately, several App Store Review Guidelines are difficult to satisfy:

- **2.5.2** — an app must be self-contained and may not download or install executable code. Pulling
  a container image is exactly that.
- **2.5.1** — public APIs only, used as intended.
- **3.1.1** — in-app purchase requirements, if we ever charged, complicated by the user bringing
  their own API keys.

## Decision

**Developer ID, hardened runtime, notarized, stapled, distributed as a DMG from our own site.**

- **Not sandboxed.** Documented publicly, with the reason.
- **Hardened runtime on**, library validation on, JIT off.
- **Notarized and stapled** on every build, including betas.
- **Sparkle 2 with EdDSA signature verification** for updates.

### The public explanation

On the download page, in plain words:

> **xBot isn't sandboxed, and here's why.**
>
> xBot runs your agents in containers on your Mac. Managing containers means starting and stopping
> other software, which Apple's sandbox doesn't allow — so xBot can't be a sandboxed app or be sold
> on the Mac App Store.
>
> It is signed with an Apple Developer ID and notarized by Apple, which means Apple has checked it
> for malicious content and macOS verifies it every time it opens.

A security-conscious user **will** check the entitlements. They should find an explanation, not a
surprise.

## Consequences

### Good

- The product is possible. This is not a preference; it is the only path.
- No review process gating releases, which matters for security fixes.
- No 15–30% commission if we ever charge.
- We control the update channel, cadence, and beta programme.
- We can ship a beta channel and an uninstaller, neither of which the App Store permits.

### Bad

- **No App Store discovery.** Distribution is entirely our problem — website, word of mouth,
  wherever the audience is.
- **We own updates.** Sparkle is mature and standard, but the appcast and the signing key are now
  our security-critical infrastructure.
- **A trust hurdle for non-technical users.** "Downloaded from the internet" is scarier than "from
  the App Store," even though notarization means Apple has scanned it.
- **We own uninstall.** No App Store uninstall path, so a complete uninstaller is a product
  requirement, not a nicety.
- **The trust asymmetry is real.** We are asking a user to download an unsandboxed app from a website
  and give it a browser with their real logins. Notarization and a clear explanation are the minimum;
  an open-source repository the user can read is a large part of the rest.

### What we do to close the gap

- **Notarize and staple every build.** An unstapled app fails to open when the machine is offline at
  first launch, which produces support mail from people who cannot describe the problem.
- **Verify Gatekeeper on a clean machine, every release.** `spctl --assess` and `stapler validate`
  must both pass on a Mac that has never seen the app.
- **Publish checksums** alongside the DMG.
- **Keep the source open.** For an app with these permissions, "you can read what it does" is worth
  more than any badge.

## Not revisited unless

Apple ships an entitlement that permits container-runtime management from a sandboxed app, or the
product stops needing to manage one — which would mean Apple's Containerization framework being
usable from within the sandbox.

Neither is likely soon. This ADR is not on a review schedule.

## Verification

On a Mac that has never seen the app:

```sh
spctl --assess --type execute --verbose /Applications/xBot.app   # accepted
xcrun stapler validate /Applications/xBot.app                    # validated
codesign --verify --deep --strict --verbose=2 /Applications/xBot.app
```

All three pass, offline, before any release is published.
