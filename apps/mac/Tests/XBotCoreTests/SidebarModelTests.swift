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

    /// The Inbox is gone: chats without a project are Recent, five at a time, then "Show all".
    @Test func recentHoldsTheChatsWithoutAProject() {
        let chats = [chat("a", in: site, ago: 1)] + (0..<7).map { chat("l\($0)", in: nil, ago: Double($0 + 2)) }
        let model = SidebarModel(projects: [site, api], chats: chats.shuffled(), running: [])
        #expect(model.recent.map(\.title) == ["l0", "l1", "l2", "l3", "l4"])
        #expect(model.hiddenRecent == 2)
        let all = SidebarModel(projects: [site, api], chats: chats, running: [], showsAllRecent: true)
        #expect(all.recent.count == 7 && all.hiddenRecent == 0)
    }

    @Test func searchIgnoresCaseAndAccents() {
        let chats = [chat("Café menu", in: site, ago: 1), chat("Billing", in: api, ago: 2), chat("cafe idea", in: nil, ago: 3)]
        let model = SidebarModel(projects: [site, api], chats: chats, running: [], query: "CAFE")
        #expect(model.recent.map(\.title) == ["cafe idea"])
        #expect(model.groups.map(\.project.name) == ["site"])
    }
}
