import Foundation

struct FilterSettings: Codable, Equatable {
    var shorts = true
    var reels = true
    var ads = true
    var recommendations = true
    var youtubeFeed = true
    var instagramFeed = true
    var waitSeconds = 30
    var stories = false
    var instagramRecommendations = true
    var grayscale = false
    var postAlarm = true
    var postLimit = 10
    var restScreen = true
    var restSeconds = 60
    var blockAdult = false
    var dcRecommendedOnly = true
    var dcGalleryMode = "none"
    var dcGalleryIDs: [String] = []
    var hideInstallPrompts = true

    init() {}
    enum CodingKeys: String, CodingKey {
        case shorts, reels, ads, recommendations, youtubeFeed, instagramFeed, waitSeconds
        case stories, instagramRecommendations, grayscale, postAlarm, postLimit, restScreen, restSeconds, blockAdult
        case dcRecommendedOnly, dcGalleryMode, dcGalleryIDs
        case hideInstallPrompts
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shorts = try c.decodeIfPresent(Bool.self, forKey: .shorts) ?? true
        reels = try c.decodeIfPresent(Bool.self, forKey: .reels) ?? true
        ads = try c.decodeIfPresent(Bool.self, forKey: .ads) ?? true
        recommendations = try c.decodeIfPresent(Bool.self, forKey: .recommendations) ?? true
        youtubeFeed = try c.decodeIfPresent(Bool.self, forKey: .youtubeFeed) ?? true
        instagramFeed = try c.decodeIfPresent(Bool.self, forKey: .instagramFeed) ?? true
        waitSeconds = min(120, max(0, try c.decodeIfPresent(Int.self, forKey: .waitSeconds) ?? 30))
        stories = try c.decodeIfPresent(Bool.self, forKey: .stories) ?? false
        instagramRecommendations = try c.decodeIfPresent(Bool.self, forKey: .instagramRecommendations) ?? true
        grayscale = try c.decodeIfPresent(Bool.self, forKey: .grayscale) ?? false
        postAlarm = try c.decodeIfPresent(Bool.self, forKey: .postAlarm) ?? true
        postLimit = min(100, max(1, try c.decodeIfPresent(Int.self, forKey: .postLimit) ?? 10))
        restScreen = try c.decodeIfPresent(Bool.self, forKey: .restScreen) ?? true
        restSeconds = min(1800, max(5, try c.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 60))
        blockAdult = try c.decodeIfPresent(Bool.self, forKey: .blockAdult) ?? false
        dcRecommendedOnly = try c.decodeIfPresent(Bool.self, forKey: .dcRecommendedOnly) ?? true
        let mode = try c.decodeIfPresent(String.self, forKey: .dcGalleryMode) ?? "none"
        dcGalleryMode = ["none", "allow", "block"].contains(mode) ? mode : "none"
        dcGalleryIDs = try c.decodeIfPresent([String].self, forKey: .dcGalleryIDs) ?? []
        hideInstallPrompts = try c.decodeIfPresent(Bool.self, forKey: .hideInstallPrompts) ?? true
    }

    var json: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }
}

enum Shared {
    static var group: String {
        Bundle.main.object(forInfoDictionaryKey: "GoyoAppGroup") as? String ?? "group.app.goyo.detox"
    }
    static var defaults: UserDefaults {
        #if WEB_ONLY
        return .standard
        #else
        return UserDefaults(suiteName: group) ?? .standard
        #endif
    }
    static let selectionKey = "activitySelection"
    static let allowedSelectionKey = "allowedActivitySelection"
    static let studyAllowOnlyKey = "studyAllowOnly"
    static let enabledKey = "systemLockEnabled"
    static let unlockUntilKey = "systemUnlockUntil"
    static let activityName = "goyo.temporary-unlock"
    static let studyActiveKey = "studyActive"
    static let studyLockKey = "studyLockEnabled"
    static let familyModeKey = "familyAuthorizationMode"
    static let removalKey = "denyAppRemoval"
    static var settings: FilterSettings {
        get {
            guard let data = defaults.data(forKey: "filterSettings"),
                  let value = try? JSONDecoder().decode(FilterSettings.self, from: data) else { return FilterSettings() }
            return value
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "filterSettings") }
    }
}
