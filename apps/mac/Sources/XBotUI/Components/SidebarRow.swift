import SwiftUI

/// A sidebar row: icon, title, something trailing. Selection is a raised fill, not a colour.
public struct SidebarRow<Trailing: View>: View {
    let systemImage: String?
    let title: String
    let isSelected: Bool
    let trailing: Trailing
    @State private var hovering = false

    public init(_ title: String, systemImage: String? = nil, isSelected: Bool = false,
                @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .frame(width: Space.l)
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textTertiary)
            }
            Text(title)
                .font(isSelected ? Typography.emphasis : Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Space.xs)
            trailing
        }
        .padding(.horizontal, Space.s)
        .frame(height: Metrics.row)
        .background(
            isSelected ? Palette.raised : (hovering ? Palette.hover : .clear),
            in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous).strokeBorder(Palette.hairline)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

extension SidebarRow where Trailing == EmptyView {
    public init(_ title: String, systemImage: String? = nil, isSelected: Bool = false) {
        self.init(title, systemImage: systemImage, isSelected: isSelected) { EmptyView() }
    }
}
