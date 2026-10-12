# Design system

> **Source of truth for values:** `apps/mac/Sources/XBotUI/DesignSystem/` (`Palette`, `Typography`,
> `Space`, `Motion`, `Depth`, `MotionGate`) and `XBotUI/Components/` on the Mac;
> `apps/ios/Sources/Glass.swift` and `Accent.swift` on the iPhone and iPad; `XBotWorld` for the
> pixel-art worlds. The values below were copied from that code in October 2026. Where they
> disagree, the code wins — then fix this page. The look itself came from the
> [premium UI spec](superpowers/specs/2026-10-08-premium-ui-design.md).

Derived from Apple's *Designing Fluid Interfaces* (WWDC 2018), *The Details of UI Typography*
(WWDC 2020), and the eight design principles. Translated to SwiftUI.

**These are tokens, not suggestions.** No raw hex, no raw point size, no raw duration in a view. If a
value is not here, add it to the design system first. The exceptions are deliberate and named: the
pixel-art worlds keep their own inks (see [§10](#10-the-pixel-art-worlds)), and the phone has its own
small token set (see [§11](#11-iphone-and-ipad)).

---

## The through-line

> An interface feels alive when motion starts from the current on-screen value, inherits the user's
> velocity, projects momentum forward, and can be grabbed and reversed at any instant.

Springs are the tool that makes this natural, because they are inherently interruptible and
velocity-aware. Everything in the Motion section follows from that sentence.

---

## 1. Response — kill latency

The moment lag appears, directness "falls off a cliff." This is the foundation.

- **Feedback on press, never on release.** A button reacts to `configuration.isPressed` in its
  `ButtonStyle` — never in the action closure.
- **Audit every delay.** No debounce on the input path. No artificial "feels responsive" timer. No
  waiting for a transition to finish before accepting the next input.
- **Feedback is continuous during an interaction, not only at its end.** A drag updates 1:1 the
  whole way through.

`XBotButtonStyle` (in `Motion.swift`) is the pattern, and `PrimaryButtonStyle` and
`QuietButtonStyle` do the same:

```swift
public struct XBotButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.1, bounce: 0), value: configuration.isPressed)
    }
}
```

---

## 2. Motion tokens

Apple replaced mass/stiffness/damping with two designer-facing parameters, and SwiftUI's
`.spring(duration:bounce:)` maps to them directly:

- **`bounce`** — overshoot. `0` = critically damped, smooth settle. Higher = bouncier.
- **`duration`** — Apple's *response*: how quickly the value reaches its target. **Not a fixed
  duration.** A spring has no fixed duration; settle time emerges.

```swift
public enum Motion {
    /// Default for everything. No overshoot.
    public static let standard   = Animation.spring(duration: 0.4, bounce: 0)
    /// Small state changes: toggles, highlights, badges.
    public static let quick      = Animation.spring(duration: 0.25, bounce: 0)
    /// Panels, sheets, drawers.
    public static let panel      = Animation.spring(duration: 0.3, bounce: 0.2)
    /// Only after a flick, throw, or drag release.
    public static let momentum   = Animation.spring(duration: 0.4, bounce: 0.2)
    /// Reposition of an existing element.
    public static let reposition = Animation.spring(duration: 0.4, bounce: 0)
    /// Reduce Motion's stand-in: a short cross-fade, not nothing.
    public static let reduced    = Animation.easeOut(duration: 0.15)
}
```

Views animate through `.motion(_:value:)`, never `.animation` with a token directly: the modifier
swaps in `Motion.reduced` when Reduce Motion is on, so no call site can forget.

From Apple's shipped values: move/reposition `damping 1.0 / response 0.4`; rotation
`0.8 / 0.4`; drawer/sheet `0.8 / 0.3`.

### The rules

1. **Default to `bounce: 0`.** Overshoot on a menu that faded in feels wrong. Overshoot on a card
   you flicked feels right. **Bounce is earned by a gesture, not chosen by taste.**
2. **Never `.easeInOut(duration:)` on anything the user can touch.** Fixed-duration curves cannot be
   grabbed mid-flight. They are acceptable only for non-interactive decoration.
3. **Never lock out input during a transition.** A closing panel the user grabs again follows the
   finger — it does not finish closing and then reopen.
4. **Animate from the presentation value, not the target.** SwiftUI does this correctly for spring
   animations on the same property; manual animation must read the live value on interrupt or the
   element visibly jumps.
5. **Decompose 2D motion into independent X and Y springs.** One spring on a 2D distance desyncs
   when the axes have different velocities.

### Velocity handoff

When a gesture ends, motion continues **at the finger's exact velocity**. This is the detail that
separates "fluid" from "fine."

```swift
.onEnded { value in
    withAnimation(.spring(duration: 0.4,
                          bounce: 0.2,
                          initialVelocity: value.velocity.height / distanceRemaining)) {
        offset = target
    }
}
```

### Momentum projection

Do not snap to the nearest boundary from the release point. Project where the gesture was *going*,
then snap to the target nearest the projection. `project(initialVelocity:decelerationRate:)` in
`Motion.swift`:

```swift
/// Apple's projection from the Designing Fluid Interfaces sample. Exponential decay —
/// NOT the textbook v²/(2·decel), which is not what Apple ships.
func project(initialVelocity: CGFloat, decelerationRate: CGFloat = 0.998) -> CGFloat {
    (initialVelocity / 1000) * decelerationRate / (1 - decelerationRate)
}
```

Use `0.998` for scroll feel, `0.99` for snappier.

**Commit vs. revert is decided by velocity sign, not position.** A user who drags a panel a long way
and flicks it back has said "back."

### Rubber-banding

At a boundary, resist progressively. A hard stop reads as frozen. `rubberband(_:dimension:constant:)`:

```swift
func rubberband(_ overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
    (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
}
```

### Spatial consistency

- **Enter and exit along the same path.** The right panel dismisses to the right, always.
- **Anchor to the source.** A popover scales from the control that opened it, not from its own
  centre.
- **Mirror easing on reversible transitions** so the return path matches the outbound one.

### Hint in the direction of travel

Intermediate frames should telegraph the outcome. A panel opening from the right should already be
moving rightward at frame one, not scaling from its centre.

---

## 3. The motion gate

Looping animation costs CPU every frame, whether anyone is looking or not. So **every looping
animation pauses while xBot is not the active app**, and picks up where it was on return.

- `.motionGate()` sits on the main window's root (`XBotApp.swift`). It reads
  `controlActiveState` and sets the `motionPaused` environment value (declared in
  `XBotWorld/Motion.swift`, so the worlds can read it too) to true while the window is inactive.
- Every `TimelineView` that loops passes it on: `paused: motionPaused` (with Reduce Motion where
  that applies). Today that is the text-art wallpaper, the Galaxy stop's pixels and knob on the
  effort slider, the Agents page and its world, the sidebar's miniature world, agent faces and
  sprites.
- The phone does the same from its scene phase: paused whenever the app is not `.active`.

**Measured on the release build:** about 0.0–0.01 % CPU while xBot is in the background, and about
12 % frontmost with an animated wallpaper. A new looping animation that does not read
`motionPaused` breaks the first number; that is a bug, not a trade-off.

---

## 4. Colour

Semantic tokens only, in `Palette.swift`. Every one resolves in light and dark (`dynamic(light,
dark)`). **No view ever names a hex value.**

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `window` | `#F7F7F5` | `#1E1E1E` | The window |
| `sidebar` | `#F0F0EE` | `#191919` | The sidebar |
| `raised` | `#FFFFFF` | `#262626` | Cards, the composer |
| `inset` | `#F2F2F0` | `#202020` | Panels inside cards, the composer's context strip |
| `terminalBackground` | `#FBFBFA` | `#151515` | Behind a terminal's text |
| `hairline` | black 8 % | white 8 % | Borders |
| `hover` | black 4 % | white 5 % | Hover fills |
| `tabSelected` | white 60 % | white 10 % | The selected chat tab |
| `textPrimary` | `#1A1A1A` | `#ECECEC` | Text |
| `textSecondary` / `textTertiary` | the same at 60 % / 40 % | | Quieter text |
| `textInverse` | `#FFFFFF` | `#1A1A1A` | Text on the primary button and toasts |
| `accent` | `#B65E8C` | `#D08AB0` | Sakura: selection, send, focus, links, the Plan chip |
| `running` | `#2C6FD1` | `#4C90EE` | Work in progress |
| `success` | `#2F9E5B` | `#4CB876` | Done |
| `failure` | `#D0453E` | `#F07A72` | Failed |
| `warning` | `#C98A1E` | `#E8A845` | Needs attention |

Each state colour has a `…Tint` at 12 % (dark 18 %; `failureTint` 10 % / 16 %) for the pill it sits
on. Also in `Palette`: the effort slider's plum-to-pink fill and Galaxy blues, the profile heatmap's
four shades of Claude's clay, four code-highlight colours, the six text-art wallpaper inks
(`asciiInk`: mint, amber, rose, sky, violet, snow — brighter on dark, deeper on light), and
`Palette.agent(_:)`, each agent's mark: Claude Code clay (`#D97757` / `#E08A6E`), Codex in ink
(`textPrimary`), Antigravity Google blue (`#1A73E8` / `#8AB4F8`), Copilot purple (`#8250DF` /
`#C297FF`).

**One accent, and it is xBot's own.** The Mac app does not follow the system accent: sakura is used
only for selection, send, focus, links and the Plan chip. Surfaces stay neutral; state colours
appear only where state is meant. (The phone lets the person choose the accent; see §11.)

**Colour is never the only signal.** A status pill is a dot *and* mono capitals ("● CONNECTED"); a
chip that is on changes colour *and* fill. This serves `accessibilityDifferentiateWithoutColor` and
the eight per cent of men who will not see the difference between our green and our amber.

---

## 5. Typography

Apple designs type to change shape with size. The same discipline here. `Typography.swift`:

| Token | Size | Weight | Tracking (modifier) |
| --- | --- | --- | --- |
| `hero` | 26 | semibold | −0.4 (`heroText()`) |
| `title` | 15 | semibold | −0.2 (`titleText()`) |
| `body` | 13 | regular | 0 (`bodyText()`) |
| `reading` | 13.5 | regular | 0, line spacing 4 (`readingText()`, for replies) |
| `emphasis` | 13 | medium | 0 (`emphasisText()`) |
| `chip` | 12 | medium | — |
| `caption` | 11 | regular | +0.1 (`captionText()`) |
| `label` | 10 | medium, SF Mono | +0.6, uppercase (`labelText()`: "3 OF 7 DONE") |
| `mono` | 12 | SF Mono | — |

### Rules

- **Type and tracking together.** Views use the modifiers (`titleText()`, `captionText()` …), which
  set both, because they are not separable choices.
- **Tracking is size-specific, never one value for all sizes.** Large text wants *negative*
  tracking; small text slightly positive.
- **Weight does the hierarchy; sizes stay close.** Hierarchy comes from weight, size and leading as
  a set, not size alone.
- **SF Pro by default, or the person's typeface.** Settings › Appearance › Font can set any family
  installed on the Mac (see §8). Everything except `label` and `mono` follows it.
- **SF Mono for code, paths, logs, branch names, model identifiers and metadata,** whatever typeface
  is chosen, because columns of code need a fixed width. Not for numbers in prose.
- **Tokens are computed, not stored.** Each read looks at `Appearance.shared`, so Observation
  re-renders a view when the family changes. Stored tokens were fixed at first use and a new font
  only appeared after a relaunch.

---

## 6. Space and size

An 8-point base scale. Half-steps exist for optical adjustment; nothing else does.

```swift
public enum Space {
    public static let xxs: CGFloat = 2
    public static let xs:  CGFloat = 4
    public static let s:   CGFloat = 8
    public static let m:   CGFloat = 12
    public static let l:   CGFloat = 16
    public static let xl:  CGFloat = 24
    public static let xxl: CGFloat = 32
}

public enum Radius {
    public static let small:  CGFloat = 6   // rows, chips
    public static let medium: CGFloat = 10  // panels inside cards
    public static let large:  CGFloat = 14  // cards, the composer
}
```

Corners are `RoundedRectangle(…, style: .continuous)`.

`Metrics` holds every fixed size: the sidebar (220–340, ideal 260), the inspector (260–420, ideal
300), the 32 pt title bar, 28 pt rows and icon buttons, 26 pt chips, the 30 pt send button, the
680 pt composer, a 720 pt reading width (wider windows add margin, not line length), the default
window (1280 × 820) and minimum (900 × 600), and the sizes of individual pages and sheets. Add a
size there, with a comment saying what it is for, rather than writing a number in a view.

**Grouping is meaning.** Proximity implies relationship: put a control near what it affects. If a
control needs a label to explain what it does, the mapping is weak — move it.

---

## 7. Depth and surfaces

Two depths, in `Depth.swift`:

| Modifier | Shadow | Use |
| --- | --- | --- |
| `cardShadow()` | black 6 %, radius 1.5, y 1 | A card on the page |
| `floatingShadow()` | black 10 %, radius 12, y 8 | Something over the page: the composer, terminal windows, toasts |
| `raisedSurface(radius:)` | — | `raised` fill plus a `hairline` border, at `Radius.large` by default |

The Mac app uses solid, neutral surfaces with hairlines and these two shadows, not stacked
translucent materials. The one translucent fill is `.regularMaterial` behind the Agents page's
header, so it reads over the world.

The rules that still govern any translucency:

- **Never stack a light translucent surface on another.** Legibility collapses immediately.
- **Dim to focus, separate to keep flow.** A modal task gets a scrim. A parallel, non-blocking panel
  — the inspector — sits beside the conversation, not over it.
- **Put colour on a solid layer,** never on a translucent foreground.
- **Scroll edge effects, not hard dividers,** where content scrolls under something floating.

---

## 8. Appearance: theme, wallpaper, icon, typeface

Settings › Appearance, backed by `Appearance` in `XBotCore` (one shared observable object, because
the window, the Settings window and the type scale all read it).

- **Theme:** Dark (the default), Light, or Match System.
- **Wallpaper** (`Backdrop.swift`): **Sunset** (ships with xBot, the default), **Desktop** (the
  picture on the person's desktop right now), **Choose…** (a picture of their own, copied into
  xBot's folder so the original can move), **Randomize…** (an agent draws a text-art wallpaper,
  still or animated), or **None**.
  - The picture covers the top 62 % of the content (`Metrics.backdropHeight`) and fades into the
    window. Full strength on Home; 38 % behind a conversation, so the text stays the thing you read.
  - In dark mode a photo is dimmed under 42 % black, because a bright picture at full strength
    glares. Text art is drawn at 80 % (dark) or 60 % (light) of the backdrop's strength.
  - Text art is SF Mono in one of the six inks, filling the width, 1–12 frames per second, up to 24
    frames. Reduce Motion shows the first frame; the motion gate pauses it.
  - Drawing one needs an agent that gives structured answers, so only Claude Code and Codex are
    offered.
  - **Reduce Transparency removes the wallpaper.** Pictures are decoded once and cached, because
    decoding a full-size photo on every layout pass made resizing stutter.
  - On the Agents page, the chosen world replaces the wallpaper (see §10).
- **App icon:** Ink (the default), Rose, Sunset, Plum — colours of `xBot.icon`.
- **Typeface:** System (SF Pro) or any family installed on the Mac, with a sample line beneath.
  Code and file names stay in SF Mono. A saved family that is no longer installed falls back to the
  system font.

---

## 9. Feedback

Four kinds: **status, completion, warning, error.** Each has a home.

| Kind | Surface |
| --- | --- |
| Status | `StatusPill`, the running state in the sidebar and tabs |
| Completion | Inline in the conversation; a toast for things done elsewhere |
| Warning | Inline, next to the thing it concerns (the permission menu's note that Antigravity edits with full access) |
| Error | Inline with a specific sentence and, where there is one, an action. Never a modal alert unless the app cannot continue |

**Undo over confirmation.** Deleting a chat is immediate; the toast (`ToastHost`, a dark capsule,
bottom centre) offers Undo.

**Validate inline, not on submit.**

Haptics and sound, should they be added, follow three rules: **causality** (fire on the actual
event), **harmony** (visual, sound and haptic on the same frame), **utility** (only for meaningful
moments, or people learn to ignore all of it). xBot sends no notifications and sets no Dock badge
today.

---

## 10. The pixel-art worlds

The Agents page, the sidebar's miniature and the phone's Agents tab draw the crew in a living world.
All of it is in the `XBotWorld` library, shared by the Mac and the iPhone/iPad so both draw the same
thing.

- **Five settings** (`WorkplaceSetting`): Village, Sky Realm, Underwater Kingdom, Moonbase,
  Enchanted Forest. Chosen on the Agents page and remembered; an unknown saved value falls back to
  Village. The chosen world is the Agents page's edge-to-edge backdrop, in place of the Appearance
  wallpaper on that page only.
- **Original art.** Avatars are original pixel-art chibis *in the manner of* MapleStory Classic — a
  big head, a small body, a dark outline (`#1D1922`) — built from a template per part on a 16 × 24
  grid (`AvatarSprite`). Nothing is copied from another game. Sprites face right and are mirrored to
  face left.
- **Pixels stay pixels.** Sprites are drawn as filled cells in a `Canvas`: 4 pt per sprite pixel on
  the Mac's Agents page (`WorldStage.Metrics.regular`), 3 pt on a phone (`.compact`). Scenery is
  built from cells snapped to the same grid — stepped edges and scanline ellipses, not blurs or
  smooth curves — so it shares the sprites' pixel language.
- **Inks are art, not interface.** Each realm and `AvatarPalette` keep their own colours, separate
  from `Palette`. The world never uses UI tokens, and UI chrome never borrows a world's inks.
- **One clock, from the caller.** A realm draws everything from the date it is given. Under Reduce
  Motion that date is frozen, so every orbit, fish and cloud stops, idle bobbing is zero and mounts
  stay still. The motion gate (§3) pauses the clock while the app is in the background.
- **Decoration does not take input.** Scenery is `.allowsHitTesting(false)` and hidden from
  accessibility; the agents are what you tap (to open their chat), and the page and world picker
  are labelled.
- **Company order, no lines.** HeadMaster stands on the top tier, each manager's team on the tier
  below under them, each agent in a slot of their own where they stroll, sit at a desk to work and
  say what they are doing in a speech bubble.
- **Avatars always draw.** A missing part is the first choice and an out-of-range one wraps, so an
  avatar saved by another version of xBot never fails.

---

## 11. iPhone and iPad

The phone is a remote for the Mac, with a look of its own: **Liquid Glass controls floating over calm
charcoal cards, rounded type, one accent** (`apps/ios/Sources/Glass.swift`).

- **Liquid Glass for controls, not content.** The composer is `.glassEffect(.regular.interactive())`
  on a 24 pt rounded rectangle, with glass circle buttons; send is tinted with the accent when it
  can send. Prominent actions use `.buttonStyle(.glassProminent)`. The bottom tab bar (Home, Chats,
  Agents, Projects, Search; a sidebar on iPad) folds away on scroll (`.tabBarMinimizeBehavior(.onScrollDown)`).
- **Cards** (`.card()`): `secondarySystemGroupedBackground` — charcoal in dark mode — with
  **28 pt continuous corners** (`Glass.radius`), 18 pt padding, a fill a few per cent lighter at the
  top and a hairline highlight on the top edge; a soft shadow in light mode only. One horizontal
  margin everywhere: 16 pt (`Glass.margin`).
- **SF Rounded** for the whole app (`.fontDesign(.rounded)` on the root). Section titles are
  `.title2` bold rounded; big numbers are heavy rounded with monospaced digits. Text styles
  (`.body`, `.footnote`, `.caption2` …) rather than fixed sizes, so Dynamic Type scales them.
- **The accent is the person's.** Settings › Appearance offers eight presets — Orchid `#B55E8C`
  (the default), Violet `#7C5CE6`, Blue `#2F7CF6`, Teal `#14A3A3`, Green `#2FA866`, Amber `#E39A1F`,
  Coral `#E5604D`, Graphite `#6E7280` — plus any custom colour. Every view reads `Theme.accent`, and
  glows and gradients derive from it (`Glass.glow` is a brighter version; `Glass.violet` turns the
  hue 35°). Theme is Match the device, Light or Dark.
- **Provider colours** (`ProviderStyle` in `Accent.swift`) tell agents apart at a glance, each a
  primary and a secondary for gradients: Claude `#D97757`, Codex `#10A37F`, Antigravity `#4285F4`,
  Copilot `#8957E5`, with others reserved (Cursor, OpenCode, Grok, Mistral) and a stable hue for
  anyone else. Home's plan board draws one to four plans as concentric rings in those colours, five
  or more as segments of one arc.
- **Motion** pauses whenever the app is not active, as on the Mac.

---

## 12. Accessibility

Handled in the tokens so no call site can forget.

- **Reduce Motion** → `.motion()` swaps every spring for `Motion.reduced`, a 0.15 s cross-fade.
  Elastic and overshoot drop entirely. Opacity and colour changes that aid comprehension stay.
  **Reduced motion is not no feedback** — it is a gentler, non-vestibular equivalent. Looping
  decoration (text art, worlds, the Galaxy shimmer) stops on a still frame.
- **Reduce Transparency** → the wallpaper is not drawn.
- **Differentiate Without Colour** → never colour alone (§4).
- Decorative art is hidden from VoiceOver; controls built from symbols carry an
  `accessibilityLabel` (`IconButton` uses its help text).
- Avoid full-window moving backgrounds and slow looping oscillations near 0.2 Hz. Ease theme changes
  rather than cutting brightness.

---

## 13. Component inventory

Each lives in one file under `XBotUI/Components/` and takes only tokens. There are no snapshot
tests.

| Component | File | What it is |
| --- | --- | --- |
| `PrimaryButtonStyle` | `Buttons.swift` | The one strong action on a surface: a black capsule (white in dark mode) |
| `QuietButtonStyle` | `Buttons.swift` | A secondary action: text that gets a capsule fill on hover |
| `IconButton` | `Buttons.swift` | A 28 pt symbol button with a hover fill and an accessibility label |
| `Chip` | `Chip.swift` | The composer's quiet rounded control ("● Claude Code · Opus ⌄"), as a menu label or a toggle |
| `Card`, `CardFooter`, `InsetPanel`, `MonoLabel` | `Card.swift` | A titled card with mono metadata and an optional footer; a panel inside it; small mono capitals |
| `StatusPill` | `StatusPill.swift` | A dot and mono capitals on a tint of the state's colour (`PillState`) |
| `SidebarRow` | `SidebarRow.swift` | Icon, title, trailing; selection is a raised fill, not a colour |
| `CodeBlockView` | `CodeBlockView.swift` | A fenced code block: highlighted, copyable, and in a chat a Run button for shell code |
| `ToastHost` | `ToastView.swift` | The current toast, bottom centre, with its action (Undo) |
| `Backdrop`, `AsciiArtView` | `Backdrop.swift` | The wallpaper and the text-art wallpaper (§8) |
| `AppMarkView` | `AppMark.swift` | The xBot mark, from `xBot.icon` |

Feature views (the composer, effort slider, transcript, inspector, Agents page) live in their
feature folders under `XBotUI` and are built from these.

---

## 14. The principles this serves

Named, because they are the vocabulary for arguing about a design.

1. **Purpose** — decide what not to build. Every feature spends the user's attention.
2. **Agency** — offer choices, back them with forgiveness. Easy undo for slips; a confirmation
   dialog only for genuinely destructive and irreversible actions. Overusing confirmation trains
   people to click through it.
3. **Responsibility** — act in the user's interest. Ask for permission at the right moment, for only
   what is needed. Anticipate misuse: an agent with a shell and full access can do real harm, which
   is why the permission mode is on the composer, in plain words, every time.
4. **Familiarity** — build on what people know. A chat app is a chat app. Things that look the same
   behave the same.
5. **Flexibility** — the non-technical path and the terminal-dweller path are the same app at
   different depths.
6. **Simplicity, not minimalism** — burying everything in one place looks minimal and is not simple.
   Common path first, advanced exactly one level deeper.
7. **Craft** — nothing is random. Every spacing, timing, and alignment value is defensible. Jittery
   scrolling and misaligned icons read as carelessness, and carelessness in an app that runs agents
   in your folders reads as untrustworthiness.
8. **Delight** — the result of the other seven, not confetti on top.

**The emotion we are designing for is calm confidence.** The person is letting software act in
their projects on their behalf. Every motion, every colour, and every sentence should make that feel
like a considered decision rather than a leap.
