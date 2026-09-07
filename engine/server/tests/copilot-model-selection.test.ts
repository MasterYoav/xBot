import { describe, expect, test } from "bun:test";
import { HttpAgent } from "@ag-ui/client";
import type { BaseEvent, RunAgentInput } from "@ag-ui/core";
import { buildAgents, registeredAgentFromRow } from "../src/copilot";

/*
 * The hop the product actually uses.
 *
 * ADR-0002's per-agent model was proven live by driving the agent process directly, which leaves the
 * production path — surface, `copilot.ts`, `HttpAgent`, endpoint — unmeasured. Everything between
 * those two points is serialisation: `copilot.ts` puts the selection on `forwardedProps`, the client
 * encodes the run, and the agent reads `forwardedProps.xbotModel` back out. A field that does not
 * survive that trip fails silently and in the worst possible way — the endpoint falls back to its
 * deployment default and answers, so the person sees a reply, believes their model setting took, and
 * is billed against a vendor they did not pick.
 *
 * So this asserts on the bytes on the wire rather than on the object handed to the client.
 */

const riskRow = {
  id: "risk",
  name: "Risk",
  type: "remote_ag_ui" as const,
  title: "Risk & Compliance",
  roleDescription: "Investigate policies and controls.",
};

/** The endpoint lives in the row's configuration, which is where the normaliser looks for it. */
const ENDPOINT = "http://risk.internal/ag-ui";

const model = { provider: "openai" as const, defaultModel: "gpt-4.1" };

/** A run that finishes immediately, so the client completes rather than hanging on the assertion. */
function finished(input: RunAgentInput): Response {
  const events: BaseEvent[] = [
    {
      type: "RUN_STARTED",
      threadId: input.threadId,
      runId: input.runId,
    } as BaseEvent,
    {
      type: "RUN_FINISHED",
      threadId: input.threadId,
      runId: input.runId,
    } as BaseEvent,
  ];
  return new Response(
    events.map((event) => `data: ${JSON.stringify(event)}\n\n`).join(""),
    { headers: { "content-type": "text/event-stream" } },
  );
}

/** Run one Bot through the real client and hand back what was posted to the endpoint. */
async function bodyPostedFor(
  configuration: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  let posted: Record<string, unknown> | undefined;

  const dialler = async (_url: string | URL | Request, init?: RequestInit) => {
    posted = JSON.parse(String(init?.body));
    return finished(posted as unknown as RunAgentInput);
  };

  const agents = await buildAgents(
    [
      registeredAgentFromRow({
        ...riskRow,
        configuration: { endpoint: ENDPOINT, ...configuration },
      }),
    ] as never,
    model,
    null,
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    dialler as never,
  );

  const risk = agents.risk;
  if (!(risk instanceof HttpAgent))
    throw new Error("Expected the remote agent");

  /*
   * `runAgent`, never `run`.
   *
   * Everything `copilot.ts` adds to a remote Bot's run — the standing role, the holdings message,
   * the tools, the signed assertion and the model selection — is registered with `.use()`, and
   * `copilot.ts` says in as many words that `.use()` middleware is applied by `runAgent` and not by
   * `run`. A test that drove `run` would dial the endpoint, receive a well-formed run, assert
   * happily on `forwardedProps` and be measuring an empty object. This one did, before it was
   * corrected — which is the same silent failure the production path would have.
   */
  risk.messages = [{ id: "m1", role: "user", content: "hello" }] as never;
  await risk.runAgent();

  if (!posted) throw new Error("The client never dialled the endpoint");
  return posted;
}

describe("a Bot's model selection, on the wire", () => {
  test("reaches the endpoint under the name the agent reads", async () => {
    const selection = {
      providerId: "anthropic",
      model: "claude-sonnet-4-5",
      apiKey: "sk-ant-not-a-real-key",
    };
    const posted = await bodyPostedFor({ modelSelection: selection });

    /*
     * `xbotModel`, not `modelSelection`. The name is the contract between two processes that never
     * share a type: `copilot.ts` writes it and `agent-langgraph/src/index.ts` reads it, and renaming
     * either half quietly reverts every per-agent model to the deployment default.
     */
    const forwarded = posted.forwardedProps as Record<string, unknown>;
    expect(forwarded.xbotModel).toEqual(selection);
  });

  test("is absent when the Bot never chose one", async () => {
    // Absent is not the same as a default. Only the endpoint knows what its deployment is
    // configured for, so sending one from here would override a setting this side cannot see.
    const posted = await bodyPostedFor({});
    const forwarded = posted.forwardedProps as Record<string, unknown>;
    expect(forwarded).not.toHaveProperty("xbotModel");
  });
});
