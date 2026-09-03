# Design system

Derived from Apple's *Designing Fluid Interfaces* (WWDC 2018), *The Details of UI Typography*
(WWDC 2020), and the eight design principles. Translated to SwiftUI.

**These are tokens, not suggestions.** No raw hex, no raw point size, no raw duration in a view. If a
value is not here, add it here first.

---

## The through-line

> An interface feels alive when motion starts from the current on-screen value, inherits the user's
> velocity, projects momentum forward, and can be grabbed and reversed at any instant.

Springs are the tool that makes this natural, because they are inherently interruptible and
velocity-aware. Everything in the Motion section follows from that sentence.

---

## 1. Response — kill latency

The moment lag appears, directness "falls off a cliff." This is the foundation.

- **Feedback on press, never on release.** A button highlights on `onLongPressGesture(minimumDuration: 0)`
  or a `ButtonStyle` that reacts to `configuration.isPressed` — never in the action closure.
- **Audit every delay.** No debounce on the input path. No artificial "feels responsive" timer. No
  waiting for a transition to finish before accepting the next input.
- **Feedback is continuous during an interaction, not only at its end.** A drag updates 1:1 the
  whole way through.

```swift
struct XBotButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
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
    public static let standard  = Animation.spring(duration: 0.4, bounce: 0)
    /// Small state changes: toggles, highlights, badges.
    public static let quick     = Animation.spring(duration: 0.25, bounce: 0)
    /// Panels, sheets, drawers. Momentum-adjacent.
    public static let panel     = Animation.spring(duration: 0.3, bounce: 0.2)
    /// Only after a flick, throw, or drag release.
    public static let momentum  = Animation.spring(duration: 0.4, bounce: 0.2)
    /// Reposition of an existing element.
    public static let reposition = Animation.spring(duration: 0.4, bounce: 0)
}
```

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
then snap to the target nearest the projection.

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

At a boundary, resist progressively. A hard stop reads as frozen.

```swift
func rubberband(_ overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
    (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
}
```

### Spatial consistency

- **Enter and exit along the same path.** The right panel dismisses to the right, always.
- **Anchor to the source.** A popover scales from the control that opened it, not from its own
  centre. `.transformOrigin` on the trigger's anchor.
- **Mirror easing on reversible transitions** so the return path matches the outbound one.

### Hint in the direction of travel

Intermediate frames should telegraph the outcome. Control Center's modules "grow up and out toward
your finger." A panel opening from the right should already be moving rightward at frame one, not
scaling from its centre.

---

## 3. Colour

Semantic tokens only. Every one resolves in light and dark. **No view ever names a hex value.**

```swift
public enum Palette {
    // Surfaces
    public static let windowBackground   = Color("WindowBackground")
    public static let railBackground     = Color("RailBackground")
    public static let panelBackground    = Color("PanelBackground")
    public static let elevatedSurface    = Color("ElevatedSurface")

    // Message bubbles — from the Grok Bot reference
    public static let bubbleIncoming     = Color("BubbleIncoming")     // light neutral fill
    public static let bubbleIncomingText = Color("BubbleIncomingText")
    public static let bubbleOutgoing     = Color("BubbleOutgoing")     // near-black
    public static let bubbleOutgoingText = Color("BubbleOutgoingText") // white

    // Text
    public static let textPrimary        = Color.primary
    public static let textSecondary      = Color.secondary
    public static let textTertiary       = Color("TextTertiary")

    // State
    public static let stateRunning       = Color("StateRunning")       // green
    public static let stateReconnecting  = Color("StateReconnecting")  // amber
    public static let stateStopped       = Color("StateStopped")       // neutral
    public static let stateFailed        = Color("StateFailed")        // red
    public static let attention          = Color("Attention")          // needs-you accent

    // Agent identity — the avatar palette from the reference picker
    public static let agentColors: [Color] = [
        Color("AgentBlack"), Color("AgentBrown"), Color("AgentRed"),
        Color("AgentOrange"), Color("AgentAmber"), Color("AgentGreen"),
        Color("AgentTeal"),  Color("AgentBlue"),  Color("AgentPurple"),
        Color("AgentPink"),  Color("AgentGrey"),
    ]
}
```

