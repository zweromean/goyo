import SwiftUI
import Combine
import PhotosUI
import UIKit

struct LauncherEntry: Identifiable, Codable {
    var id = UUID()
    var title: String
    var address: String
    var symbol = "app.fill"
    var photo: Data?
    var isWebsite: Bool
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published private(set) var entries: [LauncherEntry]
    init() {
        entries = Shared.defaults.data(forKey: "launcherEntries").flatMap { try? JSONDecoder().decode([LauncherEntry].self, from: $0) } ?? []
    }
    static func validURL(_ text: String, website: Bool) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = url.scheme?.lowercased() else { return nil }
        if website { return scheme == "https" && url.host != nil ? url : nil }
        guard scheme.range(of: "^[a-z][a-z0-9+.-]*$", options: .regularExpression) != nil,
              !["http", "https", "javascript", "data", "file", "itms", "itms-apps", "itms-services", "prefs", "app-prefs"].contains(scheme) else { return nil }
        return url
    }
    func save(_ entry: LauncherEntry) -> Bool {
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 40, Self.validURL(entry.address, website: entry.isWebsite) != nil else { return false }
        var item = entry; item.title = title
        if let i = entries.firstIndex(where: { $0.id == item.id }) { entries[i] = item }
        else { guard entries.count < 30 else { return false }; entries.append(item) }
        persist(); return true
    }
    func remove(_ id: UUID) { entries.removeAll { $0.id == id }; persist() }
    private func persist() { Shared.defaults.set(try? JSONEncoder().encode(entries), forKey: "launcherEntries") }
}

