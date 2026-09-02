# ADR-0003 — Which container runtime the app drives

**Status:** Accepted, with a scheduled review
**Date:** 2026-09
**Related:** [07-container-runtime.md](../07-container-runtime.md), [06-onboarding.md](../06-onboarding.md)

---

## Context

macOS cannot run Linux containers natively. Every option is a Linux VM with a management layer, and
the choice affects the hardest screen in the product — the one in onboarding where we have to tell a
non-technical user they need another piece of software.

The constraints:

- **We cannot bundle Docker Desktop.** Its licence does not permit redistribution, and it requires a
  paid subscription for organisations above a size and revenue threshold. Shipping a consumer app
  that silently puts a company in breach of a licence is not acceptable.
- **Most developers already have Docker Desktop.** For that audience, requiring anything else is
  friction for no gain.
- **A non-technical user has nothing**, and installing a 4 GB developer tool is the moment they are
  most likely to quit.
- **Whatever we choose must be scriptable without a terminal appearing.**

## The options

| Runtime | Licence | Install | Notes |
| --- | --- | --- | --- |
| **Docker Desktop** | Paid above a threshold | ~4 GB, GUI | Ubiquitous. Best compatibility. Cannot bundle |
| **Colima** | Apache 2.0 | Small, CLI | Free, headless, no GUI to confuse. Needs the Docker CLI, usually via Homebrew |
| **OrbStack** | Commercial for business | Moderate | Fastest and nicest. Same licensing shape as Docker |
| **Podman Desktop** | Apache 2.0 | Moderate | Free, rootless. Compose support less mature |
| **Apple Containerization** | Apple | Built in | Apple silicon only. Young. **The right long-term answer** |

⚠️ **Apple's `container` / `containerization` project moves quickly.** Its Compose story, networking
model, and macOS floor may have changed since this was written. **Verify current status before
implementing the driver.**

## Decision

**Drive whatever is there, through an abstraction. Prefer, in order.**

### 1. The abstraction is not optional

All runtime interaction goes through `ContainerDriver`
([07-container-runtime.md](../07-container-runtime.md)). Adding a runtime is a new conformance, not a
rewrite. This is the actual decision — everything below is a preference ordering that we expect to
change.

### 2. Detection order, if something is already installed

```
Docker Desktop → OrbStack → Colima → Podman → Apple container
```

**If any of these is present and working, use it and say nothing.** A developer who already has
Docker running should never be asked to install anything, and should never be told which runtime we
picked.

### 3. What we install when nothing is present

**Colima + the Docker CLI**, installed by the app into its own Application Support directory,
without touching Homebrew and without a terminal window appearing.

**Why Colima:**

- **Apache 2.0.** No licensing question for any user, ever.
- **Headless.** No second app icon, no second menu bar item, no tray notifications, no update
  prompts from software the user did not knowingly install. Compared with Docker Desktop, this is the
  difference between "xBot needed something" and "xBot installed a developer tool on my Mac."
- **Small.** A fraction of Docker Desktop's footprint.
- **Docker-API compatible**, so `DockerDriver` works against it with only lifecycle differences.

**Why not Docker Desktop as the installed default:** we cannot redistribute it, so "install for me"
would mean driving their GUI installer — fragile, and it puts a licensing obligation on the user we
did not ask them about.

**Why not OrbStack:** technically the best of the three and the same licensing shape as Docker. It
remains the manual-path recommendation for users who want it.

### 4. The manual path always exists

"I'll install Docker Desktop myself" opens docker.com and leaves onboarding on a live check that
flips green the moment Docker appears. **The user does not come back and press Recheck.** We poll.

### 5. Apple Containerization is the scheduled review

It removes the install screen entirely on Apple silicon, which is the single largest improvement
available to onboarding. `AppleContainerDriver` is written as soon as it is credible.

**Review trigger:** whichever comes first — the framework reaching a stable release with the
networking and volume behaviour we need, or six months from the v1.0 ship date.

## Consequences

### Good

- Developers with an existing runtime see nothing. The best possible outcome for that audience.
- Non-technical users get a small, free, invisible runtime rather than a large developer tool.
- No user is ever put in breach of a licence by installing our app.
- The abstraction means the Apple migration is one new file, not a rewrite.

### Bad

- **Three drivers to test.** Docker, Colima, and later Apple. Each has its own lifecycle quirks, and
  Colima in particular has to be started before the Docker CLI works.
- **We own an installer.** Downloading and installing Colima and the Docker CLI correctly, with
  progress, resume, and failure handling, is a real piece of work in `XBotRuntime`.
- **⚠️ Colima on Intel Macs is slower**, and Intel Macs are where the resource cost already hurts
  most. Detect and warn.
- **`hostGatewayAddress()` differs by runtime**, and getting it wrong means the user's local Ollama
  silently does not work — a failure that looks like a model problem, not a networking one. This is
  the driver method most worth testing.

### The screen we cannot eliminate

Whatever we choose, a non-technical user with nothing installed sees one screen that says "xBot needs
another piece of software." That screen is the highest-risk moment in the product. This decision
minimises what it asks for; it does not remove it.

Only Apple Containerization removes it, which is why the review is scheduled rather than optional.

## Verification

Onboarding completes successfully, with no terminal window appearing, on all of:

- A Mac with Docker Desktop already running
- A Mac with Docker Desktop installed but stopped
- A Mac with OrbStack
- A clean Mac with nothing (installs Colima)
- A clean Mac where the user chooses the manual Docker path
- ⚠️ An Intel Mac, with the resource warning shown
