import type { CopilotKitIntelligence } from "@copilotkit/runtime/v2";

/**
 * The platform client, answered locally instead of by CopilotKit Intelligence.
 *
 * SPIKE. Nothing here stores anything yet. Every method records that it was reached and then
 * throws, except the handful that are called at wiring time and whose return value is used
 * synchronously — those answer with a local placeholder so the process can finish booting.
 *
 * The point is enumeration. `CopilotRuntime` calls 30 of this client's 36 members somewhere in
 * `@copilotkit/runtime` 1.69.0, but xBot's configuration does not enter every path that leads to
 * them: no Slack or Teams assets, no enterprise learning, no hosted inspector. Booting against
 * this and driving a conversation prints the methods xBot actually depends on, and that set — not
 * the vendor's full surface — is the work list for `LocalHistoryProvider` (ADR-0001).
 *
 * A `Proxy` over a bare object rather than a subclass, and only because nothing forwards. The
 * comment on `IntelligenceKnowingANewThread` in `copilot.ts` records why a forwarding proxy cannot
 * work: the base class keeps its state in `#private` fields, which a method invoked with the proxy
 * as `this` cannot reach. That constraint binds a wrapper that delegates. This one never delegates,
 * so it never reaches for a private field, and it does not inherit 36 members it would have to
 * override one at a time to be sure it had covered them. When the real provider lands it should be
 * a class implementing the surface this spike proves is needed.
 */
export function createLocalIntelligence(options: {
  /** Where the deployment serves its own API. Handed back in place of the platform's addresses. */
  selfUrl: string;
  /** Called once per distinct method reached, for the enumeration this spike exists to produce. */
  onReached?: (method: string) => void;
}): CopilotKitIntelligence {
  const { selfUrl, onReached } = options;
  const wsUrl = selfUrl.replace(/^http/, "ws");
  const reached = new Set<string>();

  // Answered rather than thrown: each is called while the process is still wiring itself up and
  // its result is used synchronously, so throwing here would end the boot before the request paths
  // this spike exists to observe have run even once.
  const atWiringTime: Record<string, () => unknown> = {
    ɵgetApiUrl: () => selfUrl,
    ɵgetClientWsUrl: () => `${wsUrl}/ws/client`,
    ɵgetChannelsWsUrl: () => `${wsUrl}/ws/channels`,
    ɵgetRunnerWsUrl: () => `${wsUrl}/ws/runner`,
    ɵgetRunnerAuthToken: () => "local",
    ɵgetApiKey: () => "local",
    ɵisEnterpriseLearningEnabled: () => false,
    // Subscription registrations return their own unsubscribe. Registering nothing is honest: in
    // local mode there is no hosted stream to hear from, and the emitter that replaces it does not
    // exist yet.
    onThreadCreated: () => () => {},
    onThreadUpdated: () => () => {},
    onThreadDeleted: () => () => {},
  };

  return new Proxy({} as CopilotKitIntelligence, {
    get(_target, property) {
      // Anything that probes for a thenable must not be handed a function, or an `await` on this
      // object would call it and hang waiting to be resolved.
      if (typeof property !== "string" || property === "then") return undefined;

      return (...args: unknown[]) => {
        if (!reached.has(property)) {
          reached.add(property);
          onReached?.(property);
          console.info(
            JSON.stringify({
              type: "local-intelligence-reached",
              method: property,
            }),
          );
        }
        const answer = atWiringTime[property];
        if (answer) return answer();
        throw new Error(
          `Local history is not implemented yet: CopilotKitIntelligence.${property} (${args.length} argument(s)). See docs/decisions/0001-local-history-provider.md.`,
        );
      };
    },
  });
}
