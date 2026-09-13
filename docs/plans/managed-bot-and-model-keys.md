# Plan: a Bot in the box, and model keys that reach it

**Why this exists.** Driving the real `HTTPEngineClient` against a real engine for the first time
(`Tests/XBotEngineTests/LiveEngineTests.swift`) found that the product's core path has never worked
end to end:

1. **No agent can be created.** `POST /api/agents` answers *"This deployment has no managed Bot."*
   The one-container image runs postgres, migrations, the API and the computer — `agent-langgraph`
   is not even copied into it — so `MANAGED_AGENT_AG_UI_URL` is never set, and `profile-store.create`
   refuses any coworker without its own endpoint. Onboarding's "Meet your agent" fails for every
   user, and so does every agent created from the rail.
2. **No model key reaches the engine.** Keys go to the macOS Keychain and are read back only to show
   "Connected". Nothing sends one to the engine's credential vault, and `wireFormat` carries no key.
3. **The agent will not boot without a deployment key.** `agent-langgraph` exits unless
   `BOT_PROVIDER` and that provider's key are in its environment — upstream's posture, and the
   opposite of ADR-0002's per-agent, per-run keys.

"M2 proven live" drove `agent-langgraph` directly with environment variables. The app → engine →
model path was never exercised.

This implements ADR-0002's existing decision; it is not a new one.

## Engine

- **E1 — the Bot in the image.** Copy `agent-langgraph` into the image with its own locked
  dependencies (as `agent-computer` already is). Two s6 services: `agent-token`, a oneshot that
  generates `MANAGED_AGENT_TOKEN` when unset (mirroring `computer-token`), and `agent`, a longrun on
  `127.0.0.1:4201` in per-run mode with its tool URL pointed at the API beside it. The API sets
  `MANAGED_AGENT_AG_UI_URL` to it when unset. Port 4201 is not published.
- **E2 — per-run mode.** `XBOT_PER_RUN_MODELS=true` skips the boot-time provider/key requirement and
  leaves no deployment default: every run must carry its selection and key, and one that does not
  gets the registry's named problem as a `RUN_ERROR`. Unset, behaviour is exactly upstream's.
- **E3 — resolve the key per run.** Before `copilot.ts` forwards `xbotModel`, a selection with no key
  of its own gets one from the vault: kind `model`, provider = the selection's `providerId`, keyId =
  `modelKeyId(providerId, baseURL)`. Resolved on every run, so a replaced key is used by the next
  message. Never published — `publishableSelection` already strips it.

## App

- **A1 — the client.** `HTTPEngineClient.storeModelKey` posts to `/api/admin/credentials` (adding a
  key under an existing id replaces it); `removeModelKey` revokes the live one.
- **A2 — sync.** The Keychain stays the source of truth (invariant 2). Every time the engine reaches
  running, every connected provider's key — vendor and custom — is written to the vault; connecting
  or disconnecting a provider while the engine runs syncs that one. Ollama needs none.
- **Key identity** is shared: `modelKeyId(providerId, baseURL)` is `xbot-model:<providerId>` with
  `@<baseURL>` appended when there is one, trailing slash removed — the same string computed on both
  sides, so two custom endpoints never share a key.

## Verification

- Unit tests on both sides for the key id, the resolution, per-run mode, and the sync.
- The live test against a locally built image: create an agent (fails today), sync a deliberately
  invalid key, send, and see the vendor's refusal come back as the router's sentence. That proves
  every hop — app, vault, resolution, Bot, vendor — without holding a real key.

## Status — built and verified

- **E1–E3, A1–A2** are in. Unit tests on both sides; the loader's vault glue against a real database
  (`server/tests/agent-model-keys.integration.test.ts`).
- **Against a locally built image** (`xbot/engine:verify`, a throwaway container with its own
  volumes): `POST /api/agents` answers 201 on the managed Bot where it answered 400; the live suite
  passes, including store / replace / revoke in the vault.
- **The Bot half inside that image**, with a run posted straight to it carrying a deliberately invalid
  Anthropic key: `RUN_ERROR` *"Anthropic rejected the key. Check it in Settings."* — the Bot booted with
  no key in its environment, the per-run key reached Anthropic, and the refusal was classified.
- **Not verified from here:** the last hop, through the conversation store. Without a CopilotKit key
  every run stops at `LocalIntelligence.getOrCreateThread` (ADR-0007) and answers 502. The app blocks
  sending in that state, so nobody meets the 502; `LiveEngineTests.aStoredKeyTravelsAllTheWayToTheVendor`
  is the check to run once an engine has Intelligence (`XBOT_LIVE_ENGINE_HAS_INTELLIGENCE=1`).

### Found on the way

- **Every edit to an agent failed against a real engine.** `HTTPEngineClient.updateAgent` re-sent the
  agent's endpoint on the belief that omitting it resets the agent; the engine keeps the stored one,
  and re-sending the managed Bot's loopback address is refused by the engine's own network guard. So
  renaming, relabelling and changing the model all failed for every agent. Fixed by not sending it.
