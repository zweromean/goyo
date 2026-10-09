import SwiftUI
import Combine

enum PlanKind: String, Codable, CaseIterable { case task = "할 일", event = "일정" }
struct PlanItem: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var date: Date
    var subjectID: UUID?
    var subjectName: String?
    var kind: PlanKind = .task
    var isDone = false
}
@MainActor
final class PlannerModel: ObservableObject {
    @Published private(set) var items: [PlanItem]
    init() {
        items = Shared.defaults.data(forKey: "plannerItems").flatMap { try? JSONDecoder().decode([PlanItem].self, from: $0) } ?? []
    }
    func save(_ value: PlanItem) {
        var item = value
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.title.isEmpty, item.title.count <= 160 else { return }
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
        else { items.append(item) }
        persist()
    }
    func toggle(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].kind == .task else { return }
        items[i].isDone.toggle(); persist()
    }
    func remove(_ id: UUID) { items.removeAll { $0.id == id }; persist() }
    func on(_ day: Date) -> [PlanItem] {
        items.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }
    }
    private func persist() { Shared.defaults.set(try? JSONEncoder().encode(items), forKey: "plannerItems") }
}

struct TodoView: View {
    @EnvironmentObject private var planner: PlannerModel
    @State private var day = Date()
    @State private var allDates = false
    @State private var editing: PlanItem?
    private var tasks: [PlanItem] {
        planner.items.filter { $0.kind == .task && (allDates || Calendar.current.isDate($0.date, inSameDayAs: day)) }
            .sorted { a, b in a.isDone != b.isDone ? !a.isDone : a.date < b.date }
    }
    var body: some View {
        List {
            Section {
                DatePicker("날짜", selection: $day, displayedComponents: .date)
                Toggle("전체 날짜의 할 일 보기", isOn: $allDates)
                Button { editing = PlanItem(title: "", date: day) } label: { Label("할 일 추가", systemImage: "plus") }
            }
            Section("할 일 \(tasks.filter { $0.isDone }.count)/\(tasks.count) 완료") {
                ForEach(tasks) { item in PlanRow(item: item, edit: { editing = item }) }
                if tasks.isEmpty { Text("할 일을 추가해 오늘의 공부를 계획하세요.").font(.subheadline).foregroundStyle(.secondary) }
            }
        }.listStyle(.plain).sheet(item: $editing) { item in PlanEditor(item: item) }
    }
}

struct PlanRow: View {
    let item: PlanItem
    let edit: () -> Void
    @EnvironmentObject private var planner: PlannerModel
    @EnvironmentObject private var study: StudyModel
    private var subject: StudySubject? { study.subjects.first { $0.id == item.subjectID } }
    var body: some View {
        HStack(spacing: 14) {
            if item.kind == .task {
                Button { planner.toggle(item.id) } label: { Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle").font(.title2) }
                    .buttonStyle(.borderless).accessibilityLabel(item.isDone ? "미완료로 변경" : "완료로 변경")
            } else { Image(systemName: "calendar").font(.title2).foregroundStyle(GoyoTheme.studyGreen) }
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).strikethrough(item.isDone).foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                    HStack {
                        if let name = subject?.name ?? item.subjectName {
                            Text(name).padding(.horizontal, 7).padding(.vertical, 2)
                                .background((subject?.color ?? .gray).opacity(0.15), in: Capsule())
                        }
                        Text(item.date.formatted(item.kind == .event ? .dateTime.month().day().hour().minute() : .dateTime.month().day()))
                            .foregroundStyle(.secondary)
                    }.font(.caption)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
        }.padding(.vertical, 4)
            .swipeActions { Button("삭제", role: .destructive) { planner.remove(item.id) } }
            .contextMenu {
                Button("수정", action: edit)
                Button("삭제", role: .destructive) { planner.remove(item.id) }
            }
    }
}

struct PlanEditor: View {
    @EnvironmentObject private var planner: PlannerModel
    @EnvironmentObject private var study: StudyModel
    @Environment(\.dismiss) private var dismiss
    @State private var item: PlanItem
    init(item: PlanItem) { _item = State(initialValue: item) }
    var body: some View {
        NavigationStack {
            Form {
                TextField("제목", text: $item.title)
                Picker("종류", selection: $item.kind) { ForEach(PlanKind.allCases, id: \.self) { kind in Text(kind.rawValue).tag(kind) } }
                DatePicker(item.kind == .task ? "할 날짜" : "일정 시간", selection: $item.date,
                           displayedComponents: item.kind == .task ? [.date] : [.date, .hourAndMinute])
                Picker("과목", selection: $item.subjectID) {
                    Text("과목 없음").tag(nil as UUID?)
                    ForEach(study.subjects) { subject in Text(subject.name).tag(Optional(subject.id)) }
                    if let id = item.subjectID, !study.subjects.contains(where: { $0.id == id }) {
                        Text(item.subjectName ?? "삭제된 과목").tag(Optional(id))
                    }
                }
                if item.kind == .task { Toggle("완료", isOn: $item.isDone) }
            }.navigationTitle(item.kind.rawValue).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") {
                            item.subjectName = study.subjects.first { $0.id == item.subjectID }?.name ?? (item.subjectID == nil ? nil : item.subjectName)
                            if item.kind == .event { item.isDone = false }
                            planner.save(item); dismiss()
                        }.disabled(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.title.count > 160)
                    }
                }
        }
    }
}

