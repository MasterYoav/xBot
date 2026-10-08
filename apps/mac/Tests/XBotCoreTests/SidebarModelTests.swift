import Foundation
import Testing
@testable import XBotCore

@Suite struct SidebarModelTests {
    let site = Project(name: "site", path: "/tmp/site")
    let api = Project(name: "api", path: "/tmp/api")

    func chat(_ title: String, in project: Project?, ago: TimeInterval) -> Chat {
        Chat(projectID: project?.id, title: title, harness: .claude, mode: .editFiles,
             updatedAt: Date(timeIntervalSinceNow: -ago))
    }

    @Test func projectsShowTheirFiveNewestChatsAndCountTheRest() {
        let chats = (0..<7).map { chat("c\($0)", in: site, ago: Double($0)) }
        let model = SidebarModel(projects: [site], chats: chats, running: [])
        #expect(model.groups.first?.chats.map(\.title) == ["c0", "c1", "c2", "c3", "c4"])
        #expect(model.groups.first?.hidden == 2)
        let open = SidebarModel(projects: [site], chats: chats, running: [], expanded: [site.id])
        #expect(open.groups.first?.chats.count == 7 && open.groups.first?.hidden == 0)
    }

    @Test func aProjectIsRunningWhenAnyOfItsChatsIs() {
        let busy = chat("busy", in: api, ago: 100)
        let model = SidebarModel(projects: [site, api], chats: (0..<6).map { chat("\($0)", in: api, ago: Double($0)) } + [busy],
                                 running: [busy.id])
        #expect(model.groups.map(\.isRunning) == [false, true])
    }

    @Test func recentIsTheFiveNewestEverywhereAndInboxIsTheLooseOnes() {
        let chats = [chat("a", in: site, ago: 1), chat("b", in: nil, ago: 2), chat("c", in: api, ago: 3),
                     chat("d", in: nil, ago: 4), chat("e", in: site, ago: 5), chat("f", in: site, ago: 6)]
        let model = SidebarModel(projects: [site, api], chats: chats.shuffled(), running: [])
        #expect(model.recent.map(\.title) == ["a", "b", "c", "d", "e"])
        #expect(model.inbox.map(\.title) == ["b", "d"])
    }

    @Test func searchIgnoresCaseAndAccents() {
        let chats = [chat("Café menu", in: site, ago: 1), chat("Billing", in: api, ago: 2)]
        let model = SidebarModel(projects: [site, api], chats: chats, running: [], query: "CAFE")
        #expect(model.recent.map(\.title) == ["Café menu"])
        #expect(model.groups.map(\.project.name) == ["site"])
    }
}
