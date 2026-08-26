# Design System

## Direction

Native macOS utility: the notch and left edge use the same semantic system surface, system typography, SF Symbols, standard selection states, and restrained hierarchy. The product follows the current macOS light or dark appearance automatically.

## Color

- Surface: macOS `windowBackgroundColor` for both floating surfaces so the wallpaper or underlying window cannot tint them differently.
- Text: semantic `primary`, `secondary`, and label colors.
- Accent: the user's macOS accent color for current time, selection, links, and focus only.
- Dividers: macOS `separatorColor`.
- Danger and warning: macOS semantic red and orange. Color never replaces a text or symbol cue.
- Deadline wave: system accent for approaching, semantic orange for urgent, and semantic red for overdue; urgency also controls timing and notification copy, so color is never the only signal.

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
- Notch task surface: a conventional 560-point-wide macOS floating rectangle, with height derived from unfinished task count between 240 and 500 points. It is centered on the built-in display notch, touches the physical top edge with no gap, and uses 16-point continuous corners when fully open. The hit target equals the hardware notch rectangle reported by macOS and never extends into the surrounding menu bar.
- Main app: week-first schedule and task workspaces use the same native sidebar material and the same macOS `windowBackgroundColor` content surface; familiar macOS toolbar and sheets.

Avoid nested cards. Rows are grouped with alignment, rhythm, and hairlines only.

## Motion

- Edge activation delay: 50 ms while preserving the original 6-point-wide middle-edge trigger. Enter: 160 ms short-distance slide/fade; exit: 120 ms after a 90 ms pointer bridge. A 60 Hz pointer-boundary monitor keeps the panel open while the pointer remains in either the trigger or panel, and pre-rasterized content reduces repeated drawing during motion.
- Notch expansion: activation begins after a 35 ms intent filter. The trigger and collapsed mask derive their exact rectangle from `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea`; they do not extend below or beside the physical black notch. The panel window remains at its final geometry while the shape mask grows from that hardware rectangle to the full surface in 180 ms. Content fades in after 35 ms; on exit, content fades first and the shell contracts after 35 ms in 140 ms. Do not pre-rasterize the task `ScrollView` because doing so prevents its lazy rows from reliably drawing. A 60 Hz pointer-boundary monitor keeps the surface open while the pointer is inside the trigger or panel and begins a 70 ms dismissal bridge immediately after the pointer leaves both. Do not animate window geometry or stagger task rows.
- Deadline wave: three 1.4-point outlines leave the exact physical notch in 220 ms intervals, expand over 1.05 seconds, and disappear within 1.7 seconds. A soft same-color shadow supplies light without gradients. The 60 Hz animation timeline runs only while the wave panel is visible and is paused immediately afterward.
- Reminder cadence: timed tasks use approaching/urgent thresholds of 3h/1h for High, 2h/30m for Normal, and 1h/15m for Low. Date-only tasks cue at 09:00 and 19:30, with 20:30 as the effective deadline. Each pre-deadline stage appears once; overdue repeats no more than every two hours.
- Interruption policy: suppress waves and fallback notifications during 23:30–07:30, frontmost full-screen work, Apple `screencaptureui`, or manual overlay pause. On return, merge all pending cues into one wave and at most one fallback notification. Third-party recorders without a public system recording signal require the manual pause control.
- Task completion: immediate check response, 180 ms compression/crossfade, then persistence.
- Do not use gradients or fade masks. Overflow uses the native scroll indicator.
- Reduce Motion: no spring, no stagger, no scale; use 120–160 ms opacity transitions.

## States

Every surface covers loading/reload, empty, populated, overflow, long text, unavailable data, and paused edge-trigger states. Empty schedule explains how to add an event; empty tasks communicates completion without celebration effects that linger.