struct StudyCalendarView: View {
    @EnvironmentObject private var study: StudyModel
    @EnvironmentObject private var planner: PlannerModel
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())!.start
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var editing: PlanItem?
    @State private var rating: RatingRequest?
    private var cal: Calendar { Calendar.current }
    private var cells: [Date?] {
        let first = cal.dateInterval(of: .month, for: month)!.start
        let count = cal.range(of: .day, in: .month, for: first)!.count
        let padding = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: padding) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: first) }
    }
    private var weekdays: [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(cal.firstWeekday - 1 + $0) % 7] }
    }
    private var interval: DateInterval { cal.dateInterval(of: .day, for: day)! }
    private var records: [StudySegment] {
        study.segments.filter { $0.start < interval.end && $0.end > interval.start }.sorted { $0.start > $1.start }
    }
    var body: some View {
        List {
            Section {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless).accessibilityLabel("이전 달")
                    Spacer(); Text(month.formatted(.dateTime.year().month())).font(.headline); Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless).accessibilityLabel("다음 달")
                    Button("오늘") { day = cal.startOfDay(for: Date()); month = cal.dateInterval(of: .month, for: day)!.start }.buttonStyle(.borderless)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 8) {
                    ForEach(0..<7, id: \.self) { index in Text(weekdays[index]).font(.caption).foregroundStyle(.secondary) }
                    ForEach(cells.indices, id: \.self) { index in
                        if let date = cells[index] { dayCell(date) }
                        else { Color.clear.frame(height: 56) }
                    }
                }
            }
            Section(day.formatted(.dateTime.month().day().weekday())) {
                Text("공부 \(GoyoTheme.time(study.seconds(for: nil, since: interval.start, until: interval.end)))").font(.headline).monospacedDigit()
                ForEach(study.subjects.filter { study.seconds(for: $0.id, since: interval.start, until: interval.end) > 0 }) { subject in
                    HStack {
                        Circle().fill(subject.color).frame(width: 10, height: 10); Text(subject.name); Spacer()
                        Text(GoyoTheme.time(study.seconds(for: subject.id, since: interval.start, until: interval.end))).monospacedDigit()
                    }.font(.subheadline)
                }
                HStack {
                    Button("할 일 추가") { editing = PlanItem(title: "", date: day) }
                    Spacer()
                    Button("일정 추가") { editing = PlanItem(title: "", date: day, kind: .event) }
                }.buttonStyle(.borderless)
                ForEach(planner.on(day)) { item in PlanRow(item: item, edit: { editing = item }) }
                if planner.on(day).isEmpty { Text("등록된 할 일과 일정이 없습니다.").font(.caption).foregroundStyle(.secondary) }
            }
            Section("공부 기록 · 집중도") {
                ForEach(records) { segment in
                    Button { rating = RatingRequest(id: segment.id) } label: { StudyRecordRow(segment: segment) }.buttonStyle(.plain)
                }
                if records.isEmpty { Text("이 날짜의 공부 기록이 없습니다.").font(.caption).foregroundStyle(.secondary) }
            }
        }.listStyle(.plain)
            .sheet(item: $editing) { item in PlanEditor(item: item) }
            .sheet(item: $rating) { request in FocusRatingView(segmentID: request.id) }
    }
    private func shift(_ offset: Int) {
        if let next = cal.date(byAdding: .month, value: offset, to: month) { month = next; day = next }
    }
    private func dayCell(_ date: Date) -> some View {
        let selected = cal.isDate(date, inSameDayAs: day)
        let range = cal.dateInterval(of: .day, for: date)!
        let minutes = Int(study.seconds(for: nil, since: range.start, until: range.end) / 60)
        let hasPlan = !planner.on(date).isEmpty
        return Button { day = date } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: date))").font(.subheadline.weight(selected ? .bold : .regular))
                Text(minutes > 0 ? "\(minutes)분" : " ").font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.5)
                Circle().fill(hasPlan ? (selected ? Color.white : GoyoTheme.violet) : Color.clear).frame(width: 4, height: 4)
            }.frame(maxWidth: .infinity).frame(height: 56)
                .background(selected ? GoyoTheme.studyGreen : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(selected ? Color.white : Color.primary)
        }.buttonStyle(.plain).accessibilityLabel("\(date.formatted(.dateTime.month().day())), 공부 \(minutes)분\(hasPlan ? ", 일정 있음" : "")")
    }
}
