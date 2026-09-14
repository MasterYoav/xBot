import { createHmac, timingSafeEqual } from "node:crypto";
import type { MiddlewareHandler } from "hono";

/** The cookie the Mac app's admin webview authenticates with. See {@link xbotBearerAuth}. */
export const XBOT_ADMIN_COOKIE = "xbot_admin";
/** Where the webview trades the bearer token for that cookie. */
export const XBOT_ADMIN_SESSION_PATH = "/xbot/admin-session";

/**
 * Loopback is not a boundary on a shared Mac. When `XBOT_ENGINE_TOKEN` is set — which the app
 * always does — every request must carry it except `/health`, which Docker's HEALTHCHECK calls
 * without credentials.
 *
 * Carrying it has two forms. Native clients send the bearer header. The Mac app's admin webview
 * cannot: a webview puts no header on its document request or on the `<script>` and `<link>` loads
 * that follow, so Settings → Plugins answered "Unauthorized." and never drew. It trades the token
 * once, on a POST to {@link XBOT_ADMIN_SESSION_PATH}, for a cookie that is HttpOnly (no page script
 * can read it), SameSite=Strict (no other site's requests carry it), and derived from the token
 * rather than equal to it (it cannot be replayed as a bearer header). That replaced a script patching
 * `fetch` to add the raw token to every request from every page the webview loaded — including a
 * third-party OAuth page during a connector sign-in.
 */
export function xbotBearerAuth(token: string): MiddlewareHandler {
  const expected = Buffer.from(`Bearer ${token}`);
  const sessionValue = createHmac("sha256", token)
    .update("xbot-admin-webview-session")
    .digest("hex");
  const expectedCookie = Buffer.from(sessionValue);

  return async (context, next) => {
    if (context.req.path === "/health") return next();

    const hasBearer = matches(context.req.header("Authorization"), expected);

    if (context.req.path === XBOT_ADMIN_SESSION_PATH) {
      if (context.req.method !== "POST" || !hasBearer) {
        return context.json({ error: "Unauthorized." }, 401);
      }
      context.header(
        "Set-Cookie",
        `${XBOT_ADMIN_COOKIE}=${sessionValue}; Path=/; HttpOnly; SameSite=Strict`,
      );
      return context.redirect(safeLocalPath(context.req.query("to")), 303);
    }

    if (
      !hasBearer &&
      !matches(cookieValue(context.req.header("Cookie")), expectedCookie)
    ) {
      return context.json({ error: "Unauthorized." }, 401);
    }

    return next();
  };
}

/** The admin cookie's value from a Cookie header, if present. */
function cookieValue(header: string | undefined): string | undefined {
  if (!header) return undefined;
  for (const part of header.split(";")) {
    const [name, ...rest] = part.trim().split("=");
    if (name === XBOT_ADMIN_COOKIE) return rest.join("=");
  }
  return undefined;
}

/**
 * A path on this origin, or `/`.
 *
 * Only a single leading slash followed by a non-slash: `//host` is protocol-relative and would leave
 * the origin, and anything with a scheme is refused outright. An exchange that could redirect
 * anywhere is an open redirect with a session attached.
 */
function safeLocalPath(to: string | undefined): string {
  if (!to?.startsWith("/") || to.startsWith("//") || to.includes("\\")) {
    return "/";
  }
  return to;
}

/**
 * Constant-time comparison, because `!==` stops at the first byte that differs.
 *
 * This token is the whole boundary. Behind it are the agents, their browser profiles — which hold
 * real logins — and the credential vault, and anything else running as this user can reach the
 * port. A comparison whose duration depends on how much of the token is right leaks it a byte at a
 * time to something patient enough to measure, which is why every auth library does this and why
 * it is not worth being the exception.
 *
 * The length check is deliberately outside the timing-safe call: `timingSafeEqual` throws on a
 * length mismatch rather than returning false, and a token of the wrong length reveals only its
 * length, which an attacker supplying it already knows.
 */
function matches(header: string | undefined, expected: Buffer): boolean {
  if (header === undefined) return false;
  const supplied = Buffer.from(header);
  if (supplied.length !== expected.length) return false;
  return timingSafeEqual(supplied, expected);
}
