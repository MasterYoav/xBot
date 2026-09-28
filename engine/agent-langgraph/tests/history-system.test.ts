import { describe, expect, test } from "bun:test";
import type { RunAgentInput } from "@ag-ui/core";
import { SystemMessage } from "@langchain/core/messages";
import { COMPUTER_GUIDANCE } from "../../shared/bot-prompt";
import { toLangChainMessages } from "../src/history";

/**
 * Every system text arrives as one leading system message.
 *
 * The server sends its own standing messages — the role, what this Bot holds — and the Bot puts its
 * guidance first. OpenAI answers any number of system messages anywhere; Anthropic refuses the run
 * outright ("System messages are only permitted as the first passed message"), so every Anthropic
 * agent failed before reaching the vendor. Found by the first live run through the server.
 */
const input = (messages: unknown[]): RunAgentInput =>
  ({ messages }) as unknown as RunAgentInput;

describe("system messages", () => {
  test("are merged, in order, into the first message and nowhere else", () => {
    const messages = toLangChainMessages(
      input([
        { role: "system", content: "You are the research agent." },
        { role: "user", content: "hello" },
        { role: "developer", content: "You hold Drive." },
      ]),
    );

    const system = messages.filter((m) => m instanceof SystemMessage);
    expect(system).toHaveLength(1);
    expect(messages[0]).toBe(system[0]);
    const text = String(system[0]?.content);
    expect(text.indexOf(COMPUTER_GUIDANCE)).toBe(0);
    expect(text.indexOf("You are the research agent.")).toBeLessThan(
      text.indexOf("You hold Drive."),
    );
    expect(messages).toHaveLength(2);
  });
});
