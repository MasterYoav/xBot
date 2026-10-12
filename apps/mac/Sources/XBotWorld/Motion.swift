import SwiftUI

extension EnvironmentValues {
    /// True while xBot isn't the active app: the looping animations (wallpaper, the agents' world,
    /// sprites) stop drawing, so a Mac serving a phone, or just sitting behind other apps, spends
    /// nothing on them. They pick up where they were when you come back.
    @Entry public var motionPaused = false
}
