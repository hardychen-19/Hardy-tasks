import AppKit
import QuartzCore
import ServiceManagement
import SwiftUI

// MARK: - Local schedule data

struct ScheduleItem: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var startAt: Date
    var endAt: Date
    var notes: String?
    var createdAt: Date
    var updatedAt: Date?
}

enum ScheduleStore {
    static var fileURL: URL {
        SharedFiles.directory.appendingPathComponent("schedule.json")
    }

    static func load() -> [ScheduleItem] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder.taskDecoder.decode([ScheduleItem].self, from: data)
        else {
            return []
        }
        return normalized(items)
    }

    static func save(_ items: [ScheduleItem]) {
        guard let data = try? JSONEncoder.taskEncoder.encode(normalized(items)) else { return }
        try? FileManager.default.createDirectory(at: SharedFiles.directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    static func normalized(_ items: [ScheduleItem]) -> [ScheduleItem] {
        items.sorted {
            if $0.startAt != $1.startAt { return $0.startAt < $1.startAt }
            return $0.createdAt < $1.createdAt
        }
    }
}

@MainActor
final class ScheduleModel: ObservableObject {
    @Published private(set) var items: [ScheduleItem] = ScheduleStore.load()

    func reload() {
        items = ScheduleStore.load()
    }

    func items(on date: Date) -> [ScheduleItem] {
        items.filter { Calendar.current.isDate($0.startAt, inSameDayAs: date) }
    }

    func add(title: String, startAt: Date, endAt: Date, notes: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, endAt > startAt else { return }
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        items.append(ScheduleItem(
            id: UUID().uuidString.uppercased(),
            title: trimmed,
            startAt: startAt,
            endAt: endAt,
            notes: cleanNotes.isEmpty ? nil : cleanNotes,
            createdAt: Date(),
            updatedAt: nil
        ))
        persist()
    }

    func update(_ item: ScheduleItem, title: String, startAt: Date, endAt: Date, notes: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, endAt > startAt else { return }
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        items = items.map { existing in
            guard existing.id == item.id else { return existing }
            var changed = existing
            changed.title = trimmed
            changed.startAt = startAt
            changed.endAt = endAt
            changed.notes = cleanNotes.isEmpty ? nil : cleanNotes
            changed.updatedAt = Date()
            return changed
        }
        persist()
    }

    func delete(_ item: ScheduleItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func conflicts(for candidate: ScheduleItem) -> [ScheduleItem] {
        items.filter { item in
            item.id != candidate.id && candidate.startAt < item.endAt && candidate.endAt > item.startAt
        }
    }

    private func persist() {
        items = ScheduleStore.normalized(items)
        ScheduleStore.save(items)
        NotificationCenter.default.post(name: .quietTasksScheduleChanged, object: nil)
    }
}

extension Notification.Name {
    static let quietTasksOpenSchedule = Notification.Name("quietTasks.openSchedule")
    static let quietTasksScheduleChanged = Notification.Name("quietTasks.scheduleChanged")
}

// MARK: - Main workspace

private enum WorkspaceSection: Hashable {
    case schedule
    case tasks
}

private enum ScheduleViewFilter: String, CaseIterable, Identifiable {
    case today
    case week
    case upcoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "This Week"
        case .upcoming: "All Schedules"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .week: "calendar"
        case .upcoming: "list.bullet"
        }
    }
}

struct RootWorkspaceView: View {
    @State private var selection: WorkspaceSection = .schedule

    var body: some View {
        TabView(selection: $selection) {
            ScheduleWorkspaceView()
                .tabItem { Label("Schedule", systemImage: "calendar.day.timeline.left") }
                .tag(WorkspaceSection.schedule)

            TaskWorkspaceView()
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(WorkspaceSection.tasks)
        }
        .onReceive(NotificationCenter.default.publisher(for: .quietTasksOpenSchedule)) { _ in
            selection = .schedule
        }
        .onOpenURL { _ in
            NotificationCenter.default.post(name: .quietTasksScheduleChanged, object: nil)
        }
        .environment(\.locale, Locale(identifier: "en_US"))
        .frame(minWidth: 980, minHeight: 680)
    }
}

