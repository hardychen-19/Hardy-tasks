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

struct RootWorkspaceView: View {
    @State private var selection: WorkspaceSection = .schedule

    var body: some View {
        TabView(selection: $selection) {
            ScheduleWorkspaceView()
                .tabItem { Label("日程", systemImage: "calendar.day.timeline.left") }
                .tag(WorkspaceSection.schedule)

            TaskWorkspaceView()
                .tabItem { Label("待办", systemImage: "checklist") }
                .tag(WorkspaceSection.tasks)
        }
        .onReceive(NotificationCenter.default.publisher(for: .quietTasksOpenSchedule)) { _ in
            selection = .schedule
        }
        .onOpenURL { _ in
            NotificationCenter.default.post(name: .quietTasksScheduleChanged, object: nil)
        }
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .frame(minWidth: 980, minHeight: 680)
    }
}

struct ScheduleWorkspaceView: View {
    @StateObject private var model = ScheduleModel()
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
        VStack(spacing: 0) {
            header
            Divider()
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
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
                Text("本周日程")
                    .font(.system(size: 24, weight: .semibold))
                Text(weekRangeText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { moveWeek(-1) } label: { Image(systemName: "chevron.left") }
                .help("上一周")
            Button("今天") { weekAnchor = Date() }
            Button { moveWeek(1) } label: { Image(systemName: "chevron.right") }
                .help("下一周")
            Button {
                showingNewItem = true
            } label: {
                Label("新建日程", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var weekRangeText: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        let style = Date.FormatStyle.dateTime.month().day().locale(Locale(identifier: "zh_CN"))
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
                Text(date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "zh_CN"))))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Calendar.current.isDateInToday(date) ? Color.qtCyan : .secondary)
                Text(date.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN"))))
                    .font(.system(size: 22, weight: .semibold))
            }
            .padding(16)

            Divider()

            if items.isEmpty {
                Text("没有日程")
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
        .background(Calendar.current.isDateInToday(date) ? Color.qtCyan.opacity(0.035) : .clear)
    }
}

