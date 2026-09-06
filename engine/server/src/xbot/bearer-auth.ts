import { timingSafeEqual } from "node:crypto";
import type { MiddlewareHandler } from "hono";

/**
 * Loopback is not a boundary on a shared Mac. When `XBOT_ENGINE_TOKEN` is set — which the app
 * always does — every request must carry it except `/health`, which Docker's HEALTHCHECK calls
 * without credentials.
 */
export function xbotBearerAuth(token: string): MiddlewareHandler {
  const expected = Buffer.from(`Bearer ${token}`);

  return async (context, next) => {
    if (context.req.path === "/health") return next();

    if (!matches(context.req.header("Authorization"), expected)) {
      return context.json({ error: "Unauthorized." }, 401);
    }

    return next();
  };
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
