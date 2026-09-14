# Plan: the computer, as client tools in the Mac app

**Why.** Upstream's agents use their computer through **client-side tools**. OpenBot's web app
registers them with `useFrontendTool` (`engine/app/src/lib/copilot/computer-tools.tsx`); the engine never
offers them. The Mac app is xBot's client and sends `tools: []` on every run, so no xBot agent has ever
been offered a browser, files, or a shell — the product's headline feature does not function.

## The contract, from CopilotKit's client (`@copilotkit/core` `runAgent` / `executeSpecificTool`)

1. Every run carries `tools`: the client tools' names, descriptions and JSON-schema parameters.
2. The Bot calls one: `TOOL_CALL_START/ARGS/END`, no result from the engine, then `RUN_FINISHED`.
3. The client runs the handler, then inserts `{ role: "tool", toolCallId, content }` — the handler's
   return, JSON-stringified — right after the assistant message that carries the tool calls.
4. It starts a follow-up run sending the **whole** message list, and repeats until no client tool is
   pending (CopilotKit caps the depth).

## Steps

- **C1 — executor.** `XBotEngine.ComputerTools`: the tool definitions as AG-UI `tools`, and an executor
  mapping each call to `/api/computers/:botId/<path>`, shaping results exactly as upstream's
  `callComputer` does — `{ok: true, …body}`, or `{ok: false, reason}` with `refused`/`rule` on 403 and
  `humanHasControl` or `staleRefs` on 409. **Verifiable now** against a real engine's browser.
- **C2 — offer the tools.** Runs carry the definitions instead of `[]`.
- **C3 — continuation loop.** Hold AG-UI-native messages per channel (the assistant tool-call message
  and tool results), execute pending client calls at `RUN_FINISHED`, follow up with the full list.
  **Not verifiable without a CopilotKit key**: continuation runs through the conversation store.
- **C4 — the two prompts.** `computer_request_secret` (masked field, value never returned) and
  `computer_request_help` (take control, hand back), both waiting on `/control` state.

## Status

- **C1 done**, verified against a real engine: navigate, snapshot, write/read a file, run a command
  (`LiveComputerToolsTests`).
- **C2 done.** Every run carries `ComputerTools.wireTools`.
- **C3 done, verified only against a stubbed engine.** `WireTranscript` rebuilds the conversation with
  `@ag-ui/client`'s reducer, id for id, starting from the thread's stored history — which also fixes
  agents having no memory of earlier messages. `HTTPEngineClient.stream` runs pending calls at
  `RUN_FINISHED` and follows up, capped at 25 rounds. **Needs one real conversation with a CopilotKit
  key** before v1: that the history route's rows round-trip, and that follow-ups do not duplicate.
- C4 next.
