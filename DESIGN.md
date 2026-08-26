# Design System

## Direction

Native macOS utility: the notch and left edge use the same semantic system surface, system typography, SF Symbols, standard selection states, and restrained hierarchy. The product follows the current macOS light or dark appearance automatically.

## Color

- Surface: macOS `windowBackgroundColor` for both floating surfaces so the wallpaper or underlying window cannot tint them differently.
- Text: semantic `primary`, `secondary`, and label colors.
- Accent: the user's macOS accent color for current time, selection, links, and focus only.
- Dividers: macOS `separatorColor`.
- Danger and warning: macOS semantic red and orange. Color never replaces a text or symbol cue.

No gradients and no fixed light/dark palette. Appearance always follows macOS.

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
- Notch task surface: 600 points wide, with height derived from unfinished task count between 240 and 500 points. It is centered on the built-in display notch; lower corners are 14 points.
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
