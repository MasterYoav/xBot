import Foundation
import Testing
import XBotBrain
@testable import XBotCore

@Suite struct AvatarTests {
    @Test func roundTripsAsJSON() throws {
        let avatar = AgentAvatar(skin: 2, hair: 3, hairColor: 4, eyes: 1, outfit: 2, outfitColor: 5, accessory: 1)
        let data = try JSONEncoder().encode(avatar)
        #expect(try JSONDecoder().decode(AgentAvatar.self, from: data) == avatar)
    }

    /// From a newer xBot with more parts, or an older one with fewer: never fatal.
    @Test func unknownAndMissingPartsAreTolerated() throws {
        let json = #"{"skin": 99, "hair": 1, "wings": 3}"#
        let avatar = try JSONDecoder().decode(AgentAvatar.self, from: Data(json.utf8))
        #expect(avatar.hair == 1)
        #expect((0..<AgentAvatar.Part.skin.count).contains(avatar.skin))
        #expect(avatar.eyes == 0)
    }

    @Test func steppingAPartWrapsAround() {
        var avatar = AgentAvatar()
        avatar.step(.hair, by: -1)
        #expect(avatar.hair == AgentAvatar.Part.hair.count - 1)
        avatar.step(.hair, by: 1)
        #expect(avatar.hair == 0)
    }

    @Test func randomAvatarsDiffer() {
        var rng = SystemRandomNumberGenerator()
        let avatars = Set((0..<20).map { _ in AgentAvatar.random(using: &rng) })
        #expect(avatars.count > 5)
    }
}

@Suite struct HandoffTests {
    @Test func readsEveryBlock() {
        let reply = """
            Plan: two parts.

            ```handoff
            to: Forge
            task: Add a dark mode toggle.
            Keep it small.
            ```

            ```handoff
            to: quill
            task: Note it in the release notes.
            ```
            """
        #expect(Handoff.all(in: reply) == [
            Handoff(to: "Forge", task: "Add a dark mode toggle.\nKeep it small."),
            Handoff(to: "quill", task: "Note it in the release notes."),
        ])
    }

    @Test func theBlocksAreLeftOutOfWhatIsShown() {
        let reply = "Splitting it.\n\n```handoff\nto: Forge\ntask: Build.\n```\n\nBack soon.\n```swift\nlet x = 1\n```"
        #expect(Handoff.stripping(reply) == "Splitting it.\n\nBack soon.\n```swift\nlet x = 1\n```")
    }

    @Test func ignoresOtherCodeAndEmptyTasks() {
        let reply = "```swift\nto: Forge\ntask: no\n```\n```handoff\nto: Forge\ntask:\n```"
        #expect(Handoff.all(in: reply).isEmpty)
    }
}

@Suite struct InstructionsArgumentTests {
    func request(_ instructions: String?) -> TurnRequest {
        TurnRequest(prompt: "x", directory: URL(filePath: "/tmp"), mode: .readOnly, instructions: instructions)
    }

    @Test func claudeAppendsThemToItsSystemPrompt() throws {
        let arguments = HarnessKind.claude.arguments(for: request("You are Forge.\nBuild things."))
        let index = try #require(arguments.firstIndex(of: "--append-system-prompt"))
        #expect(arguments[index + 1] == "You are Forge.\nBuild things.")
        #expect(!HarnessKind.claude.arguments(for: request(nil)).contains("--append-system-prompt"))
    }

    /// A TOML string: quotes, backslashes and newlines escaped, or Codex can't read it.
    @Test func codexGetsThemAsDeveloperInstructions() {
        let arguments = HarnessKind.codex.arguments(for: request("Say \"hi\"\\\nthen go"))
        #expect(arguments.contains(#"developer_instructions="Say \"hi\"\\\nthen go""#))
        #expect(arguments.last == "-")
        #expect(!HarnessKind.codex.arguments(for: request(nil)).contains { $0.hasPrefix("developer_instructions") })
    }
}

