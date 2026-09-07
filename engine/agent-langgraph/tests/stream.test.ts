import { describe, expect, test } from "bun:test";
import {
  EMPTY_REPLY_FALLBACK,
  type RunStreamEvent,
  streamRun,
} from "../src/stream";

/**
 * The reader that turns a run's framework events into the AG-UI wire.
 *
 * Driven with hand-built event streams rather than a real graph, because the thing worth pinning is
 * the translation: which AG-UI events a given sequence of framework events produces, and — the case
 * this suite exists for — that a run which produced nothing a person can see still ends on a visible
 * line rather than a silent RUN_FINISHED. The empty-reply guard used to live in the graph's state,
 * where this reader never looks, so it never reached the surface; the assertions below are on what
 * the surface actually receives.
 */

const RUN = { runId: "run_1", threadId: "thread_1" };

/** Collect what streamRun sends, as plain `{type, ...}` records. */
async function collect(
  events: RunStreamEvent[] | (() => Promise<AsyncIterable<RunStreamEvent>>),
): Promise<Array<Record<string, unknown>>> {
  const sent: Array<Record<string, unknown>> = [];
  const makeEvents =
    typeof events === "function"
      ? events
      : async () =>
          (async function* () {
            for (const event of events) yield event;
          })();
  await streamRun(makeEvents, RUN, (event) =>
    sent.push(event as unknown as Record<string, unknown>),
  );
  return sent;
}

const types = (sent: Array<Record<string, unknown>>) =>
  sent.map((event) => event.type);

const modelStream = (content: unknown): RunStreamEvent => ({
  event: "on_chat_model_stream",
  data: { chunk: { content } },
});

describe("a run that produces nothing a person can see", () => {
  test("an empty reply ends on the fallback line, not a silent RUN_FINISHED", async () => {
    // No stream deltas, no tool calls: the shape a strict provider returns on a run it will not
    // answer, and the shape the graph ends immediately.
    const sent = await collect([]);

    expect(types(sent)).toEqual([
      "TEXT_MESSAGE_START",
      "TEXT_MESSAGE_CONTENT",
      "TEXT_MESSAGE_END",
      "RUN_FINISHED",
    ]);
    expect(sent[1]).toMatchObject({ delta: EMPTY_REPLY_FALLBACK });
    // The message the fallback is drawn as has to be a real, closed message the surface can render.
    expect(sent[0]).toMatchObject({
      role: "assistant",
      messageId: "msg_run_1_0",
    });
  });

  test("a reply that is only a reasoning summary counts as empty", async () => {
    // The Responses API puts a reasoning model's private working in a content block with a `text`
    // field under a non-text type. It is never shown, so a reply carrying only that is silent to the
    // person and must reach the same fallback — the case the old state-based guard got wrong, because
    // it read any `text` field as visible.
    const sent = await collect([
      modelStream([{ type: "reasoning", text: "thinking it over" }]),
    ]);

    expect(types(sent)).toEqual([
      "TEXT_MESSAGE_START",
      "TEXT_MESSAGE_CONTENT",
      "TEXT_MESSAGE_END",
      "RUN_FINISHED",
    ]);
    expect(sent[1]).toMatchObject({ delta: EMPTY_REPLY_FALLBACK });
  });
});

