import journal from "../../drizzle/meta/_journal.json" with { type: "json" };

/** What `/health` returns when the Mac app owns this deployment (M3). */
export type XBotHealth = {
  status: "ok";
  product: "xBot";
  engineVersion: string;
  schemaVersion: string;
};

const schemaVersion = journal.entries.at(-1)?.tag ?? "unknown";

/**
 * Identifies this process as xBot's engine, with version metadata the app can show in diagnostics.
 *
 * Lives in a new file rather than editing upstream's health handler inline, so merges stay clean.
 */
export function xbotHealthPayload(
  engineVersion = process.env.XBOT_ENGINE_VERSION ?? "0.0.5",
): XBotHealth {
  return {
    status: "ok",
    product: "xBot",
    engineVersion,
    schemaVersion,
  };
}
