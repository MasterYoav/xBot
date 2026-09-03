/**
 * Which model an agent answers on, as it crosses process boundaries.
 *
 * Shared because it crosses two of them and the validation must not be written twice. The API
 * server reads it out of an agent's stored configuration, which the Mac app writes; the agent
 * process reads it off `forwardedProps`, which the API server writes. Both are reading data they
 * did not construct, and a parser that lives in one of them is a parser the other will approximate.
 *
 * Only the wire shape lives here. Which providers exist, what they default to and what they need is
 * the agent process's business — see `agent-langgraph/src/models/registry.ts` — because that is
 * where the clients are constructed and where the answer can change without a server release.
 */
export interface ModelSelection {
  /** A provider the agent process knows: `openai`, `anthropic`, `google`, `openai-compatible`. */
  providerId: string;
  /** Empty means "that provider's usual model", which is what an unloaded picker sends. */
  model: string;
  /** Required by `openai-compatible`, which has no endpoint of its own. Ignored elsewhere. */
  baseURL?: string;
  /** This agent's own key, when one was resolved for it. Never logged, never echoed. */
  apiKey?: string;
}

/**
 * A selection, or nothing, from a value nobody validated.
 *
 * `undefined` rather than a throw, and it means one specific thing at both call sites: "this agent
 * did not choose", which falls back to the workspace default. A stored configuration written by an
 * older app, a hand-edited row, or a half-saved settings pane all land here, and none of them
 * should stop a person's conversation — the fallback answers instead.
 *
 * `providerId` is the only required field because it is the only one without a sane default. An
 * unknown provider is deliberately *not* rejected here: the agent process owns the provider list
 * and returns a named problem for one it does not know, which is a sentence the person can act on.
 * Dropping it silently here would turn that into an unexplained fallback to somebody else's model.
 */
export function parseModelSelection(
  value: unknown,
): ModelSelection | undefined {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return undefined;
  }
  const raw = value as Record<string, unknown>;
  const providerId =
    typeof raw.providerId === "string" ? raw.providerId.trim() : "";
  if (!providerId) return undefined;

  const model = typeof raw.model === "string" ? raw.model.trim() : "";
  const baseURL = typeof raw.baseURL === "string" ? raw.baseURL.trim() : "";
  const apiKey = typeof raw.apiKey === "string" ? raw.apiKey.trim() : "";

  return {
    providerId,
    model,
    // Absent rather than empty, so a caller can tell "not set" from "set to nothing" without
    // knowing which of the two the writer meant.
    ...(baseURL ? { baseURL } : {}),
    ...(apiKey ? { apiKey } : {}),
  };
}
