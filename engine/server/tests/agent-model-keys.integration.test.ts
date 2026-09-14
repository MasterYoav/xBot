import { afterAll, afterEach, describe, expect, test } from "bun:test";
import { randomUUID } from "node:crypto";
import { eq, like } from "drizzle-orm";
import { modelKeyId } from "../../shared/model-selection";
import { createAgentProfileStore } from "../src/agents/profile-store";
import type { AgentActor } from "../src/agents/profile-types";
import { createRuntimeAgentLoader } from "../src/agents/runtime-agents";
import {
  createCredential,
  createCredentialStore,
  revokeCredential,
} from "../src/credentials";
import { createDatabase } from "../src/db/client";
import { agentProfiles, agents, credentials, users } from "../src/db/schema";
import { TEST_POOL } from "./support/database";

/*
 * The vault meeting the loader, against a real database.
 *
 * The unit tests pin `attachModelKey` with a fake lookup. This is the glue they cannot reach:
 * `findLiveByKey`, `readSecret` and `decryptSecret` together, on rows the credential service really
 * wrote — which is what every run of every agent in the Mac app now depends on.
 */
const databaseUrl =
  process.env.DATABASE_URL ??
  "postgres://openbot:openbot@localhost:5432/openbot";
const database = createDatabase(databaseUrl, TEST_POOL);
const encryptionKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
const store = createCredentialStore(database);
const managedEndpoint = new URL("http://127.0.0.1:4201/ag-ui");
const profileStore = createAgentProfileStore(database, managedEndpoint);
const loadAgents = createRuntimeAgentLoader(
  database,
  { reader: store, encryptionKey, store },
  { endpoint: managedEndpoint, token: "managed-token" },
);
const service = {
  encryptionKey,
  store,
  auditStore: { insert: async () => undefined },
};

const prefix = `model-keys-${randomUUID()}`;
const createdUserIds: string[] = [];
const createdAgentIds: string[] = [];

/** A provider name unique to this file, so the cleanup cannot touch anybody else's rows. */
const provider = `${prefix}-anthropic`;

afterEach(async () => {
  await database
    .delete(credentials)
    .where(like(credentials.provider, `${prefix}%`));
  for (const id of createdAgentIds.splice(0)) {
    await database.delete(agentProfiles).where(eq(agentProfiles.agentId, id));
    await database.delete(agents).where(eq(agents.id, id));
  }
  for (const id of createdUserIds.splice(0)) {
    await database.delete(users).where(eq(users.id, id));
  }
});

afterAll(async () => {
  await database.$client.close();
});

async function owner(): Promise<AgentActor> {
  const id = `${prefix}-user-${randomUUID()}`;
  await database
    .insert(users)
    .values({ id, email: `${id}@example.test`, name: "Key test" });
  createdUserIds.push(id);
  return { id, role: "user" };
}

async function agentOn(actor: AgentActor, baseURL?: string, endpoint?: string) {
  const profile = await profileStore.create(actor, {
    ...(endpoint ? { endpoint } : {}),
    name: "Keyed",
    title: "Keyed",
    roleDescription: "Keyed",
    visibility: "private",
    modelSelection: {
      providerId: provider,
      model: "claude-sonnet-4-5",
      ...(baseURL ? { baseURL } : {}),
    },
  });
  createdAgentIds.push(profile.id);
  return profile;
}

function keyOf(loaded: Awaited<ReturnType<typeof loadAgents>>, id: string) {
  const agent = loaded.find((candidate) => candidate.id === id) as
    | { modelSelection?: { apiKey?: string } }
    | undefined;
  return agent?.modelSelection?.apiKey;
}

function modelKey(actor: AgentActor, plaintext: string, baseURL?: string) {
  return {
    kind: "model" as const,
    provider,
    keyId: modelKeyId(provider, baseURL),
    plaintext,
    metadata: {},
    actorUserId: actor.id,
  };
}

describe("model keys from the vault, on a real database", () => {
  test("a customer endpoint never receives the deployment's model key", async () => {
    const actor = await owner();
    const agent = await agentOn(
      actor,
      undefined,
      "https://agent.example/ag-ui",
    );
    await createCredential(service, modelKey(actor, "private-deployment-key"));
    expect(keyOf(await loadAgents(actor), agent.id)).toBeUndefined();
  });

  test("a stored key arrives on the agent's selection, decrypted", async () => {
    const actor = await owner();
    const agent = await agentOn(actor);
    await createCredential(service, modelKey(actor, "sk-ant-from-the-vault"));

    expect(keyOf(await loadAgents(actor), agent.id)).toBe(
      "sk-ant-from-the-vault",
    );
  });

  test("a replaced key is what the very next load carries", async () => {
    const actor = await owner();
    const agent = await agentOn(actor);
    await createCredential(service, modelKey(actor, "first"));
    await createCredential(service, modelKey(actor, "second"));

    expect(keyOf(await loadAgents(actor), agent.id)).toBe("second");
  });

  test("a revoked key is not carried", async () => {
    const actor = await owner();
    const agent = await agentOn(actor);
    const stored = await createCredential(
      service,
      modelKey(actor, "about-to-go"),
    );
    await revokeCredential(service, stored.id, actor.id);

    expect(keyOf(await loadAgents(actor), agent.id)).toBeUndefined();
  });

  test("a key for another address is not borrowed", async () => {
    const actor = await owner();
    const agent = await agentOn(actor, "https://gateway.example.test/v1");
    await createCredential(
      service,
      modelKey(
        actor,
        "for-somewhere-else",
        "https://openrouter.example.test/v1",
      ),
    );

    expect(keyOf(await loadAgents(actor), agent.id)).toBeUndefined();
  });
});
