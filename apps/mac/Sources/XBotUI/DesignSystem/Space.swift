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
    /// The rail. Fixed, per docs/09-ui-spec.md.
    public static let railWidth: CGFloat = 68
    public static let panelWidth: ClosedRange<CGFloat> = 320...420
    public static let minimumWindow = CGSize(width: 900, height: 600)
    /// Below this the panel becomes an overlay rather than a column.
    public static let panelCollapsesBelow: CGFloat = 1100
    /// A bubble never spans the conversation. ~70%, per the spec and the reference.
    public static let bubbleMaximumWidthFraction: CGFloat = 0.7
}