struct ScheduleWorkspaceView: View {
    @StateObject private var model = ScheduleModel()
    @State private var selectedView: ScheduleViewFilter = .week
    @State private var weekAnchor = Date()
    @State private var editingItem: ScheduleItem?
    @State private var showingNewItem = false

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .weekOfYear, for: weekAnchor)
        let start = interval?.start ?? calendar.startOfDay(for: weekAnchor)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedView) {
                Section("Views") {
                    ForEach(ScheduleViewFilter.allCases) { filter in
                        Label(filter.title, systemImage: filter.symbol)
                            .tag(filter)
                    }
                }

                Section("Overview") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(model.items(on: Date()).count) today")
                            .font(.headline)
                        Text("\(weekItemCount) this week")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Schedule")
            .frame(minWidth: 220)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                detailContent
            }
            .workspaceContentSurface()
        }
        .sheet(isPresented: $showingNewItem) {
            ScheduleEditSheet(
                item: nil,
                seedDate: weekAnchor,
                onSave: { title, start, end, notes in
                    model.add(title: title, startAt: start, endAt: end, notes: notes)
                    showingNewItem = false
                },
                onDelete: nil,
                onCancel: { showingNewItem = false }
            )
        }
        .sheet(item: $editingItem) { item in
            ScheduleEditSheet(
                item: item,
                seedDate: item.startAt,
                onSave: { title, start, end, notes in
                    model.update(item, title: title, startAt: start, endAt: end, notes: notes)
                    editingItem = nil
                },
                onDelete: {
                    model.delete(item)
                    editingItem = nil
                },
                onCancel: { editingItem = nil }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .quietTasksScheduleChanged)) { _ in
            model.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reload()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedView.title)
                    .font(.system(size: 24, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selectedView == .week {
                Button { moveWeek(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous Week")
                Button("Today") { weekAnchor = Date() }
                Button { moveWeek(1) } label: { Image(systemName: "chevron.right") }
                    .help("Next Week")
            }
            Button {
                showingNewItem = true
            } label: {
                Label("New Schedule", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedView {
        case .week:
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(weekDays, id: \.self) { day in
                        ScheduleDayColumn(
                            date: day,
                            items: model.items(on: day),
                            onEdit: { editingItem = $0 }
                        )
                        .frame(width: 220)
                        if day != weekDays.last { Divider() }
                    }
                }
                .frame(minHeight: 560, alignment: .top)
            }
        case .today:
            ScheduleAgendaList(
                items: model.items(on: Date()),
                emptyText: "No schedules today",
                onEdit: { editingItem = $0 }
            )
        case .upcoming:
            ScheduleAgendaList(
                items: model.items.filter { $0.endAt >= Calendar.current.startOfDay(for: Date()) },
                emptyText: "No upcoming schedules",
                showsDate: true,
                onEdit: { editingItem = $0 }
            )
        }
    }

    private var weekItemCount: Int {
        guard let first = weekDays.first,
              let last = weekDays.last,
              let end = Calendar.current.date(byAdding: .day, value: 1, to: last)
        else { return 0 }
        return model.items.filter { $0.startAt >= first && $0.startAt < end }.count
    }

    private var headerSubtitle: String {
        switch selectedView {
        case .today:
            Date().formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "en_US")))
        case .week:
            weekRangeText
        case .upcoming:
            "Upcoming schedules in chronological order"
        }
    }

    private var weekRangeText: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        let style = Date.FormatStyle.dateTime.month().day().locale(Locale(identifier: "en_US"))
        return "\(first.formatted(style)) – \(last.formatted(style))"
    }

    private func moveWeek(_ amount: Int) {
        weekAnchor = Calendar.current.date(byAdding: .weekOfYear, value: amount, to: weekAnchor) ?? weekAnchor
    }
}

