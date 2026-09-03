/**
 * Which model answers a run, resolved per run rather than per process.
 *
 * Upstream reads `BOT_PROVIDER` once at module scope and every agent in the container gets it.
 * ADR-0002 moves the choice onto the agent: two agents in one engine can sit on different
 * providers, and changing one from a dropdown applies to its next message with no restart.
 *
 * Its own module rather than more of `index.ts`, for the reason `model-options.ts` gives: that file
 * calls `serve()` at module scope, so importing it to reach one pure function binds a port. It is
 * also new-file work on purpose — `docs/03-openbot-fork.md` treats a heavily edited upstream file
 * as a permanent merge conflict, so the router lives here and `index.ts` keeps one seam.
 *
 * Nothing in this file reads `process.env`. That is ADR-0002's pair of hard rules for implementers,
 * and it is not only about tidiness: environment variables leak into `/proc`, into child processes
 * and into crash dumps, and the container this runs beside holds a shell a model can drive. Keys
 * arrive as arguments, from the engine's vault, and the caller is where the environment is read.
 */

/*
 * The wire shape lives in `shared/`, because the API server writes what this reads and a parser
 * written on one side of a boundary is a parser the other side approximates.
 *
 * Note what it does *not* contain: which providers exist. That is below, in this process, so a
 * provider can be added without a server release.
 */
import type { ModelSelection } from "../../../shared/model-selection";

export type { ModelSelection };

/** A selection that is ready to construct a client from. */
export interface ResolvedModel {
  providerId: ProviderId;
  model: string;
  apiKey: string;
  baseURL?: string;
  useResponsesApi: boolean;
}

export type ProblemKind =
  | "noSelection"
  | "unknownProvider"
  | "noKey"
  | "noBaseURL";

/**
 * Why a run cannot start, in a shape the app can match on.
 *
 * `kind` rather than a string, because docs/04 rule 3 is that "no key configured for Anthropic",
 * "Anthropic rejected the key" and "Anthropic is rate-limiting you" are three different sentences
 * with three different buttons. A caller cannot choose a button from prose.
 *
 * And rule 4: a missing key is a UI state, not an exception. So this is returned, never thrown —
 * the composer disables itself with a reason rather than the run failing on send.
 */
export interface ModelProblem {
  kind: ProblemKind;
  providerId?: string;
  message: string;
}

interface ProviderDefinition {
  displayName: string;
  defaultModel: string;
  /** `openai-compatible` is the one that runs without a key: a local Ollama asks for none. */
  requiresKey: boolean;
  /** The compatible adapter is a base URL and nothing else, so it cannot default one. */
  requiresBaseURL: boolean;
}

/**
 * The providers this build knows, and the single entry that covers everything it does not.
 *
 * Tier 1 keeps upstream's three under the same ids, so an existing deployment's `BOT_PROVIDER`
 * value still names the same thing. `openai-compatible` is the addition that matters: one adapter
 * with a per-agent base URL reaches xAI, Ollama, OpenRouter, Groq, Together, Fireworks, DeepSeek,
 * Mistral, LM Studio, vLLM and any corporate gateway. docs/04 calls it the single highest-leverage
 * piece of the router, and this is why — the long tail costs a text field, not an adapter each.
 *
 * A list rather than prose because it is also the error message. Somebody who guessed a provider
 * name should be told which names exist, not sent to find a reference.
 */
export const PROVIDERS: Record<string, ProviderDefinition> = {
  openai: {
    displayName: "OpenAI",
    defaultModel: "gpt-5.5",
    requiresKey: true,
    requiresBaseURL: false,
  },
  anthropic: {
    displayName: "Anthropic",
    defaultModel: "claude-sonnet-4-5",
    requiresKey: true,
    requiresBaseURL: false,
  },
  google: {
    displayName: "Google",
    defaultModel: "gemini-2.5-flash",
    requiresKey: true,
    requiresBaseURL: false,
  },
  "openai-compatible": {
    displayName: "an OpenAI-compatible endpoint",
    // Empty on purpose: an endpoint names its own catalogue, so guessing one here would be wrong
    // for every deployment that is not the one we guessed for.
    defaultModel: "",
    requiresKey: false,
    requiresBaseURL: true,
  },
};

export type ProviderId = keyof typeof PROVIDERS;

/**
 * OpenAI only: the models that reject function tools on `/v1/chat/completions`.
 *
 * Upstream infers this once, at boot, from one `BOT_MODEL`. Per-agent selection means two agents in
 * one process can disagree about it, so the inference moves onto the resolved model. Dropping it
 * would give somebody who picked `gpt-5.6` from a dropdown a Bot that starts, looks healthy, and
 * fails on its first tool call — the exact failure the upstream comment was written about.
 */
const NEEDS_RESPONSES_API = /^gpt-5\.[6-9]|^gpt-[6-9]/;

export interface ResolveRequest {
  /** What this agent chose. Absent means it never chose. */
  selection: ModelSelection | undefined;
  /** The workspace default, which is what an agent that never chose inherits. */
  fallback: ModelSelection | undefined;
  /** Deployment-wide keys by provider id, from the vault. Never from the environment. */
  keys: Record<string, string | undefined>;
}

