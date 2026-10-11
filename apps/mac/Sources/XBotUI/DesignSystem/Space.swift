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
    public static let sidebarWidth: ClosedRange<CGFloat> = 220...340
    public static let sidebarIdealWidth: CGFloat = 260
    /// The right-hand column: files and changes.
    public static let inspectorWidth: ClosedRange<CGFloat> = 260...420
    public static let inspectorIdealWidth: CGFloat = 300
    /// The title bar row: the traffic lights, the tab strip. Measured from the running window
    /// (`unifiedCompact`): a 32pt title bar with the lights centred at 16.
    public static let titleBar: CGFloat = 32
    /// Room the traffic lights take at the left of the title bar row.
    public static let trafficLights: CGFloat = 78
    public static let tabMinWidth: CGFloat = 110
    public static let topBar: CGFloat = 44
    public static let row: CGFloat = 28
    public static let iconButton: CGFloat = 28
    public static let chipHeight: CGFloat = 26
    public static let sendButton: CGFloat = 30
    public static let composerWidth: CGFloat = 680
    /// A transcript line longer than this is hard to read; wider windows add margin, not width.
    public static let readingWidth: CGFloat = 720
    public static let tabMaxWidth: CGFloat = 230
    public static let suggestionHeight: CGFloat = 96
    public static let minimumWindow = CGSize(width: 900, height: 600)
    public static let defaultWindow = CGSize(width: 1280, height: 820)
    public static let toolOutputMaxHeight: CGFloat = 240
    /// A plan step's tool rows sit under its title, past the status icon.
    public static let stepIndent: CGFloat = 22
    public static let progressHeight: CGFloat = 2
    public static let dot: CGFloat = 6
    /// The effort slider.
    public static let effortCardWidth: CGFloat = 300
    public static let effortTrackHeight: CGFloat = 26
    public static let effortKnob: CGFloat = 24
    /// The person's picture: in the sidebar footer, in the menu, on the profile.
    public static let avatarSmall: CGFloat = 28
    public static let avatarMenu: CGFloat = 36
    public static let avatarLarge: CGFloat = 96
    public static let accountMenuWidth: CGFloat = 288
    /// The token heatmap: one square a day.
    public static let heatCell: CGFloat = 9
    public static let heatGap: CGFloat = 3
    public static let toolTile: CGFloat = 52
    public static let settingsWidth: CGFloat = 520
    /// A wallpaper choice in Settings › Appearance: the window's proportions, small.
    public static let wallpaperThumb = CGSize(width: 96, height: 60)
    /// How much of the content height the backdrop covers before it has faded out.
    public static let backdropHeight: CGFloat = 0.62
}
