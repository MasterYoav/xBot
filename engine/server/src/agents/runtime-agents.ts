import { and, eq, isNotNull, isNull, or } from "drizzle-orm";
import { type RegisteredAgent, registeredAgentFromRow } from "../copilot";
import { modelKeyId } from "../../../shared/model-selection";
import {
  type CredentialSecretReader,
  type CredentialStore,
  decryptSecret,
} from "../credentials";
import type { Database } from "../db/client";
import {
  agentProfiles,
  agents,
  channelAgents,
  channelMemberships,
} from "../db/schema";
import { agentAuthHeaders, authFromConfiguration } from "./auth-header";
import type { AgentActor } from "./profile-types";

/**
 * Read the agents one person may run, on every request.
 *
 * The filtering is in the query, not in JavaScript afterwards: a private coworker must never be
 * read into the process for an actor who cannot see it, and "we fetched it but did not show it" is
 * the shape most accidental disclosures take.
 */
export function createRuntimeAgentLoader(
  database: Database,
  /** Resolves a customer agent's key at load time. Absent means no agent can carry one. */
  vault?: {
    reader: CredentialSecretReader;
    encryptionKey: string;
    /** Finds a model key by provider and address. Absent means no agent carries one. */
    store?: Pick<CredentialStore, "findLiveByKey">;
  },
  /** Secret for the deployment-managed Bot. Never sent to customer-owned endpoints. */
  managedAgent?: { endpoint: URL; token: string },
) {
  return async (actor: AgentActor): Promise<RegisteredAgent[]> => {
    const [active, tombstones] = await Promise.all([
      selectActiveAgents(database, actor),
      selectTombstoneAgents(database, actor),
    ]);

    // A row whose configuration cannot be understood is skipped rather than mounted as a broken
    // agent. Tombstones are appended after, and never overwrite a live agent of the same id.
    const registered = new Map<string, RegisteredAgent>();
    for (const row of active) {
      const agent = registeredAgentFromRow(row);
      if (!agent) continue;
      // The key is resolved per load, rather than being cached on the row: revoking a
      // credential then takes effect on the next run rather than on the next restart.
      if (agent.type === "remote_ag_ui" && vault) {
        const headers = await agentAuthHeaders({
          reader: vault.reader,
          encryptionKey: vault.encryptionKey,
          auth: authFromConfiguration(row.configuration),
        });
        if (headers) agent.headers = headers;
      }
      if (
        agent.type === "remote_ag_ui" &&
        managedAgent &&
        agent.endpoint === managedAgent.endpoint.toString()
      ) {
        agent.headers = {
          ...agent.headers,
          "x-openbot-agent-token": managedAgent.token,
        };
      }
      // The model key, beside the endpoint key and for the same reason: resolved per load, so a key
      // replaced or removed in the app is what the very next run uses.
      if (agent.type === "remote_ag_ui" && vault?.store) {
        const { store, reader, encryptionKey } = vault;
        await attachModelKey(agent, async (providerId, baseURL) => {
          const live = await store.findLiveByKey({
            kind: "model",
            provider: providerId,
            keyId: modelKeyId(providerId, baseURL),
          });
          if (!live) return undefined;
          const secret = await reader.readSecret(live.id);
          if (!secret || secret.revokedAt) return undefined;
          return decryptSecret(encryptionKey, secret.encryptedValue);
        });
      }
      registered.set(agent.id, agent);
    }
    for (const row of tombstones) {
      if (registered.has(row.id)) continue;
      registered.set(row.id, {
        id: row.id,
        name: row.name,
        type: "unavailable",
        reason: `${row.name} has been deleted and can no longer run. Its conversations remain readable.`,
      });
    }

    return [...registered.values()];
  };
}

function selectActiveAgents(database: Database, actor: AgentActor) {
  return database
    .select({
      id: agents.id,
      name: agents.name,
      type: agents.type,
      configuration: agents.configuration,
      title: agentProfiles.title,
      roleDescription: agentProfiles.roleDescription,
    })
    .from(agents)
    .innerJoin(agentProfiles, eq(agentProfiles.agentId, agents.id))
    .where(
      and(
        isNull(agentProfiles.deletedAt),
        actor.role === "admin"
          ? undefined
          : or(
              eq(agentProfiles.visibility, "public"),
              eq(agentProfiles.ownerUserId, actor.id),
            ),
      ),
    );
}

/**
 * Deleted coworkers the caller still has history with.
 *
 * Registered so Intelligence can restore the thread the person is reading. Membership of a channel
 * the agent worked in is what authorizes this, not the profile's visibility, which is why deleting
 * a coworker leaves its conversations readable instead of erasing them.
 */
function selectTombstoneAgents(database: Database, actor: AgentActor) {
  return database
    .selectDistinct({ id: agents.id, name: agents.name })
    .from(agents)
    .innerJoin(agentProfiles, eq(agentProfiles.agentId, agents.id))
    .innerJoin(channelAgents, eq(channelAgents.agentId, agents.id))
    .innerJoin(
      channelMemberships,
      and(
        eq(channelMemberships.channelId, channelAgents.channelId),
        eq(channelMemberships.userId, actor.id),
      ),
    )
    .where(isNotNull(agentProfiles.deletedAt));
}

/**
 * Put the vault's key for this agent's model onto its selection, when the selection has none.
 *
 * ADR-0002: the model is the agent's, the key is the vault's, and the two meet per run. `copilot.ts`
 * forwards `modelSelection` to the Bot as it is, so a selection that leaves here carrying its key is
 * all it takes for the Bot to answer on it — and `publishableSelection` strips the key before any
 * surface can read it back. Without this nothing put a key there at all: the app held the key in the
 * Keychain, the vault could hold it too, and the run reached the vendor with neither.
 *
 * A key already on the selection wins — that is a key somebody set for this agent specifically. A
 * lookup that finds nothing leaves the selection alone, so the Bot answers with the registry's own
 * sentence about the missing key rather than a failure from here.
 */
export async function attachModelKey(
  agent: RegisteredAgent,
  resolve: (
    providerId: string,
    baseURL?: string,
  ) => Promise<string | undefined>,
): Promise<void> {
  if (agent.type !== "remote_ag_ui") return;
  const selection = agent.modelSelection;
  if (!selection?.providerId || selection.apiKey) return;
  const key = await resolve(selection.providerId, selection.baseURL);
  if (key) agent.modelSelection = { ...selection, apiKey: key };
}