**Accent colour follows the system.** The user's macOS accent is theirs. We do not override it.

**Colour is never the only signal.** The runtime status dot has a shape as well as a colour, for
`accessibilityDifferentiateWithoutColor` and for the eight percent of men who will not see the
difference between our green and our amber.

---

## 4. Typography

Apple designs type to change shape with size. The same discipline here.

```swift
public enum Type {
    public static let displayTitle  = Font.system(size: 28, weight: .semibold, design: .default)
    public static let sectionTitle  = Font.system(size: 17, weight: .semibold)
    public static let body          = Font.system(size: 13)
    public static let bodyEmphasis  = Font.system(size: 13, weight: .medium)
    public static let caption       = Font.system(size: 11)
    public static let mono          = Font.system(size: 12, design: .monospaced)
}
```

### Rules

- **Tracking is size-specific, never one value for all sizes.** Large display text wants *negative*
  tracking — letters read too far apart as they grow. Small text wants slightly positive tracking.
  `displayTitle` gets `.tracking(-0.4)`; body stays at `0`; `caption` gets `+0.1`.
- **Leading tracks size inversely.** Tight on large headings, looser on body copy.
- **Hierarchy from weight + size + leading as a set,** not size alone. Weight adds presence without
  taking space.
- **The system font, always.** San Francisco already ships optical sizing, tracking tables, and
  legibility tuning. Overriding it needs a reason we do not have.
- **`design: .monospaced` for code, paths, logs, and model identifiers.** Not for numbers in prose.
- **Dynamic Type is respected and the layout scales with it.** Spacing in relative units. A larger
  text size must not clip a label or break the rail.

---

