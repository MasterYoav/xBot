# Architecture

## The shape

```
┌──────────────────────────────────────────────────────────────────┐
│  xBot.app  (SwiftUI, Developer ID signed, unsandboxed)           │
│                                                                  │
│  XBotUI ──── XBotCore ──── XBotEngine ──┐      XBotRuntime ──┐   │
│  views        state         API client  │      container mgr │   │
│                             SSE stream  │      health/pull   │   │
└─────────────────────────────────────────┼────────────────────┼───┘
                                          │                    │
                       HTTP + SSE         │                    │ CLI / socket
                       127.0.0.1:3001     │                    │
                                          ▼                    ▼
┌──────────────────────────────────────────────────────────────────┐
│  Container runtime (Docker / Colima / Apple Containerization)    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  xbot-engine                             :3001 (loopback)  │  │
│  │  ┌──────────┐  ┌─────────────┐  ┌──────────────────────┐   │  │
│  │  │ API      │  │ agent       │  │ PostgreSQL           │   │  │
│  │  │ (Hono)   │  │ runtime     │  │ + pgvector           │   │  │
│  │  │          │  │ (AG-UI)     │  │                      │   │  │
│  │  │ gateway  │  │             │  │ threads, memory,     │   │  │
│  │  │ policy   │  │ model       │  │ audit, policy,       │   │  │
│  │  │ audit    │  │ router      │  │ credentials, agents  │   │  │
│  │  └──────────┘  └─────────────┘  └──────────────────────┘   │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │  computer :4100 — Chromium, /workspace, shell        │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌─────────────┐   v2: supervisor creates one computer per agent │
│  │ supervisor  │   ┌───────────┐ ┌───────────┐ ┌───────────┐     │
│  │ :4300       │──▶│ computer  │ │ computer  │ │ computer  │     │
│  └─────────────┘   │  agent A  │ │  agent B  │ │  agent C  │     │
│                    └───────────┘ └───────────┘ └───────────┘     │
└──────────────────────────────────────────────────────────────────┘
                                          │
                                          │ outbound, only where you point it
                                          ▼
              OpenAI · Anthropic · Google · xAI · Ollama (local) · MCP servers
```

## Two deployment shapes

xBot ships one of these depending on milestone. The app hides the difference.

### v1 — single container

One image. Everything except the user's own model provider is inside it: the API, the built web
assets, the agent runtime, one Chromium, and PostgreSQL with pgvector. One port published on
loopback. Two volumes for durability.

Upstream already builds almost exactly this — the root `Dockerfile` uses s6-overlay to supervise the
API, the computer, and an optional embedded Postgres (`EMBEDDED_POSTGRES=on`), all on one port. We
inherit it and turn the embedded database on by default.

**Trade:** no supervisor, so no Docker socket, so **all agents share one browser and one
workspace**. Acceptable for v1 on a single-user laptop. Not acceptable long-term — see below.

**Why v1 is this shape:** a single `docker run` with two volumes is a state machine the app can
actually own. Compose orchestration on a consumer machine has too many ways to end up half-up.

### v2 — compose, one computer per agent

The full upstream topology. The supervisor holds the Docker socket and creates a container per
agent, each with its own workspace volume and its own Chromium profile. This is what makes "each
agent has its own logins" true rather than approximately true.

**Why it matters:** in v1, agent A can read agent B's cookies, because they are the same browser
profile. If you give one agent your bank and another agent a scraping task, that is a real problem.
V1 ships with this stated plainly in the UI. V2 fixes it.

## Services and ports

Every port binds `127.0.0.1`. Nothing listens on a routable interface. The browser inside a computer
holds real logins; that is the whole reason.

| Service | Port | v1 | v2 | Responsibility |
| --- | --- | --- | --- | --- |
| API + web assets | `3001` | ✅ | ✅ | REST, AG-UI runtime, auth, policy, audit, credentials, gateway |
| computer | `4100` | internal | internal | Chromium, `/workspace`, shell, screenshots, file tools |
| agent runtime | `4201` | internal | ✅ | AG-UI endpoint, model router |
| supervisor | `4300` | — | ✅ | Creates, stops, resets, lists per-agent computers |
| PostgreSQL | `5432` | internal | ✅ | All product data |

"internal" means the port is not published to the host at all — it is reachable only from the
sibling process inside the same container. The app talks to `3001` and nothing else.

**Port collision is expected.** 5432 in particular is very often already a Homebrew Postgres on a
developer's machine. The app probes before starting and picks a free port in a private range,
recording the choice. It never asks the user to resolve this. See
[07-container-runtime.md](07-container-runtime.md).

## How a message becomes an action

This is the path that matters. Every security property lives on it.

