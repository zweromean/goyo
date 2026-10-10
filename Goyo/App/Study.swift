import SwiftUI
import Combine

struct StudySubject: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var colorKey: String = "auto"
    init(id: UUID = UUID(), name: String, colorKey: String = "auto") { self.id = id; self.name = name; self.colorKey = colorKey }
    enum CodingKeys: String, CodingKey { case id, name, colorKey }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        colorKey = try c.decodeIfPresent(String.self, forKey: .colorKey) ?? "auto"
    }
    var color: Color {
        let key = colorKey == "auto" ? ["국어": "coral", "수학": "purple", "영어": "teal", "탐구": "gold"][name] ?? "green" : colorKey
        return StudyPalette.color(key)
    }
}
enum StudyPalette {
    static let keys = ["coral", "purple", "teal", "gold", "green", "blue"]
    static let names = ["coral": "코랄", "purple": "보라", "teal": "청록", "gold": "노랑", "green": "초록", "blue": "파랑"]
    static func color(_ key: String) -> Color {
        switch key {
        case "coral": return Color(red: 0.91, green: 0.43, blue: 0.44)
        case "purple": return Color(red: 0.58, green: 0.45, blue: 0.80)
        case "teal": return Color(red: 0.28, green: 0.69, blue: 0.67)
        case "gold": return Color(red: 0.84, green: 0.64, blue: 0.23)
        case "blue": return .blue
        default: return GoyoTheme.studyGreen
        }
    }
}
struct StudySegment: Identifiable, Codable {
    var id: UUID = UUID()
    var subjectID: UUID
    var name: String
    var start: Date
    var end: Date
    var focusRating: Int = 0
    init(subjectID: UUID, name: String, start: Date, end: Date) {
        self.subjectID = subjectID; self.name = name; self.start = start; self.end = end
    }
    enum CodingKeys: String, CodingKey { case id, subjectID, name, start, end, focusRating }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); subjectID = try c.decode(UUID.self, forKey: .subjectID)
        name = try c.decode(String.self, forKey: .name)
        start = try c.decode(Date.self, forKey: .start); end = try c.decode(Date.self, forKey: .end)
        focusRating = min(5, max(0, try c.decodeIfPresent(Int.self, forKey: .focusRating) ?? 0))
    }
}
struct ActiveStudy: Codable { var subjectID: UUID; var name: String; var start: Date }

