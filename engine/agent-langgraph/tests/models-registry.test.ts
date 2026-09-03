import { describe, expect, test } from "bun:test";
import {
  PROVIDERS,
  classifyModelError,
  resolveModel,
} from "../src/models/registry";

/**
 * The router's resolution, with no network anywhere near it.
 *
 * ADR-0002 moves model choice off `BOT_PROVIDER` — read once, per process — and onto the agent,
 * resolved per request. The two rules it hands implementers are both about `process.env`: a request
 * path must read neither a provider name nor a key from it. So `resolveModel` takes its credentials
 * as an argument. Nothing here reads the environment, which is also what makes it testable.
 */
const keys = { openai: "sk-o", anthropic: "sk-a", google: "sk-g" };

describe("resolving which model answers a run", () => {
  test("the agent's own selection wins over the workspace default", () => {
    const result = resolveModel({
      selection: { providerId: "anthropic", model: "claude-sonnet-4-5" },
      fallback: { providerId: "openai", model: "gpt-5.5" },
      keys,
    });
    expect(result.model?.providerId).toBe("anthropic");
    expect(result.model?.model).toBe("claude-sonnet-4-5");
    expect(result.model?.apiKey).toBe("sk-a");
  });

  test("an agent that never chose inherits the workspace default", () => {
    const result = resolveModel({
      selection: undefined,
      fallback: { providerId: "google", model: "gemini-2.5-flash" },
      keys,
    });
    expect(result.model?.providerId).toBe("google");
    expect(result.model?.model).toBe("gemini-2.5-flash");
  });

  test("a selection naming no model falls back to that provider's default", () => {
    // The picker can hand over a provider before a model list has loaded. Answering on the
    // provider's usual model beats refusing a run over a field the person never saw.
    const result = resolveModel({
      selection: { providerId: "anthropic", model: "" },
      fallback: { providerId: "openai", model: "gpt-5.5" },
      keys,
    });
    expect(result.model?.model).toBe(PROVIDERS.anthropic.defaultModel);
  });

  test("no selection and no default is a problem, not a guess", () => {
    const result = resolveModel({
      selection: undefined,
      fallback: undefined,
      keys,
    });
    expect(result.model).toBeUndefined();
    expect(result.problem?.kind).toBe("noSelection");
  });

  /**
   * Rule 4 of docs/04: a missing key is a UI state, not an exception. It has to come back as a
   * named, matchable kind so the composer can disable itself and say which provider to connect —
   * `Error: 401` is explicitly not acceptable.
   */
  test("a provider with no key names the provider rather than throwing", () => {
    const result = resolveModel({
      selection: { providerId: "anthropic", model: "claude-sonnet-4-5" },
      fallback: undefined,
      keys: {},
    });
    expect(result.model).toBeUndefined();
    expect(result.problem?.kind).toBe("noKey");
    expect(result.problem?.providerId).toBe("anthropic");
    expect(result.problem?.message).toContain("Anthropic");
  });

  test("a provider this build does not know is named, with the ones it does", () => {
    const result = resolveModel({
      selection: { providerId: "bedrock", model: "anything" },
      fallback: undefined,
      keys,
    });
    expect(result.problem?.kind).toBe("unknownProvider");
    for (const id of Object.keys(PROVIDERS)) {
      expect(result.problem?.message).toContain(id);
    }
  });
});

/**
 * The compatible adapter, which is the whole reason step 1 of the implementation order ships first.
 *
 * One provider entry with a per-agent base URL covers xAI, Ollama, OpenRouter, Groq, Together,
 * Fireworks, DeepSeek, Mistral, LM Studio, vLLM and any corporate gateway. It is what turns "every
 * AI" from a roadmap item into a text field.
 */
