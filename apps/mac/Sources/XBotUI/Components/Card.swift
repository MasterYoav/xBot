import SwiftUI

/// A titled card: title, a quiet subtitle and mono metadata on one line; a body; an optional footer.
public struct Card<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String?
    let meta: String?
    let content: Content
    let footer: Footer

    public init(
        title: String, subtitle: String? = nil, meta: String? = nil,
        @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.meta = meta
        self.content = content()
        self.footer = footer()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(title).emphasisText().foregroundStyle(Palette.textPrimary)
                if let subtitle { Text(subtitle).captionText().foregroundStyle(Palette.textTertiary) }
                Spacer(minLength: Space.s)
                if let meta { MonoLabel(meta) }
            }
            .padding(.horizontal, Space.m)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
            content
                .padding(.horizontal, Space.xs)
            footer
        }
        .raisedSurface()
        .cardShadow()
    }
}

extension Card where Footer == EmptyView {
    public init(title: String, subtitle: String? = nil, meta: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, meta: meta, content: content, footer: { EmptyView() })
    }
}

/// The footer row of a card: mono status on the left, actions on the right.
public struct CardFooter<Actions: View>: View {
    let status: String
    let actions: Actions

    public init(_ status: String, @ViewBuilder actions: () -> Actions) {
        self.status = status
        self.actions = actions()
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            MonoLabel(status)
            Spacer()
            actions
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
    }
}

/// A panel inside a card: lists, illustrations, code.
public struct InsetPanel<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.inset, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }
}

/// Metadata in small mono capitals: "6 STEPS", "READ-ONLY PLANNING".
public struct MonoLabel: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text).labelText().foregroundStyle(Palette.textTertiary)
    }
}
