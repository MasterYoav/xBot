import { afterAll, describe, expect, test } from "bun:test";
import { randomUUID } from "node:crypto";
import type { BaseEvent, Message, RunAgentInput } from "@ag-ui/client";
import { AbstractAgent, EventType } from "@ag-ui/client";
import { eq } from "drizzle-orm";
import { lastValueFrom, Observable } from "rxjs";
import { createDatabase } from "../src/db/client";
import { localThreads } from "../src/db/schema";
import {
  LocalThreadRunner,
  localRoutineIntelligence,
} from "../src/history/local-thread-runner";
import { TEST_POOL } from "./support/database";

/**
 * Local history, against a real database: what a restart gives back is what the person saw.
 *
 * The runner's own runs are the vendor's; what this file guards is the part xBot added — that a turn
 * is kept, kept once, kept as the transcript rather than the prompt, and read back after a restart.
 * The last of those is the one the Mac app depends on and the one an in-memory runner silently fails.
 */

const database = createDatabase(
  process.env.DATABASE_URL ??
    "postgres://openbot:openbot@localhost:5432/openbot",
  TEST_POOL,
);
const suite = randomUUID().slice(0, 8);
const threads: string[] = [];

afterAll(async () => {
  for (const threadId of threads) {
    await database
      .delete(localThreads)
      .where(eq(localThreads.threadId, threadId));
  }
});

/** Answers every run with one assistant message, `reply-<runId>`. */
class Echo extends AbstractAgent {
  run(input: RunAgentInput) {
    return new Observable<BaseEvent>((subscriber) => {
      const messageId = `reply-${input.runId}`;
      subscriber.next({
        type: EventType.RUN_STARTED,
        threadId: input.threadId,
        runId: input.runId,
      } as BaseEvent);
      subscriber.next({
        type: EventType.TEXT_MESSAGE_START,
        messageId,
        role: "assistant",
      } as BaseEvent);
      subscriber.next({
        type: EventType.TEXT_MESSAGE_CONTENT,
        messageId,
        delta: "heard you",
      } as BaseEvent);
      subscriber.next({
        type: EventType.TEXT_MESSAGE_END,
        messageId,
      } as BaseEvent);
      subscriber.next({
        type: EventType.RUN_FINISHED,
        threadId: input.threadId,
        runId: input.runId,
      } as BaseEvent);
      subscriber.complete();
    });
  }
}

function newThread(): string {
  const threadId = `thread_local_${suite}_${threads.length}`;
  threads.push(threadId);
  return threadId;
}

async function turn(
  runner: LocalThreadRunner,
  threadId: string,
  messages: Message[],
  persistedInputMessages?: Message[],
) {
  const agent = new Echo();
  agent.agentId = "bot_echo";
  agent.setMessages(messages);
  const runId = randomUUID();
  await lastValueFrom(
    runner.run({
      threadId,
      agent,
      input: {
        threadId,
        runId,
        messages,
        state: {},
        tools: [],
        context: [],
        forwardedProps: {},
      },
      ...(persistedInputMessages ? { persistedInputMessages } : {}),
    }),
    { defaultValue: undefined },
  );
  return runId;
}

/** The write is queued behind the run's end; wait for the row rather than for a timer. */
async function stored(threadId: string, count: number) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const [row] = await database
      .select()
      .from(localThreads)
      .where(eq(localThreads.threadId, threadId));
    const messages = (row?.messages as { messages?: Message[] } | undefined)
      ?.messages;
    if (messages && messages.length >= count) return messages;
    await Bun.sleep(20);
  }
  throw new Error(`${threadId} never reached ${count} stored messages`);
}

const user = (id: string, content: string): Message => ({
  id,
  role: "user",
  content,
});

describe("a conversation kept locally", () => {
  test("survives a restart", async () => {
    const threadId = newThread();
    const runId = await turn(new LocalThreadRunner(database), threadId, [
      user("u1", "hello"),
    ]);
    await stored(threadId, 2);

    const restarted = new LocalThreadRunner(database);
    await restarted.hydrate();

    expect(
      restarted.getThreadMessages(threadId).map((message) => message.id),
    ).toEqual(["u1", `reply-${runId}`]);
  });

  test("keeps one copy when the whole conversation is sent again", async () => {
    const threadId = newThread();
    const runner = new LocalThreadRunner(database);
    const first = await turn(runner, threadId, [user("u1", "hello")]);
    const history = runner.getThreadMessages(threadId);
    const second = await turn(runner, threadId, [
      ...history,
      user("u2", "again"),
    ]);

    const ids = ["u1", `reply-${first}`, "u2", `reply-${second}`];
    expect(runner.getThreadMessages(threadId).map((m) => m.id)).toEqual(ids);
    expect((await stored(threadId, 4)).map((m) => m.id)).toEqual(ids);
  });

  test("keeps what the transcript shows, not the prompt the model was sent", async () => {
    const threadId = newThread();
    const runner = new LocalThreadRunner(database);
    const runId = await turn(
      runner,
      threadId,
      [user("prompt", "a paragraph of instructions for the model")],
      [user("shown", "Handed over by the other Bot")],
    );

    expect(runner.getThreadMessages(threadId).map((m) => m.id)).toEqual([
      "shown",
      `reply-${runId}`,
    ]);
  });

  test("answers a routine in the platform's row shape", async () => {
    const threadId = newThread();
    const runner = new LocalThreadRunner(database);
    const runId = await turn(runner, threadId, [user("u1", "hello")]);

    const { messages } = await localRoutineIntelligence(
      runner,
    ).getThreadMessages({ threadId, userId: "anyone" });

    expect(messages).toEqual([
      { id: "u1", role: "user", content: "hello" },
      { id: `reply-${runId}`, role: "assistant", content: "heard you" },
    ]);
  });
});
