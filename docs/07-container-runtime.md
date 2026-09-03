# Container runtime

How the app runs containers on someone's Mac without them ever knowing containers exist.

## The problem

macOS cannot run Linux containers natively. Every option is a Linux VM with a management layer on
top, and each option has a different cost. The decision is recorded in
[ADR-0003](decisions/0003-container-runtime.md); this document is the mechanics.

The short version:

| Runtime | Install cost | Licence | Fit |
| --- | --- | --- | --- |
| **Docker Desktop** | ~4 GB, GUI installer | **Paid above a company-size threshold** | Ubiquitous. Most users already have it |
| **Colima** | Small, CLI-installed | Apache 2.0 | Free. Headless. No GUI to confuse anyone |
| **OrbStack** | Moderate | Commercial for business use | Fastest, nicest — same licensing shape as Docker |
| **Apple Containerization** | Built into recent macOS | Apple's | Apple silicon only. Young. **The right long-term answer** |
| **Podman Desktop** | Moderate | Apache 2.0 | Free. Rootless. Compose support is less mature |

**⚠️ Verify current status before implementing.** Apple's `container` / `containerization` project
moves quickly and its Compose story, networking model, and macOS version floor may have changed since
this was written. Check before committing the driver.

## The abstraction

The app never calls `docker` directly from view code. It goes through a driver protocol, so adding a
runtime is a new conformance rather than a rewrite.

```swift
public protocol ContainerDriver: Sendable {
    var identifier: RuntimeIdentifier { get }

    func probe() async -> ProbeResult
    func ensureDaemonRunning() async throws

    func pullImage(_ ref: ImageReference,
                   progress: @Sendable (PullProgress) -> Void) async throws
    func imageExists(_ ref: ImageReference) async -> Bool

    func createVolume(_ name: String) async throws
    func volumeExists(_ name: String) async -> Bool

    func run(_ spec: ContainerSpec) async throws -> ContainerHandle
    func stop(_ handle: ContainerHandle, timeout: Duration) async throws
    func remove(_ handle: ContainerHandle) async throws
    func inspect(_ handle: ContainerHandle) async throws -> ContainerStatus
    func logs(_ handle: ContainerHandle, tail: Int) async throws -> [LogLine]

    /// An address inside the container that reaches a service on the host.
    /// Docker: host.docker.internal. Others differ.
    func hostGatewayAddress() async throws -> String
}
```

