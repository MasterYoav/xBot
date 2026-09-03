import { describe, expect, test } from "bun:test";
import { parseModelSelection } from "./model-selection";

/**
 * The parser both sides of the boundary use, so neither approximates the other.
 *
 * Everything it reads was written somewhere else — an agent's stored configuration comes from the
 * Mac app, `forwardedProps` comes from the API server — so every field is checked rather than
 * trusted. The rule throughout is that a malformed selection is "this agent did not choose", which
 * falls back to the workspace default, rather than an error in front of somebody mid-conversation.
 */
describe("reading a model selection from data nobody validated", () => {
  test("keeps a complete selection", () => {
    expect(
      parseModelSelection({
        providerId: "openai-compatible",
        model: "grok-4",
        baseURL: "https://api.x.ai/v1",
        apiKey: "xai-key",
      }),
    ).toEqual({
      providerId: "openai-compatible",
      model: "grok-4",
      baseURL: "https://api.x.ai/v1",
      apiKey: "xai-key",
    });
  });

  test("a provider alone is a choice — the model has a sane default, the provider has none", () => {
    expect(parseModelSelection({ providerId: "anthropic" })).toEqual({
      providerId: "anthropic",
      model: "",
    });
  });

  test("absent optional fields stay absent rather than becoming empty strings", () => {
    const result = parseModelSelection({
      providerId: "openai",
      model: "gpt-5.5",
    });
    expect("baseURL" in (result ?? {})).toBe(false);
    expect("apiKey" in (result ?? {})).toBe(false);
  });

  test("trims, because a pasted base URL or key arrives with whitespace", () => {
    expect(
      parseModelSelection({
        providerId: " anthropic ",
        model: " claude-sonnet-4-5 ",
        apiKey: " sk-a\n",
      }),
    ).toEqual({
      providerId: "anthropic",
      model: "claude-sonnet-4-5",
      apiKey: "sk-a",
    });
  });

  test("no provider means no choice, which is the workspace default", () => {
    expect(parseModelSelection({ model: "gpt-5.5" })).toBeUndefined();
    expect(parseModelSelection({ providerId: "" })).toBeUndefined();
    expect(parseModelSelection({ providerId: "   " })).toBeUndefined();
    expect(parseModelSelection({ providerId: 7 })).toBeUndefined();
  });

  test("anything that is not an object is not a selection", () => {
    for (const value of [
      undefined,
      null,
      "anthropic",
      3,
      true,
      [],
      [{ providerId: "x" }],
    ]) {
      expect(parseModelSelection(value)).toBeUndefined();
    }
  });

  test("a wrongly-typed field is ignored, not fatal — the rest of the row still answers", () => {
    expect(
      parseModelSelection({ providerId: "openai", model: 5, baseURL: {} }),
    ).toEqual({ providerId: "openai", model: "" });
  });

  /**
   * An unknown provider survives on purpose. The agent process owns the provider list and answers
   * with a sentence naming what it does know; dropping it here would turn that into a silent
   * fallback to a model the person did not choose and may not want billed.
   */
  test("keeps a provider this side has never heard of, for the other side to name", () => {
    expect(parseModelSelection({ providerId: "bedrock", model: "x" })).toEqual({
      providerId: "bedrock",
      model: "x",
    });
  });
});