1. **The user sends a message.** SwiftUI composer → `POST` to the API on `3001`.
2. **The server resolves who is asking and which agent.** In xBot there is one local user, so this
   is trivial — but the code path is upstream's multi-actor one and stays that way.
3. **The turn is dispatched to the agent's AG-UI endpoint.** The agent may be the built-in runtime
   or a user-supplied endpoint.
4. **The model router resolves the provider and model for *this agent***, fetches the key from the
   credential vault, and calls the vendor. ([04-model-providers.md](04-model-providers.md))
5. **The model asks for a tool.** Click, type, navigate, read a file, run a command, call an MCP
   tool.
6. **The call returns to the server gateway — never straight to the computer.** The gateway:
   1. resolves the target from the server-held page snapshot,
   2. evaluates the action policy,
   3. **writes an audit row for the decision**,
   4. calls the computer only if the decision forwards,
   5. writes a second audit row if a forwarded action then fails.
7. **The result streams back** to the conversation over SSE and into the thread store.

The critical property is step 6. **The computer does not decide policy.** It has a shell and a
browser; a container that could also authorise itself would be no boundary at all. Policy lives in
the API process, and the audit row is written *before* the action, not after — so an action that
crashes the computer is still recorded.

The policy engine **fails closed**: a missing policy permits nothing, a broken deny rule denies, a
broken allow rule does not permit, and a malformed configured policy stops the server from starting.

## Data

All of it in one PostgreSQL database with pgvector.

| | |
| --- | --- |
| **Agents** | Profile, avatar, instructions, granted tools, **model selection** (new) |
| **Threads & messages** | Durable conversation history — **local, ours, new** (ADR-0001) |
| **Memory** | Embeddings for recall across conversations — **local, ours, new** (ADR-0001) |
| **Audit** | Append-only. Every gateway decision, every control handover, every secret request |
| **Policy** | The rule set the gateway evaluates |
| **Credentials** | The vault. Encrypted at rest with a key held in the macOS Keychain |
| **Channels** | Conversations, including multi-agent ones |
| **Routines** | Scheduled recurring tasks |

**Durability is the app's problem, not the container's.** The database lives on a named volume. The
app never destroys that volume as part of an update, a restart, or a repair. There is exactly one
code path that removes it and it is behind a confirmation in Advanced settings.

## What the app talks to

The Swift client uses three transports against `127.0.0.1:3001`:

| Transport | Used for |
| --- | --- |
| **REST (JSON)** | Agents, channels, settings, credentials, policy, audit, routines |
| **SSE** | The AG-UI turn stream — tokens, tool calls, tool results, state deltas |
| **Polled `GET /screenshot`** | The live view of an agent's browser |

The live screen is a polled screenshot endpoint upstream, not a video stream. That is good news for
the client — it is an image request on a timer, adaptive: fast while a turn is running, slow when
idle, stopped when the panel is not visible.

## Trust boundaries

Four, from outside in.

1. **The host ↔ the runtime.** The app can start containers. Anything that can talk to the
   container runtime socket is root-equivalent on the host. Only the app and (in v2) the supervisor
   touch it.
2. **The app ↔ the API.** Loopback plus a token generated on first run and held in the Keychain.
   Loopback is not a boundary on a shared machine; the token is.
3. **The API ↔ the computer.** `COMPUTER_TOKEN`. The computer serves only `/health` without it.
4. **The agent ↔ everything.** The gateway. This is the one that matters, because everything behind
   it is code a model wrote.

**Where the database sits relative to the agent** is the subtle one and upstream got it right: in
the compose topology, Postgres is on a separate network from the agents' computers, because an
agent has a shell and a shell reaches whatever its container reaches. In the v1 single-container
shape that separation does not exist — the database is a sibling process on the same loopback.
That is the second reason v1 is a stepping stone, and it is stated in
[10-security.md](10-security.md).

## Where xBot diverges from upstream

Summary; details in [03-openbot-fork.md](03-openbot-fork.md).

| Area | Upstream | xBot |
| --- | --- | --- |
| Threads & memory | Hosted CopilotKit Intelligence, **mandatory** | Local Postgres provider, default |
| Model selection | `BOT_PROVIDER` env var, process-wide, 3 vendors | Per-agent, runtime, every vendor + Ollama |
| Auth | OAuth/SAML/OIDC, or single-user mode | Single local user. Keychain-backed token |
| Configuration | `.env` file | App settings → generated env → container |
| Client | React/Vite on `:3010` | Native SwiftUI. React kept for admin only |
| Install | `git clone` + `scripts/start.sh` | `.dmg` |
| Tenant package | YAML in `examples/` | Defaults compiled in, editable in the app |
