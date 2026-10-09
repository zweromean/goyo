#if !WEB_ONLY
import FamilyControls
import ManagedSettings
import Foundation

enum Locking {
    static let store = ManagedSettingsStore(named: .init("goyo-lock"))
    static let protection = ManagedSettingsStore(named: .init("goyo-protection"))
    static var studying: Bool {
        Shared.defaults.bool(forKey: Shared.studyActiveKey) && Shared.defaults.bool(forKey: Shared.studyLockKey)
    }
    static func applyProtection() {
        let approved = AuthorizationCenter.shared.authorizationStatus == .approved
        guard approved else { protection.clearAllSettings(); return }
        protection.webContent.blockedByFilter = Shared.settings.blockAdult
            ? .auto(Set(AdultSites.domains.map { WebDomain(domain: $0) }), except: []) : nil
        // This setting affects app removal across the device; family approval is required by our UI.
        protection.application.denyAppRemoval = Shared.defaults.bool(forKey: Shared.familyModeKey) && Shared.defaults.bool(forKey: Shared.removalKey) ? true : nil
    }
    static var selection: FamilyActivitySelection {
        get {
            guard let data = Shared.defaults.data(forKey: Shared.selectionKey),
                  let value = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return FamilyActivitySelection() }
            return value
        }
        set { Shared.defaults.set(try? JSONEncoder().encode(newValue), forKey: Shared.selectionKey) }
    }
    static func apply() {
        guard Shared.defaults.bool(forKey: Shared.enabledKey) || studying else { store.clearAllSettings(); return }
        let chosen = selection
        store.shield.applications = chosen.applicationTokens.isEmpty ? nil : chosen.applicationTokens
        store.shield.applicationCategories = chosen.categoryTokens.isEmpty ? nil : .specific(chosen.categoryTokens)
        store.shield.webDomains = chosen.webDomainTokens.isEmpty ? nil : chosen.webDomainTokens
        store.shield.webDomainCategories = chosen.categoryTokens.isEmpty ? nil : .specific(chosen.categoryTokens)
    }
    static func endUnlock() {
        Shared.defaults.removeObject(forKey: Shared.unlockUntilKey)
        apply()
    }
    static func reconcile() {
        let until = Shared.defaults.double(forKey: Shared.unlockUntilKey)
        applyProtection()
        if studying { apply(); return }
        if until > Date().timeIntervalSince1970 && Shared.defaults.bool(forKey: Shared.enabledKey) {
            store.clearAllSettings()
        } else { endUnlock() }
    }
}
#endif
