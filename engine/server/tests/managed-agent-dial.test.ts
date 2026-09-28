import { describe, expect, test } from "bun:test";
import { createAgentFetch } from "../src/agents/endpoint";
import { dialableHosts } from "../src/agents/managed-agent-host";

// The one-container image runs the Bot beside the API at a loopback address (docker/s6 api/run).
// Every run dials it through the private-address guard, which refused it: no conversation through
// the server could ever be answered.
const managed = {
  endpoint: new URL("http://127.0.0.1:4201/ag-ui"),
  token: "t",
};
const answering = (async () =>
  new Response("ok", { status: 200 })) as unknown as typeof fetch;

describe("the deployment's own Bot", () => {
  test("is dialled", async () => {
    const dial = createAgentFetch({
      allowedHosts: dialableHosts(new Set(), managed),
      fetchImpl: answering,
    });
    expect((await dial("http://127.0.0.1:4201/ag-ui")).status).toBe(200);
  });

  test("names its port, so the rest of loopback stays refused", async () => {
    const dial = createAgentFetch({
      allowedHosts: dialableHosts(new Set(), managed),
      fetchImpl: answering,
    });
    await expect(dial("http://127.0.0.1:5432/")).rejects.toThrow();
  });

  test("adds nothing when there is none, and keeps what was named", () => {
    const named = new Set(["agents.internal"]);
    expect(dialableHosts(named, undefined)).toBe(named);
    expect([...dialableHosts(named, managed)].sort()).toEqual([
      "127.0.0.1:4201",
      "agents.internal",
    ]);
  });
});
