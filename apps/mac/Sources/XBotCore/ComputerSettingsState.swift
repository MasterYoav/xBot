import Foundation
import Observation
import XBotEngine

/// Settings → Computer: deployment-wide browser action policy.
@MainActor
@Observable
public final class ComputerSettingsState {
    public private(set) var policy: ActionPolicy?
    public private(set) var problem: String?
    public private(set) var isLoading = false
    public private(set) var isSaving = false

    public init() {}

    public func load(fetch: () async throws -> ActionPolicy) async {
        isLoading = true
        problem = nil
        defer { isLoading = false }
        do {
            policy = try await fetch()
        } catch {
            policy = nil
            problem = String(localized: "The engine isn't running, so the rules couldn't be loaded.")
        }
    }

    public func setAutoReview(_ enabled: Bool, persist: (ActionPolicy) async throws -> ActionPolicy) async {
        guard var current = policy else { return }
        current.mode = enabled ? .enforce : .dryRun
        await save(current, persist: persist)
    }

    public func isPresetEnabled(_ preset: ComputerPolicyPreset) -> Bool {
        policy?.deny.contains(preset.rule) ?? false
    }

    public func setPreset(
        _ preset: ComputerPolicyPreset,
        enabled: Bool,
        persist: (ActionPolicy) async throws -> ActionPolicy
    ) async {
        guard var current = policy else { return }
        if enabled {
            guard !current.deny.contains(preset.rule) else { return }
            current.deny.append(preset.rule)
        } else {
            current.deny.removeAll { $0 == preset.rule }
        }
        await save(current, persist: persist)
    }

    private func save(
        _ next: ActionPolicy,
        persist: (ActionPolicy) async throws -> ActionPolicy
    ) async {
        isSaving = true
        problem = nil
        defer { isSaving = false }
        do {
            policy = try await persist(next)
        } catch {
            problem = String(localized: "Those rules couldn't be saved. The previous boundary is still in force.")
        }
    }
}
