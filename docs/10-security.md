# Security

xBot gives a language model a browser with the user's real logins in it, a filesystem, and a shell.
That is the product. It is also, stated plainly, a large amount of trust, and the security model is
what earns it.

Most of this is inherited from OpenBot, which took it seriously. The xBot-specific parts are the
Keychain, the local token, and what the app is permitted to write down.

---

## The threat model

Ordered by likelihood, not drama.

| # | Threat | Mitigation |
| --- | --- | --- |
| 1 | **The model does something the user did not intend** — clicks buy, sends an email, deletes a file | The gateway: resolve → policy → **audit** → act. Fails closed |
| 2 | **Prompt injection from a web page the agent is reading** | The gateway again. Page content is data, never instruction. Policy evaluates the *action*, not the model's stated reason for it |
| 3 | **Keys leak** — logs, crash reports, diagnostics, screenshots | Keychain, never `process.env` in request paths, tested redaction |
| 4 | **One agent reaches another's logins** | Per-agent computers and profiles (**v2**). ⚠️ Not true in v1 — see below |
| 5 | **The agent reaches the database or the host network** | Network separation in compose; the private-address floor |
| 6 | **Another process on the Mac talks to the engine** | Loopback + a bearer token in the Keychain |
| 7 | **A malicious or compromised engine image** | Pinned digests, signature verification, no `:latest` |
| 8 | **The user is socially engineered by their own agent** | Handover is explicit, secret entry is a separate channel, destructive actions confirm |

---

## Secrets

### The three the app holds

| Secret | Where | Notes |
| --- | --- | --- |
| Provider API keys | **macOS Keychain** | One item per provider. `kSecAttrAccessibleWhenUnlocked` |
| Engine bearer token | **macOS Keychain** | Generated on first run. Sent on every request |
| DB encryption key | **macOS Keychain** | The engine's `KEY_ENCRYPTION_KEY`. Generated — never upstream's example value, which is public and refused in production |

**Rules, and they are absolute:**

- **Never `UserDefaults`.** It is a plist in the user's Library, world-readable by any process
  running as them.
- **Never a file in Application Support.** Same problem, plus it survives an uninstall.
- **Never a log line.** Not at debug level, not behind a flag, not temporarily.
- **Never in an error message shown on screen.** "Anthropic rejected the key ending `…4f2a`" is
  acceptable. Echoing the key is not.
- **Never in a crash report.** Do not hold a decrypted key in a long-lived property; fetch, use,
  release.
- **Never in diagnostics.** The redaction function has a test that fails if a known-secret pattern
  survives it. **Do not rely on care.**

### Passing keys to the engine

**⚠️ The tension worth naming.** Upstream passes provider keys to the agent container as environment
variables (`ANTHROPIC_API_KEY` and friends). Environment variables leak — into `/proc`, into child
processes, into crash dumps. The container also runs a shell that a model controls.

**xBot's position:** keys live in the engine's encrypted credential vault, not the environment. The
model router fetches a key per request from the vault, and the vault is encrypted at rest with
`KEY_ENCRYPTION_KEY`, which comes from the Keychain and is passed to the engine at start.

This means one secret transits the environment instead of N. It is not perfect — the encryption key
is in the process environment — but it is a much smaller surface, and it means the keys are not
sitting in a variable a shell can read.

**Corollary, and it is a rule:** *never read a provider key from `process.env` in request-handling
code.* If you find one, that is a bug with a security label.

### Secret entry to an agent

Inherited from upstream and correct: when an agent needs a password to complete a task, entry is a
separate channel from chat content. The audit records *that* a secret was requested and its
**character count** — never its value. The value never enters the transcript, so it never enters the
model's context on the next turn.

The UI for this is a card, not a message bubble. See [09-ui-spec.md](09-ui-spec.md).

---

## Isolation

### v1 — one shared computer

⚠️ **Be honest about this in the product, not just in the docs.**

The v1 single-container shape has no supervisor, which means no Docker socket, which means **all
agents share one Chromium profile and one workspace.** Agent A can read the cookies agent B used to
log into your bank.

**This is stated in the UI**, in Settings → Computer, in plain words:

> In this version, all your agents share one browser. An agent can see sites another agent has
> signed into. Give agents separate logins for anything sensitive.

Shipping this quietly would be the worst decision available. Shipping it with a sentence is
acceptable for an early version. Not shipping the sentence is not.

### v2 — one computer per agent

The upstream topology, and the fix. Each agent gets a container with its own workspace volume and
its own browser profile. The supervisor holds the Docker socket — which is root-equivalent on the
host — and exposes only four verbs: ensure, stop, reset, list.

Additionally:

- **gVisor** (`COMPUTER_RUNTIME=runsc`) where the host supports it. A shared kernel is not an
  isolation story for code a model wrote.