Implementations: `DockerDriver` (CLI against Docker or Colima's socket), `ColimaInstaller`
(downloads Colima + Docker CLI into Application Support when the user chooses **Install for me**),
`FakeDriver` for tests, and `RuntimeLauncher` for picking the preferred `docker` executable path.

**Not implemented:** separate `ColimaDriver` or `AppleContainerDriver` types. Colima is reached
through the same `DockerDriver` once its daemon is running.

### What exists today

`RuntimeController` drives the full state machine. `DockerDriver` handles probe, pull, run, stop,
adopt-or-create for `xbot-engine`, and log tailing. Onboarding can install Colima via
`ColimaInstaller`, persist the user's runtime choice, and surface failures with copyable diagnostics
(`DiagnosticsClipboard` with redaction tests). Environment for the container is composed in
`EngineEnvironment` — see [`env-mapping.md`](env-mapping.md).

**`hostGatewayAddress()` is load-bearing** and easy to overlook. Two things inside the container need
to reach the host: the agent's tool-call callback (upstream already uses `host.docker.internal`) and
**the user's local Ollama**. Getting this wrong means Ollama silently does not work — the worst
failure mode, because it looks like a model problem.

## The state machine

Explicit, exhaustive, and every state has a UI representation. Nothing is "probably fine."

```
                     ┌──────────────┐
                     │ notDetected  │───── install ────┐
                     └──────────────┘                  │
                            ▲                          ▼
     probe ─────────────────┼──────────────────► ┌──────────┐
                            │                    │ stopped  │
                            │                    └──────────┘
                            │                          │ start
                            │                          ▼
                            │                    ┌──────────┐
                            │                    │ pulling  │──┐ progress
                            │                    └──────────┘◄─┘
                            │                          │
                            │                          ▼
                            │              ┌───────────────────────┐
                            │              │ starting              │
                            │              │  · volumes            │
                            │              │  · ports              │
                            │              │  · container          │
                            │              │  · migrations         │
                            │              │  · health             │
                            │              └───────────────────────┘
                            │                    │            │
                            │              healthy        failed
                            │                    ▼            ▼
                            │              ┌──────────┐  ┌──────────┐
                            └── daemon ────│ running  │  │  failed  │
                                gone       └──────────┘  └──────────┘
                                                 │  ▲
                                        health   │  │ recovers
                                        lost     ▼  │
                                            ┌──────────┐
                                            │ degraded │
                                            └──────────┘
```

**`degraded` matters.** The engine answering slowly, or the computer being down while the API is up,
is a real and common state. It is not `running` and it is not `failed`. The UI shows the
`Reconnecting` pill — exactly the one in the Grok Bot screenshots — and keeps the loaded conversation
readable.

## Starting the engine

### 1. Negotiate ports

**Never assume a port is free.** Yoav's own screenshots show what happens: a Homebrew Postgres
already on 5432, the engine connecting to the wrong database, and `role "openbot" does not exist`.

```swift
func allocatePort(preferred: UInt16, range: ClosedRange<UInt16>) throws -> UInt16
```

Bind-test each candidate on `127.0.0.1`. Take the first that binds. **Persist the choice** — a port
that moves between launches breaks bookmarks, the CLI, and the admin webview.

In the v1 single-container shape only one port is published, which makes this nearly trivial. It
becomes real in v2.

### 2. Ensure volumes

| Volume | Contents | Destroyed by |
| --- | --- | --- |
| `xbot-data` | PostgreSQL. Conversations, agents, **audit trail** | Reset only |
| `xbot-workspace` | Agent files | Reset, or per-agent reset |
| `xbot-profiles` | Chromium profiles — the agents' logins | Reset, or per-agent reset |

**Exactly one code path removes `xbot-data`**, it is behind a two-step confirmation in Advanced, and
it names what is lost. Update, restart, and repair never touch it.

### 3. Compose the environment

The app renders settings into an environment block. The user never sees this.

```swift
struct EngineEnvironment {
    static func compose(settings: Settings,
                        secrets: SecretStore,
                        ports: PortAllocation,
                        hostGateway: String) -> [String: String]
}
```

Key mappings from upstream's `.env` surface:

| Upstream setting | xBot source |
| --- | --- |
| `DATABASE_URL` | **Not passed from the app.** Embedded Postgres generates a password on first boot and writes the URL into the container's own environment |
| `EMBEDDED_POSTGRES` | `on` in v1 |
| `XBOT_ENGINE_TOKEN` | Generated on first run → **Keychain**. Required on every request except `/health` |
| `KEY_ENCRYPTION_KEY` | Generated on first run → **Keychain**. Upstream's example key is public and refused in production; we generate |
| `PORT` / `SERVER_PORT` | Negotiated. Both set to the same value — upstream refuses to start if they disagree |
| `OPENBOT_SINGLE_USER` | `true`. Plus our bearer token — see [10-security.md](10-security.md) |
| `TRUSTED_ORIGINS` | The app's origin |
| `INTELLIGENCE_*`, `COPILOTKIT_LICENSE_TOKEN` | **Not set.** Replaced by the local history provider (ADR-0001) |
| `BOT_PROVIDER`, `*_API_KEY` | **Not set.** Replaced by the model router (ADR-0002) |
| `OPENBOT_TOOL_URL` | Built from `hostGatewayAddress()` |
| `AGENT_COMPUTER_ALLOW_PRIVATE_HOSTS` | **Not set by default.** See below |
| `COMPUTER_MAX_BROWSERS` | From detected RAM. 8 GB → 1, 16 GB → 2, 32 GB+ → 4 |
| `AUDIT_RETENTION_DAYS` | Unset (keep everything). Configurable in Advanced |

**⚠️ `AGENT_COMPUTER_ALLOW_PRIVATE_HOSTS` deserves care.** Upstream documents it as laptop-only, and
turning it on removes the whole private-address floor — an agent could then reach link-local
addresses, including cloud metadata endpoints. It is also the switch a user might want in order to
let an agent browse a service on their own machine. **Default off. Exposed in Advanced with a plain
description of what it allows, never on by default, never enabled to fix an unrelated problem.**

### 4. Run

`docker run` with: loopback port publishing only, the three volumes, the environment block, a
restart policy, `--security-opt no-new-privileges` where supported, and memory limits derived from
host RAM.

### 5. Migrate and wait for health

Migrations run inside the container on start. The app polls `GET /health` until it **answers as
xBot** — parsing the response body, not accepting any 200. Timeout 120 s on first run (migrations),
30 s after.

## Updating

Two things update independently:

**The app** — Sparkle, standard macOS. See [11-packaging-and-updates.md](11-packaging-and-updates.md).

**The engine image** — the app checks a manifest, and an update is:

1. Pull the new image (background, resumable, never blocking use of the running one)
2. Prompt at a natural moment — not mid-conversation
3. Stop the old container
4. Start the new one **against the same volumes**
5. Migrations run
6. Health check
7. **On failure: roll back to the previous image tag, same volumes, and report it**

**Keep the previous image until the new one has been healthy for a full session.** Disk is cheaper
than an unbootable engine.

**⚠️ Migrations are the rollback hazard.** A forward migration that the old image cannot read makes
step 7 impossible. Either migrations stay backward-compatible for one version, or a pre-migration
database dump is taken to a file the app can restore. **Decide before the first schema change ships
to a user** — after that, it is too late.

## Resources

Containers on a laptop are a battery and memory question, and being casual about it is how an app
gets uninstalled.

**Memory.** Postgres plus the engine plus one Chromium is roughly 1.5–2.5 GB. Each additional
computer in v2 adds a few hundred MB. `COMPUTER_MAX_BROWSERS` and `COMPUTER_BROWSER_IDLE_MS` exist
upstream for exactly this — set them from detected RAM. An idle browser costs only a relaunch,
because the profile is on a volume.

**Idle.** The engine idles cheaply, but the VM does not. **The app stops the engine after a
configurable idle period, default 30 minutes**, and starts it on demand when the user sends a
message. Starting a stopped container is seconds, not the first-run minutes.

**On battery.** Longer idle timeout, slower screen polling, no background image pulls. Visible in
Settings, on by default.

**Surfaced honestly.** Settings → Advanced shows current memory and disk use with a link to per-agent
resets. A user who thinks the app is heavy should be able to see whether it is.

## Diagnostics

The user never reads a log. **Copy diagnostics** exists so they can send one.

Included: app and engine versions, runtime and version, host arch and macOS, allocated ports, state
machine history, container status, last 200 engine log lines, last 50 runtime driver commands and
exit codes.

**Never included:** API keys, the engine token, the encryption key, conversation content, page
contents, screenshots, file contents, or anything from the audit trail beyond row counts.

The redaction is a tested function with a test that fails if a known-secret pattern survives it. Do
not rely on care.
