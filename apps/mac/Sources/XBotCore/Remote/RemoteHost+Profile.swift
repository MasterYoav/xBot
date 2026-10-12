import Foundation
import XBotBrain
import XBotRemote

/// The Profile page and plan usage for a phone.
extension RemoteHost {
    func answerProfile(_ request: UUID, refresh: Bool) async -> HostMessage {
        if refresh || workspace.history == nil { await workspace.indexHistory() }
        if refresh { await workspace.refreshCodexUsage() }
        let stats = workspace.history.map { history -> RemoteProfile.Stats in
            let numbers = ProfileStats(days: history.days, today: .now, calendar: .current)
            func counts(_ list: [NameCount], _ limit: Int = 8) -> [RemoteCount] {
                list.prefix(limit).map { RemoteCount(name: $0.name, count: $0.count) }
            }
            return RemoteProfile.Stats(
                days: history.days, lifetime: numbers.lifetime, peak: numbers.peak,
                longestStreak: numbers.longestStreak, currentStreak: numbers.currentStreak,
                tokensByAgent: Dictionary(uniqueKeysWithValues: history.tokensByAgent.map { ($0.key.rawValue, $0.value) }),
                tasksByAgent: Dictionary(uniqueKeysWithValues: history.tasksByAgent.map { ($0.key.rawValue, $0.value) }),
                longestTask: history.longestTask, tools: counts(history.tools), skills: counts(history.skills),
                efforts: counts(history.efforts),
                projects: history.projects.sorted { $0.tokens > $1.tokens }.prefix(6)
                    .map { RemoteCount(name: ($0.path as NSString).lastPathComponent, count: $0.tokens) },
                planRuns: workspace.planRunCount)
        }
        let usage = workspace.usage.values.sorted { $0.agent.rawValue < $1.agent.rawValue }.map {
            RemoteUsage(agent: $0.agent.rawValue, plan: $0.limits.plan, fiveHourUsed: $0.limits.fiveHour?.usedPercent,
                        fiveHourResets: $0.limits.fiveHour?.resetsAt, weeklyUsed: $0.limits.weekly?.usedPercent,
                        weeklyResets: $0.limits.weekly?.resetsAt, updatedAt: $0.updatedAt)
        }
        // The name and picture the Mac's Profile uses (kept by XBotUI's Identity).
        let full = NSFullUserName()
        let name = UserDefaults.standard.string(forKey: "profile.name") ?? (full.isEmpty ? NSUserName() : full)
        let picture = try? Data(contentsOf: Store.supportDirectory.appending(path: "profile.png"))
        return .profile(requestID: request, profile: RemoteProfile(name: name, username: NSUserName(), picture: picture,
                                                                    stats: stats, usage: usage))
    }
}
