# Quiet Tasks

Quiet Tasks is a minimal macOS to-do app with a real desktop widget.

I wanted a simple task widget that could live on the macOS desktop like the built-in widgets, show only the tasks that still need attention, and stay visually quiet. I could not find one that felt right, so this project exists for anyone who wants the same thing.

Feel free to download it, use it, fork it, and contribute.

## What It Does

- Native macOS app built with SwiftUI.
- Real WidgetKit desktop widget, available in small, medium, and large sizes.
- Open, Today, All Tasks, and Done views.
- Add, edit, delete, complete, and restore tasks.
- Optional deadlines with a compact date/time popover.
- Low, Normal, and High priority options.
- Global notification defaults for deadline reminders.
- One-level subtasks with completion tracking.
- Daily, weekly, and monthly recurring tasks.
- Pinned tasks that stay above the regular list.
- System, light, and dark appearance modes for the app and widget.
- Optional Google Tasks read-only sync for showing Google task lists in Quiet Tasks.
- Widget shows open tasks only, plus progress for what is currently active.
- Completing from the widget opens the app for confirmation before the task is cleared.
- No account or cloud service required for local tasks.

## Daily Flow Product Mode

This branch also turns Quiet Tasks into a native day compass for notched MacBooks:

- Hover the middle section of the left screen edge to reveal today's read-only timeline.
- Hover the notch shoulder to expand a large task surface; unfinished tasks can be checked directly.
- Both surfaces hide automatically and respect Reduce Motion.
- The main app opens to a local week schedule and keeps schedule data separate from task data.
- A menu-bar control opens the app, pauses edge triggers, and manages startup behavior.

The interaction and visual rationale live in [`PRODUCT.md`](PRODUCT.md) and [`DESIGN.md`](DESIGN.md).

## Why This Is Better

Most to-do apps are either full productivity suites or they do not behave like a proper macOS desktop widget. Quiet Tasks is intentionally smaller:

- It is built around the desktop widget first.
- It keeps the widget readable and minimal instead of busy.
- It keeps completed tasks out of the widget so the desktop stays clean.
- It can show pinned tasks, priority, and subtasks without turning the widget into a dashboard.
- It gives the full app enough tools to manage tasks without turning into a project-management app.
- It is open source, so anyone can improve it.

## Requirements

- macOS with desktop widgets support.
- Xcode installed.
- Swift and WidgetKit support from the installed Xcode toolchain.

The current local development build stores shared app/widget data at:

```text
/Users/Shared/QuietTasks/tasks.json
```

Local schedule data is stored separately at:

```text
/Users/Shared/QuietTasks/schedule.json
```

That lets an unsigned local app and WidgetKit extension share task data during development. A production-distributed version should move this to a signed App Group.

## Download

The latest downloadable build is available from GitHub Releases:

```text
https://github.com/rakeshutekar/quiet-tasks/releases
```

Current builds are unsigned development builds. If macOS blocks the app after download, open **System Settings -> Privacy & Security** and allow it, or build from source with Xcode.

## Google Tasks Read-Only Sync

Quiet Tasks can import tasks from one Google Tasks list and show them in the app and widget. This first version is read-only: edits, completions, and deletes must still happen in Google Tasks.

To use it:

1. Create an OAuth client in Google Cloud for an installed/native app.
2. Add this redirect URI:

```text
com.rakeshutekar.quiettasks:/oauth2redirect
```

3. Open **Quiet Tasks -> Settings -> Google Tasks**.
4. Paste the OAuth client ID.
5. Connect Google, choose a task list, then click **Sync Now**.

Quiet Tasks requests the read-only Google Tasks scope:

```text
https://www.googleapis.com/auth/tasks.readonly
```

Google Tasks due dates are date-only. If a Google task has a due date, Quiet Tasks shows the date without an exact time.

## Install From Source

Clone the repo:

```bash
git clone https://github.com/rakeshutekar/quiet-tasks.git
cd quiet-tasks
```

Build the release app:

```bash
xcodebuild \
  -project QuietTasks.xcodeproj \
  -scheme "Quiet Tasks" \
  -configuration Release \
  -derivedDataPath XcodeDerivedData \
  -destination 'generic/platform=macOS' \
  build
```

Install it into Applications:

```bash
cp -R "XcodeDerivedData/Build/Products/Release/Quiet Tasks.app" /Applications/
```

Open the app once:

```bash
open -a "/Applications/Quiet Tasks.app"
```

Then add the widget:

1. Right-click the desktop.
2. Choose **Edit Widgets**.
3. Search for **Quiet Tasks**.
4. Drag the widget size you want onto the desktop.
5. Click **Done**.

If macOS blocks the app because it was built or downloaded outside the App Store, open **System Settings -> Privacy & Security** and allow it, or build it locally from Xcode.

## Development

Open the project in Xcode:

```bash
open QuietTasks.xcodeproj
```

Main files:

- `Sources/QuietTasksApp/QuietTasksApp.swift` - the macOS app.
- `Sources/QuietTasksWidget/QuietTasksWidget.swift` - the WidgetKit widget.
- `Sources/QuietTasksWidget/WidgetBundle.swift` - widget bundle entry point.
- `Scripts/make-icon.swift` - local icon generation helper.

Build from the command line:

```bash
xcodebuild \
  -project QuietTasks.xcodeproj \
  -scheme "Quiet Tasks" \
  -configuration Release \
  -derivedDataPath XcodeDerivedData \
  -destination 'generic/platform=macOS' \
  build
```

## Contributing

Contributions are welcome. Useful areas to improve:

- Signed release packaging.
- App Group storage for production signing.
- Keyboard shortcuts.
- Two-way Google Tasks sync.
- Better recurring tasks.
- iCloud sync as an optional feature.
- More widget configuration options while keeping the default UI quiet.

Please keep the app minimal, native, and calm. The point is a useful task widget that does not visually take over the desktop.

## License

MIT. Use it freely.
