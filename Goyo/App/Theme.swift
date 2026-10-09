import SwiftUI

enum GoyoTheme {
    static let studyGreen = Color(red: 0.22, green: 0.55, blue: 0.24)
    static let charcoal = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let violet = Color(red: 0.39, green: 0.36, blue: 1)
    static func time(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
}
