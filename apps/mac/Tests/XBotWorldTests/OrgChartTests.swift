import Foundation
import Testing
@testable import XBotWorld

@Suite struct OrgChartTests {
    typealias M = OrgChart.Member
    let ceo = M(id: UUID(), name: "HeadMaster", role: "Founder and orchestrator of the crew", isHeadMaster: true, managerID: nil)

    func member(_ name: String, _ role: String, manager: UUID? = nil) -> M {
        M(id: UUID(), name: name, role: role, isHeadMaster: false, managerID: manager)
    }

    @Test func rolesFindTheirDepartmentAndRank() {
        #expect(OrgChart.position(of: "CTO") == .init(department: .engineering, rank: .executive))
        #expect(OrgChart.position(of: "Chief Financial Officer") == .init(department: .finance, rank: .executive))
        #expect(OrgChart.position(of: "VP of Marketing") == .init(department: .marketing, rank: .executive))
        #expect(OrgChart.position(of: "Engineering manager") == .init(department: .engineering, rank: .lead))
        #expect(OrgChart.position(of: "Builder: features end to end") == .init(department: .engineering, rank: .member))
        #expect(OrgChart.position(of: "Senior iOS developer").department == .engineering)
        #expect(OrgChart.position(of: "Product manager").department == .product)
        #expect(OrgChart.position(of: "Data analyst").department == .finance)
        #expect(OrgChart.position(of: "Docs writer").department == .marketing)
        #expect(OrgChart.position(of: "Founder and orchestrator of the crew").rank == .ceo)
        #expect(OrgChart.position(of: "Something odd").department == .general)
    }

    @Test func executivesSitUnderTheCEOAndTeamsUnderTheirExecutive() {
        let cto = member("Nova", "CTO")
        let cfo = member("Penny", "CFO")
        let all = [ceo, cto, cfo]
        #expect(OrgChart.suggestedManager(role: "CTO", id: cto.id, among: all) == ceo.id)
        #expect(OrgChart.suggestedManager(role: "Backend engineer", id: nil, among: all) == cto.id)
        #expect(OrgChart.suggestedManager(role: "Tester", id: nil, among: all) == cto.id)
        #expect(OrgChart.suggestedManager(role: "Accountant", id: nil, among: all) == cfo.id)
        // No CMO yet: marketing goes to the CEO.
        #expect(OrgChart.suggestedManager(role: "Docs writer", id: nil, among: all) == ceo.id)
        // Product reports to the CPO if there is one, else the CTO.
        #expect(OrgChart.suggestedManager(role: "Product manager", id: nil, among: all) == cto.id)
        let cpo = member("Iris", "Chief Product Officer")
        #expect(OrgChart.suggestedManager(role: "Product manager", id: nil, among: all + [cpo]) == cpo.id)
        // The CEO reports to the person.
        #expect(OrgChart.suggestedManager(role: ceo.role, id: ceo.id, among: all) == nil)
    }

    @Test func leadsSitBetweenTheExecutiveAndTheTeam() {
        let cto = member("Nova", "CTO")
        let lead = member("Lee", "Engineering lead")
        let all = [ceo, cto, lead]
        #expect(OrgChart.suggestedManager(role: lead.role, id: lead.id, among: all) == cto.id)
        #expect(OrgChart.suggestedManager(role: "Developer", id: nil, among: all) == lead.id)
    }

    @Test func treeLevelsAndOrder() {
        let cto = member("Nova", "CTO", manager: ceo.id)
        let forge = member("Forge", "Builder", manager: cto.id)
        let hawk = member("Hawk", "Reviewer", manager: cto.id)
        let quill = member("Quill", "Scribe")   // nil: under the CEO
        let tree = OrgChart.tree([quill, hawk, forge, cto, ceo])
        #expect(tree.levels.map { $0.map(\.name) } == [["HeadMaster"], ["Quill", "Nova"], ["Hawk", "Forge"]])
        #expect(tree.manager(of: forge.id) == cto.id && tree.manager(of: quill.id) == ceo.id && tree.manager(of: ceo.id) == nil)
        #expect(Set(tree.below(ceo.id)) == Set([cto.id, forge.id, hawk.id, quill.id]))
        #expect(tree.below(cto.id) == [hawk.id, forge.id] || tree.below(cto.id) == [forge.id, hawk.id])
    }

    @Test func cyclesAndMissingManagersFallBackToTheCEO() {
        let a = UUID(), b = UUID()
        let x = M(id: a, name: "A", role: "", isHeadMaster: false, managerID: b)
        let y = M(id: b, name: "B", role: "", isHeadMaster: false, managerID: a)
        let gone = member("C", "", manager: UUID())
        let tree = OrgChart.tree([ceo, x, y, gone])
        #expect(tree.levels.count >= 2 && tree.levels[0].map(\.id) == [ceo.id])
        #expect(Set(tree.levels.flatMap { $0 }.map(\.id)) == Set([ceo.id, a, b, gone.id]))
        #expect(tree.manager(of: gone.id) == ceo.id)
        #expect(OrgChart.wouldLoop(a, under: b, in: [ceo, x, y]))
        #expect(!OrgChart.wouldLoop(gone.id, under: ceo.id, in: [ceo, gone]))
    }

    @Test func layoutSpacesSlotsApartAndCentresManagers() {
        let cto = member("Nova", "CTO", manager: ceo.id)
        let kids = (0..<3).map { member("K\($0)", "Dev", manager: cto.id) }
        let quill = member("Quill", "Scribe", manager: ceo.id)
        let layout = OrgChart.layout(OrgChart.tree([ceo, cto, quill] + kids), slot: 100)
        // Leaves at least a slot apart, on every level.
        for level in OrgChart.tree([ceo, cto, quill] + kids).levels {
            let xs = level.map { layout.x[$0.id]! }.sorted()
            for (l, r) in zip(xs, xs.dropFirst()) { #expect(r - l >= 100 - 0.001) }
        }
        let kidXs = kids.map { layout.x[$0.id]! }
        #expect(abs(layout.x[cto.id]! - (kidXs.min()! + kidXs.max()!) / 2) < 0.001)
        #expect(layout.width == 400)   // four leaves
        #expect(layout.depth[kids[0].id] == 2 && layout.depth[ceo.id] == 0)
    }

    @Test func inTheirSlotsTheyStrollNearTheirDeskAndWorkThere() {
        let a = UUID(), b = UUID()
        var world = WorkplaceWorld(width: 400, seed: 3)
        world.arrange([a: .init(home: 100, range: 20), b: .init(home: 300, range: 20)])
        world.sync([a, b])
        for _ in 0..<600 { world.step(0.05, working: []) }
        #expect(abs(world.walkers[a]!.x - 100) <= 20.001 && abs(world.walkers[b]!.x - 300) <= 20.001)
        for _ in 0..<200 { world.step(0.05, working: [b]) }
        #expect(world.walkers[b]!.x == 300 && world.walkers[b]!.pose == .sitting)
        // Moved under someone else: walks over to the new slot.
        world.arrange([a: .init(home: 250, range: 20), b: .init(home: 300, range: 20)])
        for _ in 0..<400 { world.step(0.05, working: []) }
        #expect(abs(world.walkers[a]!.x - 250) <= 20.001)
    }
}