describe("the openai-compatible provider", () => {
  test("carries the base URL it was given", () => {
    const result = resolveModel({
      selection: {
        providerId: "openai-compatible",
        model: "grok-4",
        baseURL: "https://api.x.ai/v1",
        apiKey: "xai-key",
      },
      fallback: undefined,
      keys: {},
    });
    expect(result.model?.baseURL).toBe("https://api.x.ai/v1");
    expect(result.model?.apiKey).toBe("xai-key");
  });

  test("needs a base URL, because it has no endpoint of its own", () => {
    const result = resolveModel({
      selection: { providerId: "openai-compatible", model: "grok-4" },
      fallback: undefined,
      keys: {},
    });
    expect(result.problem?.kind).toBe("noBaseURL");
  });

  test("runs without a key, which is how a local Ollama works", () => {
    const result = resolveModel({
      selection: {
        providerId: "openai-compatible",
        model: "llama3.1",
        baseURL: "http://host.docker.internal:11434/v1",
      },
      fallback: undefined,
      keys: {},
    });
    expect(result.problem).toBeUndefined();
    expect(result.model?.apiKey).toBe("");
  });

  test("a selection's own key beats the deployment's, so two agents can differ", () => {
    const result = resolveModel({
      selection: { providerId: "openai", model: "gpt-5.5", apiKey: "sk-agent" },
      fallback: undefined,
      keys,
    });
    expect(result.model?.apiKey).toBe("sk-agent");
  });
});

/**
 * The Responses API switch, which used to be inferred once at boot from one `BOT_MODEL`.
 *
 * Per-agent selection means two agents in one process can want different answers here, so the
 * inference moves onto the resolved model. Keeping it means a deployment that picks `gpt-5.6` from
 * a dropdown does not get a Bot that starts, looks healthy, and fails on its first tool call.
 */
describe("the Responses API, per model rather than per process", () => {
  test("is on for the models that reject function tools without it", () => {
    for (const model of ["gpt-5.6", "gpt-5.9-mini", "gpt-6"]) {
      const result = resolveModel({
        selection: { providerId: "openai", model },
        fallback: undefined,
        keys,
      });
      expect(result.model?.useResponsesApi).toBe(true);
    }
  });

  test("is off for the models that do not need it", () => {
    const result = resolveModel({
      selection: { providerId: "openai", model: "gpt-5.5" },
      fallback: undefined,
      keys,
    });
    expect(result.model?.useResponsesApi).toBe(false);
  });

  test("is never on for a provider that has no such thing", () => {
    const result = resolveModel({
      selection: { providerId: "anthropic", model: "gpt-6-lookalike" },
      fallback: undefined,
      keys,
    });
    expect(result.model?.useResponsesApi).toBe(false);
  });
});

/**
 * Error classification, because "Error: 401" is not a sentence anybody can act on.
 *
 * docs/04 rule 3: no key, bad key, and rate limited are three different sentences with three
 * different buttons. The classification is what lets the app choose the button.
 */
describe("classifying what a provider said went wrong", () => {
  test("401 and 403 are a rejected key, not a missing one", () => {
    expect(classifyModelError("anthropic", 401, "").kind).toBe("badKey");
    expect(classifyModelError("anthropic", 403, "").kind).toBe("badKey");
    expect(classifyModelError("anthropic", 401, "").message).toContain(
      "Anthropic",
    );
  });

  test("429 is rate limiting, which is a wait rather than a fix", () => {
    expect(classifyModelError("openai", 429, "").kind).toBe("rateLimited");
  });

  test("a 404 naming the model is a model problem, not a dead endpoint", () => {
    const result = classifyModelError(
      "openai-compatible",
      404,
      '{"error":{"message":"The model `grok-9` does not exist"}}',
    );
    expect(result.kind).toBe("modelNotFound");
  });

  test("a 404 naming nothing is the endpoint, which is the base URL being wrong", () => {
    expect(classifyModelError("openai-compatible", 404, "Not Found").kind).toBe(
      "badEndpoint",
    );
  });

  /**
   * The capability problem ADR-0002 calls the worst available outcome. A local model that cannot
   * call tools has to say so; an agent that silently stops clicking reads as a broken product.
   */
  test("a refusal of function tools is named, not folded into 'unknown'", () => {
    const result = classifyModelError(
      "openai-compatible",
      400,
      '{"error":{"message":"this model does not support tools"}}',
    );
    expect(result.kind).toBe("noToolSupport");
    expect(result.message).toContain("computer");
  });

  test("5xx and anything unrecognised stay honest about being unrecognised", () => {
    expect(classifyModelError("openai", 500, "").kind).toBe("unknown");
    expect(classifyModelError("openai", 418, "").kind).toBe("unknown");
  });
});