@MainActor @Suite struct AgentWorkspaceTests {
    let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)")

    func workspace(_ brain: ScriptedBrain, store: Store = .inMemory()) async -> Workspace {
        let w = Workspace(store: store, inbox: inbox, discover: { [.claude: brain] })
        await w.refreshHarnesses()
        return w
    }

    func settle(_ w: Workspace) async {
        for _ in 0..<400 where !w.turns.isEmpty { await Task.yield() }
    }

    @Test func theWorldIsFoundedWithHeadMasterAndThree() async {
        let w = await workspace(ScriptedBrain([.done]))
        #expect(w.agents.map(\.name) == ["HeadMaster", "Forge", "Hawk", "Quill"])
        #expect(w.agents.filter(\.isHeadMaster).count == 1)
        #expect(w.agents.allSatisfy { !$0.instructions.isEmpty && !$0.role.isEmpty })
    }

    /// Seeded once: a deleted member stays deleted after a relaunch.
    @Test func theCrewIsSeededOnlyOnce() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "agents-\(UUID().uuidString).sqlite")
        let first = await workspace(ScriptedBrain([.done]), store: try Store(database: Database(url: url)))
        let forge = try #require(first.agents.first { $0.name == "Forge" })
        _ = first.deleteAgent(forge.id)
        let second = await workspace(ScriptedBrain([.done]), store: try Store(database: Database(url: url)))
        #expect(second.agents.map(\.name) == ["HeadMaster", "Hawk", "Quill"])
    }

    @Test func headMasterCannotBeDeleted() async throws {
        let w = await workspace(ScriptedBrain([.done]))
        let found = w.agents.first(where: \.isHeadMaster)
        let head = try #require(found)
        #expect(w.deleteAgent(head.id) == nil)
        #expect(w.agents.contains { $0.id == head.id })
    }

    @Test func aDeletedAgentComesBackWithUndo() async throws {
        let w = await workspace(ScriptedBrain([.done]))
        let hawk = try #require(w.agents.first { $0.name == "Hawk" })
        let undo = try #require(w.deleteAgent(hawk.id))
        #expect(!w.agents.contains { $0.id == hawk.id })
        undo()
        #expect(w.agents.first { $0.id == hawk.id } == hawk)
    }

    @Test func hiredAgentsAreSavedAndEditable() async throws {
        let store = Store.inMemory()
        let w = await workspace(ScriptedBrain([.done]), store: store)
        var pixel = w.hire()
        pixel.name = "Pixel"
        pixel.role = "Draws sprites"
        w.saveAgent(pixel)
        #expect(try store.agents().contains { $0.id == pixel.id && $0.name == "Pixel" && $0.avatar == pixel.avatar })
        #expect(w.agents.last?.name == "Pixel")
    }

    @Test func talkingToAnAgentOpensItsChatAndEveryTurnCarriesWhoItIs() async throws {
        let brain = ScriptedBrain([.textDelta("On it."), .done])
        let w = await workspace(brain)
        let forge = try #require(w.agents.first { $0.name == "Forge" })
        let chat = try #require(w.talk(to: forge.id))
        #expect(chat.agentID == forge.id && w.selectedChatID == chat.id)
        #expect(w.send("Build the thing", in: chat.id))
        await settle(w)
        let sent = brain.requests.withLock { $0.last?.instructions }
        let instructions = try #require(sent)
        #expect(instructions.contains("You are Forge"))
        #expect(instructions.contains(forge.instructions))
        #expect(instructions.contains("HeadMaster") && instructions.contains("Quill"))
        #expect(brain.requests.withLock { $0.last?.prompt } == "Build the thing")
    }

    @Test func aPlainChatCarriesNoInstructions() async throws {
        let brain = ScriptedBrain([.done])
        let w = await workspace(brain)
        let chat = try #require(w.newChat(in: nil))
        _ = w.send("hi", in: chat.id)
        await settle(w)
        #expect(brain.requests.withLock { $0.last?.instructions } == nil)
    }

    @Test func headMastersHandoffsStartTheCrewsChats() async throws {
        let reply = "Splitting it.\n```handoff\nto: Forge\ntask: Build it.\n```\n```handoff\nto: Nobody\ntask: Lost.\n```"
        let brain = ScriptedBrain([.textDelta(reply), .done])
        let w = await workspace(brain)
        let found = w.agents.first(where: \.isHeadMaster)
        let head = try #require(found)
        let chat = try #require(w.talk(to: head.id))
        _ = w.send("Ship it", in: chat.id)
        await settle(w)
        let forge = try #require(w.agents.first { $0.name == "Forge" })
        let forgeChat = try #require(w.chats.first { $0.agentID == forge.id })
        #expect(w.messages(in: forgeChat.id).first?.parts == [.text("From HeadMaster: Build it.")])
        let notices = w.messages(in: chat.id).flatMap(\.parts).compactMap { part -> String? in
            if case .notice(let text) = part { text } else { nil }
        }
        #expect(notices.contains { $0.contains("Forge") })
        #expect(notices.contains { $0.contains("Nobody") })
    }

    /// When a member finishes what HeadMaster gave them, HeadMaster's chat hears about it.
    @Test func aFinishedHandoffReportsBack() async throws {
        let reply = "```handoff\nto: Quill\ntask: Write it down.\n```"
        let brain = ScriptedBrain([.textDelta(reply), .done])
        let w = await workspace(brain)
        let head = try #require(w.headMaster)
        let chat = try #require(w.talk(to: head.id))
        _ = w.send("Note it", in: chat.id)
        await settle(w)
        let last = try #require(w.messages(in: chat.id).last)
        let quill = try #require(w.agents.first { $0.name == "Quill" })
        #expect(last.parts.contains { if case .notice(let t) = $0 { t.hasPrefix(Handoff.finishedPrefix(quill.name)) } else { false } })
    }

    @Test func anAgentChatCanMoveProjectUntilItsFirstMessage() async throws {
        let w = await workspace(ScriptedBrain([.done]))
        let project = w.addProject(at: FileManager.default.temporaryDirectory)
        let forge = try #require(w.agents.first { $0.name == "Forge" })
        let chat = try #require(w.talk(to: forge.id))
        #expect(w.setProject(project.id, for: chat.id))
        #expect(w.chat(chat.id)?.projectID == project.id)
        _ = w.send("go", in: chat.id)
        await settle(w)
        #expect(!w.setProject(nil, for: chat.id))
        #expect(w.chat(chat.id)?.projectID == project.id)
    }

    @Test func onlyHeadMasterHandsOff() async throws {
        let brain = ScriptedBrain([.textDelta("```handoff\nto: Hawk\ntask: Review.\n```"), .done])
        let w = await workspace(brain)
        let forge = try #require(w.agents.first { $0.name == "Forge" })
        let chat = try #require(w.talk(to: forge.id))
        _ = w.send("go", in: chat.id)
        await settle(w)
        #expect(w.chats.filter { $0.agentID != nil }.count == 1)
    }

    /// Finishing in the chat the person is looking at isn't news.
    @Test func finishingInViewIsAlreadySeen() async throws {
        let w = await workspace(ScriptedBrain([.textDelta("ok"), .done]))
        let hawk = try #require(w.agents.first { $0.name == "Hawk" })
        let chat = try #require(w.talk(to: hawk.id))
        _ = w.send("Review", in: chat.id)
        await settle(w)
        #expect(w.status(of: hawk.id) == .idle)
    }

    @Test func statusFollowsTheAgentsChats() async throws {
        let w = await workspace(ScriptedBrain([.textDelta("Writing"), .toolCall(id: "t", name: "Bash", summary: "swift test")], hold: true))
        let hawk = try #require(w.agents.first { $0.name == "Hawk" })
        #expect(w.status(of: hawk.id) == .idle)
        let chat = try #require(w.talk(to: hawk.id))
        _ = w.send("Review", in: chat.id)
        for _ in 0..<50 { await Task.yield() }
        guard case .working = w.status(of: hawk.id) else { Issue.record("not working"); return }
        w.showAgents()
        w.stop(chat.id)
        #expect(w.status(of: hawk.id) == .done)
        w.markSeen(hawk.id)
        #expect(w.status(of: hawk.id) == .idle)
    }
}

