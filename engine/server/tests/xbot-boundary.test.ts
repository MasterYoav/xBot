import { describe, expect, test } from "bun:test";
import { createApp } from "../src/app";
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

    const response = await app.request("http://openbot.local/api/capabilities", {
      headers: { Authorization: `Bearer ${token}` },
    });

    // Capabilities is always mounted — the point is the gate opened.
    expect(response.status).toBe(200);
  });
});