private struct ScheduleDayColumn: View {
    let date: Date
    let items: [ScheduleItem]
    let onEdit: (ScheduleItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "en_US"))))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Calendar.current.isDateInToday(date) ? Color.accentColor : .secondary)
                Text(date.formatted(.dateTime.month().day().locale(Locale(identifier: "en_US"))))
                    .font(.system(size: 22, weight: .semibold))
            }
            .padding(16)

            Divider()

            if items.isEmpty {
                Text("No schedules")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(16)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        Button { onEdit(item) } label: {
                            ScheduleWorkspaceRow(item: item)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                    }
                }
            }
            Spacer(minLength: 16)
        }
        .background(Calendar.current.isDateInToday(date) ? Color.accentColor.opacity(0.055) : .clear)
    }
}

private struct ScheduleWorkspaceRow: View {
    let item: ScheduleItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.startAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .foregroundStyle(.tint)
            Text(item.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text("Until \(item.endAt.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .contentShape(Rectangle())
    }
}

private struct ScheduleAgendaList: View {
    let items: [ScheduleItem]
    let emptyText: String
    var showsDate = false
    let onEdit: (ScheduleItem) -> Void

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(emptyText, systemImage: "calendar.badge.clock")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        Button { onEdit(item) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 20) {
                                VStack(alignment: .trailing, spacing: 4) {
                                    if showsDate {
                                        Text(item.startAt.formatted(.dateTime.month().day().weekday(.abbreviated).locale(Locale(identifier: "en_US"))))
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    Text(item.startAt.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 15, design: .monospaced))
                                        .foregroundStyle(.tint)
                                }
                                .frame(width: showsDate ? 112 : 68, alignment: .trailing)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title)
                                        .font(.system(size: 16, weight: .medium))
                                        .lineLimit(2)
                                    Text("Until \(item.endAt.formatted(date: .omitted, time: .shortened))")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, showsDate ? 160 : 116)
                    }
                }
            }
        }
    }
}

private struct ScheduleEditSheet: View {
    let item: ScheduleItem?
    let onSave: (String, Date, Date, String) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @State private var title: String
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var notes: String

    init(
        item: ScheduleItem?,
        seedDate: Date,
        onSave: @escaping (String, Date, Date, String) -> Void,
        onDelete: (() -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        self.item = item
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        let calendar = Calendar.current
        let defaultStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: seedDate) ?? seedDate
        _title = State(initialValue: item?.title ?? "")
        _startAt = State(initialValue: item?.startAt ?? defaultStart)
        _endAt = State(initialValue: item?.endAt ?? calendar.date(byAdding: .hour, value: 1, to: defaultStart) ?? defaultStart)
        _notes = State(initialValue: item?.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(item == nil ? "New Schedule" : "Edit Schedule")
                .font(.system(size: 24, weight: .semibold))

            Form {
                TextField("Title", text: $title)
                DatePicker("Starts", selection: $startAt)
                DatePicker("Ends", selection: $endAt, in: startAt...)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...5)
            }

            if endAt <= startAt {
                Text("The end time must be later than the start time.")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            HStack {
                if let onDelete {
                    Button("Delete", role: .destructive, action: onDelete)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(title, startAt, endAt, notes) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || endAt <= startAt)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

// MARK: - Floating surfaces

private struct DayEdgePanelView: View {
    @ObservedObject var model: ScheduleModel
    let onOpenSchedule: () -> Void
    @State private var now = Date()

    private let dayStartHour = 7
    private let dayEndHour = 23

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(.primary)
                    Text(Date().formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "en_US"))))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(now.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tint)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)

            timeline
                .padding(.horizontal, 20)

