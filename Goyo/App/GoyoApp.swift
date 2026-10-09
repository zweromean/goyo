import SwiftUI
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var settings = Shared.settings {
        didSet {
            Shared.settings = settings
            #if !WEB_ONLY
            Locking.applyProtection()
            #endif
        }
    }
    @Published var settingsUnlocked = false
}

@main
struct GoyoApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var accounts = AccountModel()
    @StateObject private var breaks = BreakModel()
    @StateObject private var study = StudyModel()
    @StateObject private var planner = PlannerModel()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).environmentObject(accounts).environmentObject(breaks).environmentObject(study).environmentObject(planner)
                .tint(Color(red: 0.04, green: 0.55, blue: 0.43))
        }
    }
}
