import Foundation
import Testing
import XBotBrain
@testable import XBotCore

@MainActor @Suite struct StoreTests {
    let store = Store.inMemory()

    func chat(project: UUID? = nil) -> Chat {
        Chat(id: UUID(), projectID: project, title: "New chat", harness: .claude, model: nil,
             mode: .editFiles, sessionID: nil, createdAt: .now, updatedAt: .now)
    }

    @Test func projectsRoundTrip() throws {
        let project = Project(id: UUID(), name: "site", path: "/tmp/site", createdAt: .now)
        try store.save(project)
        #expect(try store.projects().map(\.path) == ["/tmp/site"])
    }

    @Test func messagesKeepTheirOrderAndParts() throws {
        let c = chat(); try store.save(c)
        let first = ChatMessage(id: UUID(), chatID: c.id, role: .user, parts: [.text("hi")], createdAt: .now)
        let second = ChatMessage(id: UUID(), chatID: c.id, role: .assistant, parts: [
            .text("hello"), .tool(ToolPart(id: "t", name: "Read", summary: "a", output: nil, isError: false)),
        ], createdAt: first.createdAt)
        try store.append(first); try store.append(second)
        #expect(try store.messages(in: c.id) == [first, second])
    }

    /// An upsert written as INSERT OR REPLACE deletes the row first, and the cascade would take
    /// every message in the chat with it.
    @Test func savingAChatAgainKeepsItsMessages() throws {
        var c = chat(); try store.save(c)
        try store.append(ChatMessage(id: UUID(), chatID: c.id, role: .user, parts: [.text("x")], createdAt: .now))
        c.sessionID = "s1"; c.title = "Renamed"
        try store.save(c)
        #expect(try store.messages(in: c.id).count == 1)
        #expect(try store.chats().first?.sessionID == "s1")
    }

    @Test func deletingAProjectDeletesItsChats() throws {
        let project = Project(id: UUID(), name: "p", path: "/tmp/p", createdAt: .now)
        try store.save(project)
        try store.save(chat(project: project.id))
        try store.save(chat())
        try store.deleteProject(project.id)
        #expect(try store.chats().count == 1)
    }

    @Test func chatsAreNewestFirst() throws {
        var old = chat(); old.updatedAt = .distantPast
        let new = chat()
        try store.save(old); try store.save(new)
        #expect(try store.chats().map(\.id) == [new.id, old.id])
    }

    @Test func survivesReopening() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/x.sqlite")
        let c = chat()
        do { let s = try Store(database: Database(url: url)); try s.save(c) }
        let reopened = try Store(database: Database(url: url))
        #expect(try reopened.chats().map(\.id) == [c.id])
    }
}
