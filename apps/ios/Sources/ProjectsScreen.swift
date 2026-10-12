import SwiftUI
import XBotRemote

/// The projects on the Mac: each a card with its chats and a way in to its files and changes.
struct ProjectsScreen: View {
    let client: RemoteClient
    let nav: Navigator

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(client.projects) { project in
                    let chats = client.chats.filter { $0.projectID == project.id }
                    NavigationLink(value: Destination.project(project.id)) {
                        CardRow(title: project.name, subtitle: subtitle(project, chats),
                                leading: AnyView(IconCircle(symbol: "folder.fill", tint: tint(project), size: 46))) {
                            if chats.contains(where: \.isRunning) { ProgressView().controlSize(.small) }
                            Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                        }
                        .card(padding: 16, radius: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "\(project.name): files and changes"))
                    .contextMenu {
                        Button { nav.newChat(in: project.id) } label: { Label(String(localized: "New chat here"), systemImage: "square.and.pencil") }
                    }
                }
            }
            .padding(.horizontal, Glass.margin)
            .padding(.bottom, 30)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .overlay {
            if client.projects.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "No projects yet"), systemImage: "folder")
                } description: {
                    Text(String(localized: "Add a folder from your Mac, and its chats, files and changes show up here."))
                } actions: {
                    Button(String(localized: "Add a project…")) { nav.addingProject = true }.buttonStyle(.glassProminent)
                }
            }
        }
        .navigationTitle(String(localized: "Projects"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { nav.addingProject = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel(String(localized: "Add a project…"))
            }
        }
    }

    private func subtitle(_ project: RemoteProject, _ chats: [RemoteChat]) -> String {
        let folder = (project.path ?? "").replacing(/^\/Users\/[^\/]+/, with: "~")
        return chats.isEmpty ? folder : String(localized: "\(chats.count) chats · \(folder)")
    }

    private func tint(_ project: RemoteProject) -> Color {
        let palette: [Color] = [.blue, .teal, .orange, .pink, .indigo, .green, .purple, .mint]
        // Stable across launches (hashValue isn't).
        return palette[project.name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % palette.count]
    }
}
