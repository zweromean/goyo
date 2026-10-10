import SwiftUI
import UIKit

struct StudyFocusView: View {
    @EnvironmentObject private var study: StudyModel
    @Environment(\.dismiss) private var dismiss
    @State private var tools = false
    @State private var todo = false
    @State private var calendar = false
    @State private var rating: RatingRequest?
    @AppStorage("studyKeepAwake", store: Shared.defaults) private var keepAwake = false
    @AppStorage("studyMainTimeTotal", store: Shared.defaults) private var showTotal = false
    private let green = Color(red: 0.46, green: 0.78, blue: 0.48)
    private var subject: StudySubject? { study.subjects.first { $0.id == (study.active?.subjectID ?? study.pausedSubjectID) } }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let start = Calendar.current.startOfDay(for: now)
            let current = study.active.map { max(0, now.timeIntervalSince($0.start)) } ?? 0
            let total = study.seconds(for: nil, since: start, until: now)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "line.3.horizontal") }.accessibilityLabel("집중 화면 접기")
                        Text(subject?.name ?? "공부").font(.title3.bold())
                        Text(GoyoTheme.time(subject.map { study.seconds(for: $0.id, since: start, until: now) } ?? total)).monospacedDigit()
                        Spacer()
                        Button { todo = true } label: { Image(systemName: "checkmark.square.fill") }.accessibilityLabel("할 일")
                        Button { calendar = true } label: { Image(systemName: "chart.bar.fill") }.accessibilityLabel("공부 기록")
                    }.font(.title3).padding(.vertical, 18)
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(showTotal ? "오늘 누적 공부 시간" : (study.active == nil ? "일시정지 · 휴식 중" : "현재 집중 시간")).font(.subheadline).foregroundStyle(.gray)
                            HStack(spacing: 10) {
                                Text(GoyoTheme.time(showTotal ? total : current)).font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                                Button { if study.active != nil { study.pause() } else { study.resume() } } label: {
                                    Image(systemName: study.active != nil ? "pause.fill" : "play.fill").font(.title3).foregroundStyle(.black).frame(width: 42, height: 42).background(.white, in: Circle())
                                }.accessibilityLabel(study.active != nil ? "공부 일시정지" : "공부 재개")
                            }
                        }
                        Spacer(minLength: 4)
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.clock").font(.system(size: 45))
                            Text(GoyoTheme.time(total)).font(.caption).monospacedDigit()
                        }.foregroundStyle(green)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.black, in: RoundedRectangle(cornerRadius: 24))
                    VStack(alignment: .leading, spacing: 22) {
                        HStack { Text("오늘의 공부").font(.title2.bold()); Spacer(); Text(study.active == nil ? "휴식 중" : "집중 중").foregroundStyle(green).font(.caption) }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
                            ForEach(study.subjects) { item in
                                let selected = item.id == subject?.id
                                VStack(spacing: 12) {
                                    Image(systemName: selected ? "person.fill" : "book.closed").font(.system(size: 38))
                                    Text(item.name).font(.subheadline).lineLimit(1)
                                    Text(GoyoTheme.time(study.seconds(for: item.id, since: start, until: now))).font(.caption).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                                }.frame(maxWidth: .infinity).padding(.vertical, 18).foregroundStyle(selected ? green : .gray)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? green : .clear))
                            }
                        }
                    }.padding(20).background(.black, in: RoundedRectangle(cornerRadius: 24))
                    VStack(alignment: .leading, spacing: 12) {
                        Text("오늘의 타임라인").font(.headline)
                        ForEach(study.segments.filter { $0.end > start }.suffix(12)) { segment in
                            HStack {
                                Rectangle().fill(study.subjects.first { $0.id == segment.subjectID }?.color ?? green).frame(width: 4)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(segment.name)
                                    Text("\(segment.start.formatted(.dateTime.hour().minute())) – \(segment.end.formatted(.dateTime.hour().minute()))").font(.caption).foregroundStyle(.gray)
                                }
                                Spacer(); Text(GoyoTheme.time(segment.end.timeIntervalSince(segment.start))).monospacedDigit().font(.caption)
                            }.frame(minHeight: 40)
                        }
                        if study.segments.filter({ $0.end > start }).isEmpty { Text("집중을 마치면 기록이 여기에 쌓입니다.").font(.caption).foregroundStyle(.gray) }
                    }.padding(18)
                    Button("공부 종료 · 기록 저장") {
                        let last = study.stop() ?? study.segments.last?.id
                        if let last { rating = RatingRequest(id: last) } else { dismiss() }
                    }.frame(maxWidth: .infinity).padding(16).background(green.opacity(0.15), in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(green)
                    HStack {
                        Toggle("화면 유지", isOn: $keepAwake).font(.caption)
                        Spacer(minLength: 24)
                        Button { tools = true } label: { Label("더보기", systemImage: "ellipsis") }
                    }.padding(.vertical, 12)
                }.padding(16)
            }.background(Color(white: 0.065)).foregroundStyle(.white)
        }.preferredColorScheme(.dark).buttonStyle(.plain)
            .onAppear { UIApplication.shared.isIdleTimerDisabled = keepAwake }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .onChange(of: keepAwake) { _, value in UIApplication.shared.isIdleTimerDisabled = value }
            .sheet(isPresented: $todo) { NavigationStack { TodoView().navigationTitle("To-do").toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { todo = false } } } } }
            .sheet(isPresented: $calendar) { NavigationStack { StudyCalendarView().navigationTitle("공부 기록").toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { calendar = false } } } } }
            .sheet(isPresented: $tools) {
                NavigationStack { StudyToolsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { tools = false } } } }
            }
            .sheet(item: $rating, onDismiss: { if !study.inSession { dismiss() } }) { FocusRatingView(segmentID: $0.id) }
    }
}
