# ADR-0004 — Native SwiftUI for the product surface, embedded web for admin

**Status:** Accepted
**Date:** 2026-09
**Related:** [05-mac-app.md](../05-mac-app.md), [09-ui-spec.md](../09-ui-spec.md)

---

## Context

OpenBot ships a complete React/Vite application with roughly thirty routes. Broadly two groups:

**Product surface** — conversation, agents, channels, routines, skills, settings, onboarding.

**Admin surface** — audit, boundaries, computers, credentials, identity providers, people,
playground, plugins (with per-tool detail pages), components gallery, connected accounts.

The admin group is more than half the routes and is dense, operational, and rarely opened by a
consumer. It is also already built, already correct, and maintained upstream.

The brief is a native SwiftUI app. The obvious question is where "native" ends.

## Options considered

### A. Wrap the whole React app in a WKWebView

Ship a browser window with a Mac icon.

**Rejected.** It is not a Mac app. It would not get springs, materials, VoiceOver, Dynamic Type, the
menu bar, keyboard shortcuts, or window restoration without fighting for each one. It also throws
away the entire reason for the project — the reference experience is native-feeling, and a web
wrapper is the one thing guaranteed not to feel that way.

### B. Rewrite everything in SwiftUI, including admin

Full native, no web anywhere.

**Rejected for v1.** The admin surface is roughly 15 dense screens — a CEL policy editor with a
dry-run tool, an audit browser with filtering, an MCP plugin manager with per-tool configuration, a
component gallery. Each is weeks. They are opened by a small fraction of users, rarely. Building them
before shipping delays the product by months for almost no user-facing gain, and they would then have
to be re-built every time upstream changes the underlying model.

### C. Native product surface, embedded web for admin ✅

## Decision

**Option C.**

**Native SwiftUI:** the rail, the conversation, the composer, the panel (screen, activity, routines,
agent settings), onboarding, and Settings (General, Models, Agents, Computer, Advanced, Updates).

**Embedded `WKWebView`:** audit, boundaries, computers, credentials, identity providers, people,
playground, plugins, components gallery.

Admin opens in a **dedicated window** from Settings → Advanced, not inside the main window. The seam
is at a window boundary, which is the least jarring place to put one.

The engine's single-container image already serves the built web assets on the same origin as the
API, so this costs nothing at runtime.

### The exception

**The audit trail gets a native view before v1.0.**

It is the product's central trust claim. A user who wants to know what their agent did with their
browser should not meet a different-feeling interface at exactly that moment. It is also the screen a
worried user opens, which makes it the worst possible place for a seam.

## Consequences

### Good

- Ships months earlier.
- Every screen a normal user touches is native, with correct motion, materials, and accessibility.
- The admin surface stays maintained by upstream. When OpenBot adds a policy field, our admin screen
  gets it for free.
- The engineering effort goes where users actually spend their time.

### Bad

- **A visible seam.** The admin window looks and feels different. We do not disguise this — it is
  labelled advanced and it looks it. Pretending a dense operational tool is part of the chat app
  would be worse than the honest seam.
- **Two design languages in one product.** Accepted for admin. Not accepted anywhere a normal user
  goes.
- **The webview needs the engine's auth.** The bearer token must reach it — via a
  `WKUserContentController` script or a cookie set on the loopback origin — without ever being
  visible to page content. This is a small piece of security-sensitive plumbing that needs care.
- **⚠️ The webview inherits upstream's UI conventions**, which will drift from ours. Acceptable
  inside an advanced window; a reason not to widen the boundary.

### The line, stated so it does not move

**A screen a normal user reaches during normal use is native. Always.**

If a webview screen turns out to be something normal users reach — because a feature made it common —
that screen gets rewritten natively. The boundary is defined by user behaviour, not by which
component already exists.

## Sandboxing the generative-UI case

Separately: upstream's generative UI feature lets an agent return markup, styles, and a script it
wrote for one answer, rendered in a sandboxed iframe.

In xBot this is also a `WKWebView`, and the isolation requirements are strict and non-negotiable: no
same-origin access to the engine, no session, no route into the user's data, and a JavaScript bridge
that is absent rather than restricted. This is **model-authored code rendered on a user's screen**,
which is a different and higher bar than the admin webview.

Off by default, matching upstream, which deliberately makes it a choice rather than something
acquired by upgrading.

## Verification

- Every screen in [09-ui-spec.md](../09-ui-spec.md) is native.
- The admin window authenticates without the token being reachable from page JavaScript.
- The generative-UI webview cannot reach the engine origin — tested, not assumed.
- A native audit viewer exists before v1.0 ships.
