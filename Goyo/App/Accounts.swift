import SwiftUI
import Combine

struct AccountProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var service: String
    var legacyStore: Bool
}

@MainActor
final class AccountModel: ObservableObject {
    @Published var profiles: [AccountProfile] { didSet { save() } }
    @Published var active: [String: String] { didSet { save() } }
    init() {
        if let data = Shared.defaults.data(forKey: "profiles"),
           let value = try? JSONDecoder().decode([AccountProfile].self, from: data), !value.isEmpty {
            profiles = value
        } else {
            // The first profile continues using the old app's existing login data.
            profiles = [AccountProfile(id: UUID(), name: "계정 1", service: "youtube", legacyStore: true),
                        AccountProfile(id: UUID(), name: "계정 1", service: "instagram", legacyStore: true)]
        }
        active = Shared.defaults.dictionary(forKey: "activeProfiles") as? [String: String] ?? [:]
        for service in SocialService.allCases.map(\.rawValue) where !profiles.contains(where: { $0.service == service }) {
            profiles.append(AccountProfile(id: UUID(), name: "계정 1", service: service, legacyStore: true))
        }
        save()
    }
    func forService(_ service: SocialService) -> [AccountProfile] { profiles.filter { $0.service == service.rawValue } }
    func current(_ service: SocialService) -> AccountProfile {
        let options = forService(service)
        return options.first { $0.id.uuidString == active[service.rawValue] } ?? options[0]
    }
    func choose(_ profile: AccountProfile) { active[profile.service] = profile.id.uuidString }
    func add(_ service: SocialService) {
        let profile = AccountProfile(id: UUID(), name: "계정 \(forService(service).count + 1)", service: service.rawValue, legacyStore: false)
        profiles.append(profile)
        choose(profile)
    }
    private func save() {
        Shared.defaults.set(try? JSONEncoder().encode(profiles), forKey: "profiles")
        Shared.defaults.set(active, forKey: "activeProfiles")
    }
}

struct AccountsView: View {
    @EnvironmentObject private var accounts: AccountModel
    var body: some View {
        Form {
            ForEach(SocialService.allCases) { service in
                Section(service.title) {
                    ForEach(accounts.forService(service)) { profile in
                        HStack {
                            TextField("계정 이름", text: Binding(get: {
                                accounts.profiles.first { $0.id == profile.id }?.name ?? profile.name
                            }, set: { value in
                                if let i = accounts.profiles.firstIndex(where: { $0.id == profile.id }) { accounts.profiles[i].name = String(value.prefix(40)) }
                            }))
                            Button { accounts.choose(profile) } label: {
                                Image(systemName: accounts.current(service).id == profile.id ? "checkmark.circle.fill" : "circle")
                            }.accessibilityLabel("이 계정 사용")
                        }
                    }
                    Button("계정 추가") { accounts.add(service) }.disabled(accounts.forService(service).count >= 10)
                }
            }
            Section {
                Text("각 계정은 로그인 데이터를 따로 저장합니다. 홈에서 계정을 선택한 뒤 해당 서비스에 직접 로그인하세요. 각 서비스마다 최대 10개까지 저장할 수 있습니다.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.navigationTitle("다중 계정")
    }
}
