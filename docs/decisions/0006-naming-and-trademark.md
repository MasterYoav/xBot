# ADR-0006 — Open questions about the name and the visual reference

**Status:** ⚠️ **Open — not decided**
**Date:** 2026-09
**Owner:** needs one before v1.0

---

## Why this exists

Every other ADR here records a decision. This one records a decision that has **not** been made, so
that it does not get made accidentally in a commit message.

Two related questions:

1. **The name "xBot."**
2. **How closely the interface follows Grok Bot.**

Neither blocks development. Both block a public v1.0 release.

**This document is not legal advice.** It is an engineering note about where the risk sits and what
to ask a lawyer. Get an actual trademark opinion before launch.

---

## The name

"xBot" sits close to marks associated with X Corp. and xAI: **X**, **xAI**, **Grok**, and product
naming in the form *[X thing] Bot*. Yoav's own reference product is called **Grok Bot** and lives at
`x.ai/bot`.

The concern is not copying — the name is different — but **likelihood of confusion**, which is the
test most trademark disputes turn on. It is made worse, not better, by the fact that xBot ships a
Grok integration and takes visual cues from Grok Bot. A name that would be fine in isolation gets
harder to defend when the product beside it looks familiar.

Practical exposures, in rough order of likelihood:

- **App name and bundle identifier.** `com.xbot.app` and a shipped `.app` named xBot.
- **Domain.** Any `xbot.*` registration.
- **The icon**, if it uses an X-like glyph.
- **Marketing copy** that positions the product relative to Grok Bot.

### What to do

**Before v1.0:**

1. **Get a trademark search** in the jurisdictions that matter — at minimum US and EU, plus Israel if
   that is where the entity sits.
2. **Have a fallback name ready.** Renaming after launch costs the domain, the bundle identifier
   (which cannot change without breaking updates), the signing identity, and whatever recognition
   exists.
3. **Do not build the icon around an X glyph** until this is settled. The icon is expensive to
   redo well.

**Immediately, and cheaply:**

- Use `XBOT_BUNDLE_ID` and a product-name constant everywhere rather than hardcoding the string.
  Renaming should be a build-configuration change, not a find-and-replace across a Swift package.
- Keep the code-level module names (`XBotUI`, `XBotCore`) — those are internal and cheap to change.

### Names worth considering if it moves

The requirements: pronounceable, available as a domain, not adjacent to any AI vendor's marks, and
not describing a single model — because the whole point is that it is model-agnostic.

A name that ties the product to one vendor's ecosystem is actively wrong for a product whose pitch is
"every AI." That is a product argument for renaming, independent of the legal one, and it is
probably the stronger of the two.

---

## The visual reference

The screenshots are a reference for **an interaction model**, and interaction models are not
protected. What can be protected is **trade dress** — a distinctive overall look that identifies a
source.

### What we take, without concern

These are conventions, most of them older than either product:

- A vertical rail of avatars for switching conversations — Slack, Discord, Messages
- Chat bubbles, incoming left and light, outgoing right and dark — every messaging app on the machine
- A right-hand panel for details
- A command palette with `⌘K` and `⌘1`–`⌘9`
- A composer with an attach button and a mic
- A floating status pill
- Settings grouped as Account / Appearance / System

Copying these is what **familiarity** means as a design principle: build on what people already know,
be consistent, let people predict what happens next. An app that invented its own chat layout would
be worse.

### Where the line is

Do not ship:

- **The Grok Bot avatar shapes.** The rounded-blob-with-two-eyes set in the picker screenshot is
  distinctive and is theirs. **xBot needs its own avatar shape family.** This is a real design task,
  not a copy-with-modifications task.
- **The Grok wordmark, logo, or icon**, anywhere except a small provider logo in the Models settings
  screen identifying xAI as a provider — which is nominative use and is normal.
- **Copy lifted verbatim** from their marketing or interface. Similar copy for similar functions is
  unavoidable and fine; identical sentences are not.
- **Anything implying endorsement or affiliation** with xAI or X Corp.

### The specific one to watch

The avatar picker in the reference is genuinely distinctive — the shape family is a design asset
someone made. Recreating it closely is the most identifiable copying in the whole interface and the
easiest to spot in a screenshot.

**Design a different shape family.** It is one designer-day and it removes the clearest exposure.

---

## The OpenBot attribution

Separate from the above, and settled: **MIT, and we comply.**

- `engine/LICENSE` stays, with the CopilotKit copyright line intact.
- `NOTICE` at the repo root credits OpenBot and CopilotKit.
- The About window credits OpenBot with a link. **A requirement, not a courtesy.**
- The website says xBot is built on OpenBot.

**Beyond the licence:** upstream built something good and gave it away. Crediting them prominently is
correct on the merits, and it also makes the project easier to talk about — "a native Mac app built
on OpenBot" is a clearer pitch than pretending the engine appeared from nowhere.

Do not imply that CopilotKit endorses or is affiliated with xBot. They do not and are not.

---

## Decision

**Deferred.** Development proceeds under the working name "xBot" with:

1. The product name held in **one constant**, not scattered through the code.
2. **No X-derived glyph in the icon** until the name is settled.
3. **An original avatar shape family** designed before any avatar work ships.
4. **A trademark search commissioned before v1.0.**

**This ADR must be closed — decided either way and its status updated — before the first public
release.** Nobody resolves it in a commit message.
