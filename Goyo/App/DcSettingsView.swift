import SwiftUI

struct DcSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var gallery = ""
    @State private var error: String?
    var body: some View {
        ProtectedSettings {
            Form {
                Section {
                    Toggle("개념글만 보기", isOn: $model.settings.dcRecommendedOnly)
                } footer: {
                    Text("개념글 목록에서 확인된 글만 엽니다. 일반글 링크와 개념글로 확인되지 않은 직접 주소는 차단합니다.")
                }
                Section("갤러리 제한") {
                    Picker("제한 방식", selection: $model.settings.dcGalleryMode) {
                        Text("제한 없음").tag("none")
                        Text("목록에 있는 갤러리만 허용").tag("allow")
                        Text("목록에 있는 갤러리 차단").tag("block")
                    }
                    ForEach(model.settings.dcGalleryIDs, id: \.self) { id in Text(id) }
                        .onDelete { model.settings.dcGalleryIDs.remove(atOffsets: $0) }
                    HStack {
                        TextField("갤러리 ID 또는 주소", text: $gallery).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("추가", action: add)
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.caption) }
                }
                Section {
                    Text("주소의 /board/ 다음에 오는 ID를 입력하세요. 주소 전체를 붙여넣어도 됩니다. 허용 방식에서 목록이 비어 있으면 모든 갤러리가 잠깁니다.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }.navigationTitle("디시인사이드 설정")
        }
    }
    private func add() {
        let input = gallery.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = URL(string: input).flatMap(DcPolicy.parse)?.gallery ?? DcPolicy.galleryID(input)
        guard let id else { error = "갤러리 ID 또는 갤러리 주소를 확인해주세요."; return }
        guard model.settings.dcGalleryIDs.count < 100 else { error = "갤러리는 최대 100개까지 설정할 수 있습니다."; return }
        if !model.settings.dcGalleryIDs.contains(id) { model.settings.dcGalleryIDs.append(id) }
        gallery = ""; error = nil
    }
}
