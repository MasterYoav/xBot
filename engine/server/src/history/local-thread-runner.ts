import { type BaseEvent, EventType, type Message } from "@ag-ui/client";
import {
  type AgentRunnerRunRequest,
  InMemoryAgentRunner,
  ɵGLOBAL_STORE,
} from "@copilotkit/runtime/v2";
import { of } from "rxjs";
import type { Database } from "../db/client";
import { localThreads } from "../db/schema";
import type { IntelligenceLike } from "../routines/run-turn";

/**
 * Conversations kept in this deployment's own database. ADR-0008.
 *
 * THE VENDOR'S OWN LOCAL PATH, MADE DURABLE, rather than a reimplementation of the Intelligence
 * client. A `CopilotRuntime` built without `intelligence` runs in SSE mode: `/agent/:id/run` streams
 * the run back as server-sent events, and `/threads/:id/messages` answers from the runner. Both
 * already exist upstream for `InMemoryAgentRunner`; what that runner lacks is surviving a restart.
 * This adds exactly that and nothing else — the runs themselves are still the vendor's.
 *
 * SSE mode is also the only mode the native client can use. In Intelligence mode a run answers with
 * a join token for CopilotKit's realtime socket instead of a stream, which the Mac app never spoke.
 *
 * WHAT IS KEPT is what a transcript should show, not what the model was sent: the run's
 * `persistedInputMessages` when the caller names them (a hop, a routine), otherwise the messages the
 * run carried, and then whatever the run produced. Kept messages are merged by id, so a caller that
 * sends only the newest message and one that resends the whole conversation both leave one copy of
 * each message.
 *
 * ponytail: every thread is loaded into memory at boot, because the runtime reads thread messages
 * synchronously. One person's history on one Mac is small; load per thread on first read if that
 * stops being true.
 */
export class LocalThreadRunner extends InMemoryAgentRunner {
  private readonly kept = new Map<string, Message[]>();
  /** One write at a time, so two runs that end close together land in the order they ended. */
  private writes: Promise<unknown> = Promise.resolve();

  constructor(private readonly database: Database) {
    super();
  }

  /** Read every kept conversation back. Call once, before the runtime serves anything. */
  async hydrate(): Promise<void> {
    const rows = await this.database.select().from(localThreads);
    for (const row of rows) {
      this.kept.set(
        row.threadId,
        (row.messages as { messages?: Message[] }).messages ?? [],
      );
    }
  }

  override run(request: AgentRunnerRunRequest) {
    /*
     * A conversation that is still answering refuses the next run, and says so as an event.
     *
     * The vendor's runner throws "Thread already running" here. Thrown inside the SSE handler's
     * factory, that is logged and the response — already a 200 — is closed with no events in it, so
     * the Mac app saw a reply that was simply empty and could not tell anybody why. RUN_ERROR is the
     * event every caller already reads as a failed turn: the app shows its sentence, and a routine or
     * a hop, which take a lock before they get here, treat it as the refusal it is.
     */
    if (this.isBusy(request.threadId)) {
      return of<BaseEvent>({
        type: EventType.RUN_ERROR,
        message:
          "The agent is still answering your last message in this conversation. Wait for it to finish, then send this again.",
        code: "thread_busy",
      } as BaseEvent);
    }
    const carried = request.agent.messages;
    const before = new Set(carried.map((message) => message.id));
    const shown = request.persistedInputMessages ?? carried;
    const events = super.run(request);
    const keep = () =>
      this.keep(request.threadId, request.agent.agentId ?? "default", [
        ...shown,
        ...request.agent.messages.filter((message) => !before.has(message.id)),
      ]);
    // Both ends, because an observer without `error` turns a failed run into an uncaught exception.
    events.subscribe({ complete: keep, error: keep });
    return events;
  }

  override getThreadMessages(threadId: string): Message[] {
    return [...(this.kept.get(threadId) ?? [])];
  }

  /**
   * Whether a run would be refused. The vendor's own test, read synchronously from its store
   * because `run` must answer synchronously, and `isRunning` is a promise.
   */
  private isBusy(threadId: string): boolean {
    const store = ɵGLOBAL_STORE.peek(threadId);
    return Boolean(store?.isRunning || store?.stopRequested);
  }

  private keep(threadId: string, agentId: string, messages: Message[]) {
    const prior = this.kept.get(threadId) ?? [];
    const known = new Set(prior.map((message) => message.id));
    const next = [
      ...prior,
      ...messages.filter((message) => !known.has(message.id)),
    ];
    this.kept.set(threadId, next);

    const row = { threadId, agentId, messages: { messages: next } };
    this.writes = this.writes
      .then(() =>
        this.database
          .insert(localThreads)
          .values(row)
          .onConflictDoUpdate({
            target: localThreads.threadId,
            set: { messages: row.messages, updatedAt: new Date() },
          }),
      )
      .catch((error: unknown) => {
        // Not thrown: the conversation carries on from memory. What is lost is this turn surviving a
        // restart, and the log is the only place that can be said without failing a finished run.
        console.error(
          JSON.stringify({
            type: "local-history-write-failed",
            threadId,
            error: error instanceof Error ? error.message : String(error),
          }),
        );
      });
  }
}

/**
 * The routine runner's view of a local conversation, shaped like the Intelligence client it expects.
 *
 * History comes back in the platform's row shape — the same mapping the runtime's own local
 * `/threads/:id/messages` applies — because `run-turn.ts` converts from that shape and nothing else.
 * The lock is the runner's own refusal to run twice on one thread; there is no expiry to renew.
 */
export function localRoutineIntelligence(
  runner: LocalThreadRunner,
): IntelligenceLike {
  return {
    getOrCreateThread: async () => ({}),
    getThreadMessages: async ({ threadId }) => ({
      messages: runner.getThreadMessages(threadId).map((message) => ({
        id: message.id,
        role: message.role,
        content: (message as { content?: unknown }).content,
        ...(message.role === "assistant" && message.toolCalls?.length
          ? {
              toolCalls: message.toolCalls.map((call) => ({
                id: call.id,
                name: call.function.name,
                args: call.function.arguments,
              })),
            }
          : {}),
        ...(message.role === "tool" ? { toolCallId: message.toolCallId } : {}),
      })),
    }),
    ɵacquireThreadLock: async ({ threadId }) => {
      if (await runner.isRunning({ threadId })) {
        throw Object.assign(new Error(`${threadId} is busy with another run`), {
          status: 409,
        });
      }
      return {};
    },
    ɵrenewThreadLock: async () => ({}),
    ɵcleanupThreadLock: async () => {},
  };
}
