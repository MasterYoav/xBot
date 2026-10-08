import SwiftUI
import UniformTypeIdentifiers

/// Your name and picture. The Mac account's are the defaults.
struct EditProfileSheet: View {
    let identity: Identity
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var choosing = false

    var body: some View {
        VStack(spacing: Space.l) {
            Text(String(localized: "Edit Profile")).titleText()
            Avatar(identity: identity, size: Metrics.avatarLarge)
            Button(String(localized: "Choose Picture…")) { choosing = true }.buttonStyle(QuietButtonStyle())
            TextField(String(localized: "Name"), text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: Metrics.effortCardWidth)
            HStack {
                Button(String(localized: "Cancel")) { dismiss() }.buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save")) {
                    identity.setName(name)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .onAppear { name = identity.name }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let image = NSImage(contentsOf: url) { identity.setPicture(image) }
        }
    }
}