private struct ScheduleWorkspaceRow: View {
    let item: ScheduleItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.startAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.qtCyan)
            Text(item.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text("至 \(item.endAt.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .contentShape(Rectangle())
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
            Text(item == nil ? "新建日程" : "编辑日程")
                .font(.system(size: 24, weight: .semibold))

            Form {
                TextField("事项", text: $title)
                DatePicker("开始", selection: $startAt)
                DatePicker("结束", selection: $endAt, in: startAt...)
                TextField("备注", text: $notes, axis: .vertical)
                    .lineLimit(3...5)
            }

            if endAt <= startAt {
                Text("结束时间必须晚于开始时间。")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            HStack {
                if let onDelete {
                    Button("删除", role: .destructive, action: onDelete)
                }
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("保存") { onSave(title, startAt, endAt, notes) }
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

extension Color {
    static let qtNotchBlack = Color(red: 5 / 255, green: 6 / 255, blue: 7 / 255)
    static let qtGraphite = Color(red: 21 / 255, green: 25 / 255, blue: 29 / 255)
    static let qtLakeBlue = Color(red: 25 / 255, green: 90 / 255, blue: 115 / 255)
    static let qtCyan = Color(red: 85 / 255, green: 197 / 255, blue: 200 / 255)
    static let qtMist = Color(red: 242 / 255, green: 246 / 255, blue: 247 / 255)
}

private struct DayEdgePanelView: View {
    @ObservedObject var model: ScheduleModel
    let onHover: (Bool) -> Void
    let onOpenSchedule: () -> Void
    @State private var now = Date()

    private let dayStartHour = 7
    private let dayEndHour = 23

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("今天")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(Color.qtMist)
                Text(Date().formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "zh_CN"))))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.qtMist.opacity(0.64))
                Text(now.formatted(date: .omitted, time: .shortened) + " 实时")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.qtCyan)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            timeline
                .padding(.horizontal, 20)

            Button(action: onOpenSchedule) {
                HStack {
                    Text("查看本周")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.qtCyan)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(.ultraThinMaterial)
        .background(Color.qtGraphite.opacity(0.68))
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 14,
            topTrailingRadius: 14
        ))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
        }
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .onHover(perform: onHover)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private var timeline: some View {
        GeometryReader { geometry in
            let height = max(336, geometry.size.height - 24)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 70, y: 12))
                    path.addLine(to: CGPoint(x: 70, y: height + 12))
                }
                .stroke(Color.qtMist.opacity(0.22), lineWidth: 1)

                ForEach(dayStartHour...dayEndHour, id: \.self) { hour in
                    let y = hourY(hour, height: height) + 12
                    Text(String(format: "%02d:00", hour))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.qtMist.opacity(0.46))
                        .position(x: 30, y: y)
                    Circle()
                        .fill(Color.qtMist.opacity(0.24))
                        .frame(width: 5, height: 5)
                        .position(x: 70, y: y)
                }

                ForEach(model.items(on: Date())) { item in
                    let y = dateY(item.startAt, height: height) + 12
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(isCurrent(item) ? Color.qtCyan : Color.qtLakeBlue)
                            .frame(width: 9, height: 9)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(timeRange(item))
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(isCurrent(item) ? Color.qtCyan : Color.qtMist.opacity(0.66))
                            Text(item.title)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.qtMist)
                                .lineLimit(2)
                        }
                    }
                    .frame(width: 238, alignment: .leading)
                    .padding(.vertical, isCurrent(item) ? 10 : 4)
                    .padding(.horizontal, isCurrent(item) ? 12 : 0)
                    .background(isCurrent(item) ? Color.qtLakeBlue.opacity(0.24) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .position(x: 196, y: y)
                }

                if isWithinTimeline(now) {
                    let y = dateY(now, height: height) + 12
                    Rectangle()
                        .fill(Color.qtCyan.opacity(0.76))
                        .frame(height: 1)
                        .position(x: geometry.size.width / 2, y: y)
                    Text(now.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.qtCyan)
                        .padding(.horizontal, 6)
                        .background(Color.qtGraphite)
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

private struct TaskIslandView: View {
    @ObservedObject var model: TaskModel
    let onHover: (Bool) -> Void
    let onOpenApp: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(model.openTasks.count)")
                    .font(.system(size: 38, weight: .light))
                    .monospacedDigit()
                Text("项待完成")
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                Button(action: onOpenApp) {
                    Image(systemName: "arrow.up.right")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.qtCyan)
                .help("打开 Quiet Tasks")
            }
            .padding(.horizontal, 28)
            .padding(.top, 52)
            .padding(.bottom, 16)

            Divider().overlay(Color.qtMist.opacity(0.10))

            if model.openTasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Color.qtCyan)
                    Text("今天已经清空")
                        .font(.system(size: 16, weight: .medium))
                    Text("新的待办会自动出现在这里。")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.qtMist.opacity(0.58))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.openTasks.enumerated()), id: \.element.id) { index, task in
                            TaskIslandRow(task: task) {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    model.markDone(task)
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
                                removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .leading))
                            ))
                            .animation(.easeOut(duration: 0.22).delay(min(Double(index) * 0.025, 0.16)), value: model.openTasks.count)
                            if task.id != model.openTasks.last?.id {
                                Divider().overlay(Color.qtMist.opacity(0.08)).padding(.leading, 76)
                            }
                        }
                    }
                }
                .scrollIndicators(.visible)
                .mask {
                    LinearGradient(
                        colors: [.clear, .black, .black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .foregroundStyle(Color.qtMist)
        .background(.ultraThinMaterial)
        .background(Color.qtNotchBlack.opacity(0.92))
        .clipShape(NotchIslandShape())
        .overlay {
            NotchIslandShape()
            .stroke(Color.qtMist.opacity(0.07), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .onHover(perform: onHover)
    }
}

private struct NotchIslandShape: Shape {
    func path(in rect: CGRect) -> Path {
        let notchWidth = min(224, rect.width * 0.42)
        let shoulderHeight: CGFloat = 44
        let corner: CGFloat = 14
        let center = rect.midX
        var path = Path()

        path.move(to: CGPoint(x: center - notchWidth / 2, y: 0))
        path.addLine(to: CGPoint(x: center + notchWidth / 2, y: 0))
        path.addCurve(
            to: CGPoint(x: center + notchWidth / 2 + 54, y: shoulderHeight),
            control1: CGPoint(x: center + notchWidth / 2 + 18, y: 0),
            control2: CGPoint(x: center + notchWidth / 2 + 24, y: shoulderHeight)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: shoulderHeight))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - corner, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - corner),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: shoulderHeight))
        path.addLine(to: CGPoint(x: center - notchWidth / 2 - 54, y: shoulderHeight))
        path.addCurve(
            to: CGPoint(x: center - notchWidth / 2, y: 0),
            control1: CGPoint(x: center - notchWidth / 2 - 24, y: shoulderHeight),
            control2: CGPoint(x: center - notchWidth / 2 - 18, y: 0)
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
                        .stroke(Color.qtMist.opacity(hovering ? 0.84 : 0.52), lineWidth: 1.5)
                    if hovering {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.qtCyan)
                    }
                }
                .frame(width: 28, height: 28)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("完成")

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Label(task.taskPriority.title, systemImage: task.taskPriority.symbol)
                    if let progress = task.subtaskProgressText {
                        Label(progress, systemImage: "checklist")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.qtMist.opacity(0.52))
            }

            Spacer(minLength: 16)

            if let deadline = task.deadline {
                if task.showsDeadlineTime {
                    Text(deadline.formatted(.dateTime
                        .year().month().day()
                        .hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)
                        .locale(Locale(identifier: "zh_CN"))))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.qtMist.opacity(0.60))
                    .lineLimit(1)
                } else {
                    Text(deadline.formatted(.dateTime
                        .year().month().day()
                        .locale(Locale(identifier: "zh_CN"))))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.qtMist.opacity(0.60))
                    .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(hovering ? Color.qtLakeBlue.opacity(0.16) : .clear)
        .contentShape(Rectangle())
        .scaleEffect(hovering ? 1.006 : 1, anchor: .leading)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onHover { hovering = $0 }
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
    private var edgeTrigger: NSPanel?
    private var notchTrigger: NSPanel?
    private var edgePanel: OverlayPanel?
    private var islandPanel: OverlayPanel?
    private var edgeWorkItem: DispatchWorkItem?
    private var islandWorkItem: DispatchWorkItem?
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
            self?.scheduleEdgeHide()
        })

        // The physical notch itself is not a pointer-addressable area. The trigger
        // therefore includes the slim shoulder directly below it so the gesture
        // still feels like hovering the notch instead of hunting for a pixel.
        let notchWidth: CGFloat = min(340, screen.frame.width * 0.24)
        let notchFrame = NSRect(
            x: screen.frame.midX - notchWidth / 2,
            y: screen.frame.maxY - 64,
            width: notchWidth,
            height: 64
        )
        notchTrigger = makeTrigger(frame: notchFrame, enter: { [weak self] in
            self?.scheduleIslandShow()
        }, exit: { [weak self] in
            self?.scheduleIslandHide()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    private func scheduleEdgeHide() {
        edgeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.hideEdgePanel() }
        edgeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private func scheduleIslandShow() {
        islandWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.showIslandPanel() }
        islandWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: item)
    }

    private func scheduleIslandHide() {
        islandWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.hideIslandPanel() }
        islandWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private func showEdgePanel() {
        guard !isPaused, let screen = targetScreen else { return }
        edgeWorkItem?.cancel()
        schedule.reload()
        let width: CGFloat = 360
        let height = min(720, screen.visibleFrame.height * 0.70)
        let finalFrame = NSRect(
            x: screen.frame.minX,
            y: screen.visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
        let startFrame = NSRect(x: screen.frame.minX - width + 8, y: finalFrame.minY, width: width, height: height)

        if edgePanel == nil {
            let panel = makeOverlayPanel(frame: startFrame)
            panel.contentView = NSHostingView(rootView: DayEdgePanelView(
                model: schedule,
                onHover: { [weak self] inside in
                    inside ? self?.edgeWorkItem?.cancel() : self?.scheduleEdgeHide()
                },
                onOpenSchedule: { [weak self] in
                    self?.openMainApp(schedule: true)
                    self?.hideEdgePanel()
                }
            ))
            edgePanel = panel
        }
        guard let edgePanel else { return }
        edgePanel.setFrame(startFrame, display: false)
        edgePanel.orderFrontRegardless()
        animate(edgePanel, to: finalFrame, duration: 0.32)
    }

    private func hideEdgePanel() {
        guard let panel = edgePanel, panel.isVisible else { return }
        let target = NSRect(x: panel.frame.minX - panel.frame.width + 8, y: panel.frame.minY, width: panel.frame.width, height: panel.frame.height)
        animate(panel, to: target, duration: 0.22) { panel.orderOut(nil) }
    }

    private func showIslandPanel() {
        guard !isPaused, let screen = targetScreen else { return }
        islandWorkItem?.cancel()
        tasks.reload()
        let width = min(640, screen.frame.width * 0.54)
        let height = min(500, screen.visibleFrame.height * 0.56)
        let finalFrame = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
        let startFrame = NSRect(x: finalFrame.minX, y: screen.frame.maxY - 44, width: width, height: 44)

        if islandPanel == nil {
            let panel = makeOverlayPanel(frame: startFrame)
            panel.level = .mainMenu + 1
            panel.contentView = NSHostingView(rootView: TaskIslandView(
                model: tasks,
                onHover: { [weak self] inside in
                    inside ? self?.islandWorkItem?.cancel() : self?.scheduleIslandHide()
                },
                onOpenApp: { [weak self] in
                    self?.openMainApp(schedule: false)
                    self?.hideIslandPanel()
                }
            ))
            islandPanel = panel
        }
        guard let islandPanel else { return }
        islandPanel.setFrame(startFrame, display: false)
        islandPanel.orderFrontRegardless()
        animate(islandPanel, to: finalFrame, duration: 0.36)
    }

    private func hideIslandPanel() {
        guard let panel = islandPanel, panel.isVisible else { return }
        let target = NSRect(x: panel.frame.minX, y: panel.frame.maxY - 44, width: panel.frame.width, height: 44)
        animate(panel, to: target, duration: 0.24) { panel.orderOut(nil) }
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
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none
        return panel
    }

    private func animate(_ panel: NSPanel, to frame: NSRect, duration: TimeInterval, completion: (() -> Void)? = nil) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(frame, display: true)
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
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
        menu.addItem(withTitle: "打开 Quiet Tasks", action: #selector(openApp), keyEquivalent: "")
        menu.addItem(withTitle: "查看本周日程", action: #selector(openSchedule), keyEquivalent: "")
        menu.addItem(.separator())
        let pause = NSMenuItem(title: "暂停边缘触发", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(pause)
        pauseMenuItem = pause
        let login = NSMenuItem(title: "登录时启动", action: #selector(toggleLoginItem), keyEquivalent: "")
        menu.addItem(login)
        loginMenuItem = login
        updateLoginMenuState()
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
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
