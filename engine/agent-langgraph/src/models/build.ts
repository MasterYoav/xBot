import { ChatAnthropic } from "@langchain/anthropic";
import { ChatGoogleGenerativeAI } from "@langchain/google-genai";
import { ChatOpenAI } from "@langchain/openai";
import type { ModelSelection } from "../../../shared/model-selection";
import type { ReasoningEffort } from "../model-options";
import { resolveModel } from "./registry";

/**
 * Which client a resolved selection is answered by.
 *
 * Lifted out of `index.ts` so it can be tested without booting the server. It is worth testing on
 * its own: this hop has failed silently three times (docs/12) — parsed but dropped, sent under the
 * wrong key, stored but never read back — and every one of those looked identical from outside,
 * because the wrong client still answers. A test that asserts on the client and the address it was
 * given is the only thing that tells those apart without a live vendor.
 */
export interface BuildRequest {
  /** What this agent chose. Absent means it never chose. */
  selection: ModelSelection | undefined;
  /** The workspace default, which is what an agent that never chose inherits. */
  fallback: ModelSelection | undefined;
  /** Deployment-wide keys by provider id, from the vault. Never from the environment. */
  keys: Record<string, string | undefined>;
  /** OpenAI's setting, and only ever applied to OpenAI on the Responses API. */
  reasoningEffort?: ReasoningEffort;
}

/**
 * The chat model, from whichever provider *this run* is for.
 *
 * Every one of these binds tools the same way and streams the same way, which is exactly why the
 * rest of the runtime does not know which one it got — and why per-agent selection fits here at all.
 *
 * This is the seam ADR-0002 asks for. The provider used to be a module constant; now it is an
 * argument, and `models/registry.ts` decides what it resolves to.
 */
export function buildChatModel({
  selection,
  fallback,
  keys,
  reasoningEffort,
}: BuildRequest) {
  const { model: resolved, problem } = resolveModel({
    selection,
    fallback,
    keys,
  });
  /*
   * Thrown, not exited. A missing key at *boot* is the deployer's problem and still exits at
   * startup; a missing key for one agent mid-flight is that agent's problem, and taking the process
   * down would end every other agent's conversation over it. `streamRun` turns this into a
   * RUN_ERROR carrying the sentence the registry wrote, which is the one the person needs to read.
   */
  if (!resolved) {
    throw new Error(problem?.message ?? "No model is selected for this agent.");
  }

  if (resolved.providerId === "anthropic") {
    return new ChatAnthropic({
      model: resolved.model,
      apiKey: resolved.apiKey,
      streaming: true,
      ...(resolved.baseURL ? { anthropicApiUrl: resolved.baseURL } : {}),
    });
  }
  if (resolved.providerId === "google") {
    return new ChatGoogleGenerativeAI({
      model: resolved.model,
      apiKey: resolved.apiKey,
      streaming: true,
      ...(resolved.baseURL ? { baseUrl: resolved.baseURL } : {}),
    });
  }
  /*
   * OpenAI and `openai-compatible` are the same client with a different address.
   *
   * That is the whole trick, and why docs/04 calls the compatible adapter the highest-leverage
   * piece of the router: xAI, Ollama, OpenRouter, Groq, Together, DeepSeek, LM Studio and any
   * corporate gateway all speak this API, so they cost a base URL rather than an adapter each.
   */
  return new ChatOpenAI({
    model: resolved.model,
    apiKey: resolved.apiKey,
    streaming: true,
    ...(resolved.baseURL
      ? { configuration: { baseURL: resolved.baseURL } }
      : {}),
    ...(resolved.useResponsesApi ? { useResponsesApi: true } : {}),
    /*
     * `reasoning.effort`, not the `reasoningEffort` convenience field: the integration deprecated
     * the latter in favour of merging it into this object, and one of them is the one that survives.
     *
     * Gated on the *resolved* provider, not the configured one. The startup check only knows what
     * the environment chose, so without this an agent switched to Anthropic from a dropdown would
     * be sent an OpenAI-only setting — the "configuration that goes nowhere" failure the effort
     * check exists to prevent, arriving by the new route.
     */
    ...(reasoningEffort &&
    resolved.providerId === "openai" &&
    resolved.useResponsesApi
      ? { reasoning: { effort: reasoningEffort } }
      : {}),
  });
}