@MainActor
final class StudyModel: ObservableObject {
    @Published var subjects: [StudySubject]
    @Published var segments: [StudySegment]
    @Published var active: ActiveStudy?
    @Published private(set) var pausedSubjectID: UUID?
    @Published var blockSNS: Bool
    @Published var selected: UUID
    init() {
        let d = Shared.defaults
        let saved = d.data(forKey: "studySubjects").flatMap { try? JSONDecoder().decode([StudySubject].self, from: $0) }
        let loaded = saved?.isEmpty == false ? saved! : [StudySubject(name: "국어"), StudySubject(name: "수학"), StudySubject(name: "영어"), StudySubject(name: "탐구")]
        subjects = loaded
        segments = d.data(forKey: "studySegments").flatMap { try? JSONDecoder().decode([StudySegment].self, from: $0) } ?? []
        let restored = d.data(forKey: "activeStudy").flatMap { try? JSONDecoder().decode(ActiveStudy.self, from: $0) }
        active = restored; selected = restored?.subjectID ?? loaded[0].id
        pausedSubjectID = restored == nil ? d.string(forKey: "pausedStudySubject").flatMap(UUID.init(uuidString:)) : nil
        blockSNS = d.object(forKey: Shared.studyLockKey) as? Bool ?? true
        persist()
    }
    var inSession: Bool { active != nil || pausedSubjectID != nil }
    var isBlockingSNS: Bool { inSession && blockSNS }
    func start() {
        guard active == nil, let subject = subjects.first(where: { $0.id == selected }) else { return }
        active = ActiveStudy(subjectID: subject.id, name: subject.name, start: Date())
        pausedSubjectID = nil
        Shared.defaults.removeObject(forKey: Shared.unlockUntilKey); persist()
    }
    @discardableResult func stop() -> UUID? {
        pausedSubjectID = nil
        guard let current = active else { persist(); return nil }
        let end = Date(); var id: UUID?
        if end > current.start {
            let segment = StudySegment(subjectID: current.subjectID, name: current.name, start: current.start, end: end)
            segments.append(segment); id = segment.id
        }
        active = nil; persist(); return id
    }
    func pause() {
        guard let current = active else { return }
        _ = stop(); pausedSubjectID = current.subjectID; persist()
    }
    func resume() {
        guard let id = pausedSubjectID else { return }
        selected = id; start()
    }
    func rate(_ id: UUID, stars: Int) {
        guard let i = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[i].focusRating = min(5, max(0, stars)); persist()
    }
    func setBlock(_ value: Bool) { blockSNS = value; persist() }
    func add(_ name: String, color: String = "auto") {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 40 else { return }
        let subject = StudySubject(name: clean, colorKey: color)
        subjects.append(subject); selected = subject.id; persist()
    }
    func edit(_ id: UUID, name: String, color: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard active?.subjectID != id, pausedSubjectID != id, !clean.isEmpty, clean.count <= 40, let i = subjects.firstIndex(where: { $0.id == id }) else { return }
        subjects[i].name = clean; subjects[i].colorKey = color; persist()
    }
    func remove(_ id: UUID) {
        guard subjects.count > 1, active?.subjectID != id, pausedSubjectID != id else { return }
        subjects.removeAll { $0.id == id }
        if selected == id { selected = subjects[0].id }; persist()
    }
    func seconds(for subject: UUID?, since start: Date, until end: Date) -> TimeInterval {
        var total = segments.filter { subject == nil || $0.subjectID == subject }.reduce(0.0) {
            $0 + max(0, min($1.end, end).timeIntervalSince(max($1.start, start)))
        }
        if let active, subject == nil || active.subjectID == subject {
            total += max(0, min(Date(), end).timeIntervalSince(max(active.start, start)))
        }
        return total
    }
    private func persist() {
        let d = Shared.defaults
        d.set(try? JSONEncoder().encode(subjects), forKey: "studySubjects")
        d.set(try? JSONEncoder().encode(segments), forKey: "studySegments")
        if let active { d.set(try? JSONEncoder().encode(active), forKey: "activeStudy") }
        else { d.removeObject(forKey: "activeStudy") }
        d.set(pausedSubjectID?.uuidString, forKey: "pausedStudySubject")
        d.set(inSession, forKey: Shared.studyActiveKey); d.set(blockSNS, forKey: Shared.studyLockKey)
        #if !WEB_ONLY
        Locking.reconcile()
        #endif
    }
}

