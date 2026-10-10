import ManagedSettings
import Foundation

final class ShieldActionExtension: ShieldActionDelegate {
    private func respond(_ action: ShieldAction, completion: @escaping (ShieldActionResponse) -> Void) {
        if case .primaryButtonPressed = action {
            if #available(iOS 26.5, *) {
                Shared.defaults.set(Date().timeIntervalSince1970, forKey: Shared.shieldRequestKey)
                completion(.openParentalControlsApp)
                return
            }
        }
        completion(.close)
    }
    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(action, completion: completionHandler)
    }
    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(action, completion: completionHandler)
    }
    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(action, completion: completionHandler)
    }
}
