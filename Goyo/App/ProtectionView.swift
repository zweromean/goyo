import SwiftUI

struct ProtectionView: View {
    @EnvironmentObject private var app: AppModel
    @State private var setupPIN = false
    @State private var newDomain = ""
    @State private var extraDomains = Shared.defaults.stringArray(forKey: "extraBlockedDomains") ?? []
    @State private var familyMode = Shared.defaults.bool(forKey: Shared.familyModeKey)
    @State private var denyRemoval = Shared.defaults.bool(forKey: Shared.removalKey)
    @State private var message: String?
    #if !WEB_ONLY
    @StateObject private var guardModel = GuardModel()
    #endif
    var body: some View {
        ProtectedSettings {
            Form {
                Section {
                    Button(PasscodeStore.hasPIN ? "설정 비밀번호 변경" : "설정 비밀번호 만들기") { setupPIN = true }
                    if PasscodeStore.hasPIN {
                        Button("지금 설정 잠그기") { app.settingsUnlocked = false }
                        Button("설정 비밀번호 해제", role: .destructive) {
                            if PasscodeStore.remove() { app.settingsUnlocked = false }
                            else { message = "비밀번호를 해제하지 못했습니다." }
                        }
                    }
                } header: { Text("설정 해제 방지") } footer: {
                    Text("필터·휴식·기존 앱 잠금·보호 설정 변경에 비밀번호를 요구합니다. 앱을 나가면 다시 잠깁니다.")
                }
                Section {
                    Toggle("성인 웹사이트 차단", isOn: $app.settings.blockAdult)
                    #if WEB_ONLY
                    Text("고요 브라우저에서 내장 차단 도메인과 직접 추가한 도메인을 차단합니다. 현재 빌드에서는 Apple 성인 콘텐츠 필터를 실행하지 않습니다.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    #else
                    Text(guardModel.authorized ? "Apple 성인 콘텐츠 필터와 추가 차단 도메인을 적용합니다." : "스크린 타임을 연결하면 Apple 성인 콘텐츠 필터를 사용할 수 있습니다. 연결 전에는 내장·추가 도메인 목록만 고요 브라우저에 적용합니다.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    #endif
                    TextField("추가 차단 도메인", text: $newDomain).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("차단 목록에 추가") {
                        guard let domain = AdultSites.normalize(newDomain) else { message = "example.com 형식으로 입력해주세요."; return }
                        if !extraDomains.contains(domain) { extraDomains.append(domain) }
                        newDomain = ""
                        saveDomains()
                    }.disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                    ForEach(extraDomains, id: \.self) { domain in
                        HStack {
                            Text(domain); Spacer()
                            Button("삭제") { extraDomains.removeAll { $0 == domain }; saveDomains() }
                        }
                    }
                } header: { Text("웹사이트") } footer: {
                    Text("성인 사이트 차단을 켜면 추가 도메인도 함께 차단합니다. SNS를 잠시 해제해도 성인 사이트 차단은 유지됩니다.")
                }
                #if !WEB_ONLY
                Section {
                    Toggle("가족 공유 · 보호자 승인 모드", isOn: $familyMode).disabled(guardModel.authorized)
                        .onChange(of: familyMode) { _, value in Shared.defaults.set(value, forKey: Shared.familyModeKey) }
                    Button(guardModel.authorized ? "스크린 타임 연결 상태 확인" : "스크린 타임 연결") {
                        Task { await guardModel.authorize(family: familyMode) }
                    }
                    Label(guardModel.authorized ? (familyMode ? "보호자 승인 모드로 연결됨" : "개인 승인 모드로 연결됨") : "아직 연결되지 않음", systemImage: "person.badge.shield.checkmark")
                    Toggle("앱 삭제 제한 · 기기 전체", isOn: $denyRemoval)
                        .disabled(!guardModel.authorized || !familyMode)
                        .onChange(of: denyRemoval) { _, value in
                            Shared.defaults.set(value, forKey: Shared.removalKey)
                            Locking.applyProtection()
                        }
                } header: { Text("삭제 · 스크린 타임 권한 보호") } footer: {
                    Text("보호자 승인 모드는 가족 공유의 자녀 기기와 보호자 승인을 사용합니다. 개인 승인 모드에서는 사용자가 iOS 설정에서 고요의 스크린 타임 권한을 해제할 수 있습니다. 승인 모드를 바꾸려면 기존 권한을 해제한 뒤 다시 연결하세요.")
                }
                #else
                Section("삭제 · 스크린 타임 권한 보호") {
                    Toggle("가족 공유 · 보호자 승인 모드", isOn: $familyMode)
                        .onChange(of: familyMode) { _, value in Shared.defaults.set(value, forKey: Shared.familyModeKey) }
                    Button("스크린 타임 연결") {}.disabled(true)
                    Label("권한 연결 비활성", systemImage: "pause.circle")
                    Toggle("앱 삭제 제한 · 기기 전체", isOn: $denyRemoval)
                        .onChange(of: denyRemoval) { _, value in Shared.defaults.set(value, forKey: Shared.removalKey) }
                    Text("설정값만 보관합니다. 가족 승인, 앱 삭제 제한, 스크린 타임 권한 보호는 실행되지 않습니다.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                #endif
            }.navigationTitle("보호 설정")
                .sheet(isPresented: $setupPIN) { PasscodeSetup() }
                .alert("보호 설정", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                    Button("확인") { message = nil }
                } message: { Text(message ?? "") }
                #if !WEB_ONLY
                .onAppear { guardModel.refresh(); familyMode = Shared.defaults.bool(forKey: Shared.familyModeKey) }
                .alert("스크린 타임", isPresented: Binding(get: { guardModel.error != nil }, set: { if !$0 { guardModel.error = nil } })) {
                    Button("확인") { guardModel.error = nil }
                } message: { Text(guardModel.error ?? "") }
                #endif
        }
    }
    private func saveDomains() {
        Shared.defaults.set(extraDomains, forKey: "extraBlockedDomains")
        #if !WEB_ONLY
        Locking.applyProtection()
        #endif
    }
}
