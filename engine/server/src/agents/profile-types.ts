import type { ModelSelection } from "../../../shared/model-selection";

export type AgentVisibility = "public" | "private";

export type AgentActor = {
  id: string;
  role: "admin" | "user";
};

export type AgentProfile = {
  id: string;
  name: string;
  title: string;
  roleDescription: string;
  avatarSeed: string;
  visibility: AgentVisibility;
  ownerUserId: string | null;
  systemOwned: boolean;
  hidden: boolean;
  deletedAt: Date | null;
  /** Where this coworker runs. Null for the Bot in the box. */
  endpoint: string | null;
  /** Whether a key is set for it. Never the key. */
  hasAuth: boolean;
  /**
   * Which model this coworker answers on, or undefined if it never chose.
   *
   * Read back so the settings pane can show what is stored — without it a person picks a model,
   * the agent answers on it, and the pane says "Not set" again on the next load.
   *
   * **Never carries a key.** The selection can hold one on the way in; it is stripped on the way
   * out, because this profile is published by `GET /api/agents` to every surface there is.
   */
  modelSelection?: ModelSelection;
  /**
   * Whether this agent holds a credential for calling tools back.
   *
   * A boolean, never the token: the token exists in a readable form once, in the response that issued
   * it. A surface only needs to know whether to offer "generate" or "rotate".
   */
  hasCallbackToken: boolean;
};

export type CreateAgentInput = Pick<
  AgentProfile,
  "name" | "title" | "roleDescription" | "visibility"
> & {
  /**
   * The AG-UI endpoint this Bot runs on, or undefined for the one in the box.
   *
   * This field is the AG-UI endpoint for a customer-provided agent. Without it the Bot runs on the
   * built-in endpoint.
   */
  endpoint?: string;
  /**
   * A key this agent sits behind, if any.
   *
   * Write-only. It goes to the vault and is never read back to a person: the edit form shows that a
   * key is set, not what it is. Absent on an update means "leave whatever is there alone", which is
   * why it is optional rather than defaulting to empty; a blank field must not drop a key.
   */
  auth?: { header: string; value: string };
  /**
   * Which model this coworker answers on, if it was given one of its own.
   *
   * Undefined means it never chose, and the endpoint answers on whatever its deployment is
   * configured for. Stored in `configuration` alongside `endpoint` rather than in a column of its
   * own: that field is already this agent type's open shape, so per-agent model choice costs no
   * migration and leaves no upstream merge conflict.
   */
  modelSelection?: ModelSelection;
};
