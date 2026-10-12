import SwiftUI
import XBotRemote
import XBotWorld

extension RemoteAvatar {
    /// The look, as the shared pixel art draws it.
    var look: AgentAvatar {
        AgentAvatar(skin: parts["skin"] ?? 0, hair: parts["hair"] ?? 0, hairColor: parts["hairColor"] ?? 0, eyes: parts["eyes"] ?? 0,
                    outfit: parts["outfit"] ?? 0, outfitColor: parts["outfitColor"] ?? 0, accessory: parts["accessory"] ?? 0)
    }
}

extension RemoteResident {
    var resident: WorldResident {
        let state: WorldResident.Status = switch status {
        case "working": .working(activity)
        case "done": .done
        default: .idle
        }
        return WorldResident(id: id, name: name, role: role, avatar: avatar.look, isHeadMaster: isHeadMaster, status: state)
    }
}

/// The Agents tab: the same pixel world as the Mac's Agents page, with the same crew walking about,
/// sitting down to work and saying what they're doing. The world is the Mac's: change it here
/// and the Mac follows, and the other way round.
struct AgentsWorldScreen: View {
    let client: RemoteClient
    let nav: Navigator
    @State private var stageBottom: CGFloat = 400
    @State private var editing: RemoteCrewMember?
    @State private var talking: RemoteCrewMember?