describe("a run that does produce something is left alone", () => {
  test("streamed prose is forwarded and no fallback is added", async () => {
    const sent = await collect([modelStream("Hel"), modelStream("lo")]);

    expect(types(sent)).toEqual([
      "TEXT_MESSAGE_START",
      "TEXT_MESSAGE_CONTENT",
      "TEXT_MESSAGE_CONTENT",
      "TEXT_MESSAGE_END",
      "RUN_FINISHED",
    ]);
    expect(sent[1]).toMatchObject({ delta: "Hel" });
    expect(sent[2]).toMatchObject({ delta: "lo" });
    // The fallback text appears nowhere.
    expect(sent.some((event) => event.delta === EMPTY_REPLY_FALLBACK)).toBe(
      false,
    );
  });

  test("responses-API content blocks are forwarded as text", async () => {
    const sent = await collect([
      modelStream([
        { type: "reasoning", text: "private" },
        { type: "text", text: "shown" },
      ]),
    ]);

    expect(types(sent)).toContain("TEXT_MESSAGE_CONTENT");
    expect(sent.find((e) => e.type === "TEXT_MESSAGE_CONTENT")).toMatchObject({
      delta: "shown",
    });
    expect(sent.some((event) => event.delta === EMPTY_REPLY_FALLBACK)).toBe(
      false,
    );
  });

  test("a tool the surface owns is reported with no result and no fallback", async () => {
    // The model asked for a browser-side tool; the graph ends the run without running it, so the
    // tools node never fires and the call is drained at the end with no result. It is still a thing
    // the surface has to do, so the run is not silent and gets no fallback.
    const sent = await collect([
      {
        event: "on_chat_model_end",
        data: {
          output: {
            tool_calls: [
              { id: "call_1", name: "show_chart", args: { kind: "bar" } },
            ],
          },
        },
      },
    ]);

    expect(types(sent)).toEqual([
      "TOOL_CALL_START",
      "TOOL_CALL_ARGS",
      "TOOL_CALL_END",
      "RUN_FINISHED",
    ]);
    expect(sent[0]).toMatchObject({
      toolCallId: "call_1",
      toolCallName: "show_chart",
    });
    expect(sent[1]).toMatchObject({ delta: JSON.stringify({ kind: "bar" }) });
    // A drained surface call carries no result — that is the surface's half.
    expect(types(sent)).not.toContain("TOOL_CALL_RESULT");
  });

  test("a tool this deployment ran is reported with its result and no fallback", async () => {
    const sent = await collect([
      {
        event: "on_chat_model_end",
        data: {
          output: {
            tool_calls: [{ id: "call_2", name: "search", args: { q: "cats" } }],
          },
        },
      },
      {
        event: "on_chain_end",
        name: "tools",
        data: {
          output: {
            messages: [{ tool_call_id: "call_2", content: "found 3" }],
          },
        },
      },
    ]);

    expect(types(sent)).toEqual([
      "TOOL_CALL_START",
      "TOOL_CALL_ARGS",
      "TOOL_CALL_END",
      "TOOL_CALL_RESULT",
      "RUN_FINISHED",
    ]);
    expect(sent[3]).toMatchObject({ toolCallId: "call_2", content: "found 3" });
    expect(sent.some((event) => event.delta === EMPTY_REPLY_FALLBACK)).toBe(
      false,
    );
  });
});

describe("message boundaries across a multi-turn run", () => {
  test("prose after a tool result opens a new message id", async () => {
    const sent = await collect([
      modelStream("Let me check"),
      {
        event: "on_chat_model_end",
        data: {
          output: { tool_calls: [{ id: "call_3", name: "search", args: {} }] },
        },
      },
      {
        event: "on_chain_end",
        name: "tools",
        data: {
          output: { messages: [{ tool_call_id: "call_3", content: "done" }] },
        },
      },
      modelStream("Here it is"),
    ]);

    const firstText = sent.find((e) => e.type === "TEXT_MESSAGE_START");
    const lastText = [...sent]
      .reverse()
      .find((e) => e.type === "TEXT_MESSAGE_START");
    expect(firstText).toMatchObject({ messageId: "msg_run_1_0" });
    // Reusing one id reopens a message the surface already closed and drops the second half; the
    // close between turns has to advance it.
    expect(lastText).toMatchObject({ messageId: "msg_run_1_1" });
    expect(firstText?.messageId).not.toBe(lastText?.messageId);
  });
});

describe("a failure mid-stream", () => {
  test("an open message is closed and the run ends on RUN_ERROR", async () => {
    const sent = await collect(async () =>
      (async function* () {
        yield modelStream("half a sentence");
        throw new Error("provider hung up");
      })(),
    );

    expect(types(sent)).toEqual([
      "TEXT_MESSAGE_START",
      "TEXT_MESSAGE_CONTENT",
      "TEXT_MESSAGE_END",
      "RUN_ERROR",
    ]);
    expect(sent.at(-1)).toMatchObject({ message: "provider hung up" });
    // A run that errored is not also finished.
    expect(types(sent)).not.toContain("RUN_FINISHED");
  });

  test("a failure opening the stream is reported as RUN_ERROR", async () => {
    const sent = await collect(async () => {
      throw new Error("could not build graph");
    });

    expect(types(sent)).toEqual(["RUN_ERROR"]);
    expect(sent[0]).toMatchObject({ message: "could not build graph" });
  });
});