## 5. Space

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
    public static let small:  CGFloat = 6   // badges, chips
    public static let medium: CGFloat = 10  // cards, fields
    public static let large:  CGFloat = 18  // message bubbles
    public static let xlarge: CGFloat = 22  // the composer
    public static let avatar: CGFloat = 12  // rail items
}
```

**Grouping is meaning.** Proximity implies relationship: put a control near what it affects. If a
control needs a label to explain what it does, the mapping is weak — move it.

---

## 6. Materials and depth

Translucency is a floating functional layer that brings structure without stealing focus.

```swift
public enum Material {
    public static let rail       = SwiftUI.Material.bar          // structural, heavier
    public static let panel      = SwiftUI.Material.regular
    public static let popover    = SwiftUI.Material.thick        // floating, over content
    public static let overlayPill = SwiftUI.Material.ultraThin   // the status pill
}
```

### Rules

- **Material weight encodes hierarchy.** Darker/heavier separates structural regions (the rail).
  Lighter draws attention to interactive elements.
- **Never stack a light translucent surface on another.** Legibility collapses immediately.
- **Bigger surfaces read as thicker** — stronger blur, deeper shadow than a small chip.
- **Dim to focus, separate to keep flow.** A modal task gets a scrim and pushes the background back.
  A parallel non-blocking panel — our right-hand panel — uses translucency and offset **without** a
  scrim, so the flow is not broken. This is why the settings panel in the reference sits beside the
  conversation rather than over it.
- **Vibrancy for text over translucency.** Over a blurred surface, do not use flat grey text — higher
  contrast, slightly heavier weight, a small tracking bump. Put colour on a solid layer, never on the
  translucent foreground.
- **Scroll edge effects, not hard dividers.** Where the conversation scrolls under the floating
  header, fade a small gradient mask. No 1px border.
- **Materialise, don't fade.** A glass surface animates blur radius *and* scale together on enter, so
  it reads as a material arriving rather than an opacity ramp.

---

## 7. Feedback

Four kinds: **status, completion, warning, error.** Each has a home.

| Kind | Surface |
| --- | --- |
| Status | The floating pill (`Reconnecting`), the rail dot, the panel |
| Completion | Inline in the conversation, or a haptic + subtle motion |
| Warning | Inline, next to the thing it concerns |
| Error | Inline with a specific sentence and an action. Never a modal alert unless the app cannot continue |

**Validate inline, not on submit.** An API key is checked as it is pasted, not when Continue is
pressed.

**Haptics and sound**, where the Mac supports them (trackpad):

1. **Causality** — fire on the actual causal event, and match the character to the action.
2. **Harmony** — the visual, the sound, and the haptic land on the **same frame**. Latency between
   them destroys the illusion.
3. **Utility** — only for meaningful moments: a turn completing, an agent asking for help, a
   snap-to. Over-feedback trains people to ignore all of it.

**The one that earns it:** an agent finishing a long task while the window is in the background gets
a notification. An agent asking for a handover gets a notification *and* a dock badge, because it is
blocked on the human.

---

## 8. Accessibility

Handled in the tokens so no call site can forget.

```swift
@Environment(\.accessibilityReduceMotion)       var reduceMotion
@Environment(\.accessibilityReduceTransparency) var reduceTransparency
```

- **Reduce motion** → springs become short opacity cross-fades. Elastic and overshoot drop entirely.
  Opacity and colour changes that aid comprehension stay. **Reduced motion is not no feedback** — it
  is a gentler, non-vestibular equivalent.
- **Reduce transparency** → materials become opaque fills, blur off.
- **Increase contrast** → near-solid backgrounds with defined borders.
- Avoid full-window moving backgrounds and slow looping oscillations near 0.2 Hz. Ease theme changes
  rather than cutting brightness.
- Make large moving surfaces semi-transparent while travelling and settle them back to full opacity.

`Motion.standard` returns a cross-fade when `reduceMotion` is set. The view does not branch.

---

## 9. Component inventory

Each lives in one file under `XBotUI/Components/` (or the feature folder) and takes only tokens.
**Snapshot tests are planned, not wired yet** — the inventory below is the target set.

| Component | Notes |
| --- | --- |
| `AgentAvatar` | Shape + colour + optional image. Status ring. Three sizes |
| `RailItem` | Avatar, selection state, unread dot, attention badge |
| `MessageBubble` | Incoming/outgoing, streaming state, hover actions |
| `StreamingText` | Incremental rendering. Never re-lays-out the whole message per token |
| `Composer` | Growing text field, attach, mic, send, disabled-with-reason |
| `StatusPill` | The floating `Reconnecting` capsule. `ultraThin`, materialises |
| `PanelSection` | Collapsible section in the right panel |
| `ScreenView` | The live browser frame. Aspect-preserving, take-control overlay |
| `ActivityRow` | A command, its exit code, its output. Monospaced |
| `ProviderRow` | Settings → Models. Name, state, action |
| `KeyField` | Secure entry, paste-tolerant, inline validation |
| `AvatarPicker` | Shape grid + colour swatches + Generate/Upload/Reset |
| `CommandPalette` | ⌘K. Search or create agents, ⌘1–9 shortcuts |
| `EmptyState` | Never generic. Always a sentence and an action |
| `DestructiveConfirm` | Two-step. Names what is lost. Used sparingly |

---

## 10. The principles this serves

Named, because they are the vocabulary for arguing about a design.

1. **Purpose** — decide what not to build. Every feature spends the user's attention.
2. **Agency** — offer choices, back them with forgiveness. Easy undo for slips; a confirmation
   dialog only for genuinely destructive and irreversible actions. Overusing confirmation trains
   people to click through it.
3. **Responsibility** — act in the user's interest. Ask for permission at the right moment, for only
   what is needed. Anticipate misuse: an agent with a browser and a shell can do real harm, which is
   why the gateway exists and why handover is a first-class feature.
4. **Familiarity** — build on what people know. A chat app is a chat app. Close is top-left. Things
   that look the same behave the same.
5. **Flexibility** — the non-technical path and the terminal-dweller path are the same app at
   different depths.
6. **Simplicity, not minimalism** — burying everything in one place looks minimal and is not simple.
   Common path first, advanced exactly one level deeper.
7. **Craft** — nothing is random. Every spacing, timing, and alignment value is defensible. Jittery
   scrolling and misaligned icons read as carelessness, and carelessness in an app that drives a
   browser with your logins in it reads as untrustworthiness.
8. **Delight** — the result of the other seven, not confetti on top.

**The emotion we are designing for is calm confidence.** The user is handing a piece of software a
browser with their real logins in it. Every motion, every colour, and every sentence should make that
feel like a considered decision rather than a leap.
