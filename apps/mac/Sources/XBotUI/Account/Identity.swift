import AppKit
import Collaboration
import Observation
import SwiftUI
import XBotCore

/// Who is using xBot until it signs in with an Apple ID: the Mac account's name and picture,
/// unless the person changed them in Edit Profile.
@MainActor
@Observable
final class Identity {
    static let shared = Identity()

    private(set) var name: String
    let username = NSUserName()
    private(set) var picture: NSImage?

    private static let nameKey = "profile.name"
    private static var pictureURL: URL { Store.supportDirectory.appending(path: "profile.png") }

    private init() {
        let fullName = NSFullUserName()
        name = UserDefaults.standard.string(forKey: Self.nameKey) ?? (fullName.isEmpty ? NSUserName() : fullName)
        // The local directory's own picture: no permission prompt.
        picture = NSImage(contentsOf: Self.pictureURL)
            ?? CBIdentity(name: NSUserName(), authority: CBIdentityAuthority.local())?.image
    }

    func setName(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        name = trimmed
        UserDefaults.standard.set(trimmed, forKey: Self.nameKey)
    }

    func setPicture(_ image: NSImage) {
        picture = image
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: Store.supportDirectory, withIntermediateDirectories: true)
        try? png.write(to: Self.pictureURL)
    }

    var initials: String {
        name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined()
    }
}

/// The person's picture in a circle, or their initials on the accent tint.
struct Avatar: View {
    let identity: Identity
    let size: CGFloat

    var body: some View {
        Group {
            if let picture = identity.picture {
                Image(nsImage: picture).resizable().scaledToFill()
            } else {
                Text(identity.initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.accentTint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
