import { describe, expect, test } from "bun:test";
import { ChatAnthropic } from "@langchain/anthropic";
import { ChatGoogleGenerativeAI } from "@langchain/google-genai";
import { ChatOpenAI } from "@langchain/openai";
import { buildChatModel } from "../src/models/build";

/**
 * Which client answers a selection, and at which address.
 *
 * The registry's own tests prove a selection resolves; these prove the resolution is *acted on*.
 * docs/12 records three failures on this path — parsed but dropped, sent under the wrong key,
 * stored but never read back — and all three looked healthy from outside, because a run answered
 * either way. Only the client and the address it was handed tell them apart without a live vendor.
 */
const keys = { openai: "sk-o", anthropic: "sk-a", google: "sk-g" };

describe("the client a selection is answered by", () => {
  test("anthropic gets Anthropic's client, on the model that was asked for", () => {
    const model = buildChatModel({
      selection: { providerId: "anthropic", model: "claude-sonnet-4-5" },
      fallback: undefined,
      keys,
    });
    expect(model).toBeInstanceOf(ChatAnthropic);
    expect((model as ChatAnthropic).model).toBe("claude-sonnet-4-5");
  });

  test("google gets Google's client", () => {
    const model = buildChatModel({
      selection: { providerId: "google", model: "gemini-2.5-flash" },
      fallback: undefined,
      keys,
    });
    expect(model).toBeInstanceOf(ChatGoogleGenerativeAI);
    expect((model as ChatGoogleGenerativeAI).model).toBe("gemini-2.5-flash");
  });

  test("an openai-compatible endpoint is OpenAI's client at somebody else's address", () => {
    // The base URL is the entire difference, so a build that dropped it would send a local Ollama
    // run to OpenAI — with a key that works, which is how this goes unnoticed.
    const model = buildChatModel({
      selection: {
        providerId: "openai-compatible",
        model: "llama3.1",
        baseURL: "http://host.docker.internal:11434/v1",
      },
      fallback: undefined,
      keys,
    }) as ChatOpenAI;
    expect(model).toBeInstanceOf(ChatOpenAI);
    expect(model.model).toBe("llama3.1");
    expect(model.clientConfig.baseURL).toBe(
      "http://host.docker.internal:11434/v1",
    );
  });

  test("an agent that never chose inherits the workspace default", () => {
    const model = buildChatModel({
      selection: undefined,
      fallback: { providerId: "anthropic", model: "claude-sonnet-4-5" },
      keys,
    });
    expect(model).toBeInstanceOf(ChatAnthropic);
  });

  test("no selection and no default is the agent's error, not the process's", () => {
    // Thrown rather than exited: taking the process down would end every other agent's
    // conversation over one agent's missing model.
    expect(() =>
      buildChatModel({ selection: undefined, fallback: undefined, keys }),
    ).toThrow();
  });

  test("a missing key names the provider rather than failing at the vendor", () => {
    expect(() =>
      buildChatModel({
        selection: { providerId: "google", model: "gemini-2.5-flash" },
        fallback: undefined,
        keys: { google: undefined },
      }),
    ).toThrow(/google|Google/);
  });

  test("reasoning effort reaches OpenAI on the Responses API", () => {
    const model = buildChatModel({
      selection: { providerId: "openai", model: "gpt-5.6" },
      fallback: undefined,
      keys,
      reasoningEffort: "high",
    }) as ChatOpenAI;
    expect(model.reasoning).toEqual({ effort: "high" });
  });

  test("and never reaches a provider whose API has no such setting", () => {
    // The failure this prevents: an agent switched to Anthropic from a dropdown, still carrying
    // OpenAI's setting, configured in a way that goes nowhere.
    const model = buildChatModel({
      selection: { providerId: "anthropic", model: "claude-sonnet-4-5" },
      fallback: undefined,
      keys,
      reasoningEffort: "high",
    });
    expect(model).toBeInstanceOf(ChatAnthropic);
    expect("reasoning" in model).toBe(false);
  });
});
