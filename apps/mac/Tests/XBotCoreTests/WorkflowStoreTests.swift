import Foundation
import Testing
import XBotBrain
@testable import XBotCore

@MainActor @Suite struct WorkflowStoreTests {
    func sample(projectID: UUID? = nil) -> Workflow {
        let fix = WorkflowStep(title: "Fix", kind: .agent(AgentStep(prompt: "Fix the build", brain: .fixed(BrainChoice(harness: .codex, model: "gpt-5", effort: .high)))))
        return Workflow(
            name: "Nightly", trigger: .schedule(.daily(hour: 2, minute: 30)),
            steps: [
                WorkflowStep(title: "Build", kind: .agent(AgentStep(prompt: "Build it", mode: .readOnly))),
                WorkflowStep(title: "Failing?", kind: .jev(JevStep(question: "Is the build failing?", decision: .gate(JevGate(threshold: 0.6, yes: .step(fix.id)))))),
                fix,
            ],
            harness: .claude, model: "sonnet", effort: .medium, projectID: projectID, isEnabled: false, sortIndex: 3
        )
    }

    @Test func everythingRoundTrips() throws {
        let store = Store.inMemory()
        let project = Project(name: "p", path: "/tmp/p")
        try store.save(project)
        let w = sample(projectID: project.id)
        try store.save(w)
        #expect(try store.workflows() == [w])
        var edited = w
        edited.name = "Renamed"
        edited.trigger = .manual
        edited.steps.removeFirst()
        try store.save(edited)
        #expect(try store.workflows() == [edited])
    }

    @Test func aRunChatRemembersItsWorkflowAndJevChoosing() throws {
        let store = Store.inMemory()
        let w = sample()
        try store.save(w)
        let chat = Chat(projectID: nil, title: "run", harness: .claude, mode: .editFiles, workflowID: w.id, jevChooses: true)
        try store.save(chat)
        let back = try #require(try store.chats().first)
        #expect(back.workflowID == w.id)
        #expect(back.jevChooses)
    }

    @Test func aClaimHappensOnce() throws {
        let store = Store.inMemory()
        let w = sample()
        try store.save(w)
        let now = Date.now
        #expect(try store.claimWorkflow(w.id, expected: nil, at: now))
        #expect(try !store.claimWorkflow(w.id, expected: nil, at: now))
        try store.save(w)   // the editor's copy, lastRunAt nil
        #expect(try store.workflows().first?.lastRunAt == now)
    }

    @Test func deletingAWorkflowKeepsItsRunsAsPlainChats() throws {
        let store = Store.inMemory()
        let w = sample()
        try store.save(w)
        try store.save(Chat(projectID: nil, title: "run", harness: .claude, mode: .editFiles, workflowID: w.id))
        try store.deleteWorkflow(w.id)
        #expect(try store.workflows().isEmpty)
        #expect(try store.chats().first?.workflowID == nil)
    }

    @Test func anUnreadableStepLosesOnlyItself() throws {
        let db = try Database()
        let store = try Store(database: db)
        let w = sample()
        try store.save(w)
        let good = String(decoding: try JSONEncoder().encode(w.steps[0]), as: UTF8.self)
        try db.execute("UPDATE workflows SET steps = ?", [.text("[{\"id\":\"x\",\"kind\":{\"hologram\":{}}}, \(good)]")])
        #expect(try store.workflows().first?.steps == [w.steps[0]])
    }

    @Test func aLibraryFromSchemaSixMigrates() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/x.sqlite")
        let id = UUID()
        do {
            let old = try Store(database: Database(url: url))
            try old.save(Chat(id: id, projectID: nil, title: "Old", harness: .claude, mode: .editFiles))
        }
        do {
            // Back to how v6 left it: no workflows table, no chats.workflow_id or jev_chooses.
            let db = try Database(url: url)
            try db.execute("DROP TABLE workflows")
            try db.execute("ALTER TABLE chats DROP COLUMN workflow_id")
            try db.execute("ALTER TABLE chats DROP COLUMN jev_chooses")
            try db.execute("PRAGMA user_version = 6")
        }
        let store = try Store(database: Database(url: url))
        let chat = try #require(try store.chats().first)
        #expect(chat.id == id && chat.workflowID == nil && !chat.jevChooses)
        #expect(try store.workflows().isEmpty)
        try store.save(sample())
        #expect(try store.workflows().count == 1)
        // Opening again does not try to add the columns twice.
        _ = try Store(database: Database(url: url))
    }
}