            Button(action: onOpenSchedule) {
                HStack {
                    Text("View This Week")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tint)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .drawingGroup(opaque: false, colorMode: .nonLinear)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 14,
            topTrailingRadius: 14
        ))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
        }
        .environment(\.locale, Locale(identifier: "en_US"))
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private var timeline: some View {
        GeometryReader { geometry in
            let height = max(480, geometry.size.height - 20)
            let todayItems = model.items(on: Date())
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 70, y: 12))
                    path.addLine(to: CGPoint(x: 70, y: height + 12))
                }
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)

                ForEach(dayStartHour...dayEndHour, id: \.self) { hour in
                    let y = hourY(hour, height: height) + 12
                    Text(String(format: "%02d:00", hour))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .position(x: 30, y: y)
                    Circle()
                        .fill(Color(nsColor: .tertiaryLabelColor))
                        .frame(width: 5, height: 5)
                        .position(x: 70, y: y)
                }

                ForEach(Array(todayItems.enumerated()), id: \.element.id) { index, item in
                    let y = collisionSafeY(index: index, items: todayItems, height: height) + 10
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(isCurrent(item) ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
                            .frame(width: 9, height: 9)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(timeRange(item))
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(isCurrent(item) ? Color.accentColor : Color.secondary)
                            Text(item.title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(width: 266, height: 42, alignment: .leading)
                    .padding(.horizontal, isCurrent(item) ? 12 : 0)
                    .background(isCurrent(item) ? Color.accentColor.opacity(0.12) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .position(x: 214, y: y)
                }

                if isWithinTimeline(now) {
                    let y = dateY(now, height: height) + 12
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.78))
                        .frame(height: 1)
                        .position(x: geometry.size.width / 2, y: y)
                    Text(now.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .position(x: 34, y: y)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func hourY(_ hour: Int, height: CGFloat) -> CGFloat {
        CGFloat(hour - dayStartHour) / CGFloat(dayEndHour - dayStartHour) * height
    }

    private func dateY(_ date: Date, height: CGFloat) -> CGFloat {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let value = Double((components.hour ?? dayStartHour) * 60 + (components.minute ?? 0))
        let start = Double(dayStartHour * 60)
        let end = Double(dayEndHour * 60)
        return CGFloat(min(max((value - start) / (end - start), 0), 1)) * height
    }

    private func collisionSafeY(index: Int, items: [ScheduleItem], height: CGFloat) -> CGFloat {
        guard items.indices.contains(index) else { return 0 }
        let minimumGap: CGFloat = 46
        var positions: [CGFloat] = []
        for item in items {
            let desired = dateY(item.startAt, height: height)
            let adjusted = max(desired, (positions.last ?? -minimumGap) + minimumGap)
            positions.append(adjusted)
        }
        let overflow = max(0, (positions.last ?? 0) - (height - 24))
        return max(22, positions[index] - overflow)
    }

    private func isWithinTimeline(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return (dayStartHour...dayEndHour).contains(hour)
    }

    private func isCurrent(_ item: ScheduleItem) -> Bool {
        now >= item.startAt && now <= item.endAt
    }

    private func timeRange(_ item: ScheduleItem) -> String {
        "\(item.startAt.formatted(date: .omitted, time: .shortened))–\(item.endAt.formatted(date: .omitted, time: .shortened))"
    }
}

private final class TaskIslandPresentation: ObservableObject {
    @Published var isExpanded = false
    @Published var showsContent = false
    @Published var collapsedNotchSize = CGSize(width: 224, height: 34)
}

private struct TaskIslandView: View {
    @ObservedObject var model: TaskModel
    @ObservedObject var presentation: TaskIslandPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onOpenApp: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("To Do")
                    .font(.system(size: 21, weight: .semibold))
                Text("\(model.openTasks.count) items")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tint)
                Spacer()
                Button(action: onOpenApp) {
                    Image(systemName: "arrow.up.right")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .help("Open Quiet Tasks")
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            if model.openTasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.tint)
                    Text("All Clear")
                        .font(.system(size: 16, weight: .medium))
                    Text("New tasks will appear here automatically.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.openTasks) { task in
                            TaskIslandRow(task: task) {
                                withAnimation(.easeOut(duration: 0.12)) {
                                    model.markDone(task)
                                }
                            }
                            .transition(.opacity)
                            if task.id != model.openTasks.last?.id {
                                Divider().padding(.leading, 76)
                            }
                        }
                    }
                }
                .scrollIndicators(.visible)
            }
        }
        .opacity(presentation.showsContent ? 1 : 0)
        .animation(contentAnimation, value: presentation.showsContent)
        .foregroundStyle(.primary)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(NotchExpansionShape(
            progress: presentation.isExpanded ? 1 : 0,
            collapsedSize: presentation.collapsedNotchSize
        ))
        .overlay {
            NotchExpansionShape(
                progress: presentation.isExpanded ? 1 : 0,
                collapsedSize: presentation.collapsedNotchSize
            )
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .animation(shellAnimation, value: presentation.isExpanded)
        .environment(\.locale, Locale(identifier: "en_US"))
    }

    private var shellAnimation: Animation {
        guard !reduceMotion else { return .linear(duration: 0.01) }
        if presentation.isExpanded {
            return .timingCurve(0.22, 1, 0.36, 1, duration: 0.18)
        }
        return .timingCurve(0.25, 1, 0.5, 1, duration: 0.14).delay(0.035)
    }

    private var contentAnimation: Animation {
        guard !reduceMotion else { return .linear(duration: 0.01) }
        if presentation.showsContent {
            return .easeOut(duration: 0.12).delay(0.035)
        }
        return .easeOut(duration: 0.07)
    }
}

