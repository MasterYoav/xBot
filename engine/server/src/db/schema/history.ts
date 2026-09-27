import { pgTable, text, timestamp } from "drizzle-orm/pg-core";
// NOT drizzle's `jsonb`; see ./json.ts.
import { jsonb } from "./json";

/**
 * Conversations kept by this deployment rather than by CopilotKit Intelligence (ADR-0008).
 *
 * One row per thread, holding its AG-UI messages in order. Written by `LocalThreadRunner` when a run
 * ends and read back into memory at boot. No user column: local history runs only in single-user
 * mode, where there is one person to scope to.
 */
export const localThreads = pgTable("local_threads", {
  threadId: text("thread_id").primaryKey(),
  agentId: text("agent_id").notNull(),
  /** `{ messages: Message[] }` — an object because the column type is. */
  messages: jsonb("messages").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});