- **`--security-opt no-new-privileges`**, which turns setuid off for everything not explicitly
  permitted.
- **Root inside the container is a floor, not a boundary.** Upstream permits passwordless `sudo` for
  the package managers only — `apt-get`, `apt`, `dpkg`, `apt-key`, `apt-cache` — because "install a
  tool then use it" is the point of giving an agent a shell, while `sudo cat /proc/1/environ` is not.
  Keep that list exactly as narrow as it is.

### Network

In the compose topology, PostgreSQL is on a **separate network** from the agents' computers, because
an agent has a shell and a shell reaches whatever its container reaches. Only the migration service
reaches the database by name.

⚠️ **In the v1 single-container shape this separation does not exist** — the database is a sibling
process on the same loopback. Combined with the shared-computer issue above, this is the second
reason v1 is a stepping stone and not a destination. It is one more line in the same honest
paragraph.

### The private-address floor

`AGENT_COMPUTER_ALLOW_PRIVATE_HOSTS` removes the whole private-address floor — both where an agent
may browse and which endpoint an agent may be registered against. With it on, an agent could reach
link-local addresses, including cloud metadata endpoints. Upstream refuses to start with it set under
`NODE_ENV=production`.

**xBot: off by default.** Exposed in Advanced, with a description of what it actually allows, and
**never enabled to fix an unrelated problem.** If something needs it, that is a design question, not
a settings change.

---

## The engine boundary

The engine runs in single-user mode (`OPENBOT_SINGLE_USER=true`), which upstream warns about
plainly: *"while it is set, every visitor is an administrator."*

On a laptop with loopback-only ports, a "visitor" is another process on the same Mac running as the
same user. That is a smaller threat than a network one, but it is not nothing — a malicious npm
postinstall script could reach `127.0.0.1:3001`.

**So: loopback plus a bearer token.** Generated on first run, held in the Keychain, required on every
request. The app has it. Nothing else on the machine does.

Sign-in stays in the codebase and unreachable, so upstream merges stay clean.

---

## The audit trail

The product's central trust claim, and the reason a user should be willing to run this at all.

**Properties, inherited, and none of them are to be relaxed:**

- **Append-only.** Nothing in the product deletes a row. Retention is the only thing that shrinks it,
  and it defaults to keeping everything.
- **Written before the action, not after.** An action that crashes the computer is still recorded.
- **A second row on failure**, so a forwarded action that then failed is distinguishable from one
  that succeeded.
- **Control handovers are audited** as first-class events: `computer.help_requested`,
  `computer.control_taken`, `computer.control_released`.
- **Secret requests are audited by count, not value.**
- **File writes contribute path and size, never contents.**

**xBot adds:** a native audit viewer before v1.0, because meeting a webview at the moment you want to
know what your agent did is exactly the wrong seam. See [ADR-0004](decisions/0004-native-vs-webview.md).

---

## Images

- **Pinned by digest**, never `:latest`. A tag that moves under you is not a supply chain.
- **Signature verified** before the first run of a new digest.
- **The manifest is served over HTTPS with certificate pinning**, and it lists digest, size, minimum
  app version, and migration compatibility.
- **The previous image is retained** until the new one has been healthy for a full session, so
  rollback is real.

---

## App hardening

- **Hardened runtime**, notarized, Developer ID. See [11](11-packaging-and-updates.md).
- **Unsandboxed**, because driving a container runtime requires it. Stated plainly on the download
  page rather than hidden — a security-conscious user will check and should find an explanation, not
  a surprise.
- **No entitlements beyond what is used.** Network client, and the Keychain access group.
- **Library validation on.** No unsigned code injection.
- **Sparkle configured with EdDSA signature verification** and an HTTPS appcast. An update channel
  is a code-execution channel.

---

## Telemetry

**Off by default. Opt-in. Asked for after onboarding, separately, so it is a real choice rather than
something clicked past to get in.**

If enabled: app version, macOS version, crash reports, feature-use counts, aggregate error classes.

**Never, under any setting:** conversation content, agent names, prompts, model responses, page
contents, URLs visited, file names or contents, API keys, audit rows.

**The privacy claim is the product.** A telemetry pipeline that could ever carry a prompt is not a
bug we would fix later; it is a breach of the thing that makes xBot worth choosing.

---

## What we tell the user

In Settings → Privacy, in plain language, without hedging:

> **What stays on your Mac**
> Your conversations, your agents, their files, and their browser logins. All of it is in a database
> on this computer. We have no server that could hold it.
>
> **What leaves your Mac**
> Only the calls your agents make: to the model provider you connected, and to the websites you ask
> them to visit. If you use Ollama, nothing leaves at all.
>
> **Your API keys**
> Stored in your Mac's Keychain, encrypted, and sent only to the provider they belong to.

Three paragraphs, true, and checkable. If any of it stops being true, that is a release blocker.
