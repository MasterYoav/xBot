import type { Server } from "bun";

/**
 * Streaming agent runs are exempt from Bun's idle timeout. Nothing else is.
 *
 * `Bun.serve` closes a connection that has written nothing for `idleTimeout` seconds, 10 by default.
 * A run over SSE writes RUN_STARTED and then nothing until the model's first token, and a model is
 * routinely silent for longer than that: a local model loading into memory, a request queued behind
 * another run on the same Ollama, a vendor under load, a long think before a tool call. The stream
 * was then closed under a run that was still going. The person saw an empty reply, the run finished
 * in the engine with nobody listening, and the next message on that conversation was refused with
 * "Thread already running" until it did.
 *
 * Only these requests, rather than the server's timeout raised for everything: the timeout is what
 * frees a connection a client abandoned without closing, and every other route answers in one go.
 * A run that genuinely stops producing is the stall guard's to end (AGENT_STALL_TIMEOUT_MS), which
 * says so to the person rather than dropping the connection.
 */
const AGENT_STREAM = /^\/api\/copilotkit\/agent\/[^/]+\/(run|connect)$/;

export function holdsLongSilences(request: Request): boolean {
  if (request.method !== "POST") return false;
  if (!request.headers.get("accept")?.includes("text/event-stream")) {
    return false;
  }
  return AGENT_STREAM.test(new URL(request.url).pathname);
}

/** Call first thing in `fetch`, before anything is awaited. `0` is Bun's "no idle timeout". */
export function keepStreamingRunsOpen(
  request: Request,
  server: Pick<Server<unknown>, "timeout">,
): void {
  if (holdsLongSilences(request)) server.timeout(request, 0);
}
