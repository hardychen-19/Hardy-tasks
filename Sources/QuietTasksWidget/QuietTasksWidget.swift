import AppIntents
import SwiftUI
import WidgetKit

struct SubtaskItem: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var done: Bool
    var createdAt: Date
    var updatedAt: Date?
}

struct TaskItem: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var deadline: Date?
    var done: Bool
    var createdAt: Date
    var notes: String?
    var priority: TaskPriority?
    var updatedAt: Date?
    var completedAt: Date?
    var subtasks: [SubtaskItem]? = nil
    var recurrence: TaskRecurrence? = nil
    var pinned: Bool? = nil
    var source: TaskSource? = nil
    var externalID: String? = nil
    var externalListID: String? = nil
    var externalUpdatedAt: Date? = nil
    var deadlineHasTime: Bool? = nil

    var taskPriority: TaskPriority {
        priority ?? .normal
    }

    var taskSubtasks: [SubtaskItem] {
        subtasks ?? []
    }

    var isPinned: Bool {
        pinned ?? false
    }

    var isGoogleTask: Bool {
        source == .google
    }

    var showsDeadlineTime: Bool {
        deadlineHasTime ?? true
    }

    var completedSubtaskCount: Int {
        taskSubtasks.filter(\.done).count
    }

    var subtaskProgressText: String? {
        guard !taskSubtasks.isEmpty else { return nil }
        return "\(completedSubtaskCount)/\(taskSubtasks.count)"
    }
}

enum TaskSource: String, Codable, Equatable {
    case google
}

enum TaskPriority: String, CaseIterable, Codable, Identifiable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        }
    }

    var rank: Int {
        switch self {
        case .high: 0
        case .normal: 1
        case .low: 2
        }
    }

    var symbol: String {
        switch self {
        case .low: "arrow.down"
        case .normal: "equal"
        case .high: "exclamationmark"
        }
    }
}

enum TaskRecurrence: String, CaseIterable, Codable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    func nextDate(after deadline: Date, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let component: Calendar.Component = switch self {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        }

        var next = calendar.date(byAdding: component, value: 1, to: deadline) ?? now
        while next <= now {
            next = calendar.date(byAdding: component, value: 1, to: next) ?? now
        }
        return next
    }
}

enum AppearanceMode: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

struct NotificationSettings: Codable, Equatable {
    var enabled: Bool
    var reminderOffsets: [Int]?
}

struct GoogleSyncSettings: Codable, Equatable {
    var clientID: String?
    var isConnected: Bool?
    var selectedTaskListID: String?
    var selectedTaskListTitle: String?
    var lastSyncedAt: Date?
}

struct AppSettings: Codable, Equatable {
    var notifications: NotificationSettings?
    var appearance: AppearanceMode?
    var googleSync: GoogleSyncSettings?
}

enum TaskStore {
    static var fileURL: URL {
        sharedDirectory.appendingPathComponent("tasks.json")
    }

    static var sharedDirectory: URL {
        let directory = URL(fileURLWithPath: "/Users/Shared/QuietTasks", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func load() -> [TaskItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder.taskDecoder.decode([TaskItem].self, from: data)) ?? []
    }

    static func save(_ tasks: [TaskItem]) {
        guard let data = try? JSONEncoder.taskEncoder.encode(normalized(tasks)) else { return }
        try? FileManager.default.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    static func complete(taskID: String) {
        let now = Date()
        let updatedTasks = load().map { item in
            guard item.id == taskID, !item.done, !item.isGoogleTask else { return item }
            var updated = item

            if let recurrence = item.recurrence, let deadline = item.deadline {
                updated.deadline = recurrence.nextDate(after: deadline, now: now)
                updated.subtasks = item.taskSubtasks.map { subtask in
                    var reset = subtask
                    reset.done = false
                    reset.updatedAt = now
                    return reset
                }
                updated.updatedAt = now
                return updated
            }

            updated.done = true
            updated.completedAt = now
            updated.updatedAt = now
            updated.subtasks = item.taskSubtasks.map { subtask in
                var completed = subtask
                completed.done = true
                completed.updatedAt = now
                return completed
            }
            return updated
        }
        save(updatedTasks)
    }

    static func normalized(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            if lhs.done != rhs.done { return !lhs.done }
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if lhs.taskPriority.rank != rhs.taskPriority.rank { return lhs.taskPriority.rank < rhs.taskPriority.rank }
            switch (lhs.deadline, rhs.deadline) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return lhs.createdAt > rhs.createdAt
            }
        }
    }
}

struct WidgetState: Codable, Equatable {
    var pendingCompletionTaskID: String?
}

enum WidgetStateStore {
    static var fileURL: URL {
        TaskStore.sharedDirectory.appendingPathComponent("widget-state.json")
    }

