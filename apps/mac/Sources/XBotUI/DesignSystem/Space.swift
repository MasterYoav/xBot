import CoreGraphics

/// An 8-point base scale. Half-steps exist for optical adjustment; nothing else does.
public enum Space {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

public enum Radius {
    /// Rows, chips.
    public static let small: CGFloat = 6
    /// Panels inside cards.
    public static let medium: CGFloat = 10
    /// Cards, the composer.
    public static let large: CGFloat = 14
}

public enum Metrics {
    public static let sidebarWidth: ClosedRange<CGFloat> = 200...320
    public static let sidebarIdealWidth: CGFloat = 240
    /// Room for the traffic lights above the sidebar's header.
    public static let titleBarInset: CGFloat = 38
    public static let topBar: CGFloat = 44
    public static let row: CGFloat = 28
    public static let iconButton: CGFloat = 28
    public static let chipHeight: CGFloat = 26
    public static let sendButton: CGFloat = 30
    public static let composerWidth: CGFloat = 680
    /// A transcript line longer than this is hard to read; wider windows add margin, not width.
    public static let readingWidth: CGFloat = 720
    public static let tabMaxWidth: CGFloat = 180
    public static let suggestionHeight: CGFloat = 96
    public static let minimumWindow = CGSize(width: 900, height: 600)
    public static let defaultWindow = CGSize(width: 1280, height: 820)
    public static let toolOutputMaxHeight: CGFloat = 240
    /// A plan step's tool rows sit under its title, past the status icon.
    public static let stepIndent: CGFloat = 22
    public static let progressHeight: CGFloat = 2
    public static let dot: CGFloat = 6
}
