import SwiftUI
import XBotRemote
import XBotWorld

/// Ready-made crew members, each with a look, a role and instructions, hired in one tap
/// (or opened in the editor first, to change anything).
struct SuggestedAgent: Identifiable {
    let name: String
    let role: String
    /// One line on the card.
    let pitch: String
    let instructions: String
    let symbol: String
    let tint: Color
    let look: AgentAvatar
    var id: String { name }

    func member(agent: String, parts: [RemoteAvatarPart]) -> RemoteCrewMember {
        var values: [String: Int] = ["skin": look.skin, "hair": look.hair, "hairColor": look.hairColor, "eyes": look.eyes,
                                     "outfit": look.outfit, "outfitColor": look.outfitColor, "accessory": look.accessory]
        // Within what this Mac's xBot knows.
        for part in parts where part.count > 0 { values[part.key] = (values[part.key] ?? 0) % part.count }
        return RemoteCrewMember(name: name, role: role, instructions: instructions, avatar: RemoteAvatar(parts: values), agent: agent)
    }

    static let all: [SuggestedAgent] = [
        SuggestedAgent(name: "Nova", role: String(localized: "CTO"),
                       pitch: String(localized: "Leads engineering: architecture, tech choices, the dev team."),
                       instructions: "You are the CTO. Own the technical direction: architecture, technology choices and quality. Break engineering work into clear tasks for your team, review what they deliver, and keep HeadMaster informed in plain words.",
                       symbol: "cpu.fill", tint: .purple,
                       look: AgentAvatar(skin: 1, hair: 2, hairColor: 8, eyes: 2, outfit: 5, outfitColor: 4, accessory: 2)),
        SuggestedAgent(name: "Penny", role: String(localized: "CFO"),
                       pitch: String(localized: "Leads finance: costs, budgets, pricing and numbers."),
                       instructions: "You are the CFO. Watch costs, budgets and pricing; turn numbers into decisions. Ask for data before concluding, show your sums, and flag risks early.",
                       symbol: "dollarsign.circle.fill", tint: .green,
                       look: AgentAvatar(skin: 3, hair: 6, hairColor: 2, eyes: 4, outfit: 3, outfitColor: 3, accessory: 1)),
        SuggestedAgent(name: "Marlo", role: String(localized: "Product manager"),
                       pitch: String(localized: "Turns goals into specs, priorities and a roadmap."),
                       instructions: "You are the product manager. Turn goals into short specs with clear acceptance criteria, keep a prioritised backlog, and make sure what gets built solves the real problem.",
                       symbol: "list.bullet.rectangle.portrait.fill", tint: .orange,
                       look: AgentAvatar(skin: 0, hair: 4, hairColor: 3, eyes: 1, outfit: 0, outfitColor: 2, accessory: 3)),
        SuggestedAgent(name: "Scout", role: String(localized: "Researcher"),
                       pitch: String(localized: "Digs through docs, code and the web for answers."),
                       instructions: "You research. Before answering, read the relevant code, docs and sources; quote what you found and where. Say how sure you are, separate facts from guesses, and end with a short recommendation.",
                       symbol: "binoculars.fill", tint: .teal,
                       look: AgentAvatar(skin: 2, hair: 3, hairColor: 2, eyes: 1, outfit: 4, outfitColor: 3, accessory: 2)),
        SuggestedAgent(name: "Pixel", role: String(localized: "Designer"),
                       pitch: String(localized: "Turns rough ideas into clean, usable screens."),
                       instructions: "You design interfaces. Follow the platform's guidelines and the project's existing design system. Propose layouts with clear hierarchy, spacing and states (empty, loading, error), check contrast and accessibility, and implement them carefully.",
                       symbol: "paintpalette.fill", tint: .pink,
                       look: AgentAvatar(skin: 0, hair: 5, hairColor: 4, eyes: 3, outfit: 2, outfitColor: 8, accessory: 5)),
        SuggestedAgent(name: "Probe", role: String(localized: "Tester"),
                       pitch: String(localized: "Writes tests, reproduces bugs, guards releases."),
                       instructions: "You test. Reproduce a bug with a failing test before fixing it, cover edge cases, and run the whole suite before you say you're done. Report exactly what passed and what didn't.",
                       symbol: "checkmark.seal.fill", tint: .green,
                       look: AgentAvatar(skin: 3, hair: 1, hairColor: 0, eyes: 2, outfit: 1, outfitColor: 3, accessory: 1)),
        SuggestedAgent(name: "Atlas", role: String(localized: "DevOps"),
                       pitch: String(localized: "Builds, CI, deploys and keeping things running."),
                       instructions: "You look after builds, CI and deployment. Keep pipelines fast and reproducible, explain failures from their logs, and never run destructive commands without saying so first.",
                       symbol: "server.rack", tint: .blue,
                       look: AgentAvatar(skin: 4, hair: 0, hairColor: 0, eyes: 0, outfit: 5, outfitColor: 5, accessory: 3)),
        SuggestedAgent(name: "Sentry", role: String(localized: "Security reviewer"),
                       pitch: String(localized: "Finds risky code, leaks and weak spots."),
                       instructions: "You review for security. Look for injection, secrets in code, unsafe input handling, weak auth and risky dependencies. Rank findings by severity with a concrete fix for each; don't change code unless asked.",
                       symbol: "lock.shield.fill", tint: .red,
                       look: AgentAvatar(skin: 1, hair: 7, hairColor: 9, eyes: 4, outfit: 5, outfitColor: 1, accessory: 6)),
        SuggestedAgent(name: "Ledger", role: String(localized: "Data analyst"),
                       pitch: String(localized: "Queries, numbers and charts that make sense."),
                       instructions: "You analyse data. Ask what decision the numbers are for, check the data's quality first, show your queries, and explain results in plain words with the one chart that matters.",
                       symbol: "chart.bar.xaxis", tint: .indigo,
                       look: AgentAvatar(skin: 5, hair: 2, hairColor: 1, eyes: 1, outfit: 3, outfitColor: 7, accessory: 0)),
        SuggestedAgent(name: "Compass", role: String(localized: "Product planner"),
                       pitch: String(localized: "Specs, priorities and the next small step."),
                       instructions: "You plan product work. Turn requests into a short spec: the problem, who it's for, what done looks like, and the smallest first step. Break work into tasks the crew can pick up.",
                       symbol: "map.fill", tint: .orange,
                       look: AgentAvatar(skin: 2, hair: 6, hairColor: 3, eyes: 5, outfit: 0, outfitColor: 2, accessory: 4)),
        SuggestedAgent(name: "Tidy", role: String(localized: "Refactorer"),
                       pitch: String(localized: "Cleans up code without changing what it does."),
                       instructions: "You refactor. Keep behaviour exactly the same, work in small steps with the tests passing after each, remove duplication and dead code, and explain every change in one line.",
                       symbol: "wand.and.stars", tint: .mint,
                       look: AgentAvatar(skin: 0, hair: 8, hairColor: 7, eyes: 0, outfit: 6, outfitColor: 4, accessory: 7)),
        SuggestedAgent(name: "Echo", role: String(localized: "Translator"),
                       pitch: String(localized: "Localises the app and its docs, naturally."),
                       instructions: "You translate and localise. Keep meaning and tone, use the platform's string catalogs, keep placeholders intact, and flag phrases that don't travel well.",
                       symbol: "globe", tint: .cyan,
                       look: AgentAvatar(skin: 3, hair: 4, hairColor: 5, eyes: 3, outfit: 2, outfitColor: 6, accessory: 2)),
        SuggestedAgent(name: "Page", role: String(localized: "Docs writer"),
                       pitch: String(localized: "READMEs, guides and changelogs people read."),
                       instructions: "You write documentation. Lead with what the reader wants to do, use short sentences and real examples, keep it in step with the code, and check every command you document actually works.",
                       symbol: "book.closed.fill", tint: .brown,
                       look: AgentAvatar(skin: 1, hair: 3, hairColor: 6, eyes: 2, outfit: 4, outfitColor: 9, accessory: 5)),
    ]
}