private struct NotchExpansionShape: Shape {
    var progress: CGFloat
    let collapsedSize: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let value = min(max(progress, 0), 1)
        let collapsedWidth = min(collapsedSize.width, rect.width)
        let collapsedHeight = min(collapsedSize.height, rect.height)
        let width = collapsedWidth + (rect.width - collapsedWidth) * value
        let height = collapsedHeight + (rect.height - collapsedHeight) * value
        let bounds = CGRect(
            x: rect.midX - width / 2,
            y: rect.minY,
            width: width,
            height: height
        )
        let topRadius = 16 * value
        let bottomRadius = 11 + 5 * value
        var path = Path()

        path.move(to: CGPoint(x: bounds.minX + topRadius, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.maxX - topRadius, y: bounds.minY))
        path.addQuadCurve(
            to: CGPoint(x: bounds.maxX, y: bounds.minY + topRadius),
            control: CGPoint(x: bounds.maxX, y: bounds.minY)
        )
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: bounds.maxX - bottomRadius, y: bounds.maxY),
            control: CGPoint(x: bounds.maxX, y: bounds.maxY)
        )
        path.addLine(to: CGPoint(x: bounds.minX + bottomRadius, y: bounds.maxY))
        path.addQuadCurve(
            to: CGPoint(x: bounds.minX, y: bounds.maxY - bottomRadius),
            control: CGPoint(x: bounds.minX, y: bounds.maxY)
        )
        path.addLine(to: CGPoint(x: bounds.minX, y: bounds.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: bounds.minX + topRadius, y: bounds.minY),
            control: CGPoint(x: bounds.minX, y: bounds.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct TaskIslandRow: View {
    let task: TaskItem
    let complete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 16) {
            Button(action: complete) {
                ZStack {
                    Circle()
                        .stroke(hovering ? Color.primary : Color.secondary, lineWidth: 1.5)
                    if hovering {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tint)
                    }
                }
                .frame(width: 28, height: 28)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Complete")

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Label(task.taskPriority.title, systemImage: task.taskPriority.symbol)
                    if let progress = task.subtaskProgressText {
                        Label(progress, systemImage: "checklist")
                    }
                    if let deadline = task.deadline {
                        Spacer(minLength: 8)
                        deadlineText(deadline)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(hovering ? Color.accentColor.opacity(0.10) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private func deadlineText(_ deadline: Date) -> some View {
        if task.showsDeadlineTime {
            Text(deadline.formatted(.dateTime
                .month().day()
                .hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)
                .locale(Locale(identifier: "en_US"))))
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(1)
        } else {
            Text(deadline.formatted(.dateTime
                .month().day()
                .locale(Locale(identifier: "en_US"))))
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(1)
        }
    }
}

private final class HoverTrackingView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        if let area { removeTrackingArea(area) }
        let newArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newArea)
        area = newArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayCoordinator {
    private let tasks = TaskModel()
    private let schedule = ScheduleModel()
    private let islandPresentation = TaskIslandPresentation()
    private var edgeTrigger: NSPanel?
    private var notchTrigger: NSPanel?
    private var edgePanel: OverlayPanel?
    private var islandPanel: OverlayPanel?
    private var edgeWorkItem: DispatchWorkItem?
    private var islandWorkItem: DispatchWorkItem?
    private var islandDismissWorkItem: DispatchWorkItem?
    private var edgeDismissWorkItem: DispatchWorkItem?
    private var edgePointerTimer: Timer?
    private var edgePointerOutsideSince: Date?
    private var islandPointerTimer: Timer?
    private var islandPointerOutsideSince: Date?
    private(set) var isPaused = false

    func start() {
        installTriggers()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.installTriggers() }
        }
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused {
            hideEdgePanel()
            hideIslandPanel()
            edgeTrigger?.orderOut(nil)
            notchTrigger?.orderOut(nil)
        } else {
            installTriggers()
        }
    }

    private func installTriggers() {
        guard !isPaused, let screen = targetScreen else { return }
        edgeTrigger?.orderOut(nil)
        notchTrigger?.orderOut(nil)

        let edgeFrame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY + screen.frame.height * 0.28,
            width: 6,
            height: screen.frame.height * 0.44
        )
        edgeTrigger = makeTrigger(frame: edgeFrame, enter: { [weak self] in
            self?.scheduleEdgeShow()
        }, exit: { [weak self] in
            self?.cancelPendingEdgeShow()
        })

        guard let notchFrame = physicalNotchFrame(on: screen) else { return }
        islandPresentation.collapsedNotchSize = notchFrame.size
        notchTrigger = makeTrigger(frame: notchFrame, enter: { [weak self] in
            self?.scheduleIslandShow()
        }, exit: { [weak self] in
            self?.cancelPendingIslandShow()
        })
    }

    private func makeTrigger(frame: NSRect, enter: @escaping () -> Void, exit: @escaping () -> Void) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = HoverTrackingView(frame: NSRect(origin: .zero, size: frame.size))
        view.onEnter = enter
        view.onExit = exit
        panel.contentView = view
        panel.orderFrontRegardless()
        return panel
    }

    private func scheduleEdgeShow() {
        edgeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.showEdgePanel() }
        edgeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    private func cancelPendingEdgeShow() {
        guard edgePanel?.isVisible != true else { return }
        edgeWorkItem?.cancel()
    }

    private func scheduleIslandShow() {
        islandWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.showIslandPanel() }
        islandWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035, execute: item)
    }

    private func cancelPendingIslandShow() {
        guard islandPanel?.isVisible != true else { return }
        islandWorkItem?.cancel()
    }

    private func showEdgePanel() {
        guard !isPaused, let screen = targetScreen else { return }
        edgeWorkItem?.cancel()
        edgeDismissWorkItem?.cancel()
        schedule.reload()
        let width: CGFloat = 388
        let height = screen.visibleFrame.height
        let finalFrame = NSRect(
            x: screen.frame.minX,
            y: screen.visibleFrame.minY,
            width: width,
            height: height
        )
        let startFrame = finalFrame.offsetBy(dx: -28, dy: 0)

        if edgePanel == nil {
            let panel = makeOverlayPanel(frame: startFrame)
            panel.contentView = NSHostingView(rootView: DayEdgePanelView(
                model: schedule,
                onOpenSchedule: { [weak self] in
                    self?.openMainApp(schedule: true)
                    self?.hideEdgePanel()
                }
            ))
            edgePanel = panel
        }
        guard let edgePanel else { return }
        if !edgePanel.isVisible {
            edgePanel.setFrame(startFrame, display: false)
            edgePanel.alphaValue = 0
        }
        edgePanel.orderFrontRegardless()
        animate(edgePanel, to: finalFrame, alpha: 1, duration: 0.16)
        startEdgePointerMonitor()
    }

    private func hideEdgePanel() {
        stopEdgePointerMonitor()
        guard let panel = edgePanel, panel.isVisible else { return }
        edgeDismissWorkItem?.cancel()
        let target = panel.frame.offsetBy(dx: -24, dy: 0)
        animate(panel, to: target, alpha: 0, duration: 0.12)
        let item = DispatchWorkItem { [weak self] in
            self?.edgePanel?.orderOut(nil)
        }
        edgeDismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13, execute: item)
    }

    private func startEdgePointerMonitor() {
        stopEdgePointerMonitor()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateEdgePointer() }
        }
        edgePointerTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopEdgePointerMonitor() {
        edgePointerTimer?.invalidate()
        edgePointerTimer = nil
        edgePointerOutsideSince = nil
    }

    private func evaluateEdgePointer() {
        guard let panel = edgePanel, panel.isVisible else {
            stopEdgePointerMonitor()
            return
        }

        let pointer = NSEvent.mouseLocation
        let isInsidePanel = panel.frame.insetBy(dx: -4, dy: -4).contains(pointer)
        let isInsideTrigger = edgeTrigger?.frame.contains(pointer) == true
        if isInsidePanel || isInsideTrigger {
            edgePointerOutsideSince = nil
            return
        }

        if let outsideSince = edgePointerOutsideSince {
            if Date().timeIntervalSince(outsideSince) >= 0.09 {
                hideEdgePanel()
            }
        } else {
            edgePointerOutsideSince = Date()
        }
    }

    private func showIslandPanel() {
        guard !isPaused, let screen = targetScreen else { return }
        islandWorkItem?.cancel()
        islandDismissWorkItem?.cancel()
        tasks.reload()
        let width = min(560, screen.frame.width * 0.46)
        let contentHeight = 88 + CGFloat(tasks.openTasks.count) * 84
        let height = min(500, max(240, contentHeight))
        let finalFrame = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )

        if islandPanel == nil {
            let panel = makeOverlayPanel(frame: finalFrame)
            panel.level = .mainMenu + 1
            panel.contentView = NSHostingView(rootView: TaskIslandView(
                model: tasks,
                presentation: islandPresentation,
                onOpenApp: { [weak self] in
                    self?.openMainApp(schedule: false)
                    self?.hideIslandPanel()
                }
            ))
            islandPanel = panel
        }
        guard let islandPanel else { return }
        islandPanel.setFrame(finalFrame, display: false)
        islandPanel.alphaValue = 1
        let wasVisible = islandPanel.isVisible
        if !wasVisible {
            islandPresentation.isExpanded = false
            islandPresentation.showsContent = false
        }
        islandPanel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.islandPanel?.isVisible == true else { return }
            self.islandPresentation.isExpanded = true
            self.islandPresentation.showsContent = true
        }
        startIslandPointerMonitor()
    }

    private func hideIslandPanel() {
        stopIslandPointerMonitor()
        guard let panel = islandPanel, panel.isVisible else { return }
        islandDismissWorkItem?.cancel()
        islandPresentation.isExpanded = false
        islandPresentation.showsContent = false
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
            return
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.islandPresentation.isExpanded else { return }
            self.islandPanel?.orderOut(nil)
        }
        islandDismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
    }

    private func startIslandPointerMonitor() {
        stopIslandPointerMonitor()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateIslandPointer() }
        }
        islandPointerTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopIslandPointerMonitor() {
        islandPointerTimer?.invalidate()
        islandPointerTimer = nil
        islandPointerOutsideSince = nil
    }

    private func evaluateIslandPointer() {
        guard let panel = islandPanel, panel.isVisible else {
            stopIslandPointerMonitor()
            return
        }

        let pointer = NSEvent.mouseLocation
        let isInsidePanel = panel.frame.insetBy(dx: -4, dy: -4).contains(pointer)
        let isInsideTrigger = notchTrigger?.frame.contains(pointer) == true
        if isInsidePanel || isInsideTrigger {
            islandPointerOutsideSince = nil
            return
        }

        if let outsideSince = islandPointerOutsideSince {
            if Date().timeIntervalSince(outsideSince) >= 0.07 {
                hideIslandPanel()
            }
        } else {
            islandPointerOutsideSince = Date()
        }
    }

    private func makeOverlayPanel(frame: NSRect) -> OverlayPanel {
        let panel = OverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none
        return panel
    }

    private func animate(
        _ panel: NSPanel,
        to frame: NSRect,
        alpha: CGFloat,
        duration: TimeInterval,
        completion: (() -> Void)? = nil
    ) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(frame, display: true)
            panel.alphaValue = alpha
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = alpha
        } completionHandler: {
            completion?()
        }
    }

    private func openMainApp(schedule: Bool) {
        if schedule { NotificationCenter.default.post(name: .quietTasksOpenSchedule, object: nil) }
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.level == .normal && $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private var targetScreen: NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    private func physicalNotchFrame(on screen: NSScreen) -> NSRect? {
        guard let leftShoulder = screen.auxiliaryTopLeftArea,
              let rightShoulder = screen.auxiliaryTopRightArea,
              leftShoulder.maxX < rightShoulder.minX
        else {
            return nil
        }

        let bottom = max(leftShoulder.minY, rightShoulder.minY)
        let frame = NSRect(
            x: leftShoulder.maxX,
            y: bottom,
            width: rightShoulder.minX - leftShoulder.maxX,
            height: screen.frame.maxY - bottom
        )
        guard frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }
}

