# ADR-0002 — Resolve the model per agent at request time, not per process at boot

**Status:** Accepted
**Date:** 2026-09
**Related:** [04-model-providers.md](../04-model-providers.md), [12-roadmap.md](../12-roadmap.md) M2

---

## Context

OpenBot selects a model provider from a process-wide environment variable, read once at start.
`agent-langgraph/src/index.ts`:

```ts
const PROVIDER = (process.env.BOT_PROVIDER ?? "openai").toLowerCase();
...
`BOT_PROVIDER=${PROVIDER} is not one this Bot knows. Use openai, anthropic or google.`
```

Three consequences:

1. **Process-wide.** Every agent served by that container uses the same provider and model.
2. **Boot-time.** Changing it means editing `.env` and restarting a container.
3. **Three vendors.** No xAI, no Ollama, no Mistral, no OpenRouter, no Bedrock.

Compose passes vendor keys into the container as environment variables — `OPENAI_API_KEY`,
`ANTHROPIC_API_KEY`, `GOOGLE_API_KEY` — which is the only option available when the provider is
fixed at boot.

xBot's requirement is the opposite on every axis. The product's stated positioning is "every AI,"
and the reference screenshots show separate agents (*Orchestrator*, *Grok*, *Gmail*, *monday*) each
with their own settings pane. Users expect to pick a model per agent from a dropdown and have it
apply to the next message.

There is also a security dimension. Environment variables leak — into `/proc`, into child processes,
into crash dumps — and the container runs a shell that a model controls.

## Options considered

### A. One agent container per provider

Run several `agent-runtime` containers, each with its own `BOT_PROVIDER`, and route by agent.

**Rejected.** Multiplies memory on a laptop by the number of providers a user has connected. Does not
solve per-*model* selection within a provider. Adding a provider means starting a container. And it
makes the "add a custom OpenAI-compatible endpoint" feature — which is how we support most of the
long tail — nearly impossible.

### B. Keep the env var, restart on change

Change the setting, restart the agent container.

**Rejected.** Restarting a container from a dropdown is a visible several-second stall, and it is
still process-wide: agent A's model change would silently move agent B.

### C. Per-agent selection resolved at request time ✅

### D. Route everything through an external gateway (LiteLLM, OpenRouter)

Let something else own multi-provider.

**Rejected as the default**, though it remains available *through* option C as a custom
OpenAI-compatible provider — which is the right place for it. As a default it adds a component to
install and manage, and for OpenRouter specifically it routes the user's traffic through a third
party, which contradicts the privacy claim.

## Decision

**Option C.** Model selection is a property of the agent, resolved per request.

```ts
interface ModelSelection {
  providerId: string;       // "anthropic", "ollama", "custom:my-gateway"
  model: string;
  parameters?: { temperature?: number; maxTokens?: number; reasoningEffort?: string };
}
```

Nullable. Null means the workspace default, which is itself a setting.

Resolution:

```
agent.modelSelection ?? workspace.defaultModel
  → provider registry
  → credential vault (never process.env)
  → client (cached per provider + baseURL)
  → call
```

**Two hard rules for implementers:**

1. **Never read a provider or model name from `process.env` in request-handling code.**
2. **Never read a provider key from `process.env` in request-handling code.** Keys come from the
   engine's encrypted credential vault.

### The compatible-adapter shortcut

xAI, Ollama, OpenRouter, Groq, Together, Fireworks, DeepSeek, Mistral, LM Studio, vLLM, and any
corporate gateway all speak an OpenAI-compatible API. **One `openai-compatible` adapter with a
per-agent `baseURL` covers all of them.**

This ships first. It makes Grok and Ollama work in the app in days rather than weeks, and it is what
turns "every AI" from a roadmap item into a text field.

## Consequences

### Good

- The product's central claim becomes true, and the settings screen stops being aspirational.
- Keys move out of the environment into an encrypted vault. **One secret transits the environment
  (`KEY_ENCRYPTION_KEY`) instead of N.**
- Changing a model is instant. No restart, no stall.
- A custom provider is a text field, which covers the long tail without any code.
- Per-agent model choice is genuinely useful, not just a checkbox: a cheap fast model for a triage
  agent, an expensive careful one for the agent with your bank open.

### Bad

- **Real work: 2–3 weeks**, plus 1–2 more for native adapters beyond compatible mode.
- **We own the differences between vendors.** Tool-call schemas, streaming shapes, reasoning
  parameters, and error taxonomies all differ. The adapters absorb this and the adapters are where
  the bugs will be.
- **Client caching needs care.** Constructing a client per request is wasteful; caching per
  provider+baseURL is right, and invalidating that cache when a key changes is the thing that will
  be forgotten.
- **Divergence from upstream in `agent-langgraph/`.** Mitigated by putting the router in new files
  (`models/`) and leaving one seam where the provider was read.

### The capability problem

Not every model can call tools. Many local models cannot, or do it badly. **Silently degrading an
agent to text-only is the worst available outcome** — a user watching their agent fail to click
anything, with no explanation, concludes the product is broken.

So: the model picker shows a tools badge, and selecting a model without tool support warns
explicitly that the agent will not be able to use its computer. This is a product requirement of this
ADR, not a nice-to-have.

## Verification

**Done when two agents in the same engine, on different providers, both answer correctly, and
switching one from a dropdown takes effect on the next message with no restart.**

Tests: resolution order, key lookup, client caching and invalidation, error classification. Per
adapter, a contract suite against recorded fixtures — a tool call, a streamed response, a 401, a 429,
a truncated stream. Every adapter passes the same suite.
