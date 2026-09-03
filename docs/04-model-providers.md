# Model providers

The promise is "every AI." This document is what that costs.

## What the user sees

One screen in Settings, **Models**, listing providers. Each row is a name, a state, and a key field.
The user pastes a key; the app validates it against the vendor and shows a green state or an error
in plain language.

```
Models

  OpenAI               Connected · 14 models          [ Manage ]
  Anthropic            Connected · 8 models           [ Manage ]
  Google               Not connected                  [ Connect ]
  xAI                  Not connected                  [ Connect ]
  Ollama               Running locally · 3 models     [ Manage ]

  + Add a custom provider
```

Then, per agent, one control in that agent's settings:

```
  Model      [ Claude Sonnet 4.5              ⌄ ]
             Anthropic · vision · tools · 200K context
```

Changing it takes effect on the next message. No restart. Not visible anywhere else.

**Ollama gets special treatment.** The app detects it on `localhost:11434` and lists the models the
user already has. No key. If it is not installed, the row offers a link, not an instruction.

## What exists today

**The router is built and the whole path is wired. It has not answered a real vendor yet.**

| Piece | State |
| --- | --- |
| Provider registry + resolution + error classification | `engine/agent-langgraph/src/models/registry.ts`. Four providers: `openai`, `anthropic`, `google`, `openai-compatible` |
| The seam that was `BOT_PROVIDER` | `buildModel()` takes a selection instead of closing over module constants. The environment is still read **at boot**, as the deployment fallback, so an OpenBot deployment forwarding nothing is unchanged |
| Wire type + parser | `engine/shared/model-selection.ts`, shared because the server writes what the agent reads |
| Selection on the agent | `configuration.modelSelection` — the column that already holds `endpoint`, so **no migration** |
| Forwarded per run | `forwardedProps.xbotModel`, beside the run assertion and tool names |
| Onboarding **Connect a model** step | Provider picker, secure key field, live validation via `ModelProviderValidator` |
| Keychain storage | `ProviderKeyStore` / `ProviderKeyVault` — keys never in UserDefaults or logs |
| Connection state | `ProviderConnectionStore` — injected storage, so a test never touches the real domain |
| Agent settings model picker | Dropdown in panel, backed by `ModelProviderCatalog` |
| Settings → Models | **Built.** Provider rows with live connect/disconnect, Ollama detection, and **Add a custom provider** |

**Not built yet:** native Anthropic/OpenAI/Google adapters (compatible mode reaches all three),
usage accounting, and the live two-vendor smoke that closes M2.

**Ollama container routing:** the app probes Ollama on the host (`localhost:11434`) and routes
engine calls through `hostGatewayAddress()` from the runtime driver
(`http://<gateway>:11434/v1`), not `localhost` inside the container.

### Two bugs this path shipped with, for anyone reading the history

Both were silent, and both are why the picker did nothing for weeks:

1. **The engine dropped the field.** `parseAgentInput` never read `modelSelection`, so the value the
   app was already sending went nowhere while the screen reported success.
2. **The client sent the wrong key, in a body the engine rejects.** It sent `provider` — a display
   name, `"Anthropic"` — where the engine reads `providerId`; and it built a partial PATCH against a
   parser that requires the full object, so **every** agent edit returned 400, renames included.

The lesson worth keeping: a setting that goes nowhere is worse than one that is absent, because the
screen looks the same either way.

## What upstream does instead

```ts
const PROVIDER = (process.env.BOT_PROVIDER ?? "openai").toLowerCase();
```

Read once at process start. Applies to every agent in that container. Three vendors. Changing it
means editing `.env` and restarting. See [03-openbot-fork.md](03-openbot-fork.md).

## The router

### Where the selection lives

On the agent record, not in the environment:

```ts
interface ModelSelection {
  providerId: string;       // "anthropic", "ollama", "custom:my-gateway"
  model: string;            // "claude-sonnet-4-5"
  parameters?: {
    temperature?: number;
    maxTokens?: number;
    reasoningEffort?: "low" | "medium" | "high";
  };
}
```

Nullable. Null means "use the workspace default", which is itself a setting. A new agent inherits
the default; changing the default moves every agent that never chose.

### Resolution, per request

```
resolve(agentId)
  → agent.modelSelection ?? workspace.defaultModel
  → provider registry lookup
  → credential vault: key for providerId          ← never process.env
  → construct client (cached per provider+baseURL)
  → call
```

Four rules:

1. **Never read a key from `process.env` in request-handling code.** Keys come from the vault, which
   is encrypted at rest with a key held in the macOS Keychain. Environment variables leak into crash
   reports, child processes, and `/proc`. Upstream passes them into the agent container by
   necessity; our router removes the necessity.
2. **Resolution is per request.** Not cached beyond the client object. A settings change is live on
   the next message, which is what the user expects from a dropdown.
3. **Failure is specific.** "No key configured for Anthropic" and "Anthropic rejected the key" and
   "Anthropic is rate-limiting you" are three different sentences with three different buttons.
   `Error: 401` is not acceptable.
4. **A missing key is a UI state, not an exception.** An agent whose provider has no key shows a
   badge in the rail and a prompt in the composer, and the composer is disabled with a reason. It
   does not fail on send.

