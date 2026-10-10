import SwiftUI
import Combine
import AVFoundation
import UserNotifications

struct NotesView: View {
    @AppStorage("studyNote", store: Shared.defaults) private var note = ""
    var body: some View { TextEditor(text: $note).padding().navigationTitle("메모").onChange(of: note) { _, value in if value.count > 50000 { note = String(value.prefix(50000)) } } }
}

struct StudyToolsView: View {
    @AppStorage("studyKeepAwake", store: Shared.defaults) private var keepAwake = false
    @AppStorage("studyMainTimeTotal", store: Shared.defaults) private var total = false
    @EnvironmentObject private var study: StudyModel
    var body: some View {
        Form {
            Section {
                Toggle("화면 켜짐 상태 유지", isOn: $keepAwake)
                Toggle("메인 시간 · 오늘 누적 표시", isOn: $total)
            } header: { Text("집중 화면") } footer: { Text("화면 유지는 집중 화면이 열려 있을 때 적용됩니다.") }
            Section("공부 도구") {
                NavigationLink { NotesView() } label: { Label("메모", systemImage: "bookmark.fill") }
                NavigationLink { UtilityTimerView() } label: { Label("타이머 · 스톱워치", systemImage: "timer") }
                NavigationLink { CalculatorView() } label: { Label("계산기", systemImage: "calculator") }
                NavigationLink { NoiseView() } label: { Label("백색소음", systemImage: "headphones") }
                NavigationLink { CommunicationView() } label: { Label("전화 · 문자", systemImage: "phone") }
                NavigationLink { LauncherListView() } label: { Label("허용 메뉴", systemImage: "square.grid.2x2") }
            }
        }.navigationTitle("더보기").preferredColorScheme(.dark)
    }
}

struct UtilityTimerView: View {
    @State private var stopwatch = false
    @State private var minutes = 25
    @State private var started: Date?
    @State private var deadline: Date?
    @State private var accumulated: TimeInterval = 0
    @State private var notificationMessage: String?
    private let requestID = "goyo.utility-timer"
    var body: some View {
        Form {
            Section {
                Picker("종류", selection: $stopwatch) { Text("타이머").tag(false); Text("스톱워치").tag(true) }.pickerStyle(.segmented).disabled(started != nil)
                if !stopwatch { Stepper("\(minutes)분", value: $minutes, in: 1...180).disabled(started != nil) }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(GoyoTheme.time(stopwatch ? accumulated + (started.map { context.date.timeIntervalSince($0) } ?? 0) : max(0, deadline?.timeIntervalSince(context.date) ?? Double(minutes * 60))))
                        .font(.system(size: 48, weight: .medium, design: .rounded)).monospacedDigit().frame(maxWidth: .infinity).padding(.vertical, 24)
                }
                Button(started == nil ? "시작" : "정지") {
                    if let start = started {
                        if stopwatch { accumulated += max(0, Date().timeIntervalSince(start)) }
                        started = nil; deadline = nil
                        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestID])
                    } else {
                        started = Date()
                        if !stopwatch {
                            let end = Date().addingTimeInterval(Double(minutes * 60)); deadline = end
                            Task { await schedule(end) }
                        }
                    }
                }
                Button("초기화") { started = nil; deadline = nil; accumulated = 0; UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestID]) }
                if let notificationMessage { Text(notificationMessage).font(.caption).foregroundStyle(.secondary) }
            }
        }.navigationTitle("타이머 · 스톱워치")
    }
    private func schedule(_ end: Date) async {
        let center = UNUserNotificationCenter.current()
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { notificationMessage = "알림을 허용하면 종료 알림을 받을 수 있습니다."; return }
            guard deadline == end else { return }
            let content = UNMutableNotificationContent(); content.title = "타이머 완료"; content.body = "설정한 공부 시간이 지났습니다."; content.sound = .default
            try await center.add(UNNotificationRequest(identifier: requestID, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)))
            notificationMessage = "종료 알림이 예약되었습니다."
        } catch { notificationMessage = "알림을 예약하지 못했습니다." }
    }
}

struct CalculatorView: View {
    @State private var value = "0"
    @State private var stored: Double?
    @State private var operation: String?
    @State private var fresh = true
    private let keys = ["AC", "±", "%", "÷", "7", "8", "9", "×", "4", "5", "6", "−", "1", "2", "3", "+", "0", ".", "⌫", "="]
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Text(value).font(.system(size: 54, weight: .light)).lineLimit(1).minimumScaleFactor(0.2).frame(maxWidth: .infinity, alignment: .trailing).padding()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(keys, id: \.self) { key in
                    Button { tap(key) } label: { Text(key).font(.title2).frame(maxWidth: .infinity).frame(height: 65).background(["÷", "×", "−", "+", "="].contains(key) ? Color.orange : Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain)
                }
            }
        }.padding().navigationTitle("계산기")
    }
    private func tap(_ key: String) {
        switch key {
        case "AC": value = "0"; stored = nil; operation = nil; fresh = true
        case "±": if let number = Double(value) { value = display(-number) }
        case "%": if let number = Double(value) { value = display(number / 100) }
        case "⌫": if !fresh { value = String(value.dropLast()); if value.isEmpty || value == "-" { value = "0" } }
        case "+", "−", "×", "÷":
            if !fresh { calculate() }; stored = Double(value); operation = key; fresh = true
        case "=": calculate(); stored = nil; operation = nil; fresh = true
        default:
            if fresh || value == "오류" { value = "0"; fresh = false }
            if key == "." { if !value.contains(".") { value += "." } }
            else if value.count < 16 { value = value == "0" ? key : value + key }
        }
    }
    private func calculate() {
        guard let a = stored, let b = Double(value), let operation else { return }
        let result: Double
        switch operation { case "+": result = a + b; case "−": result = a - b; case "×": result = a * b; default: result = b == 0 ? .nan : a / b }
        value = result.isFinite ? display(result) : "오류"
    }
    private func display(_ number: Double) -> String { String(format: "%.12g", number) }
}

@MainActor
final class NoisePlayer: ObservableObject {
    @Published private(set) var playing = false
    @Published var error: String?
    private var player: AVAudioPlayer?
    func toggle() {
        if playing { stop(); return }
        do {
            guard let url = Bundle.main.url(forResource: "WhiteNoise", withExtension: "wav") else { error = "소음 파일을 읽지 못했습니다."; return }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url); player.numberOfLoops = -1; player.volume = 0.22
            guard player.play() else { error = "소음을 재생하지 못했습니다."; return }
            self.player = player; playing = true
        } catch { self.error = "오디오를 시작하지 못했습니다." }
    }
    func stop() { player?.stop(); player = nil; playing = false; try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
}
struct NoiseView: View {
    @StateObject private var player = NoisePlayer()
    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "waveform").font(.system(size: 70)).foregroundStyle(.mint)
            Text("백색소음").font(.title.bold())
            Button(player.playing ? "소음 정지" : "소음 재생") { player.toggle() }.buttonStyle(.borderedProminent)
            Text("화면이 열려 있는 동안 재생합니다. 기기의 음량 버튼으로 조절하세요.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let error = player.error { Text(error).foregroundStyle(.red) }
        }.padding().frame(maxWidth: .infinity, maxHeight: .infinity).navigationTitle("백색소음").onDisappear { player.stop() }
    }
}
