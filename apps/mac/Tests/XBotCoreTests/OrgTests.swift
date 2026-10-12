import Foundation
import Testing
import XBotBrain
@testable import XBotCore

/// Who reports to whom: stored, told to each agent, and followed by hand-offs.
@MainActor @Suite(.serialized) struct OrgTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")

    func workspace(_ brain: ScriptedBrain, store: Store = .inMemory()) async -> Workspace {
        let w = Workspace(store: store, inbox: inbox, discover: { [.claude: brain] })
        await w.refreshHarnesses()
        return w
    }

    func settle(_ w: Workspace) async {
        for _ in 0..<400 where !w.turns.isEmpty { await Task.yield() }
    }

    func hireCTO(_ w: Workspace) -> Agent {
        var cto = w.hire()
        cto.name = "Nova"
        cto.role = "CTO"
        cto.managerID = w.headMaster?.id
        w.saveAgent(cto)
        return cto
    }

    @Test func managersAreStoredAndSurviveAnOldDatabase() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "org-\(UUID().uuidString).sqlite")
        let first = await workspace(ScriptedBrain([.done]), store: try Store(database: Database(url: url)))
        let cto = hireCTO(first)
        var forge = try #require(first.agents.first { $0.name == "Forge" })
        forge.managerID = cto.id
        first.saveAgent(forge)
        let again = try Store(database: Database(url: url)).agents()
        #expect(again.first { $0.name == "Forge" }?.managerID == cto.id)
        #expect(again.first { $0.name == "Nova" }?.managerID == first.headMaster?.id)
        #expect(again.first(where: \.isHeadMaster)?.managerID == nil)
    }

    @Test func headMasterReportsToThePersonAndCannotGetAManager() async throws {
        let w = await workspace(ScriptedBrain([.done]))
        let cto = hireCTO(w)
        var head = try #require(w.headMaster)
        head.managerID = cto.id
        w.saveAgent(head)
        #expect(w.headMaster?.managerID == nil)
    }

    @Test func aLoopIsRefused() async throws {
        let w = await workspace(ScriptedBrain([.done]))
        let cto = hireCTO(w)
        var forge = try #require(w.agents.first { $0.name == "Forge" })
        forge.managerID = cto.id
        w.saveAgent(forge)
        var looped = try #require(w.agent(cto.id))
        looped.managerID = forge.id
        w.saveAgent(looped)
        // Nova keeps reporting to HeadMaster.
        #expect(w.agent(cto.id)?.managerID == w.headMaster?.id)
    }

    @Test func organisingFollowsWhatCompaniesDo() async throws {
        let w = await workspace(ScriptedBrain([.done]))
        let cto = hireCTO(w)
        w.organiseLikeACompany()
        let forge = try #require(w.agents.first { $0.name == "Forge" })   // Builder
        let hawk = try #require(w.agents.first { $0.name == "Hawk" })     // Reviewer
        let quill = try #require(w.agents.first { $0.name == "Quill" })   // Scribe
        #expect(forge.managerID == cto.id && hawk.managerID == cto.id)
        #expect(quill.managerID == w.headMaster?.id)
        #expect(w.agent(cto.id)?.managerID == w.headMaster?.id)
    }

    @Test func lettingAManagerGoMovesTheirTeamUpAndUndoPutsItBack() async throws {
        let w = await workspace(ScriptedBrain([.done]))
        let cto = hireCTO(w)
        w.organiseLikeACompany()
        let undo = try #require(w.deleteAgent(cto.id))
        let forge = try #require(w.agents.first { $0.name == "Forge" })
        #expect(forge.managerID == w.headMaster?.id)
        undo()
        #expect(w.agents.first { $0.name == "Forge" }?.managerID == cto.id)
    }

    @Test func everyoneIsToldWhoTheyReportToAndWhoIsOnTheirTeam() async throws {
        let brain = ScriptedBrain([.textDelta("ok"), .done])
        let w = await workspace(brain)
        let cto = hireCTO(w)
        w.organiseLikeACompany()
        let forge = try #require(w.agents.first { $0.name == "Forge" })
        let forgeChat = try #require(w.talk(to: forge.id))
        _ = w.send("go", in: forgeChat.id)
        await settle(w)
        let forgeSees = try #require(brain.requests.withLock { $0.last?.instructions })
        #expect(forgeSees.contains("You report to Nova"))
        #expect(!forgeSees.contains("```handoff"))

        let ctoChat = try #require(w.talk(to: cto.id))
        _ = w.send("go", in: ctoChat.id)
        await settle(w)
        let ctoSees = try #require(brain.requests.withLock { $0.last?.instructions })
        #expect(ctoSees.contains("You report to HeadMaster"))
        #expect(ctoSees.contains("```handoff") && ctoSees.contains("Forge") && ctoSees.contains("Hawk"))

        let head = try #require(w.headMaster)
        let headChat = try #require(w.talk(to: head.id))
        _ = w.send("go", in: headChat.id)
        await settle(w)
        let headSees = try #require(brain.requests.withLock { $0.last?.instructions })
        #expect(headSees.contains("You report to the person"))
    }

    /// A manager hands work to their own team; it reports back to the manager's chat.
    @Test func managersHandOffToTheirTeamOnly() async throws {
        let reply = "```handoff\nto: Forge\ntask: Build it.\n```\n```handoff\nto: Quill\ntask: Not yours.\n```"
        let brain = ScriptedBrain([.textDelta(reply), .done])
        let w = await workspace(brain)
        let cto = hireCTO(w)
        w.organiseLikeACompany()
        let chat = try #require(w.talk(to: cto.id))
        _ = w.send("Ship it", in: chat.id)
        await settle(w)
        let forge = try #require(w.agents.first { $0.name == "Forge" })
        let quill = try #require(w.agents.first { $0.name == "Quill" })
        #expect(w.chats.contains { $0.agentID == forge.id })
        #expect(!w.chats.contains { $0.agentID == quill.id })
        let notices = w.messages(in: chat.id).flatMap(\.parts).compactMap { part -> String? in
            if case .notice(let text) = part { text } else { nil }
        }
        #expect(notices.contains { $0.contains("Quill") && $0.contains("team") })
        // Forge's turn finished: the CTO's chat hears about it.
        #expect(notices.contains { $0.hasPrefix(Handoff.finishedPrefix(forge.name)) })
    }
}