@Suite struct WorkplaceWorldTests {
    @Test func aWorkingAgentWalksToItsDeskAndSits() {
        let id = UUID()
        var world = WorkplaceWorld(width: 800, seed: 3)
        world.sync([id])
        let desk = world.desk(of: id)
        for _ in 0..<2000 { world.step(0.05, working: [id]) }
        let walker = world.walkers[id]!
        #expect(walker.pose == .sitting)
        #expect(abs(walker.x - desk) < 1)
    }

    @Test func idleAgentsWanderButStayInTheWorld() {
        let id = UUID()
        var world = WorkplaceWorld(width: 800, seed: 9)
        world.sync([id])
        var seen = Set<Int>()
        for _ in 0..<4000 {
            world.step(0.05, working: [])
            let x = world.walkers[id]!.x
            #expect(x >= world.margin && x <= 800 - world.margin)
            seen.insert(Int(x / 50))
        }
        #expect(seen.count > 3)
    }

    @Test func theCrewStartsSpreadOut() {
        let ids = (0..<4).map { _ in UUID() }
        var world = WorkplaceWorld(width: 1000, seed: 5)
        world.sync(ids)
        let xs = ids.map { world.walkers[$0]!.x }.sorted()
        #expect(zip(xs, xs.dropFirst()).allSatisfy { $1 - $0 > 60 })
    }

    @Test func leavingTheDeskStandsUp() {
        let id = UUID()
        var world = WorkplaceWorld(width: 800, seed: 1)
        world.sync([id])
        for _ in 0..<2000 { world.step(0.05, working: [id]) }
        world.step(0.05, working: [])
        #expect(world.walkers[id]!.pose != .sitting)
    }
}
