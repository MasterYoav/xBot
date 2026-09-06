import { describe, expect, test } from "bun:test";
import { Hono } from "hono";
import { createApp } from "../src/app";
import { xbotBearerAuth } from "../src/xbot/bearer-auth";
import { loadConfig } from "../src/config";
import { testEnvironment } from "./support/environment";

describe("xBot engine boundary", () => {
  const token = "test-engine-token";

  test("health identifies as xBot when a token is configured", async () => {
    const app = createApp(
      loadConfig({
        ...testEnvironment(),
        XBOT_ENGINE_TOKEN: token,
      }),
    );

    const response = await app.request("http://openbot.local/health");

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      status: "ok",
      product: "xBot",
      engineVersion: "0.0.5",
      schemaVersion: expect.any(String),
    });
  });

  test("health stays minimal without a token", async () => {
    const app = createApp(loadConfig(testEnvironment()));

    const response = await app.request("http://openbot.local/health");

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ status: "ok" });
  });

  test("refuses API calls without the bearer token", async () => {
    const app = createApp(
      loadConfig({
        ...testEnvironment(),
        XBOT_ENGINE_TOKEN: token,
      }),
    );

    const response = await app.request("http://openbot.local/api/capabilities");

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toEqual({ error: "Unauthorized." });
  });

  test("accepts API calls that carry the bearer token", async () => {
    const app = createApp(
      loadConfig({
        ...testEnvironment(),
        XBOT_ENGINE_TOKEN: token,
      }),
    );

    const response = await app.request(
      "http://openbot.local/api/capabilities",
      {
        headers: { Authorization: `Bearer ${token}` },
      },
    );

    // Capabilities is always mounted — the point is the gate opened.
    expect(response.status).toBe(200);
  });
});

/**
 * The token comparison, which is the whole boundary.
 *
 * Behind it are the agents, their browser profiles — which hold real logins — and the credential
 * vault, and anything running as this user can reach the port. It is compared in constant time
 * because `!==` stops at the first differing byte, and a comparison whose duration depends on how
 * much of the token is right leaks it to anything patient enough to measure.
 */
describe("the engine bearer token", () => {
  const guard = xbotBearerAuth("s3cret-token");
  const call = async (authorization?: string, path = "/api/agents") => {
    const app = new Hono();
    app.use("*", guard);
    app.get(path, (context) => context.json({ ok: true }));
    return app.request(`http://openbot.local${path}`, {
      headers: authorization ? { Authorization: authorization } : {},
    });
  };

  test("accepts the right token", async () => {
    expect((await call("Bearer s3cret-token")).status).toBe(200);
  });

  test("refuses a wrong token, a missing one, and a near miss", async () => {
    expect((await call("Bearer s3cret-tokeM")).status).toBe(401);
    expect((await call("Bearer ")).status).toBe(401);
    expect((await call(undefined)).status).toBe(401);
    // A prefix of the real token is the case a byte-at-a-time attack builds on.
    expect((await call("Bearer s3cret")).status).toBe(401);
    // The scheme is part of what is compared.
    expect((await call("s3cret-token")).status).toBe(401);
  });

  test("lets /health through, because Docker's HEALTHCHECK has no credentials", async () => {
    const app = new Hono();
    app.use("*", guard);
    app.get("/health", (context) => context.json({ status: "ok" }));
    expect((await app.request("http://openbot.local/health")).status).toBe(200);
  });

  test("does not let a path that merely looks like health through", async () => {
    const app = new Hono();
    app.use("*", guard);
    app.get("/health/secrets", (context) => context.json({ leaked: true }));
    expect(
      (await app.request("http://openbot.local/health/secrets")).status,
    ).toBe(401);
  });
});