struct LauncherIcon: View {
    let entry: LauncherEntry
    var body: some View {
        Group {
            if let data = entry.photo, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else { Image(systemName: entry.symbol).font(.system(size: 27)) }
        }.frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct LauncherEditor: View {
    @EnvironmentObject private var launcher: LauncherModel
    @Environment(\.dismiss) private var dismiss
    @State private var entry: LauncherEntry
    @State private var photo: PhotosPickerItem?
    @State private var error: String?
    init(entry: LauncherEntry = LauncherEntry(title: "", address: "https://", isWebsite: true)) { _entry = State(initialValue: entry) }
    var body: some View {
        NavigationStack {
            Form {
                Section("허용 메뉴") {
                    TextField("표시 이름", text: $entry.title)
                    Toggle("고요 안에서 웹사이트 열기", isOn: $entry.isWebsite)
                    TextField(entry.isWebsite ? "https://example.com" : "앱의 URL 스킴", text: $entry.address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Text(entry.isWebsite ? "웹사이트는 고요 브라우저에서 열립니다." : "앱이 공개한 URL 스킴으로 설치 앱을 실행합니다. 예: maps://, music://. 스크린 타임의 허용 앱에도 추가해주세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("메뉴 아이콘") {
                    HStack { LauncherIcon(entry: entry); Text(entry.title.isEmpty ? "미리보기" : entry.title) }
                    Picker("기호", selection: $entry.symbol) {
                        ForEach(["app.fill", "book.fill", "globe", "map.fill", "music.note", "pencil", "graduationcap.fill", "star.fill"], id: \.self) { symbol in
                            Image(systemName: symbol).tag(symbol)
                        }
                    }
                    PhotosPicker("사진으로 아이콘 지정", selection: $photo, matching: .images)
                    if entry.photo != nil { Button("사진 제거") { entry.photo = nil; photo = nil } }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("허용 메뉴 편집").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") { if launcher.save(entry) { dismiss() } else { error = "이름과 주소를 확인해주세요. 웹사이트는 https:// 주소를 사용하며 메뉴는 30개까지 저장할 수 있습니다." } }
                    }
                }
                .onChange(of: photo) { _, item in
                    Task {
                        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160))
                        entry.photo = renderer.jpegData(withCompressionQuality: 0.85) { _ in image.draw(in: CGRect(x: 0, y: 0, width: 160, height: 160)) }
                    }
                }
        }
    }
}

struct AppIconSettings: View {
    @State private var selected = UIApplication.shared.alternateIconName ?? "AppIcon"
    @State private var error: String?
    private let icons: [(String, String)] = [("AppIcon", "고요"), ("IconGreen", "초록"), ("IconNight", "밤"), ("IconPaper", "종이")]
    var body: some View {
        Form {
            Section("홈 화면 앱 아이콘") {
                ForEach(icons, id: \.0) { name, title in
                    Button {
                        guard UIApplication.shared.supportsAlternateIcons else { error = "이 기기에서 아이콘 변경을 사용할 수 없습니다."; return }
                        UIApplication.shared.setAlternateIconName(name == "AppIcon" ? nil : name) { failure in
                            Task { @MainActor in
                                if let failure { error = failure.localizedDescription }
                                else { selected = name }
                            }
                        }
                    } label: {
                        HStack {
                            Image("Preview" + name).resizable().frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 10))
                            Text(title); Spacer()
                            if selected == name { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            Section {
                Text("고요의 홈 화면 아이콘은 위 디자인 중에서 고릅니다. 고요 안의 허용 메뉴 아이콘은 사진과 기호로 직접 꾸밀 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("아이콘 꾸미기")
            .alert("아이콘 변경", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("확인") { error = nil }
            } message: { Text(error ?? "") }
    }
}

enum HomePanel: String, Identifiable {
    case phone, contacts, messages, notes, calendar, tools, settings, apps
    var id: String { rawValue }
}

struct RetroHomeView: View {
    let openService: (SocialService) -> Void
    let openStudy: () -> Void
    let openGuard: () -> Void
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var accounts: AccountModel
    @EnvironmentObject private var study: StudyModel
    @EnvironmentObject private var breaks: BreakModel
    @EnvironmentObject private var launcher: LauncherModel
    @State private var panel: HomePanel?
    @State private var editing: LauncherEntry?
    @State private var website: LauncherEntry?
    @State private var error: String?
    private let ink = Color(red: 0.04, green: 0.10, blue: 0.14)
    private let amber = Color(red: 1, green: 0.68, blue: 0.15)
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(context.date.formatted(.dateTime.hour().minute())).font(.system(size: 45, weight: .bold, design: .monospaced)).minimumScaleFactor(0.5).lineLimit(1)
                            Text(context.date.formatted(.dateTime.month().day().weekday(.wide))).font(.headline)
                        }
                        Spacer(); Image(systemName: "moon.stars.fill").font(.system(size: 40))
                    }.padding(.vertical, 18)
                    Button(action: openStudy) {
                        HStack { Text(study.inSession ? "집중을 이어가세요" : "소셜 끄고 · 공부 시작"); Spacer(); Image(systemName: "chevron.right") }
                            .font(.headline).padding(18).background(ink).overlay(Rectangle().stroke(.white.opacity(0.3)))
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        tile("전화", "phone.fill", accent: true) { panel = .phone }
                        tile("연락처", "person.crop.square.fill") { panel = .contacts }
                        tile("문자", "envelope.fill") { panel = .messages }
                        tile("집중 모드", "lock.fill", action: openGuard)
                        tile("메모", "note.text") { panel = .notes }
                        tile("달력", "calendar") { panel = .calendar }
                        tile("공부 도구", "waveform") { panel = .tools }
                        tile("허용 메뉴", "square.grid.2x2") { panel = .apps }
                        tile("설정", "gearshape.fill") { panel = .settings }
                    }
                    HStack {
                        Button("메뉴") { panel = .apps }; Spacer()
                        Button { panel = .phone } label: { Label("전화", systemImage: "phone.fill") }.foregroundStyle(amber)
                        Spacer(); Button { panel = .messages } label: { Label("문자", systemImage: "envelope.fill") }
                    }.font(.headline).padding(16).overlay(Rectangle().stroke(.white.opacity(0.3)))
                    Text("필요한 앱만").font(.headline).padding(.top, 8)
                    if study.isBlockingSNS { Label("공부 중 · SNS 잠금", systemImage: "lock.fill").font(.caption).foregroundStyle(amber) }
                    ForEach(SocialService.socialCases) { service in
                        HStack {
                            Button { openService(service) } label: { Label(service.title, systemImage: service.symbol).frame(maxWidth: .infinity, alignment: .leading) }
                                .disabled(study.isBlockingSNS || breaks.resting)
                            Menu(accounts.current(service).name) {
                                ForEach(accounts.forService(service)) { profile in Button(profile.name) { accounts.choose(profile) } }
                            }.font(.caption)
                        }.padding(16).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
                    ForEach(launcher.entries) { entry in
                        Button { open(entry) } label: {
                            HStack { LauncherIcon(entry: entry); Text(entry.title); Spacer(); Image(systemName: entry.isWebsite ? "globe" : "arrow.up.forward") }
                                .padding(12).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        }.contextMenu { Button("편집") { editing = entry }; Button("삭제", role: .destructive) { launcher.remove(entry.id) } }
                    }
                }.padding(18)
            }.background(ink).foregroundStyle(Color(red: 0.95, green: 0.93, blue: 0.89)).buttonStyle(.plain)
        }.toolbar(.hidden, for: .navigationBar).preferredColorScheme(.dark)
            .sheet(item: $panel) { value in
                NavigationStack {
                    Group {
                        switch value {
                        case .phone: CommunicationView(initialTab: .phone)
                        case .contacts: CommunicationView(initialTab: .contacts)
                        case .messages: CommunicationView(initialTab: .message)
                        case .notes: NotesView()
                        case .calendar: StudyCalendarView().navigationTitle("달력")
                        case .tools: StudyToolsView()
                        case .settings:
                            Form {
                                NavigationLink("아이콘 꾸미기") { AppIconSettings() }
                                NavigationLink("허용 메뉴 편집") { LauncherListView() }
                                NavigationLink("다중 계정") { AccountsView() }
                                NavigationLink("차단 필터") { FiltersView() }
                                NavigationLink("보호 설정") { ProtectionView() }
                            }.navigationTitle("설정")
                        case .apps: LauncherListView()
                        }
                    }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { panel = nil } } }
                }
            }
            .sheet(item: $editing) { entry in ProtectedSettings { LauncherEditor(entry: entry) } }
            .fullScreenCover(item: $website) { entry in
                BrowserScreen(service: .web, profile: accounts.current(.web), homeURL: LauncherModel.validURL(entry.address, website: true))
            }
            .alert("앱 열기", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("확인") { error = nil } } message: { Text(error ?? "") }
    }
    private func tile(_ title: String, _ symbol: String, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) { Image(systemName: symbol).font(.system(size: 29)); Text(title).font(.system(size: 13, weight: .semibold)) }
                .frame(maxWidth: .infinity).frame(height: 96).background(ink)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(accent ? amber : .white.opacity(0.4), lineWidth: accent ? 2 : 1))
                .foregroundStyle(accent ? amber : Color(red: 0.95, green: 0.93, blue: 0.89))
        }.accessibilityLabel(title)
    }
    private func open(_ entry: LauncherEntry) {
        guard let url = LauncherModel.validURL(entry.address, website: entry.isWebsite) else { return }
        if entry.isWebsite { website = entry }
        else { UIApplication.shared.open(url, options: [:]) { success in if !success { Task { @MainActor in error = "설치 앱과 URL 스킴을 확인해주세요." } } } }
    }
}

struct LauncherListView: View {
    @EnvironmentObject private var launcher: LauncherModel
    @State private var editing: LauncherEntry?
    var body: some View {
        ProtectedSettings {
            List {
                Section {
                    Button("허용 메뉴 추가") { editing = LauncherEntry(title: "", address: "https://", isWebsite: true) }
                    Text("웹사이트는 앱 안에서, 설치 앱은 실행 연결로 엽니다. 설치 앱의 스크린 타임 허용 여부는 앱 잠금 탭에서 설정해주세요.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(launcher.entries) { entry in
                    Button { editing = entry } label: { HStack { LauncherIcon(entry: entry); VStack(alignment: .leading) { Text(entry.title); Text(entry.address).font(.caption).foregroundStyle(.secondary) } } }
                        .swipeActions { Button("삭제", role: .destructive) { launcher.remove(entry.id) } }
                }
            }.navigationTitle("허용 메뉴").sheet(item: $editing) { LauncherEditor(entry: $0) }
        }
    }
}
