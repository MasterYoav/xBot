import { describe, expect, test } from "bun:test";
import { Hono } from "hono";
import {
  XBOT_ADMIN_COOKIE,
  XBOT_ADMIN_SESSION_PATH,
  xbotBearerAuth,
} from "../src/xbot/bearer-auth";

/*
 * The Mac app's admin webview, authenticated the way a browser can be.
 *
 * The bearer check is mounted on every path, and a webview cannot put a header on its document
 * request or on the `<script>` and `<link>` loads that follow it — so Settings → Plugins answered
 * "Unauthorized." and never drew. The app's workaround patched `fetch` and XHR to add the token, in
 * every frame and on every page the webview ever navigated to, so a third-party sign-in page opened
 * during a connector's OAuth flow would have sent the engine token to that third party.
 *
 * The app now trades the bearer token once, on a POST, for a cookie: HttpOnly so no page script can
 * read it, SameSite=Strict so no other site's requests carry it, scoped to this origin, and not the
 * token itself.
 */
const token = "test-engine-token";

function app() {
  const hono = new Hono();
  hono.use("*", xbotBearerAuth(token));
  hono.get("/admin/plugins", (context) => context.text("admin"));
  hono.get("/assets/app.js", (context) => context.text("js"));
  return hono;
}

function cookieFrom(response: Response): string | undefined {
  const header = response.headers.get("set-cookie") ?? "";
  const match = header.match(new RegExp(`${XBOT_ADMIN_COOKIE}=([^;]+)`));
  return match?.[1];
}

describe("the admin webview's session", () => {
  test("a document request with no credentials is still refused", async () => {
    const response = await app().request("http://127.0.0.1/admin/plugins");
    expect(response.status).toBe(401);
  });

  test("the bearer token is exchanged for a cookie, and the page then loads", async () => {
    const exchange = await app().request(
      `http://127.0.0.1${XBOT_ADMIN_SESSION_PATH}?to=/admin/plugins`,
      { method: "POST", headers: { Authorization: `Bearer ${token}` } },
    );
    expect(exchange.status).toBe(303);
    expect(exchange.headers.get("location")).toBe("/admin/plugins");

    const cookie = cookieFrom(exchange);
    expect(cookie).toBeDefined();
    const setCookie = exchange.headers.get("set-cookie") ?? "";
    expect(setCookie).toContain("HttpOnly");
    expect(setCookie).toContain("SameSite=Strict");
    expect(setCookie).toContain("Path=/");

    // Subresources and API calls carry it the way any browser does, with no script involved.
    for (const path of ["/admin/plugins", "/assets/app.js"]) {
      const response = await app().request(`http://127.0.0.1${path}`, {
        headers: { Cookie: `${XBOT_ADMIN_COOKIE}=${cookie}` },
      });
      expect(response.status).toBe(200);
    }
  });

  /// The cookie is derived from the token, never the token: a stolen cookie cannot be replayed as a
  /// bearer header against the API from anything that is not a browser holding the cookie.
  test("the cookie is not the token", async () => {
    const exchange = await app().request(
      `http://127.0.0.1${XBOT_ADMIN_SESSION_PATH}`,
      { method: "POST", headers: { Authorization: `Bearer ${token}` } },
    );
    const cookie = cookieFrom(exchange) ?? "";
    expect(cookie).not.toContain(token);
    const asBearer = await app().request("http://127.0.0.1/admin/plugins", {
      headers: { Authorization: `Bearer ${cookie}` },
    });
    expect(asBearer.status).toBe(401);
  });

  test("the exchange itself needs the token", async () => {
    const response = await app().request(
      `http://127.0.0.1${XBOT_ADMIN_SESSION_PATH}`,
      { method: "POST" },
    );
    expect(response.status).toBe(401);
    expect(cookieFrom(response)).toBeUndefined();
  });

  test("a forged cookie is refused", async () => {
    const response = await app().request("http://127.0.0.1/admin/plugins", {
      headers: { Cookie: `${XBOT_ADMIN_COOKIE}=not-the-real-one` },
    });
    expect(response.status).toBe(401);
  });

  /// An open redirect would let the exchange bounce a person anywhere; only paths on this origin.
  test("the redirect stays on this origin", async () => {
    for (const to of [
      "https://evil.example/",
      "//evil.example/x",
      "javascript:alert(1)",
    ]) {
      const response = await app().request(
        `http://127.0.0.1${XBOT_ADMIN_SESSION_PATH}?to=${encodeURIComponent(to)}`,
        { method: "POST", headers: { Authorization: `Bearer ${token}` } },
      );
      expect(response.headers.get("location")).toBe("/");
    }
  });
});