    static func load() -> WidgetState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder.taskDecoder.decode(WidgetState.self, from: data)
        else {
            return WidgetState(pendingCompletionTaskID: nil)
        }
        return state
    }

    static func setPendingCompletionTaskID(_ taskID: String?) {
        guard let data = try? JSONEncoder.taskEncoder.encode(WidgetState(pendingCompletionTaskID: taskID)) else { return }
        try? FileManager.default.createDirectory(at: TaskStore.sharedDirectory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

enum WidgetSettingsStore {
    static var fileURL: URL {
        URL(fileURLWithPath: "/Users/Shared/QuietTasks", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    static func loadAppearance() -> AppearanceMode {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder.taskDecoder.decode(AppSettings.self, from: data)
        else {
            return .system
        }
        return settings.appearance ?? .system
    }
}

extension JSONDecoder {
    static var taskDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var taskEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

struct RequestTaskCompletionIntent: AppIntent {
    static var title: LocalizedStringResource = "Confirm Task Completion"
    static var description = IntentDescription("Shows an inline confirmation prompt in the Hardy Tasks widget.")

    @Parameter(title: "Task ID")
    var taskID: String

    init() {
        taskID = ""
    }

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        WidgetStateStore.setPendingCompletionTaskID(taskID)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct CancelTaskCompletionIntent: AppIntent {
    static var title: LocalizedStringResource = "Cancel Task Completion"
    static var description = IntentDescription("Dismisses the inline completion confirmation prompt.")

    @Parameter(title: "Task ID")
    var taskID: String

    init() {
        taskID = ""
    }

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        if WidgetStateStore.load().pendingCompletionTaskID == taskID {
            WidgetStateStore.setPendingCompletionTaskID(nil)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct CompleteTaskFromWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var description = IntentDescription("Completes a Hardy Tasks task from the desktop widget.")

    @Parameter(title: "Task ID")
    var taskID: String

    init() {
        taskID = ""
    }

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        TaskStore.complete(taskID: taskID)
        if WidgetStateStore.load().pendingCompletionTaskID == taskID {
            WidgetStateStore.setPendingCompletionTaskID(nil)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct QuietEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskItem]
    let appearance: AppearanceMode
    let pendingCompletionTaskID: String?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> QuietEntry {
        QuietEntry(date: Date(), tasks: [
            TaskItem(id: "1", title: "Plan sprint review", deadline: Date(), done: false, createdAt: Date(), notes: nil, priority: .high, updatedAt: nil, completedAt: nil),
            TaskItem(id: "2", title: "Send design notes", deadline: nil, done: false, createdAt: Date(), notes: nil, priority: .normal, updatedAt: nil, completedAt: nil)
        ], appearance: WidgetSettingsStore.loadAppearance(), pendingCompletionTaskID: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuietEntry) -> Void) {
        completion(QuietEntry(
            date: Date(),
            tasks: TaskStore.load(),
            appearance: WidgetSettingsStore.loadAppearance(),
            pendingCompletionTaskID: WidgetStateStore.load().pendingCompletionTaskID
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuietEntry>) -> Void) {
        let entry = QuietEntry(
            date: Date(),
            tasks: TaskStore.load(),
            appearance: WidgetSettingsStore.loadAppearance(),
            pendingCompletionTaskID: WidgetStateStore.load().pendingCompletionTaskID
        )
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30))))
    }
}

struct WidgetPalette {
    var background: Color
    var surface: Color
    var primaryText: Color
    var secondaryText: Color
    var mutedText: Color
    var accent: Color
    var warning: Color
    var danger: Color

    static func palette(appearance: AppearanceMode, colorScheme: ColorScheme) -> WidgetPalette {
        let useLight = appearance == .light || (appearance == .system && colorScheme == .light)
        if useLight {
            return WidgetPalette(
                background: Color(red: 0.93, green: 0.95, blue: 0.93),
                surface: Color.white.opacity(0.72),
                primaryText: Color(red: 0.12, green: 0.14, blue: 0.13),
                secondaryText: Color(red: 0.29, green: 0.36, blue: 0.34),
                mutedText: Color(red: 0.45, green: 0.50, blue: 0.48),
                accent: Color(red: 0.18, green: 0.48, blue: 0.52),
                warning: Color(red: 0.78, green: 0.33, blue: 0.20),
                danger: Color(red: 0.83, green: 0.19, blue: 0.28)
            )
        }

        return WidgetPalette(
            background: Color(red: 0.12, green: 0.13, blue: 0.12),
            surface: Color.white.opacity(0.06),
            primaryText: .white,
            secondaryText: Color.white.opacity(0.72),
            mutedText: Color.white.opacity(0.56),
            accent: Color(red: 0.62, green: 0.86, blue: 0.88),
            warning: Color(red: 0.98, green: 0.58, blue: 0.45),
            danger: Color(red: 1.0, green: 0.28, blue: 0.36)
        )
    }
}

struct QuietTasksWidgetView: View {
    var entry: QuietEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    private var palette: WidgetPalette {
        WidgetPalette.palette(appearance: entry.appearance, colorScheme: colorScheme)
    }

    private var openTasks: [TaskItem] {
        entry.tasks.filter { !$0.done }.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if lhs.taskPriority.rank != rhs.taskPriority.rank { return lhs.taskPriority.rank < rhs.taskPriority.rank }
            switch (lhs.deadline, rhs.deadline) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return lhs.createdAt > rhs.createdAt
            }
        }
    }

    private var displayCompletedCount: Int {
        openTasks.isEmpty ? 0 : entry.tasks.filter(\.done).count
    }

    private var displayTotalCount: Int {
        openTasks.isEmpty ? 0 : entry.tasks.count
    }

    private var progress: Double {
        guard displayTotalCount > 0 else { return 0 }
        return Double(displayCompletedCount) / Double(displayTotalCount)
    }

    var body: some View {
        switch family {
        case .systemSmall:
            widgetContent(taskLimit: 2, compact: true)
        case .systemLarge:
            widgetContent(taskLimit: 7, compact: false)
        default:
            widgetContent(taskLimit: 4, compact: false)
        }
    }

    private func widgetContent(taskLimit: Int, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            header(compact: compact)
            progressView(compact: compact)

            if openTasks.isEmpty {
                Spacer()
                Text("No open tasks")
                    .font(compact ? .caption.bold() : .headline)
                    .foregroundStyle(palette.mutedText)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                    ForEach(Array(openTasks.prefix(taskLimit))) { task in
                        taskRow(task, compact: compact)
                    }

                    if openTasks.count > taskLimit {
                        Text("+ \(openTasks.count - taskLimit) more")
                            .font(.caption.bold())
                            .foregroundStyle(palette.mutedText)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetAccentable(false)
        .containerBackground(palette.background, for: .widget)
    }

    private func header(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: compact ? 1 : 2) {
                Text(entry.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(compact ? .system(size: 9, weight: .bold) : .caption.bold())
                    .foregroundStyle(palette.danger)
                    .textCase(.uppercase)
                    .lineLimit(1)
                Text("Tasks")
                    .font(compact ? .title2.bold() : .title.bold())
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Link(destination: URL(string: "quiettasks://add")!) {
                Image(systemName: "plus")
                    .font(compact ? .headline.bold() : .title2.bold())
                    .foregroundStyle(palette.accent)
                    .frame(width: compact ? 32 : 38, height: compact ? 32 : 38)
                    .background(palette.surface, in: Circle())
            }
        }
    }

    private func progressView(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 6) {
            Text("\(displayCompletedCount) / \(displayTotalCount) done")
                .font(.caption.bold())
                .monospacedDigit()
                .foregroundStyle(palette.accent)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.mutedText.opacity(0.25))
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: max(5, proxy.size.width * progress))
                }
            }
            .frame(height: compact ? 5 : 6)
        }
        .padding(compact ? 9 : 10)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
    }

    private func taskRow(_ task: TaskItem, compact: Bool) -> some View {
        HStack(alignment: .top, spacing: compact ? 6 : 8) {
            completionControl(for: task, compact: compact)

            VStack(alignment: .leading, spacing: compact ? 3 : 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if task.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: compact ? 7 : 8, weight: .bold))
                            .foregroundStyle(palette.accent)
                    }

                    if task.isGoogleTask {
                        WidgetSourceBadge(compact: compact, palette: palette)
                    } else {
                        WidgetPriorityBadge(priority: task.taskPriority, compact: compact, palette: palette)
                    }

                    Text(task.title)
                        .font(compact ? .caption.bold() : .headline)
                        .foregroundStyle(palette.accent)
                        .lineLimit(compact ? 1 : 2)
                }

                if !compact {
                    HStack(spacing: 7) {
                        if let deadline = task.deadline {
                            Text(deadlineText(deadline, for: task))
                        }
                        if let recurrence = task.recurrence {
                            Label(recurrence.title, systemImage: "repeat")
                        }
                        if let progress = task.subtaskProgressText {
                            Label(progress, systemImage: "checklist")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(palette.mutedText)
                    .lineLimit(1)
                } else if let progress = task.subtaskProgressText {
                    Text(progress)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(palette.mutedText)
                }

                if entry.pendingCompletionTaskID == task.id, !task.isGoogleTask {
                    completionPrompt(for: task, compact: compact)
                }

                if !compact && !task.taskSubtasks.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(task.taskSubtasks.prefix(2))) { subtask in
                            Link(destination: task.isGoogleTask ? googleURL(for: task) : subtaskURL(task: task, subtask: subtask)) {
                                HStack(spacing: 5) {
                                    Image(systemName: subtask.done ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 9, weight: .bold))
                                    Text(subtask.title)
                                        .strikethrough(subtask.done)
                                        .lineLimit(1)
                                }
                                .font(.caption2)
                                .foregroundStyle(subtask.done ? palette.mutedText.opacity(0.75) : palette.secondaryText)
                            }
                        }
                    }
                }
            }
        }
        .padding(compact ? 6 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
    }

    @ViewBuilder
    private func completionControl(for task: TaskItem, compact: Bool) -> some View {
        if task.isGoogleTask {
            Image(systemName: "circle")
                .font(compact ? .caption.bold() : .callout.bold())
                .foregroundStyle(palette.mutedText)
        } else {
            Button(intent: RequestTaskCompletionIntent(taskID: task.id)) {
                Image(systemName: entry.pendingCompletionTaskID == task.id ? "checkmark.circle" : "circle")
                    .font(compact ? .caption.bold() : .callout.bold())
                    .foregroundStyle(palette.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private func completionPrompt(for task: TaskItem, compact: Bool) -> some View {
        HStack(spacing: compact ? 5 : 7) {
            Text("Complete?")
                .font(compact ? .system(size: 8, weight: .bold) : .caption.bold())
                .foregroundStyle(palette.primaryText)

            Button(intent: CancelTaskCompletionIntent(taskID: task.id)) {
                Text("Cancel")
                    .font(compact ? .system(size: 8, weight: .bold) : .caption.bold())
                    .foregroundStyle(palette.mutedText)
            }
            .buttonStyle(.plain)

            Button(intent: CompleteTaskFromWidgetIntent(taskID: task.id)) {
                Text("Done")
                    .font(compact ? .system(size: 8, weight: .bold) : .caption.bold())
                    .foregroundStyle(palette.background)
                    .padding(.horizontal, compact ? 6 : 8)
                    .padding(.vertical, compact ? 2 : 3)
                    .background(palette.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .lineLimit(1)
        .padding(.top, compact ? 1 : 2)
    }

    private func completeURL(for task: TaskItem) -> URL {
        var components = URLComponents()
        components.scheme = "quiettasks"
        components.host = "complete"
        components.queryItems = [URLQueryItem(name: "id", value: task.id)]
        return components.url!
    }

    private func subtaskURL(task: TaskItem, subtask: SubtaskItem) -> URL {
        var components = URLComponents()
        components.scheme = "quiettasks"
        components.host = "subtask"
        components.queryItems = [
            URLQueryItem(name: "task", value: task.id),
            URLQueryItem(name: "subtask", value: subtask.id)
        ]
        return components.url!
    }

    private func googleURL(for task: TaskItem) -> URL {
        var components = URLComponents()
        components.scheme = "quiettasks"
        components.host = "google"
        components.queryItems = [URLQueryItem(name: "id", value: task.id)]
        return components.url!
    }

    private func deadlineText(_ deadline: Date, for task: TaskItem) -> String {
        if task.showsDeadlineTime {
            return deadline.formatted(date: .abbreviated, time: .shortened)
        }
        return deadline.formatted(date: .abbreviated, time: .omitted)
    }
}

struct WidgetPriorityBadge: View {
    var priority: TaskPriority
    var compact: Bool
    var palette: WidgetPalette

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: priority.symbol)
                .font(.system(size: compact ? 7 : 8, weight: .bold))
            Text(priority.title)
                .font(.system(size: compact ? 8 : 9, weight: .bold))
        }
        .foregroundStyle(priorityColor)
        .padding(.horizontal, compact ? 5 : 6)
        .padding(.vertical, compact ? 2 : 3)
        .background(priorityColor.opacity(0.14), in: Capsule())
        .lineLimit(1)
    }

    private var priorityColor: Color {
        switch priority {
        case .high:
            palette.warning
        case .normal:
            palette.accent
        case .low:
            palette.mutedText
        }
    }
}

struct WidgetSourceBadge: View {
    var compact: Bool
    var palette: WidgetPalette

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "link")
                .font(.system(size: compact ? 7 : 8, weight: .bold))
            Text("Google")
                .font(.system(size: compact ? 8 : 9, weight: .bold))
        }
        .foregroundStyle(palette.accent)
        .padding(.horizontal, compact ? 5 : 6)
        .padding(.vertical, compact ? 2 : 3)
        .background(palette.accent.opacity(0.14), in: Capsule())
        .lineLimit(1)
    }
}

struct QuietTasksWidget: Widget {
    let kind = "QuietTasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            QuietTasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Hardy Tasks")
        .description("Shows open Hardy Tasks on the desktop.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .containerBackgroundRemovable(false)
    }
}
