import SwiftUI
import Security
import CryptoKit

enum PasscodeStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "goyo") + ".settings",
         kSecAttrAccount as String: "settings-pin"]
    }
    private static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static var hasPIN: Bool { read() != nil }
    private static func digest(_ pin: String, salt: String) -> String {
        var bytes = Data((salt + ":" + pin).utf8)
        for _ in 0..<10000 { bytes = Data(SHA256.hash(data: bytes)) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    static func verify(_ pin: String) -> Bool {
        guard let stored = read() else { return false }
        let fields = stored.split(separator: ":")
        guard fields.count == 2 else { return false }
        let actual = Array(digest(pin, salt: String(fields[0])).utf8)
        let expected = Array(fields[1].utf8)
        guard actual.count == expected.count else { return false }
        return zip(actual, expected).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
    static func save(_ pin: String) -> Bool {
        var random = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else { return false }
        let salt = Data(random).base64EncodedString()
        let value = Data((salt + ":" + digest(pin, salt: salt)).utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData as String] = value
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
    static func remove() -> Bool { SecItemDelete(query as CFDictionary) == errSecSuccess }
}

struct ProtectedSettings<Content: View>: View {
    @EnvironmentObject private var app: AppModel
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        if !PasscodeStore.hasPIN || app.settingsUnlocked { content }
        else { PasscodePrompt() }
    }
}

struct PasscodePrompt: View {
    @EnvironmentObject private var app: AppModel
    @State private var pin = ""
    @State private var error: String?
    private var blockedUntil: Double { Shared.defaults.double(forKey: "pinBlockedUntil") }
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "lock.shield").font(.system(size: 44))
            Text("설정이 잠겨 있습니다").font(.title2.bold())
            SecureField("6자리 이상 비밀번호", text: $pin).keyboardType(.numberPad)
                .textContentType(.password).textFieldStyle(.roundedBorder)
            if let error { Text(error).foregroundStyle(.red).font(.subheadline) }
            Button("설정 잠금 해제") {
                guard Date().timeIntervalSince1970 >= blockedUntil else { error = "30초 후 다시 입력해주세요."; return }
                if PasscodeStore.verify(pin) {
                    Shared.defaults.set(0, forKey: "pinFailures")
                    app.settingsUnlocked = true
                } else {
                    let failures = Shared.defaults.integer(forKey: "pinFailures") + 1
                    Shared.defaults.set(failures, forKey: "pinFailures")
                    if failures >= 5 {
                        Shared.defaults.set(Date().addingTimeInterval(30).timeIntervalSince1970, forKey: "pinBlockedUntil")
                        Shared.defaults.set(0, forKey: "pinFailures")
                    }
                    error = "비밀번호를 확인해주세요."; pin = ""
                }
            }.buttonStyle(.borderedProminent).disabled(pin.isEmpty)
        }.padding(28).navigationTitle("설정 보호")
    }
}

struct PasscodeSetup: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var confirm = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("설정 비밀번호") {
                    SecureField("6자리 이상 숫자", text: $pin).keyboardType(.numberPad)
                    SecureField("다시 입력", text: $confirm).keyboardType(.numberPad)
                    if let error { Text(error).foregroundStyle(.red) }
                }
                Button("저장하고 설정 잠그기") {
                    guard pin.count >= 6, pin.count <= 32, pin.allSatisfy(\.isNumber), pin == confirm else {
                        error = "같은 비밀번호를 6자리 이상 숫자로 입력해주세요."; return
                    }
                    guard PasscodeStore.save(pin) else { error = "비밀번호를 저장하지 못했습니다."; return }
                    app.settingsUnlocked = false
                    dismiss()
                }
            }.navigationTitle("비밀번호 설정")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
        }
    }
}
