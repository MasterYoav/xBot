# Agents sidebar: one row in its world

## User scope

The annotated Agents block between Inbox and Projects becomes a miniature of the selected agent world. Remove the All control and the old header plus; place one hiring plus immediately after the heads. The follow-up request removes the featured-agent pill: every animated head, including HeadMaster, is in the same row.

## Interaction

- Region title, scenery and empty space open the existing Agents world page.
- Every avatar keeps its existing `openLatestChat` action.
- Plus keeps the existing hiring action; it is not world-only navigation.
- Use a sibling background button, not a parent tap gesture or nested buttons.
- Decorative artwork does not participate in hit testing or accessibility.

## Rendering

Reuse the same `WorldScenery` renderer as the full tab, scaled to the sidebar block. This shares the remembered world selection and avoids a new theme. Retain `AgentFace` unchanged, with names, roles and current status in hover help. Freeze decorative art for Reduce Motion and use the existing reduced-motion-aware hover token.

## Verified

- Debug build including test targets and signed arm64 Release build succeeded.
- Full existing suite: 317 tests pass.
- Installed binary matches the signed Release build and signature verification succeeds.
- Real installed app AX bounds show all four faces at the same y-coordinate; one plus follows them, and All is absent.
- Region navigation opens the world. Clicking Forge opens only its existing chat. Plus opens Hire an agent; Cancel dismisses without saving a new agent.
- Switching from Enchanted Forest to Moonbase changes both the full world and sidebar preview; original Enchanted Forest choice restored.
- Temporary QA instrumentation removed; no new dependency, permission or persistent user-data change.

The GitHub base chain has an existing Swift 6.3.3 compiler crash in unchanged Composer.swift; local builds use the installed Xcode toolchain.
