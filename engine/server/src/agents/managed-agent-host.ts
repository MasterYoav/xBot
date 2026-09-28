/**
 * The addresses every run may dial: the ones the deployment named, plus its own Bot's.
 *
 * The one-container image runs the Bot beside the API at a loopback address, which the
 * private-address guard in `endpoint.ts` refuses — correctly, for an address a person typed. This
 * one came from the deployment's own configuration (`MANAGED_AGENT_AG_UI_URL`), which is exactly
 * what `allowedHosts` exists for. Host and port together, so the rest of loopback — the database,
 * the computer — stays refused. Compose never needed this: there the Bot is a service name, which is
 * not a private literal.
 *
 * Dialling only. Registration keeps the named list alone, so nobody can register an agent at the
 * managed Bot's address by way of this.
 */
export function dialableHosts(
  named: ReadonlySet<string>,
  managedAgent: { endpoint: URL } | undefined,
): ReadonlySet<string> {
  if (!managedAgent) return named;
  return new Set([...named, managedAgent.endpoint.host]);
}