/** Either a model to answer on, or the reason there is none. Never both, never a throw. */
export interface ResolveResult {
  model?: ResolvedModel;
  problem?: ModelProblem;
}

/**
 * agent → workspace default → problem.
 *
 * The order is ADR-0002's, and the last step is deliberately not a guess. Defaulting to OpenAI when
 * nothing is configured is how upstream behaves and it is wrong here: it produces a Bot that
 * silently answers on a provider the person never chose and may have no key for.
 */
export function resolveModel(request: ResolveRequest): ResolveResult {
  const chosen = request.selection ?? request.fallback;
  if (!chosen?.providerId) {
    return {
      problem: {
        kind: "noSelection",
        message:
          "No model is selected for this agent and the workspace has no default. Choose one in the agent's settings.",
      },
    };
  }

  const providerId = chosen.providerId.trim().toLowerCase();
  const provider = PROVIDERS[providerId];
  if (!provider) {
    return {
      problem: {
        kind: "unknownProvider",
        providerId,
        message: `${providerId} is not a provider this engine knows. Use one of: ${Object.keys(PROVIDERS).join(", ")}.`,
      },
    };
  }

  const baseURL = chosen.baseURL?.trim() || undefined;
  if (provider.requiresBaseURL && !baseURL) {
    return {
      problem: {
        kind: "noBaseURL",
        providerId,
        message:
          "A custom provider needs the address of its endpoint. Add the base URL in the agent's settings.",
      },
    };
  }

  /*
   * A selection's own key first, then the deployment's.
   *
   * Empty and unset are the same thing here, the trap `BOT_MODEL` already documents upstream: a
   * compose file passing `${OPENAI_API_KEY:-}` hands on an empty string, which is a value, and the
   * run then fails at the vendor rather than here where it can be explained.
   */
  const apiKey =
    chosen.apiKey?.trim() || request.keys[providerId]?.trim() || "";
  if (provider.requiresKey && !apiKey) {
    return {
      problem: {
        kind: "noKey",
        providerId,
        message: `No key is connected for ${provider.displayName}. Connect one in Settings to use this agent.`,
      },
    };
  }

  // An empty model is the same as an unset one — see `BOT_MODEL` upstream. The picker can hand
  // over a provider before its model list has loaded, and answering on that provider's usual model
  // beats refusing the run over a field the person was never shown.
  const model = chosen.model?.trim() || provider.defaultModel;

  return {
    model: {
      providerId,
      model,
      apiKey,
      baseURL,
      useResponsesApi:
        providerId === "openai" && NEEDS_RESPONSES_API.test(model),
    },
  };
}

export type ErrorKind =
  | "badKey"
  | "rateLimited"
  | "modelNotFound"
  | "badEndpoint"
  | "noToolSupport"
  | "unknown";

export interface ModelError {
  kind: ErrorKind;
  message: string;
}

/**
 * What a provider's refusal actually means, in the caller's words rather than the vendor's.
 *
 * Every vendor has its own error taxonomy and ADR-0002 is explicit that absorbing the differences
 * is the router's job and where its bugs will be. Matched on status first and body text second,
 * because the statuses agree across vendors and the prose does not.
 */
export function classifyModelError(
  providerId: string,
  status: number,
  body: string,
): ModelError {
  const name = PROVIDERS[providerId]?.displayName ?? providerId;
  const text = body.toLowerCase();

  /*
   * Tool support is checked before the status buckets, because the refusal arrives as a plain 400
   * and would otherwise land in "unknown" — the outcome ADR-0002 names as the worst available.
   * A local model that cannot call tools has to say so; an agent that silently stops clicking
   * reads to the person watching as a broken product rather than a model choice.
   */
  if (
    text.includes("does not support tools") ||
    text.includes("tools are not supported") ||
    text.includes("does not support function")
  ) {
    return {
      kind: "noToolSupport",
      message: `This model cannot call tools, so the agent will not be able to use its computer. Choose a model with tool support.`,
    };
  }

  if (status === 401 || status === 403) {
    return {
      kind: "badKey",
      message: `${name} rejected the key. Check it in Settings.`,
    };
  }

  if (status === 429) {
    return {
      kind: "rateLimited",
      message: `${name} is rate-limiting this key. Wait a moment and try again.`,
    };
  }

  if (status === 404) {
    // A 404 that names the model is the catalogue; a bare one is the address. Telling them apart
    // matters most for a custom endpoint, where a typo in the base URL and a typo in the model
    // name are both easy and need opposite fixes.
    if (text.includes("model")) {
      return {
        kind: "modelNotFound",
        message: `${name} has no model by that name. Pick another in the agent's settings.`,
      };
    }
    return {
      kind: "badEndpoint",
      message: `Nothing answered at that address. Check the base URL in the agent's settings.`,
    };
  }

  return {
    kind: "unknown",
    message: `${name} returned an error (${status}).`,
  };
}
