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
    static var allowedSelection: FamilyActivitySelection {
        get {
            guard let data = Shared.defaults.data(forKey: Shared.allowedSelectionKey),
                  let value = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return FamilyActivitySelection() }
            return value
        }
        set { Shared.defaults.set(try? JSONEncoder().encode(newValue), forKey: Shared.allowedSelectionKey) }
    }
    static func apply() {
        guard AuthorizationCenter.shared.authorizationStatus == .approved else { store.clearAllSettings(); return }
        guard Shared.defaults.bool(forKey: Shared.enabledKey) || studying else { store.clearAllSettings(); return }
        let chosen = selection
        let allowed = allowedSelection
        let apps = chosen.applicationTokens.subtracting(allowed.applicationTokens)
        let domains = chosen.webDomainTokens.subtracting(allowed.webDomainTokens)
        let allowOnly = studying && Shared.defaults.bool(forKey: Shared.studyAllowOnlyKey)
        store.shield.applications = allowOnly || apps.isEmpty ? nil : apps
        store.shield.applicationCategories = allowOnly
            ? .all(except: allowed.applicationTokens)
            : (chosen.categoryTokens.isEmpty ? nil : .specific(chosen.categoryTokens, except: allowed.applicationTokens))
        store.shield.webDomains = allowOnly || domains.isEmpty ? nil : domains
        store.shield.webDomainCategories = allowOnly
            ? .all(except: allowed.webDomainTokens)
            : (chosen.categoryTokens.isEmpty ? nil : .specific(chosen.categoryTokens, except: allowed.webDomainTokens))
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