/**
 * Token usage, read off the model's own reply and reported once per run.
 *
 * docs/04-model-providers.md is specific about what may be shown: token counts the APIs actually
 * return, and a spend estimated from a local price table. Never a percentage of a quota — that
 * implies a limit we do not know and cannot enforce, and a number a person cannot verify is worse
 * than no number.
 *
 * Accumulated across the run rather than emitted per model call, because the tool loop means one
 * turn can be several calls, and a person reading "this reply cost N tokens" means the whole turn.
 */
describe("token usage", () => {
  const usage = (input: number, output: number) =>
    ({
      event: "on_chat_model_end",
      data: {
        output: {
          usage_metadata: { input_tokens: input, output_tokens: output },
        },
      },
    }) as unknown as RunStreamEvent;

  test("reports what one model call used", async () => {
    const sent = await collect([
      { event: "on_chat_model_stream", data: { chunk: { content: "hi" } } },
      usage(120, 34),
    ]);
    const custom = sent.find((event) => event.type === "CUSTOM");
    expect(custom).toBeDefined();
    expect(custom?.name).toBe("xbot.usage");
    expect(custom?.value).toEqual({ inputTokens: 120, outputTokens: 34 });
  });

  test("adds up every call in a turn, because the tool loop makes several", async () => {
    const sent = await collect([
      { event: "on_chat_model_stream", data: { chunk: { content: "one" } } },
      usage(100, 10),
      { event: "on_chat_model_stream", data: { chunk: { content: "two" } } },
      usage(50, 5),
    ]);
    const custom = sent.find((event) => event.type === "CUSTOM");
    expect(custom?.value).toEqual({ inputTokens: 150, outputTokens: 15 });
  });

  test("says nothing when the provider reported nothing", async () => {
    // Not zero. Zero is a measurement; absent is the honest answer when a provider does not
    // report usage, and a Usage screen showing 0 tokens for a real turn would be a lie.
    const sent = await collect([
      { event: "on_chat_model_stream", data: { chunk: { content: "hi" } } },
      {
        event: "on_chat_model_end",
        data: { output: {} },
      } as unknown as RunStreamEvent,
    ]);
    expect(sent.find((event) => event.type === "CUSTOM")).toBeUndefined();
  });

  test("arrives before the run is finished, so a reader has it in the same stream", async () => {
    const sent = await collect([
      { event: "on_chat_model_stream", data: { chunk: { content: "hi" } } },
      usage(1, 2),
    ]);
    const usageIndex = sent.findIndex((event) => event.type === "CUSTOM");
    const finishedIndex = sent.findIndex(
      (event) => event.type === "RUN_FINISHED",
    );
    expect(usageIndex).toBeGreaterThan(-1);
    expect(usageIndex).toBeLessThan(finishedIndex);
  });
});

/**
 * The router's sentence, in place of the vendor's.
 *
 * `classifyModelError` was written, exported and tested, and then called from nowhere — so a
 * provider's refusal reached the person as whatever prose the vendor SDK put in an exception.
 * ADR-0002 says absorbing those differences is the router's job. These two tests are the wiring
 * that had been missing, so the same thing cannot quietly come loose again.
 */
describe("a provider's refusal, explained", () => {
  const failing = async (): Promise<AsyncIterable<RunStreamEvent>> => {
    throw Object.assign(new Error('401 {"error":"invalid x-api-key"}'), {
      status: 401,
    });
  };

  test("the explanation replaces the vendor's own message", async () => {
    const sent: Array<Record<string, unknown>> = [];
    await streamRun(
      failing,
      RUN,
      (event) => sent.push(event as unknown as Record<string, unknown>),
      () => "Anthropic rejected the key. Check it in Settings.",
    );

    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({
      type: "RUN_ERROR",
      message: "Anthropic rejected the key. Check it in Settings.",
    });
    // The vendor's own prose is what the person used to be shown.
    expect(String(sent[0]?.message)).not.toContain("x-api-key");
  });

  /// Undefined means "not a provider saying no", and the error's own message is then the best
  /// available answer — a socket that hung up is not a key problem and must not be dressed as one.
  test("no explanation leaves the error's own message alone", async () => {
    const sent: Array<Record<string, unknown>> = [];
    await streamRun(
      async () => {
        throw new Error("socket hang up");
      },
      RUN,
      (event) => sent.push(event as unknown as Record<string, unknown>),
      () => undefined,
    );

    expect(sent[0]).toMatchObject({ message: "socket hang up" });
  });
});
