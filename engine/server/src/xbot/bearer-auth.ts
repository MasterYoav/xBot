import type { MiddlewareHandler } from "hono";

/**
 * Loopback is not a boundary on a shared Mac. When `XBOT_ENGINE_TOKEN` is set — which the app
 * always does — every request must carry it except `/health`, which Docker's HEALTHCHECK calls
 * without credentials.
 */
export function xbotBearerAuth(token: string): MiddlewareHandler {
  return async (context, next) => {
    if (context.req.path === "/health") return next();

    const header = context.req.header("Authorization");
    if (header !== `Bearer ${token}`) {
      return context.json({ error: "Unauthorized." }, 401);
    }

    return next();
  };
}
