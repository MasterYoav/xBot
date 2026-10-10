import Foundation
import XBotBrain

/// The Abilities and Notes pages, which took Home's place in the sidebar.
extension Workspace {
    func makeAbilities() -> AbilityCatalog {
        let catalog = AbilityCatalog(
            tools: { [weak self] in
                guard let self else { return [:] }
                var tools: [HarnessKind: AbilityCatalog.Tool] = [:]
                for (kind, brain) in self.brains {
                    if let harness = brain as? HarnessBrain {
                        tools[kind] = .init(executable: harness.executable, environment: harness.environment)
                    }
                }
                return tools
            },
            project: { [weak self] in self?.contextProject?.url }
        )
        catalog.report = { [weak self] text in self?.toasts.show(text) }
        return catalog
    }

    public func showAbilities() { page = .abilities }

    /// Notes for a project; nil keeps the one already shown.
    public func showNotes(for projectID: UUID? = nil) {
        if let projectID { notesProjectID = projectID }
        page = .notes
    }

    /// The project on the Notes page: the one chosen there, else the one in context, else the first.
    public var notesProject: Project? {
        notesProjectID.flatMap { id in projects.first { $0.id == id } } ?? contextProject ?? projects.first
    }

    /// One notes model per project, kept while the app runs so an unsaved edit survives switching.
    public func notes(for project: Project) -> ProjectNotes {
        if let notes = projectNotes[project.id], notes.folder == project.url { return notes }
        let notes = ProjectNotes(folder: project.url)
        notes.reload()
        projectNotes[project.id] = notes
        return notes
    }
}