struct RatingRequest: Identifiable { let id: UUID }
enum StudyTab: String, CaseIterable { case timer = "타이머", statistics = "통계", todo = "To-do", calendar = "캘린더" }
struct StudyView: View {
    @EnvironmentObject private var study: StudyModel
    @State private var tab: StudyTab = .timer
    @State private var editSubjects = false
    @State private var rating: RatingRequest?
    @State private var focusScreen = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                header(context.date)
                HStack(spacing: 0) {
                    ForEach(StudyTab.allCases, id: \.self) { value in
                        Button { tab = value } label: {
                            VStack(spacing: 12) {
                                Text(value.rawValue).font(.subheadline.weight(tab == value ? .semibold : .regular))
                                Rectangle().fill(tab == value ? Color.primary : .clear).frame(height: 3)
                            }.frame(maxWidth: .infinity).padding(.top, 18)
                        }.buttonStyle(.plain).foregroundStyle(tab == value ? Color.primary : Color.secondary)
                    }
                }
                Group {
                    switch tab {
                    case .timer: timer(context.date)
                    case .statistics: statistics(context.date)
                    case .todo: TodoView()
                    case .calendar: StudyCalendarView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(Color(.systemBackground))
        }.toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $editSubjects) { NavigationStack { SubjectsEditor() } }
            .sheet(item: $rating) { request in FocusRatingView(segmentID: request.id) }
            .fullScreenCover(isPresented: $focusScreen) { StudyFocusView() }
            .onChange(of: study.inSession) { _, value in if value { focusScreen = true } }
    }
    private func header(_ now: Date) -> some View {
        let today = Calendar.current.startOfDay(for: now)
        return VStack(spacing: 24) {
            HStack {
                Text("공부").font(.headline)
                Spacer(); Text(now.formatted(.dateTime.month().day().weekday(.abbreviated))).font(.subheadline); Spacer()
                Image(systemName: study.active == nil ? "book.closed" : "book.fill")
            }
            Text(GoyoTheme.time(study.seconds(for: nil, since: today, until: now)))
                .font(.system(size: 54, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                .accessibilityLabel("오늘 총 공부 시간")
            Text(study.active.map { "\($0.name) 공부 중 · \(GoyoTheme.time(now.timeIntervalSince($0.start)))" } ?? "오늘의 시간을 차곡차곡")
                .font(.subheadline).opacity(0.85)
        }.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 32)
            .frame(maxWidth: .infinity).foregroundStyle(.white).background(GoyoTheme.studyGreen)
    }
    private func timer(_ now: Date) -> some View {
        let today = Calendar.current.startOfDay(for: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if study.inSession {
                    Button("집중 화면으로 돌아가기") { focusScreen = true }.buttonStyle(.borderedProminent)
                }
                ForEach(study.subjects) { subject in
                    let running = study.active?.subjectID == subject.id
                    HStack(spacing: 16) {
                        Button {
                            if running { if let id = study.stop() { rating = RatingRequest(id: id) } }
                            else { study.selected = subject.id; study.start() }
                        } label: {
                            Image(systemName: running ? "stop.fill" : "play.fill").font(.title3)
                                .frame(width: 48, height: 48).background(subject.color, in: Circle()).foregroundStyle(.white)
                        }.disabled(study.active != nil && !running).accessibilityLabel("\(subject.name) \(running ? "종료" : "시작")")
                        Text(subject.name).font(.title3.weight(.medium))
                        Spacer()
                        Text(GoyoTheme.time(study.seconds(for: subject.id, since: today, until: now)))
                            .font(.system(.title3, design: .rounded).weight(.medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    }.padding(.vertical, 16)
                }
                HStack {
                    Button { editSubjects = true } label: { Label("과목 편집", systemImage: "pencil") }
                    Button { tab = .todo } label: { Label("To-do", systemImage: "checkmark.square") }
                    Button { tab = .calendar } label: { Label("캘린더", systemImage: "calendar") }
                }.buttonStyle(.bordered).font(.caption).padding(.top, 12)
                NavigationLink("공부 중 잠금 설정") {
                    ProtectedSettings {
                        Form {
                            Toggle("공부 중 SNS 잠그기", isOn: Binding(get: { study.blockSNS }, set: { study.setBlock($0) }))
                            Text("고요의 SNS 진입을 막고, 전체 버전에서는 선택한 기존 앱도 잠급니다.")
                        }.navigationTitle("공부 중 잠금").toolbar(.visible, for: .navigationBar)
                    }
                }.font(.subheadline).padding(.top, 18)
                Text("화면을 끄거나 앱을 나가도 시간이 이어집니다. 공부를 마치면 과목의 정지 버튼을 눌러주세요.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 10)
            }.padding(.horizontal, 24).padding(.bottom, 24)
        }
    }
    private func statistics(_ now: Date) -> some View {
        let today = Calendar.current.startOfDay(for: now)
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        return List {
            Section("과목별 공부 시간") {
                ForEach(study.subjects) { subject in
                    VStack(alignment: .leading, spacing: 8) {
                        Label { Text(subject.name) } icon: { Circle().fill(subject.color).frame(width: 10, height: 10) }
                        Text("오늘 \(GoyoTheme.time(study.seconds(for: subject.id, since: today, until: now))) · 이번 주 \(GoyoTheme.time(study.seconds(for: subject.id, since: week, until: now)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("최근 기록 · 집중도") {
                ForEach(Array(study.segments.sorted { $0.start > $1.start }.prefix(50))) { segment in
                    Button { rating = RatingRequest(id: segment.id) } label: { StudyRecordRow(segment: segment) }.buttonStyle(.plain)
                }
                if study.segments.isEmpty { Text("첫 공부 기록을 남겨보세요.").foregroundStyle(.secondary) }
            }
        }.listStyle(.plain)
    }
}
struct StudyRecordRow: View {
    let segment: StudySegment
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(segment.name).font(.headline); Spacer(); Text(GoyoTheme.time(segment.end.timeIntervalSince(segment.start))).monospacedDigit() }
            HStack {
                Text(segment.start.formatted(.dateTime.month().day().hour().minute())).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if segment.focusRating == 0 { Text("집중도 평가하기").font(.caption).foregroundStyle(.secondary) }
                else { Text(String(repeating: "★", count: segment.focusRating) + String(repeating: "☆", count: 5 - segment.focusRating)).foregroundStyle(.orange).font(.caption) }
            }
        }.padding(.vertical, 4)
    }
}
struct FocusRatingView: View {
    let segmentID: UUID
    @EnvironmentObject private var study: StudyModel
    @Environment(\.dismiss) private var dismiss
    @State private var stars = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Text("얼마나 집중하셨나요?").font(.title2.bold())
                if let segment = study.segments.first(where: { $0.id == segmentID }) {
                    Text("\(segment.name) · \(GoyoTheme.time(segment.end.timeIntervalSince(segment.start)))").foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    ForEach(1...5, id: \.self) { value in
                        Button { stars = value } label: { Image(systemName: value <= stars ? "star.fill" : "star").font(.largeTitle).foregroundStyle(.orange) }
                            .accessibilityLabel("집중도 \(value)점")
                    }
                }
                Text("직접 매기는 집중도 평가입니다.").font(.caption).foregroundStyle(.secondary)
                Button("평가 저장") { study.rate(segmentID, stars: stars); dismiss() }.buttonStyle(.borderedProminent).disabled(stars == 0)
                Button("나중에 평가") { dismiss() }
            }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("집중도").navigationBarTitleDisplayMode(.inline)
                .onAppear { stars = study.segments.first { $0.id == segmentID }?.focusRating ?? 0 }
        }.presentationDetents([.medium])
    }
}
struct SubjectsEditor: View {
    @EnvironmentObject private var study: StudyModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = "coral"
    var body: some View {
        List {
            Section("과목") {
                ForEach(study.subjects) { subject in
                    NavigationLink { SubjectDetailEditor(subject: subject) } label: {
                        Label { Text(subject.name) } icon: { Circle().fill(subject.color).frame(width: 14, height: 14) }
                    }
                }
            }
            Section("새 과목") {
                TextField("과목 이름", text: $name)
                Picker("색상", selection: $color) { ForEach(StudyPalette.keys, id: \.self) { key in Text(StudyPalette.names[key] ?? key).tag(key) } }
                Button("추가") { study.add(name, color: color); name = "" }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 40)
            }
        }.navigationTitle("과목 편집").toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
    }
}
struct SubjectDetailEditor: View {
    let subject: StudySubject
    @EnvironmentObject private var study: StudyModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var color: String
    init(subject: StudySubject) { self.subject = subject; _name = State(initialValue: subject.name); _color = State(initialValue: subject.colorKey) }
    var body: some View {
        Form {
            TextField("과목 이름", text: $name)
            Picker("색상", selection: $color) {
                Text("자동").tag("auto")
                ForEach(StudyPalette.keys, id: \.self) { key in Text(StudyPalette.names[key] ?? key).tag(key) }
            }
            Button("저장") { study.edit(subject.id, name: name, color: color); dismiss() }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 40 || study.active?.subjectID == subject.id)
            Button("과목 삭제", role: .destructive) { study.remove(subject.id); dismiss() }
                .disabled(study.subjects.count <= 1 || study.active?.subjectID == subject.id)
            Text("과목을 삭제해도 이전 공부 기록은 남습니다.").font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("과목 설정")
    }
}
