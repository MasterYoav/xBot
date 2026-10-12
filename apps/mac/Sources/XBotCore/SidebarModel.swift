import Foundation

/// What the sidebar shows: projects with their newest chats, and Recent — all narrowed
/// by the search field. Worked out here so the view only draws it.
public struct SidebarModel: Equatable, Sendable {
    public struct Group: Equatable, Sendable, Identifiable {
        public var project: Project
        /// Newest first; at most `chatsPerProject` unless the project is expanded.
        public var chats: [Chat]
        /// Chats in this project not shown.
        public var hidden: Int
        public var isRunning: Bool
        public var id: UUID { project.id }
    }

    public static let chatsPerProject = 5
    public static let recentCount = 5

    public var groups: [Group]
    /// Chats without a project, newest first; at most `recentCount` unless `showsAllRecent`.
    public var recent: [Chat]
    public var hiddenRecent: Int

    public init(
        projects: [Project], chats: [Chat], running: Set<UUID>, query: String = "", expanded: Set<UUID> = [],
        showsAllRecent: Bool = false
    ) {
        let needle = query.trimmingCharacters(in: .whitespaces)
        // An automation's or a workflow's runs are its history, on its page, not the sidebar's.
        let shown = chats
            .filter { $0.automationID == nil && $0.workflowID == nil }
            .filter { needle.isEmpty || $0.title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .sorted { $0.updatedAt > $1.updatedAt }
        groups = projects.compactMap { project in
            let mine = shown.filter { $0.projectID == project.id }
            if !needle.isEmpty && mine.isEmpty { return nil }
            let limit = expanded.contains(project.id) ? mine.count : Self.chatsPerProject
            return Group(
                project: project,
                chats: Array(mine.prefix(limit)),
                hidden: max(0, mine.count - limit),
                isRunning: chats.contains { $0.projectID == project.id && running.contains($0.id) }
            )
        }
        let loose = shown.filter { $0.projectID == nil }
        let limit = showsAllRecent || !needle.isEmpty ? loose.count : Self.recentCount
        recent = Array(loose.prefix(limit))
        hiddenRecent = max(0, loose.count - limit)
    }
}
