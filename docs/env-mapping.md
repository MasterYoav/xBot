# Environment mapping

Upstream's configuration surface is `engine/.env.example` — well over a hundred settings. xBot
translates app settings into an environment block the container receives. The user never edits a
file.

Every upstream variable is tagged **expose**, **default**, **ignore**, or **deferred**. Decisions
live in `apps/mac/Sources/XBotRuntime/EngineEnvironment.swift` and this table.

---

## Core container (M3)

| Upstream variable | xBot decision | Source |
| --- | --- | --- |
| `DATABASE_URL` | **Not passed.** Embedded Postgres generates a password on first boot | Container init |
| `EMBEDDED_POSTGRES` | `on` | Hardcoded in `EngineEnvironment.compose` |
| `PORT` / `SERVER_PORT` | Negotiated loopback port; both set identically | `PortAllocator` + compose |
| `KEY_ENCRYPTION_KEY` | Generated per install → Keychain | `KeyEncryptionKeyStore` |
| `XBOT_ENGINE_TOKEN` | Generated per install → Keychain | `EngineTokenStore` |
| `OPENBOT_SINGLE_USER` | `true` | Hardcoded |
| `TRUSTED_ORIGINS` | `xbot://app` | Hardcoded |
| `OPENBOT_TOOL_URL` | Built from `hostGatewayAddress()` and port | `EngineEnvironment.compose` |
| `COMPUTER_MAX_BROWSERS` | From host RAM (8 GB → 1, 16 GB → 2, 32 GB+ → 4) | `EngineEnvironment.browserLimit` |
| Container memory limit | From host RAM (4–12 GB cap) | `EngineEnvironment.memoryLimitBytes` → `ContainerSpec` |
| `AUDIT_RETENTION_DAYS` | Unset (keep everything). Advanced setting later | Optional in `Inputs` |
| `AGENT_COMPUTER_ALLOW_PRIVATE_HOSTS` | Off unless Advanced enables it | Optional in `Inputs` |

---

## Intelligence (deferred for v1 local mode)

| Upstream variable | xBot decision | Notes |
| --- | --- | --- |
| `INTELLIGENCE_API_URL` | **Deferred** — all four unset selects local history | ADR-0007; v1 may set all four for Intelligence mode |
| `INTELLIGENCE_GATEWAY_WS_URL` | **Deferred** | Same |
| `INTELLIGENCE_API_KEY` | **Deferred** | Keychain when exposed in onboarding |
| `COPILOTKIT_LICENSE_TOKEN` | **Deferred** | Telemetry only upstream |

---

## Model providers (M2)

| Upstream variable | xBot decision | Notes |
| --- | --- | --- |
| `BOT_PROVIDER` | **Ignore** — replaced by per-agent model router | ADR-0002 |
| `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, `XAI_API_KEY` | **Ignore** at container level | Keys from Keychain via model router |
| `OLLAMA_BASE_URL` | **Via model selection** — `baseURL` on the agent uses `hostGatewayAddress()` | App probes host; engine uses gateway URL |

---

## Auth / multi-user (ignore in v1)

| Upstream variable | xBot decision |
| --- | --- |
| `BETTER_AUTH_*`, OAuth client IDs | **Ignore** — single-user + bearer token |
| `INITIAL_ADMIN_EMAILS` | **Ignore** |

---

## Deployment / dev-only (ignore)

| Upstream variable | xBot decision |
| --- | --- |
| `TENANT_PACKAGE_DIR` | **Ignore** — not used in single-container image |
| `DEPLOYMENT_ID` | **Ignore** |
| `OPENBOT_GENERATIVE_UI` | **Ignore** — off unless explicitly enabled later |
| `NODE_ENV` | Set in Dockerfile (`production`) |

---

## Computer / browser (defaults)

| Upstream variable | xBot decision |
| --- | --- |
| `COMPUTER_BROWSER_IDLE_MS` | **Default upstream** — not overridden by app yet |
| `COMPUTER_TOKEN`, `SUPERVISOR_TOKEN` | **Internal** — generated inside container |

---

## Health / versioning (M3)

| Variable | xBot decision |
| --- | --- |
| `XBOT_ENGINE_VERSION` | Set at image build (`scripts/build-engine-image.sh` → Docker `ARG`) |
| `/health` response | Parsed by `HTTPEngineClient.health()`; version shown in diagnostics |

---

## Volumes

Three named volumes per `RuntimeController`: `xbot-data` (Postgres + audit), `xbot-workspace`,
`xbot-profiles` (browser profiles). See `docs/07-container-runtime.md`.

When upstream adds a new `.env` setting, add a row here before merging the fork bump.
