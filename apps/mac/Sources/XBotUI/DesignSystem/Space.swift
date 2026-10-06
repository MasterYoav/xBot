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
    public static let small: CGFloat = 6
    public static let medium: CGFloat = 10
    public static let large: CGFloat = 18
    public static let xlarge: CGFloat = 22
    public static let avatar: CGFloat = 12
}

public enum Metrics {
    public static let sidebarWidth: ClosedRange<CGFloat> = 220...360
    public static let sidebarIdealWidth: CGFloat = 260
    /// A transcript line longer than this is hard to read; wider windows add margin, not width.
    public static let readingWidth: CGFloat = 760
    public static let minimumWindow = CGSize(width: 900, height: 600)
    public static let defaultWindow = CGSize(width: 1280, height: 820)
    public static let titleBarHeight: CGFloat = 52
    public static let tabWidth: CGFloat = 200
    public static let toolOutputMaxHeight: CGFloat = 240
}