    private var setting: WorkplaceSetting { client.world.flatMap { WorkplaceSetting(rawValue: $0.setting) } ?? .village }
    private var residents: [RemoteResident] { client.world?.residents ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            WorldStage(setting: setting, residents: residents.map(\.resident),
                       open: { nav.push(.member($0)) },
                       newChat: { id in talking = member(id) },
                       edit: { id in editing = member(id) })
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { stageBottom = $0 }
                .accessibilityIdentifier("world-stage")
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    crewCards
                    SectionTitle(title: String(localized: "Worlds"))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 6)
                    worlds
                }
                .padding(.horizontal, Glass.margin)
                .padding(.top, 6)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background {
            WorkplaceBackdrop(setting: setting, stageBottom: stageBottom)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: setting)
        }
        .navigationBarTitleDisplayMode(.inline)
        // The worlds are drawn for night and day alike; glass over them reads best dark.
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { worldMenu }
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = newMember() } label: { Image(systemName: "person.badge.plus") }
                    .accessibilityLabel(String(localized: "Hire"))
                    .disabled(client.avatarParts.isEmpty || client.agents.isEmpty)
            }
        }
        .overlay(alignment: .bottom) {
            if let gone = client.lastLetGo {
                UndoBanner(text: String(localized: "\(gone) left")) { Task { await client.undoLetGo() } } dismiss: { client.lastLetGo = nil }
                    .padding(.bottom, 60)
            }
        }
        .animation(.snappy, value: client.lastLetGo)
        .sheet(item: $editing) { member in
            CrewEditor(client: client, member: member, parts: client.avatarParts,
                       isNew: !(client.crew ?? []).contains { $0.id == member.id }) { answer in
                client.applyCrew(answer)
                editing = nil
            }
        }
        .sheet(item: $talking) { member in
            TalkSheet(client: client, member: member) { chatID in
                talking = nil
                nav.push(.chat(chatID))
            }
            .presentationDetents([.medium])
        }
        .task { await client.loadCrew() }
        // Someone hired or let go on the Mac: refresh the details behind the cards.
        .onChange(of: residents.map(\.id)) { Task { await client.loadCrew() } }
    }

    private func member(_ id: UUID) -> RemoteCrewMember? { client.crew?.first { $0.id == id } }

    private func newMember() -> RemoteCrewMember {
        var look: [String: Int] = [:]
        for part in client.avatarParts { look[part.key] = Int.random(in: 0..<max(part.count, 1)) }
        return RemoteCrewMember(name: "", avatar: RemoteAvatar(parts: look), agent: client.agents.first?.id ?? "claude")
    }

    // MARK: Pieces

    private var worldMenu: some View {
        Menu {
            Picker(String(localized: "World"), selection: Binding(get: { setting }, set: { world in Task { await client.setWorld(world.rawValue) } })) {
                ForEach(WorkplaceSetting.allCases, id: \.self) { world in
                    Label(world.title, systemImage: world.symbol).tag(world)
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: setting.symbol)
                Text(setting.title).font(.system(.headline, design: .rounded, weight: .bold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
        }
        .accessibilityIdentifier("world-menu")
        .accessibilityLabel(String(localized: "World: \(setting.title)"))
    }

    private var crewCards: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(residents) { resident in
                    Button { nav.push(.member(resident.id)) } label: { ResidentCard(resident: resident) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("crew-card")
                        .contextMenu {
                            if let member = member(resident.id) {
                                Button { talking = member } label: { Label(String(localized: "Message"), systemImage: "bubble.left") }
                                Button { editing = member } label: { Label(String(localized: "Edit"), systemImage: "pencil") }
                                if !member.isHeadMaster {
                                    Button(role: .destructive) { Task { await client.letGo(member) } } label: {
                                        Label(String(localized: "Let go"), systemImage: "person.badge.minus")
                                    }
                                }
                            }
                        }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private var worlds: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(WorkplaceSetting.allCases, id: \.self) { world in
                    Button { Task { await client.setWorld(world.rawValue) } } label: {
                        WorldThumbnail(setting: world, chosen: world == setting)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(world.title)
                    .accessibilityAddTraits(world == setting ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

/// Someone on the crew, on glass over the world: their face, name and what they're up to.
private struct ResidentCard: View {
    let resident: RemoteResident

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(AvatarPalette.tile(resident.avatar.look))
                    LivingAvatar(avatar: resident.avatar.look, pixel: 46 / 17, talking: resident.status == "working",
                                 headOnly: true, seed: resident.id.hashValue)
                        .offset(y: -46 * 0.12)
                        .frame(width: 46, height: 46)
                        .clipShape(Circle())
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(resident.name).font(.system(.headline, design: .rounded, weight: .bold)).lineLimit(1)
                        if resident.isHeadMaster { Image(systemName: "crown.fill").font(.caption2).foregroundStyle(.yellow) }
                    }
                    Text(resident.role.isEmpty ? " " : resident.role).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(status).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(14)
        .frame(width: 190, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch resident.status { case "working": .orange; case "done": .green; default: Color(.systemGray3) }
    }

    private var status: String {
        switch resident.status {
        case "working": resident.activity ?? String(localized: "Working")
        case "done": String(localized: "Done")
        default: String(localized: "Free")
        }
    }
}

/// A world's postcard: its scenery, still, with a tick on the one the crew lives in.
private struct WorldThumbnail: View {
    let setting: WorkplaceSetting
    let chosen: Bool
    private static let still = Date(timeIntervalSinceReferenceDate: 800_000_000)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WorldScenery(setting: setting, date: Self.still, width: 420)
                .frame(width: 420, height: WorldStage.height)
                .scaleEffect(0.36, anchor: .topLeading)
                .frame(width: 151, height: WorldStage.height * 0.36, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(chosen ? Color.white : .white.opacity(0.15), lineWidth: chosen ? 3 : 1))
                .overlay(alignment: .topTrailing) {
                    if chosen {
                        Image(systemName: "checkmark.circle.fill").font(.title3).symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Theme.accent).padding(7)
                    }
                }
            Text(setting.title).font(.system(.footnote, design: .rounded, weight: .bold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4)
        }
        .environment(\.motionPaused, true)
    }
}

/// Someone on the crew: their details, chats, and what you can do with them.
struct CrewMemberScreen: View {
    let client: RemoteClient
    let nav: Navigator
    let memberID: UUID
    @State private var editing: RemoteCrewMember?
    @State private var talking: RemoteCrewMember?

    var body: some View {
        Group {
            if let member = client.crew?.first(where: { $0.id == memberID }) {
                CrewDetail(client: client, member: member, edit: { editing = member }, talk: { talking = member },
                           letGo: {
                               nav.drop(.member(memberID))
                               Task { await client.letGo(member) }
                           })
            } else {
                ProgressView()
            }
        }
        .task { if client.crew == nil { await client.loadCrew() } }
        .sheet(item: $editing) { member in
            CrewEditor(client: client, member: member, parts: client.avatarParts, isNew: false) { answer in
                client.applyCrew(answer)
                editing = nil
            }
        }
        .sheet(item: $talking) { member in
            TalkSheet(client: client, member: member) { chatID in
                talking = nil
                nav.push(.chat(chatID))
            }
            .presentationDetents([.medium])
        }
    }
}
