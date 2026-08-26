# Design System

## Direction

Black Monolith with Tidal Time: the notch becomes a continuous black task surface; the left edge reveals a translucent day instrument organized by time rather than cards.

## Color

- Notch Black: `#050607` — notch continuity and deepest surface.
- Graphite: `#15191D` — primary translucent panel material.
- Deep Lake Blue: `#195A73` — selected and focused states.
- Clear Water Cyan: `#55C5C8` — current time, completion feedback, and primary focus.
- Mist White: `#F2F6F7` — primary text.
- Secondary text: Mist White at 62–72% opacity, adjusted to maintain contrast.
- Danger: system red; warning: system orange. Color never replaces a text or symbol cue.

No gradients. Frosted material is functional separation, not decoration.

## Typography

Use the macOS system font and SF Symbols. The hierarchy uses a fixed native scale:

- Display date: 36 pt, regular or medium.
- Surface title: 22 pt, semibold.
- Event/task title: 16 pt, medium.
- Time: 15 pt, regular, monospaced digits.
- Metadata: 12–13 pt, regular.

Chinese titles are limited to two lines; time and deadlines never wrap. Weight, spacing, and opacity establish hierarchy before color.

## Spacing

Use a 4-point base scale: 4, 8, 12, 16, 24, 32, 48. Related metadata stays within 4–8 points; rows use 12–16 points internally; major surface groups use 24–32 points.

## Surfaces

- Edge schedule: 388 points wide and exactly fills the usable height between the menu bar and Dock. It never crosses either system region. The time axis preserves true position while compact event rows use collision-safe spacing and single-line truncation.
- Notch task surface: 600 points wide by up to 480 points high, centered on the built-in display notch. Its top edge visually merges with the notch; lower corners are 14 points.
- Main app: week-first schedule workspace with a task sidebar; familiar macOS toolbar and sheets.

Avoid nested cards. Rows are grouped with alignment, rhythm, and hairlines only.

## Motion

- Edge activation delay: about 250 ms. Enter: 200 ms short-distance slide/fade; exit: 150 ms after a 350 ms hover bridge.
- Notch expansion: 180 ms short-distance slide/fade with a pre-laid-out fixed-size surface. Do not animate window height or stagger task rows.
- Task completion: immediate check response, 180 ms compression/crossfade, then persistence.
- Do not use gradients or fade masks. Overflow uses the native scroll indicator.
- Reduce Motion: no spring, no stagger, no scale; use 120–160 ms opacity transitions.

## States

Every surface covers loading/reload, empty, populated, overflow, long text, unavailable data, and paused edge-trigger states. Empty schedule explains how to add an event; empty tasks communicates completion without celebration effects that linger.