### The provider interface

```ts
interface ModelProvider {
  id: string;
  displayName: string;

  // How the user connects it
  auth: { kind: "apiKey"; keyFormat?: RegExp } | { kind: "none" };
  baseURL?: string;          // user-overridable for compatible endpoints

  // What it can do
  listModels(credential: Credential): Promise<ModelInfo[]>;
  validate(credential: Credential): Promise<ValidationResult>;

  // The actual call
  createClient(credential: Credential, options: ClientOptions): LanguageModel;

  capabilities: {
    tools: boolean;
    vision: boolean;
    streaming: boolean;
    structuredOutput: boolean;
  };
}
```

`listModels` is why the settings screen can say "Connected · 14 models" rather than making the user
type a model string. Vendors that offer no model-list endpoint fall back to a curated static list
plus a free-text field.

## The vendors

### Tier 1 — first-class adapters

| Provider | Auth | Notes |
| --- | --- | --- |
| **Anthropic** | API key | Native tool use. Extended thinking where the model supports it |
| **OpenAI** | API key | Some models require the Responses API — upstream already tracks this with `BOT_RESPONSES_API`. Keep that logic, move it per-model |
| **Google** | API key | Gemini. Different tool schema; the adapter absorbs it |
| **xAI** | API key | Grok. OpenAI-compatible endpoint, so this can ship in compatible mode first |
| **Ollama** | none | Local. Detected, not configured. See below |

### Tier 2 — the compatible adapter

One adapter, `openai-compatible`, with a user-supplied `baseURL`. Covers **OpenRouter, Groq,
Together, Fireworks, DeepSeek, Mistral, LM Studio, vLLM, llama.cpp**, and any corporate gateway.

This is the single highest-leverage piece of the router. It turns "every AI" from a roadmap item
into a text field, and it is how xAI and Ollama work on day one before their dedicated adapters
exist.

The "Add a custom provider" row is exactly this: name, base URL, model, optional key. **Built** —
`CustomProviderStore` and `ModelSettingsState.addCustomProvider`.

**One rule in it is a security rule, not a nicety.** A key sent to a plain-`http` address on another
machine crosses the network in clear text, so it is refused before any request is made. Loopback is
exempt — it never leaves the machine, and it is exactly where a local Ollama or LM Studio lives, so
refusing there would block the case the row exists to serve.

### Tier 3 — later

Bedrock and Vertex, both of which need real cloud credential flows (SigV4, service accounts) rather
than a pasted key. Real demand exists; it is not v1.

## Ollama

The local case deserves its own treatment because it is the one that makes the privacy claim
literal, and because its UX is different from every other provider.

**Detection, not configuration.** The app probes `http://localhost:11434/api/tags` at launch and
when the Models screen opens. Found → the row is live and lists the user's installed models. Not
found → the row reads "Not detected" with a link to ollama.com and no further instruction.

**No key.** The auth kind is `none`. The Connect button is absent.

**Model list is the user's, not ours.** `/api/tags` returns what they have pulled. We do not offer
to pull models — that is Ollama's job and doing it for them means owning multi-gigabyte download
progress inside our app for no gain.

**Honest capability reporting.** Many local models handle tool calls poorly or not at all. The model
picker shows a tools badge, and selecting a model without it warns that the agent will not be able
to use its computer. **Silently degrading an agent to text-only is the worst outcome here** — a user
watching their agent fail to click anything with no explanation will conclude xBot is broken.

**Resolved:** the container reaches the host's Ollama via `hostGatewayAddress()` — passed into
`ModelProviderCatalog.ollamaBaseURL(hostGateway:)` when building model selections. The app still
probes `localhost:11434` on the Mac for detection; only the engine-facing URL uses the gateway.

## Costs and limits

Both screenshots of Grok Bot show a **Weekly usage 31%** meter, because that product owns the model
and therefore owns the quota. We do not. The user's quota is with their vendor.

**What we can honestly show:** token counts per conversation and per agent, from the usage numbers
the APIs return, and an estimated spend using a locally-maintained price table. Both live in a
**Usage** pane.

**What we must not do:** show a percentage meter. It implies a limit we do not know and cannot
enforce. A number the user cannot verify and we cannot guarantee is worse than no number.

For Ollama, usage shows tokens and no cost.

## Testing

- **Unit:** resolution order (agent → workspace default → error), key lookup, client caching, error
  classification. No network.
- **Contract:** each adapter against a recorded fixture — a tool call, a streamed response, a 401, a
  429, a truncated stream. Every adapter passes the same suite.
- **Live smoke:** one real call per configured provider, run manually before a release, not in CI.

## Implementation order

1. Provider registry + interface + `openai-compatible` adapter. **This alone makes xAI, Ollama,
   OpenRouter, and Groq work.**
2. `model_selection` on the agent record + the settings UI.
3. Router resolution, replacing the `BOT_PROVIDER` read.
4. Native Anthropic, OpenAI, and Google adapters.
5. Ollama detection and model listing.
6. Usage accounting.

Steps 1–3 are the blocker. Step 4 onward is quality.
