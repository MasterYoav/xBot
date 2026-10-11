/// When xBot's animations run. Idle, xBot used about a fifth of a core redrawing worlds, faces and
/// wallpapers behind other apps; now every animation clock pauses unless xBot is the active app
/// and its window is on screen (not hidden, minimised or covered).
public enum MotionPolicy {
    public static func isLive(appActive: Bool, windowOnScreen: Bool) -> Bool { appActive && windowOnScreen }
}
