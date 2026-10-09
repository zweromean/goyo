import SwiftUI

enum SocialService: String, Identifiable, CaseIterable {
    case youtube, instagram, dcinside
    var id: String { rawValue }
    var title: String {
        switch self { case .youtube: return "YouTube"; case .instagram: return "Instagram"; case .dcinside: return "디시인사이드" }
    }
    var symbol: String {
        switch self { case .youtube: return "play.rectangle.fill"; case .instagram: return "camera.fill"; case .dcinside: return "text.bubble.fill" }
    }
    var subtitle: String {
        switch self { case .youtube: return "검색과 영상 시청"; case .instagram: return "메시지와 프로필"; case .dcinside: return "갤러리 제한 · 개념글 전용" }
    }
    var url: URL {
        switch self {
        case .youtube: return URL(string: "https://m.youtube.com")!
        case .instagram: return URL(string: "https://www.instagram.com/direct/inbox/")!
        case .dcinside: return URL(string: "about:blank")!
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var accounts: AccountModel
    @EnvironmentObject private var breaks: BreakModel
    @EnvironmentObject private var study: StudyModel
    @Environment(\.scenePhase) private var phase
    @State private var pending: SocialService?
    @State private var opened: SocialService?
    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "moon.circle.fill").font(.system(size: 44)).foregroundStyle(.mint)
                            Text("필요한 것만,\n조용하게.").font(.system(size: 32, weight: .bold))
                            Text("검색과 연락은 남기고, 끝없는 스크롤은 끄세요.")
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(28)
                        .background(Color(red: 0.04, green: 0.1, blue: 0.18), in: RoundedRectangle(cornerRadius: 28))
                        .foregroundStyle(.white)

                        Text("SNS 열기").font(.title2.bold())
                        if study.isBlockingSNS {
                            Label("공부 중입니다. SNS가 잠겨 있습니다.", systemImage: "book.closed")
                        }
                        ForEach(SocialService.allCases) { service in
                            Menu {
                                ForEach(accounts.forService(service)) { profile in Button(profile.name) { accounts.choose(profile) } }
                            } label: {
                                Label("\(service.title) · \(accounts.current(service).name)", systemImage: "person.crop.circle")
                            }
                            Button { pending = service } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: service.symbol).font(.title).frame(width: 48)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(service.title).font(.title3.bold())
                                        Text(service.subtitle)
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(model.settings.waitSeconds == 0 ? "열기" : "\(model.settings.waitSeconds)초 대기")
                                        .font(.subheadline.weight(.semibold))
                                }.padding(20).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                            }.buttonStyle(.plain).disabled(study.isBlockingSNS || breaks.resting)
                        }
                        NavigationLink("계정 관리") { AccountsView() }
                        Label("차단 설정은 전용 브라우저에 적용됩니다.", systemImage: "slider.horizontal.3")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(20)
                }.background(Color(.systemGroupedBackground)).navigationTitle("고요")
            }.tabItem { Label("홈", systemImage: "house") }
            NavigationStack { FiltersView() }.tabItem { Label("필터", systemImage: "line.3.horizontal.decrease.circle") }
            NavigationStack { GuardView() }.tabItem { Label("앱 잠금", systemImage: "lock.shield") }
            NavigationStack { StudyView() }.tabItem { Label("공부", systemImage: "book") }
            NavigationStack { ProtectionView() }.tabItem { Label("보호", systemImage: "shield") }
        }
        .sheet(item: $pending) { service in
            WaitView(title: service.title, seconds: model.settings.waitSeconds) {
                pending = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if !study.isBlockingSNS && !breaks.resting { opened = service }
                }
            }
        }
        .fullScreenCover(item: $opened) { service in BrowserCover(service: service) }
        .fullScreenCover(isPresented: Binding(get: { breaks.resting && opened == nil && pending == nil }, set: { _ in })) { RestView() }
        .onChange(of: phase) { _, value in if value == .background { model.settingsUnlocked = false } }
        .saturation(model.settings.grayscale ? 0 : 1)
    }
}

struct FiltersView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ProtectedSettings {
        Form {
            Section("짧은 영상") {
                Toggle("유튜브 쇼츠 차단", isOn: $model.settings.shorts)
                Toggle("인스타그램 릴스 차단", isOn: $model.settings.reels)
            }
            Section("추천과 피드") {
                Toggle("유튜브 추천 영상 숨기기", isOn: $model.settings.recommendations)
                Toggle("유튜브 홈 피드 숨기기", isOn: $model.settings.youtubeFeed)
                Toggle("인스타그램 홈·탐색 피드 숨기기", isOn: $model.settings.instagramFeed)
                Toggle("인스타그램 추천 게시물 숨기기", isOn: $model.settings.instagramRecommendations)
                Toggle("인스타그램 스토리 숨기기", isOn: $model.settings.stories)
            }
            Section("디시인사이드") {
                NavigationLink("개념글 · 갤러리 제한") { DcSettingsView() }
            }
            Section {
                Toggle("그레이스케일", isOn: $model.settings.grayscale)
            } header: { Text("화면") } footer: { Text("고요의 화면을 흑백으로 표시합니다. 아이폰 전체의 색상 설정은 바꾸지 않습니다.") }
            Section {
                Toggle("게시물 수 알림", isOn: $model.settings.postAlarm)
                Stepper("게시물 \(model.settings.postLimit)개마다", value: $model.settings.postLimit, in: 1...100)
                Toggle("휴식 화면 띄우기", isOn: $model.settings.restScreen)
                Stepper("휴식 \(model.settings.restSeconds)초", value: $model.settings.restSeconds, in: 5...1800, step: 5)
            } header: { Text("시청 알림 · 휴식") } footer: {
                Text("화면에 절반 이상 1초 동안 표시된 인스타그램 게시물과 2초 이상 재생된 유튜브 영상을 셉니다. 같은 게시물은 다시 세지 않습니다. 실제 웹 화면에서 식별 가능한 게시물만 집계합니다.")
            }
            Section {
                Toggle("웹 광고 필터", isOn: $model.settings.ads)
            } header: { Text("광고") } footer: {
                Text("알려진 광고 서버와 웹 화면의 광고 영역을 차단합니다. 영상 자체에 포함된 광고는 남을 수 있습니다.")
            }
            Section {
                Stepper("열기 전 대기: \(model.settings.waitSeconds)초", value: $model.settings.waitSeconds, in: 0...120, step: 5)
                Button("30초로 설정") { model.settings.waitSeconds = 30 }
            } header: { Text("잠깐 멈추기") } footer: {
                Text("대기하는 동안 고요가 화면에 열려 있어야 합니다. 다른 앱으로 이동하면 남은 시간이 멈춥니다.")
            }
            Section("적용 범위") {
                Text("영상·피드 필터는 고요 안에서 연 유튜브·인스타그램에 적용됩니다. 기존 앱은 ‘앱 잠금’에서 전체 접근을 관리합니다.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.navigationTitle("차단 필터")
        }
    }
}
