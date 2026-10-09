import Foundation

enum DcPolicy {
    struct Route {
        let gallery: String
        let post: String?
        let recommended: Bool
    }
    static func galleryID(_ value: String) -> String? {
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return id.range(of: "^[a-z0-9_]{1,80}$", options: .regularExpression) != nil ? id : nil
    }
    static func parse(_ url: URL) -> Route? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["https", "http"].contains(c.scheme ?? "") else { return nil }
        let path = c.path.split(separator: "/").map(String.init)
        let query = c.queryItems ?? []
        func value(_ key: String) -> String? { query.first { $0.name == key }?.value }
        if c.host == "m.dcinside.com", path.count == 2 || path.count == 3,
           ["board", "mini"].contains(path[0]), let gallery = galleryID(path[1]) {
            let post = path.count == 3 ? path[2] : nil
            if let post, post.range(of: "^[0-9]+$", options: .regularExpression) == nil { return nil }
            return Route(gallery: gallery, post: post, recommended: value("recommend") == "1")
        }
        if c.host == "gall.dcinside.com", let gallery = value("id").flatMap(galleryID),
           let marker = path.firstIndex(of: "board"), marker == path.count - 2,
           marker == 0 || (marker == 1 && ["mgallery", "mini"].contains(path[0])) {
            let action = path[marker + 1]
            guard ["list", "lists", "view"].contains(action) else { return nil }
            let post = action == "view" ? value("no") : nil
            if action == "view", post == nil { return nil }
            if let post, post.range(of: "^[0-9]+$", options: .regularExpression) == nil { return nil }
            return Route(gallery: gallery, post: post, recommended: value("exception_mode") == "recommend")
        }
        return nil
    }
    static func allows(_ gallery: String, settings: FilterSettings) -> Bool {
        let ids = Set(settings.dcGalleryIDs.compactMap(galleryID))
        switch settings.dcGalleryMode {
        case "allow": return ids.contains(gallery)
        case "block": return !ids.contains(gallery)
        default: return true
        }
    }
    static func recommendedList(_ url: URL) -> URL {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let mobile = c.host == "m.dcinside.com"
        let key = mobile ? "recommend" : "exception_mode"
        var items = (c.queryItems ?? []).filter { ![key, "no"].contains($0.name) }
        items.append(URLQueryItem(name: key, value: mobile ? "1" : "recommend"))
        if let route = parse(url), route.post != nil {
            if mobile { c.path = "/\(c.path.hasPrefix("/mini/") ? "mini" : "board")/\(route.gallery)" }
            else { c.path = c.path.replacingOccurrences(of: "/view", with: "/lists") }
        }
        c.queryItems = items
        return c.url ?? url
    }
    static func listURL(_ id: String, recommended: Bool) -> URL? {
        guard let gallery = galleryID(id) else { return nil }
        return URL(string: "https://m.dcinside.com/board/\(gallery)\(recommended ? "?recommend=1" : "")")
    }
    static func listURL(from url: URL, recommended: Bool) -> URL? {
        guard parse(url) != nil else { return nil }
        let list = recommendedList(url)
        guard !recommended, var c = URLComponents(url: list, resolvingAgainstBaseURL: false) else { return list }
        c.queryItems = (c.queryItems ?? []).filter { !["recommend", "exception_mode"].contains($0.name) }
        return c.url
    }
}
