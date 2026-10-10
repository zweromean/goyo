import SwiftUI
import WebKit
import Combine

final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

@MainActor
final class BrowserSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    @Published var loading = true
    @Published var message: String?
    @Published var canGoBack = false
    private var configured = false
    private var filters: FilterSettings
    private var adVersion = 0
    private let service: SocialService
    private let profile: AccountProfile
    private let homeURL: URL
    private var recommendedPosts: [String: Set<String>] = [:]
    var onPost: ((String) -> Void)?
    var suspended = false {
        didSet { webView.evaluateJavaScript("window.GoyoFilter && window.GoyoFilter.setResting(\(suspended));", completionHandler: nil) }
    }

    init(service: SocialService, profile: AccountProfile, settings: FilterSettings, homeURL: URL? = nil) {
        self.service = service
        self.profile = profile
        self.filters = settings
        self.homeURL = homeURL ?? service.url
        let config = WKWebViewConfiguration()
        config.websiteDataStore = profile.legacyStore ? .default() : WKWebsiteDataStore(forIdentifier: profile.id)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(WKUserScript(source: Self.script(settings), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.configuration.userContentController.add(WeakMessageHandler(self), name: "goyo")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        configureAds(settings.ads) { [weak self] in
            guard let self else { return }
            self.configured = true
            self.home()
        }
    }

    func update(_ settings: FilterSettings) {
        guard configured, settings != filters else { return }
        let adChanged = filters.ads != settings.ads
        let dcChanged = filters.dcRecommendedOnly != settings.dcRecommendedOnly || filters.dcGalleryMode != settings.dcGalleryMode || filters.dcGalleryIDs != settings.dcGalleryIDs
        filters = settings
        // Future full navigations also receive the latest settings.
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: Self.script(settings), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView.evaluateJavaScript("window.GoyoFilter && window.GoyoFilter.update(\(settings.json));", completionHandler: nil)
        webView.evaluateJavaScript("window.GoyoDcFilter && window.GoyoDcFilter.update(\(settings.json));", completionHandler: nil)
        webView.evaluateJavaScript("window.GoyoInstallPrompts && window.GoyoInstallPrompts.update(\(settings.json));", completionHandler: nil)
        if dcChanged && service == .dcinside {
            recommendedPosts.removeAll()
            if let url = webView.url, let route = DcPolicy.parse(url), DcPolicy.allows(route.gallery, settings: settings) {
                webView.load(URLRequest(url: settings.dcRecommendedOnly ? DcPolicy.recommendedList(url) : url))
            } else { home() }
        }
        if adChanged { configureAds(settings.ads) { [weak self] in self?.webView.reload() } }
    }

    private static func script(_ settings: FilterSettings) -> String {
        let source = ["DcPolicy", "Filters", "DcFilters", "InstallPrompts"].compactMap { name -> String? in
            guard let url = Bundle.main.url(forResource: name, withExtension: "js") else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }.joined(separator: "\n")
        return "window.__goyoSettings=\(settings.json);\n\(source)"
    }
    func home() {
        if service == .dcinside {
            webView.loadHTMLString("""
                <!doctype html><html lang="ko"><meta name="viewport" content="width=device-width,initial-scale=1">
                <style>body{font:17px -apple-system,sans-serif;padding:32px 24px;color:#555;line-height:1.7}h2{color:#242424}p{font-size:14px}</style>
                <h2>필요한 갤러리만 열어보세요</h2><p>위에서 갤러리 ID나 주소를 입력해주세요.<br>설정한 갤러리는 ‘갤러리 목록’에서 선택할 수 있습니다.</p>
                <p>개념글 전용 모드에서는 개념글 목록에서 확인된 게시물만 열립니다.</p></html>
                """, baseURL: nil)
        } else { webView.load(URLRequest(url: homeURL)) }
    }
    func openGallery(_ input: String) {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let suppliedURL = URL(string: clean)
        let route = suppliedURL.flatMap(DcPolicy.parse)
        let id = route?.gallery ?? DcPolicy.galleryID(clean)
        guard let id else { message = "갤러리 ID 또는 주소를 확인해주세요."; return }
        let target = route == nil ? DcPolicy.listURL(id, recommended: filters.dcRecommendedOnly) : suppliedURL.flatMap { DcPolicy.listURL(from: $0, recommended: filters.dcRecommendedOnly) }
        guard let url = target else { return }
        guard DcPolicy.allows(id, settings: filters) else { message = "갤러리 제한이 적용되었습니다."; return }
        webView.load(URLRequest(url: url))
    }

    private func configureAds(_ enabled: Bool, completion: @escaping () -> Void) {
        adVersion += 1
        let version = adVersion
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        guard enabled else { completion(); return }
        guard let url = Bundle.main.url(forResource: "AdRules", withExtension: "json"),
              let rules = try? String(contentsOf: url, encoding: .utf8) else {
            message = "광고 필터 파일을 읽지 못했습니다."
            completion(); return
        }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "GoyoAds-v1", encodedContentRuleList: rules) { [weak self] list, error in
            Task { @MainActor in
                guard let self, version == self.adVersion else { return }
                if let list { controller.add(list) }
                if error != nil { self.message = "광고 필터를 준비하지 못했습니다. 새로고침해주세요." }
                completion()
            }
        }
    }

    func search(_ query: String) {
        guard service == .youtube, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var components = URLComponents(string: "https://m.youtube.com/results")!
        components.queryItems = [URLQueryItem(name: "search_query", value: query)]
        if let url = components.url { webView.load(URLRequest(url: url)) }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { loading = true; message = nil }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false; canGoBack = webView.canGoBack
        webView.evaluateJavaScript("window.GoyoFilter && window.GoyoFilter.setResting(\(suspended));", completionHandler: nil)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let frameURL = message.frameInfo.request.url,
              let payload = message.body as? [String: Any] else { return }
        if service == .dcinside, payload["kind"] as? String == "dcRecommended" {
            guard let route = DcPolicy.parse(frameURL), route.post == nil, route.recommended,
                  filters.dcRecommendedOnly, DcPolicy.allows(route.gallery, settings: filters),
                  payload["gallery"] as? String == route.gallery, let ids = payload["ids"] as? [String] else { return }
            let valid = ids.prefix(500).filter { $0.range(of: "^[0-9]{1,20}$", options: .regularExpression) != nil }
            if recommendedPosts.count >= 20 && recommendedPosts[route.gallery] == nil { recommendedPosts.removeAll() }
            recommendedPosts[route.gallery] = Set(valid)
            return
        }
        let host = frameURL.host ?? ""
        guard
              host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "instagram.com" || host.hasSuffix(".instagram.com"),
              payload["kind"] as? String == "post",
              let id = payload["id"] as? String, !id.isEmpty, id.count <= 512, !suspended else { return }
        onPost?(id)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    private func fail(_ error: Error) {
        loading = false
        if (error as NSError).code != NSURLErrorCancelled { message = "페이지를 불러오지 못했습니다. 인터넷 연결을 확인하고 새로고침해주세요." }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        // Keep login and browsing in this WebView; don't escape filters into native SNS apps.
        guard ["https", "http", "about", "blob"].contains(url.scheme ?? "") else {
            message = "기존 앱 대신 고요 안에서 계속 이용해주세요."
            decisionHandler(.cancel); return
        }
        let host = url.host ?? ""
        if filters.hideInstallPrompts && (host == "apps.apple.com" || host == "itunes.apple.com" || host == "play.google.com") {
            decisionHandler(.cancel); return
        }
        if service == .dcinside, action.targetFrame?.isMainFrame == false, let route = DcPolicy.parse(url) {
            let allowed = DcPolicy.allows(route.gallery, settings: filters) &&
                (!filters.dcRecommendedOnly || (route.post == nil ? route.recommended : recommendedPosts[route.gallery]?.contains(route.post!) == true))
            if !allowed { decisionHandler(.cancel); return }
        }
        if service == .dcinside && (action.targetFrame?.isMainFrame ?? true) && url.scheme != "about" {
            if host == "sign.dcinside.com" { decisionHandler(.allow); return }
            guard let route = DcPolicy.parse(url) else {
                message = "갤러리 목록과 게시물만 열 수 있습니다. 위에서 갤러리 ID를 입력해주세요."
                decisionHandler(.cancel); return
            }
            guard DcPolicy.allows(route.gallery, settings: filters) else {
                message = "갤러리 제한이 적용되었습니다."; decisionHandler(.cancel); return
            }
            if filters.dcRecommendedOnly {
                if route.post == nil && !route.recommended {
                    decisionHandler(.cancel)
                    webView.load(URLRequest(url: DcPolicy.recommendedList(url))); return
                }
                if let post = route.post, recommendedPosts[route.gallery]?.contains(post) != true {
                    message = "개념글 목록에서 확인된 게시물만 열 수 있습니다."
                    decisionHandler(.cancel); return
                }
            }
        }
        if filters.blockAdult && AdultSites.isBlocked(host) {
            message = "성인 사이트 차단이 적용되었습니다."
            decisionHandler(.cancel); return
        }
        let isYouTube = host == "youtube.com" || host.hasSuffix(".youtube.com")
        let isInstagram = host == "instagram.com" || host.hasSuffix(".instagram.com")
        let blocked = (isYouTube && filters.shorts && url.path.hasPrefix("/shorts")) ||
            (isInstagram && filters.reels && (url.path == "/reel" || url.path.hasPrefix("/reel/") || url.path == "/reels" || url.path.hasPrefix("/reels/"))) ||
            (isInstagram && filters.instagramFeed && url.path.hasPrefix("/explore"))
            || (isInstagram && filters.stories && url.path.hasPrefix("/stories/"))
        if blocked { message = "차단 설정이 적용된 화면입니다." }
        decisionHandler(blocked ? .cancel : .allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil { webView.load(action.request) }
        return nil
    }
}

struct WebSurface: UIViewRepresentable {
    let session: BrowserSession
    func makeUIView(context: Context) -> WKWebView { session.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct BrowserScreen: View {
    let service: SocialService
    let profile: AccountProfile
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var accounts: AccountModel
    @EnvironmentObject private var breaks: BreakModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: BrowserSession
    @State private var query = ""
    @State private var showFilters = false
    init(service: SocialService, profile: AccountProfile, homeURL: URL? = nil) {
        self.service = service
        self.profile = profile
        _session = StateObject(wrappedValue: BrowserSession(service: service, profile: profile, settings: Shared.settings, homeURL: homeURL))
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if service == .youtube {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("보고 싶은 영상 검색", text: $query).submitLabel(.search)
                            .onSubmit { session.search(query) }
                        Button("검색") { session.search(query) }.disabled(query.isEmpty)
                    }.padding(12).background(Color(.secondarySystemBackground))
                }
                if service == .dcinside {
                    VStack(spacing: 8) {
                        HStack {
                            TextField("갤러리 ID 또는 주소", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .submitLabel(.go).onSubmit { session.openGallery(query) }
                            Button("열기") { session.openGallery(query) }.disabled(query.isEmpty)
                        }
                        HStack {
                            Text(model.settings.dcRecommendedOnly ? "개념글 전용" : "전체글").font(.caption)
                            Spacer()
                            Menu("갤러리 목록") {
                                ForEach(model.settings.dcGalleryIDs, id: \.self) { id in
                                    Button(id) { query = id; session.openGallery(id) }
                                        .disabled(!DcPolicy.allows(id, settings: model.settings))
                                }
                                Button("갤러리 제한 설정") { showFilters = true }
                            }.font(.caption)
                        }
                    }.padding(12).background(Color(.secondarySystemBackground))
                }
                if session.loading { ProgressView().frame(maxWidth: .infinity).padding(4) }
                if let message = session.message {
                    HStack {
                        Text(message).font(.subheadline)
                        Spacer()
                        Button("닫기") { session.message = nil }
                    }.padding(12).background(Color(.secondarySystemBackground))
                }
                WebSurface(session: session).saturation(model.settings.grayscale ? 0 : 1)
                HStack {
                    Button { session.webView.goBack() } label: { Image(systemName: "chevron.left") }
                        .disabled(!session.canGoBack)
                    Spacer()
                    Button("처음 화면") { session.home() }
                    Spacer()
                    Button { session.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                }.padding(16).background(.bar)
            }
            .navigationTitle(service.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("완료") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(accounts.forService(service)) { account in
                            Button(account.name) { accounts.choose(account) }
                        }
                        Button("필터 설정") { showFilters = true }
                    } label: { Label(profile.name, systemImage: "person.crop.circle") }
                }
            }
            .sheet(isPresented: $showFilters) {
                NavigationStack { FiltersView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { showFilters = false } } } }
            }
            .onChange(of: model.settings) { _, value in session.update(value) }
            .onAppear {
                session.onPost = { id in breaks.record(id: id, account: profile.id, service: service.rawValue, settings: model.settings) }
                session.suspended = breaks.resting
            }
            .onChange(of: breaks.resting) { _, value in session.suspended = value }
            .fullScreenCover(isPresented: Binding(get: { breaks.resting }, set: { _ in })) { RestView() }
            .alert("시청 알림", isPresented: Binding(get: { breaks.notice != nil && !breaks.resting }, set: { if !$0 { breaks.notice = nil } })) {
                Button("확인") { breaks.notice = nil }
            } message: { Text(breaks.notice ?? "") }
        }
    }
}

struct BrowserCover: View {
    let service: SocialService
    @EnvironmentObject private var accounts: AccountModel
    var body: some View {
        let account = accounts.current(service)
        BrowserScreen(service: service, profile: account).id(account.id)
    }
}
