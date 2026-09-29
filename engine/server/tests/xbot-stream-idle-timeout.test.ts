import { afterAll, describe, expect, test } from "bun:test";
import { serve } from "bun";
import {
  holdsLongSilences,
  keepStreamingRunsOpen,
} from "../src/xbot/stream-idle-timeout";

/**
 * A run whose model says nothing for longer than Bun's idle timeout.
 *
 * Bun closes a connection that has written nothing for `idleTimeout` seconds, 10 by default, and a
 * streaming run writes RUN_STARTED and then nothing until the model's first token. A cold local model,
 * a queue behind another run, or a slow vendor is silent for longer than that. The stream was then
 * closed under the run: the person saw an empty reply, the run carried on in the engine, and their
 * next message was refused with "Thread already running".
 */
describe("streaming runs outlive the server's idle timeout", () => {
  // Well past the timeout: Bun checks idle connections on a coarse timer, so a silence only just
  // over one second is sometimes survived by luck.
  const silenceMs = 6_000;
  const server = serve({
    port: 0,
    // Short, so the test does not wait the default's ten seconds to show the same thing.
    idleTimeout: 1,
    fetch(request, server) {
      keepStreamingRunsOpen(request, server);
      const body = new ReadableStream({
        async start(controller) {
          controller.enqueue(new TextEncoder().encode("data: started\n\n"));
          await Bun.sleep(silenceMs);
          controller.enqueue(new TextEncoder().encode("data: finished\n\n"));
          controller.close();
        },
      });
      return new Response(body, {
        headers: { "content-type": "text/event-stream" },
      });
    },
  });
  afterAll(() => server.stop(true));

  const read = async (path: string, accept: string) => {
    const response = await fetch(`http://127.0.0.1:${server.port}${path}`, {
      method: "POST",
      headers: { accept },
    });
    try {
      return await response.text();
    } catch {
      return "(connection closed)";
    }
  };

  test("a streaming run is not cut off while its model is silent", {
    timeout: 15_000,
  }, async () => {
    const body = await read(
      "/api/copilotkit/agent/agent_1/run",
      "text/event-stream",
    );
    expect(body).toContain("data: finished");
  });

  test("anything else keeps the server's idle timeout", {
    timeout: 15_000,
  }, async () => {
    const body = await read("/api/channels", "application/json");
    expect(body).not.toContain("data: finished");
  });
});

describe("which requests hold long silences", () => {
  const post = (path: string, accept = "text/event-stream") =>
    new Request(`http://engine.local${path}`, {
      method: "POST",
      headers: { accept },
    });

  test("an agent run that asks for a stream", () => {
    expect(holdsLongSilences(post("/api/copilotkit/agent/a/run"))).toBe(true);
    expect(
      holdsLongSilences(post("/api/copilotkit/agent/agent_x%2Fy/connect")),
    ).toBe(true);
  });

  test("not a run that asks for JSON, and not an ordinary route", () => {
    expect(
      holdsLongSilences(
        post("/api/copilotkit/agent/a/run", "application/json"),
      ),
    ).toBe(false);
    expect(holdsLongSilences(post("/api/channels"))).toBe(false);
    expect(
      holdsLongSilences(
        new Request("http://engine.local/api/copilotkit/agent/a/run", {
          headers: { accept: "text/event-stream" },
        }),
      ),
    ).toBe(false);
  });
});
