import SwiftUI
import MessageUI
import ContactsUI

enum CommunicationTab: String, CaseIterable { case phone = "전화", contacts = "연락처", message = "문자" }
struct CommunicationView: View {
    @State private var tab: CommunicationTab
    @State private var number = ""
    @State private var text = ""
    @State private var showContacts = false
    @State private var showMessage = false
    @State private var error: String?
    init(initialTab: CommunicationTab = .phone) { _tab = State(initialValue: initialTab) }
    private var cleanNumber: String { number.filter { "0123456789+*#".contains($0) } }
    private var canCall: Bool { !cleanNumber.isEmpty && cleanNumber == number && cleanNumber.count <= 30 }
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Picker("연락 방법", selection: $tab) { ForEach(CommunicationTab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                HStack {
                    TextField("전화번호", text: $number).keyboardType(.phonePad).font(.system(size: 30, weight: .medium, design: .monospaced))
                    Button { if !number.isEmpty { number.removeLast() } } label: { Image(systemName: "delete.left") }.accessibilityLabel("한 자리 지우기")
                }.padding(16).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                if tab == .contacts {
                    Image(systemName: "person.crop.square.fill").font(.system(size: 70)).padding(20)
                    Button("연락처에서 전화번호 선택") { showContacts = true }.buttonStyle(.borderedProminent)
                    Text("선택한 번호만 고요에 전달됩니다.").font(.caption).foregroundStyle(.secondary)
                }
                if tab == .message {
                    TextEditor(text: $text).frame(minHeight: 140).padding(10).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    Button("문자 작성 창 열기") {
                        guard MFMessageComposeViewController.canSendText() else { error = "이 기기에서 문자 작성 기능을 사용할 수 없습니다."; return }
                        showMessage = true
                    }.buttonStyle(.borderedProminent).disabled(!canCall)
                    Text("받는 사람과 내용을 확인한 뒤 직접 전송해주세요.").font(.caption).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"], id: \.self) { key in
                            Button { if number.count < 30 { number += key } } label: {
                                Text(key).font(.system(size: 38, weight: .bold, design: .monospaced)).frame(maxWidth: .infinity).frame(height: 72)
                                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.3)))
                            }.buttonStyle(.plain)
                        }
                    }
                    Button { call() } label: { Label("전화 연결", systemImage: "phone.fill").frame(maxWidth: .infinity).padding(16) }
                        .buttonStyle(.borderedProminent).tint(.orange).disabled(!canCall)
                    Button("연락처에서 선택") { showContacts = true }
                }
            }.padding(18)
        }.background(Color(red: 0.04, green: 0.10, blue: 0.14)).foregroundStyle(.white)
            .navigationTitle("전화 · 문자").navigationBarTitleDisplayMode(.inline).preferredColorScheme(.dark)
            .sheet(isPresented: $showContacts) { ContactNumberPicker { value in number = value.filter { "0123456789+*#".contains($0) }; showContacts = false } }
            .sheet(isPresented: $showMessage) { MessageComposer(number: cleanNumber, bodyText: text) { showMessage = false } }
            .alert("전화 · 문자", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("확인") { error = nil } } message: { Text(error ?? "") }
    }
    private func call() {
        // The iPhone phone service doesn't support * and # in tel URLs.
        guard canCall, !cleanNumber.contains("*"), !cleanNumber.contains("#"), let url = URL(string: "tel:" + cleanNumber) else {
            error = "일반 전화번호를 입력해주세요. 특수 서비스 번호는 전화 앱에서 입력해주세요."; return
        }
        UIApplication.shared.open(url, options: [:]) { success in
            if !success { Task { @MainActor in error = "전화 연결을 열지 못했습니다. 아이폰의 전화 기능과 허용 앱 설정을 확인해주세요." } }
        }
    }
}

struct MessageComposer: UIViewControllerRepresentable {
    let number: String
    let bodyText: String
    let done: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = [number]; controller.body = bodyText
        return controller
    }
    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) { done() }
    }
}

struct ContactNumberPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let selected: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected, cancel: { dismiss() }) }
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let controller = CNContactPickerViewController(); controller.delegate = context.coordinator
        controller.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        controller.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        controller.predicateForSelectionOfContact = NSPredicate(value: false)
        controller.predicateForSelectionOfProperty = NSPredicate(format: "key == 'phoneNumbers'")
        return controller
    }
    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}
    final class Coordinator: NSObject, CNContactPickerDelegate {
        let selected: (String) -> Void
        let cancel: () -> Void
        init(selected: @escaping (String) -> Void, cancel: @escaping () -> Void) { self.selected = selected; self.cancel = cancel }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
            if let phone = contactProperty.value as? CNPhoneNumber { selected(phone.stringValue) }
        }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) { cancel() }
    }
}
