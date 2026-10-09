import Foundation

enum AdultSites {
    static var domains: Set<String> {
        let builtIn: Set<String> = ["pornhub.com", "xvideos.com", "xnxx.com", "xhamster.com", "redtube.com", "youporn.com", "spankbang.com", "chaturbate.com", "stripchat.com", "nhentai.net"]
        let custom = Shared.defaults.stringArray(forKey: "extraBlockedDomains") ?? []
        return builtIn.union(custom.compactMap(normalize))
    }
    static func normalize(_ input: String) -> String? {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidate = clean.contains("://") ? clean : "https://" + clean
        guard let host = URLComponents(string: candidate)?.host, host.contains("."), !host.contains(" ") else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
    static func isBlocked(_ hostname: String) -> Bool {
        let host = hostname.lowercased()
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
