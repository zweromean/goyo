import SwiftUI
#if !WEB_ONLY
import FamilyControls
import DeviceActivity
import Combine

@MainActor
final class GuardModel: ObservableObject {
    @Published var authorized = AuthorizationCenter.shared.authorizationStatus == .approved
    @Published var enabled = Shared.defaults.bool(forKey: Shared.enabledKey)
    @Published var selection = Locking.selection
    @Published var error: String?
    @Published var until: Date?
    private let center = DeviceActivityCenter()
    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }
    func refresh() {
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
        enabled = Shared.defaults.bool(forKey: Shared.enabledKey)
        let value = Shared.defaults.double(forKey: Shared.unlockUntilKey)
        until = value > Date().timeIntervalSince1970 ? Date(timeIntervalSince1970: value) : nil
        if authorized { Locking.reconcile() }
    }
    func authorize(family: Bool = false) async {
        if authorized && family != Shared.defaults.bool(forKey: Shared.familyModeKey) {
            error = "아이폰 설정에서 기존 고요의 스크린 타임 접근을 해제한 뒤 승인 모드를 변경해주세요."
            return
        }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: family ? .child : .individual)
            Shared.defaults.set(family, forKey: Shared.familyModeKey)
            refresh()
        } catch { self.error = "스크린 타임 연결을 완료하지 못했습니다. 아이폰에서 권한을 허용한 뒤 다시 시도해주세요." }
    }
    func saveSelection() {
        Locking.selection = selection
        if enabled { relock() }
    }
    func setEnabled(_ value: Bool) {
        guard !value || (authorized && hasSelection) else {
            error = "스크린 타임을 연결하고 잠글 앱을 선택해주세요."
            return
        }
        enabled = value
        Shared.defaults.set(value, forKey: Shared.enabledKey)
        relock()
    }
    func relock() {
        // Clear the pending unlock first: intervalDidEnd can also run when monitoring stops.
        Shared.defaults.removeObject(forKey: Shared.unlockUntilKey)
        center.stopMonitoring([DeviceActivityName(Shared.activityName)])
        until = nil
        Locking.apply()
    }
    func unlock() -> Bool {
        guard !Locking.studying else { error = "공부 기록을 종료한 뒤 앱 잠금을 해제해주세요."; return false }
        guard authorized && enabled && hasSelection else {
            error = "잠금이 켜진 앱을 선택한 뒤 다시 시도해주세요."
            return false
        }
        relock()
        let start = Date().addingTimeInterval(1)
        // Apple's DeviceActivity requires a schedule at least 15 minutes long.
        let end = start.addingTimeInterval(16 * 60)
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: Calendar.current.dateComponents(components, from: start),
            intervalEnd: Calendar.current.dateComponents(components, from: end), repeats: false
        )
        do {
            try center.startMonitoring(DeviceActivityName(Shared.activityName), during: schedule)
            Shared.defaults.set(end.timeIntervalSince1970, forKey: Shared.unlockUntilKey)
            Locking.store.clearAllSettings()
            until = end
            return true
        } catch {
            Locking.endUnlock()
            self.error = "자동 재잠금 예약을 만들지 못해 앱 잠금을 유지했습니다. 다시 시도해주세요."
            return false
        }
    }
}
#endif

struct GuardView: View {
    @EnvironmentObject private var app: AppModel
    #if !WEB_ONLY
    @StateObject private var guardModel = GuardModel()
    @Environment(\.scenePhase) private var phase
    @State private var showPicker = false
    @State private var showWait = false
    private let refreshClock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    #endif
    var body: some View {
        #if WEB_ONLY
        Form {
            Section("브라우저 버전") {
                Text("이 버전은 고요 안의 SNS 필터와 열기 전 대기를 제공합니다.")
                Text("기존 앱 전체 잠금은 Goyo 전체 버전을 설치하면 사용할 수 있습니다.")
                    .foregroundStyle(.secondary)
            }
        }.navigationTitle("앱 잠금")
        #else
        Form {
            Section("스크린 타임") {
                Label(guardModel.authorized ? "스크린 타임 연결됨" : "스크린 타임 연결 필요", systemImage: guardModel.authorized ? "checkmark.circle" : "exclamationmark.circle")
                Text("선택한 앱 \(guardModel.selection.applicationTokens.count)개")
                NavigationLink("스크린 타임 · 잠금 설정") {
                    ProtectedSettings {
                        Form {
                            Button("스크린 타임 연결") { Task { await guardModel.authorize(family: Shared.defaults.bool(forKey: Shared.familyModeKey)) } }
                            Button("잠글 앱 선택") { showPicker = true }.disabled(!guardModel.authorized)
                            Toggle("선택한 앱 잠그기", isOn: Binding(get: { guardModel.enabled }, set: { guardModel.setEnabled($0) }))
                                .disabled(!guardModel.authorized || !guardModel.hasSelection)
                            Text("고요 자체는 선택하지 마세요. 공부 중에는 이 설정과 별도로 선택한 앱이 잠깁니다.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.navigationTitle("잠금 설정")
                            .familyActivityPicker(isPresented: $showPicker, selection: $guardModel.selection)
                    }
                }
            }
            Section("대기 후 사용") {
                if let until = guardModel.until {
                    Label("앱 사용 가능", systemImage: "lock.open")
                    HStack { Text("자동 재잠금까지"); Spacer(); Text(until, style: .timer).monospacedDigit() }
                    Button("지금 다시 잠그기") { guardModel.relock() }
                } else {
                    Button("\(app.settings.waitSeconds)초 기다리고 잠금 해제") { showWait = true }
                        .disabled(!guardModel.authorized || !guardModel.enabled || !guardModel.hasSelection)
                    Text("대기가 끝나면 선택한 앱을 16분 동안 사용할 수 있습니다. 시간이 지나면 다시 잠깁니다.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Section("사용 순서") {
                Text("잠긴 앱을 열면 안내 화면이 표시됩니다. 홈 화면에서 고요를 열고 ‘앱 잠금’ 탭에서 기다린 뒤 원하는 앱으로 돌아가세요.")
                    .font(.subheadline)
            }
        }
        .navigationTitle("앱 잠금")
        .onChange(of: guardModel.selection) { _, _ in guardModel.saveSelection() }
        .onChange(of: phase) { _, value in if value == .active { guardModel.refresh() } }
        .onReceive(refreshClock) { _ in if phase == .active { guardModel.refresh() } }
        .onAppear { guardModel.refresh() }
        .sheet(isPresented: $showWait) {
            WaitView(title: "선택한 앱 잠금 해제", seconds: app.settings.waitSeconds) {
                _ = guardModel.unlock()
                showWait = false
            }
        }
        .alert("앱 잠금", isPresented: Binding(get: { guardModel.error != nil }, set: { if !$0 { guardModel.error = nil } })) {
            Button("확인") { guardModel.error = nil }
        } message: { Text(guardModel.error ?? "") }
        #endif
    }
}
