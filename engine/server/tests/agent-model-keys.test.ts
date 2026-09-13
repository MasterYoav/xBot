import { describe, expect, test } from "bun:test";
import { modelKeyId } from "../../shared/model-selection";
import { attachModelKey } from "../src/agents/runtime-agents";
import type { RegisteredAgent } from "../src/copilot";

/*
 * Model keys meeting the agent that uses them, per run.
 *
 * Found by driving the real client against a real engine: the app kept keys in the Keychain, the
 * vault could hold them, and no run ever carried one. See docs/plans/managed-bot-and-model-keys.md.
 */
describe("the vault key for a model", () => {
  /*
   * These exact strings are also pinned by the Mac app's tests. The two sides share no code, only
   * this string, so the examples are the contract.
   */
  test("names the provider, and the address when there is one", () => {
    expect(modelKeyId("anthropic")).toBe("xbot-model:anthropic");
    expect(modelKeyId("openai-compatible", "https://api.x.ai/v1")).toBe(
      "xbot-model:openai-compatible@https://api.x.ai/v1",
    );
  });

  test("treats a trailing slash and stray whitespace as the same endpoint", () => {
    expect(
      modelKeyId("openai-compatible", " https://openrouter.ai/api/v1/ "),
    ).toBe("xbot-model:openai-compatible@https://openrouter.ai/api/v1");
    expect(modelKeyId(" Anthropic ")).toBe("xbot-model:anthropic");
  });

  test("keeps two custom endpoints apart", () => {
    expect(
      modelKeyId("openai-compatible", "https://openrouter.ai/api/v1"),
    ).not.toBe(
      modelKeyId("openai-compatible", "https://gateway.example.com/v1"),
    );
  });

  test("an empty address is no address", () => {
    expect(modelKeyId("openai", "")).toBe("xbot-model:openai");
  });
});

describe("attaching the key to an agent's selection", () => {
  const remote = (selection?: Record<string, unknown>) =>
    ({
      id: "a1",
      name: "A",
      type: "remote_ag_ui",
      endpoint: "http://127.0.0.1:4201/ag-ui",
      standingMessage: { id: "s", role: "system", content: "" },
      ...(selection ? { modelSelection: selection } : {}),
    }) as unknown as RegisteredAgent;

  test("a selection with no key gets the vault's", async () => {
    const agent = remote({
      providerId: "anthropic",
      model: "claude-sonnet-4-5",
    });
    const asked: string[] = [];
    await attachModelKey(agent, async (provider, baseURL) => {
      asked.push(modelKeyId(provider, baseURL));
      return "sk-ant-from-vault";
    });
    expect(asked).toEqual(["xbot-model:anthropic"]);
    expect(
      (agent as { modelSelection?: { apiKey?: string } }).modelSelection
        ?.apiKey,
    ).toBe("sk-ant-from-vault");
  });

  test("looks the key up by the selection's own address", async () => {
    const agent = remote({
      providerId: "openai-compatible",
      model: "grok-4",
      baseURL: "https://api.x.ai/v1",
    });
    let asked = "";
    await attachModelKey(agent, async (provider, baseURL) => {
      asked = modelKeyId(provider, baseURL);
      return "xai-key";
    });
    expect(asked).toBe("xbot-model:openai-compatible@https://api.x.ai/v1");
  });

  /// A key set on this agent specifically is somebody's deliberate choice, and wins.
  test("a key already on the selection is left alone", async () => {
    const agent = remote({
      providerId: "openai",
      model: "gpt-5.5",
      apiKey: "agent-own",
    });
    let called = false;
    await attachModelKey(agent, async () => {
      called = true;
      return "vault";
    });
    expect(called).toBe(false);
    expect(
      (agent as { modelSelection?: { apiKey?: string } }).modelSelection
        ?.apiKey,
    ).toBe("agent-own");
  });

  /// Nothing in the vault leaves the selection keyless, so the Bot says which key is missing.
  test("no key in the vault changes nothing", async () => {
    const agent = remote({ providerId: "google", model: "gemini-2.5-flash" });
    await attachModelKey(agent, async () => undefined);
    expect(
      (agent as { modelSelection?: { apiKey?: string } }).modelSelection
        ?.apiKey,
    ).toBeUndefined();
  });

  test("an agent with no selection is not looked up", async () => {
    const agent = remote();
    let called = false;
    await attachModelKey(agent, async () => {
      called = true;
      return "x";
    });
    expect(called).toBe(false);
  });
});