extension View {
    func workspaceContentSurface() -> some View {
        background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Menu bar and lifecycle

@MainActor
final class QuietTasksAppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayCoordinator()
    private var statusItem: NSStatusItem?
    private var pauseMenuItem: NSMenuItem?
    private var loginMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay.start()
        installStatusItem()
        registerLoginItemIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first(where: { $0.level == .normal })?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    private func installStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Quiet Tasks")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Quiet Tasks", action: #selector(openApp), keyEquivalent: "")
        menu.addItem(withTitle: "View This Week", action: #selector(openSchedule), keyEquivalent: "")
        menu.addItem(.separator())
        let pause = NSMenuItem(title: "Pause Edge Triggers", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(pause)
        pauseMenuItem = pause
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        menu.addItem(login)
        loginMenuItem = login
        updateLoginMenuState()
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    @objc private func openApp() {
        activateMainWindow(showSchedule: false)
    }

    @objc private func openSchedule() {
        activateMainWindow(showSchedule: true)
    }

    @objc private func togglePause() {
        overlay.setPaused(!overlay.isPaused)
        pauseMenuItem?.state = overlay.isPaused ? .on : .off
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
        updateLoginMenuState()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func activateMainWindow(showSchedule: Bool) {
        if showSchedule { NotificationCenter.default.post(name: .quietTasksOpenSchedule, object: nil) }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.level == .normal && $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }

    private func registerLoginItemIfNeeded() {
        if SMAppService.mainApp.status == .notRegistered {
            try? SMAppService.mainApp.register()
        }
        updateLoginMenuState()
    }

    private func updateLoginMenuState() {
        loginMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
