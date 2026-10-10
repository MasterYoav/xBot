# Agents workplace worlds

## Approved scope

Restore the earlier Sky Realm dragon and add three distinct animated pixel-art environments alongside Village and Sky Realm:

- **Underwater Kingdom** — coral reef, jellyfish, palace ruins, schools of fish and a passing whale; bubble habitats for the crew.
- **Moonbase** — Earth over the lunar horizon, meteor showers, craters, domes, antennas and orbital workstations.
- **Enchanted Forest** — ancient trees, treehouses, glowing mushrooms, fireflies and woodland creatures; wooden/leaf work platforms.

The user approved this scope in the UI before implementation. This extends the existing Agents workplace, not the bot runtime or computer model.

The subsequent layout correction makes the chosen world the Agents tab's sole edge-to-edge backdrop. It replaces Appearance's wallpaper on that tab, not on other tabs. The crew's stage is transparent and no longer a separately framed environment; neutral material keeps its header and cards readable.

## Implementation

1. Extend `WorkplaceSetting` while retaining `village` and `skyRealm` persisted identifiers and the Village fallback for unknown values.
2. Replace the expanding segmented selector with a native World menu to avoid crowding the Agents header.
3. Route each setting to distinct full-tab layered scenery and agent mounts, reusing existing avatars, working state, speech bubbles, chat actions and holographic screens. Measure the crew stage bottom in the root coordinate space to align the background terrain. Continue the same world's terrain behind lower cards.
4. Freeze decorative animation and bobbing for Reduce Motion. Foreground scenery cannot intercept input. Keep worlds decorative and hidden from accessibility while labeling the workplace and picker.
5. Recover the original dragon drawing from actual prior source/history, not an approximation.

## Verification

- Test-first five-world availability; test persistence for every world and unknown-value fallback.
- Build test targets and run the suite; report pre-existing failures separately.
- Inspect real running-app screenshots for each environment and the restored dragon.
- Exercise the World menu, agent chat action and a real working agent.
- Build signed Release, install and verify `/Applications/XBot.app`, then publish a stacked PR on `ascii-wallpaper`, continuing the existing PR chain toward `master`.

No new dependencies, services, credentials, data migration or agent permissions.

## Verified delivery

- Debug build including test targets and signed arm64 Release build succeeded.
- Full suite: 317 tests passed across the Brain, Core and UI test bundles, including Agents-only wallpaper routing and scroll/short-viewport terrain-alignment regression tests.
- All three new scenes and Sky Realm inspected in real-app snapshots, including the passing whale and restored dragon.
- A real isolated Forge turn showed the seated pose, holographic screen, speech bubble and Working now entry. Temporary probe code was removed afterwards.
- Installed World menu exposes all five entries; selecting Underwater Kingdom switches the live scene. Clicking Forge opens its chat; the empty QA-created chat was removed, and the prior Village selection restored.
- Installed binary matches the signed build byte-for-byte and includes all three new world titles.
- All five full-tab worlds inspected after the layout correction; the normal new-chat tab still shows its unchanged sunset wallpaper. The reinstalled Release app's Agents page shows the sole world background in dark appearance too.
- Tested real scrolling to 200 points and a 644-point-tall window, both separately and together. Terrain uses the measured stage bottom without a viewport-height clamp; clipping remains at the viewport boundary. Temporary layout probes were removed before the final builds.
- Independent review found no introduced security concerns or logic errors. It noted the inherited mixed working/idle Reduce Motion world-stepping behavior as a follow-up; the new decorative animation clock is frozen correctly.

### Dragon provenance

Recovered from the original pre-rebuild source payload (message 8348 in the local xBot conversation), not recreated. The restored `dragon` function is an exact text match; its SHA-256 is `b8d55c56348cbf9cb2f7bd299f2ee000f89918afb6de27fab8ed7490d09507cb`. Current visibility layering is retained separately.
