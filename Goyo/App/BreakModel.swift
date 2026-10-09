import Foundation
import Combine
import CryptoKit
import AudioToolbox

struct ReadingLedger: Codable {
    var seen: [String] = []
    var total = 0
    var sinceAlert = 0
}

@MainActor
final class BreakModel: ObservableObject {
    @Published var until: Date?
    @Published var notice: String?
    @Published var totals: [String: Int] = [:]
    init() {
        let timestamp = Shared.defaults.double(forKey: "breakUntil")
        until = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }
    var resting: Bool { until != nil }
    func record(id: String, account: UUID, service: String, settings: FilterSettings) {
        guard !resting, settings.postAlarm || settings.restScreen else { return }
        let key = "ledger." + account.uuidString
        var ledger = Shared.defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ReadingLedger.self, from: $0) } ?? ReadingLedger()
        let hash = SHA256.hash(data: Data((service + ":" + id).utf8)).map { String(format: "%02x", $0) }.joined()
        guard !ledger.seen.contains(hash) else { return }
        ledger.seen.append(hash)
        if ledger.seen.count > 3000 { ledger.seen.removeFirst(ledger.seen.count - 3000) }
        ledger.total += 1
        ledger.sinceAlert += 1
        totals[account.uuidString] = ledger.total
        if ledger.sinceAlert >= settings.postLimit {
            ledger.sinceAlert = 0
            if settings.postAlarm {
                notice = "게시물 \(settings.postLimit)개를 확인하셨습니다."
                AudioServicesPlaySystemSound(1005)
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
            if settings.restScreen {
                until = Date().addingTimeInterval(TimeInterval(settings.restSeconds))
                Shared.defaults.set(until!.timeIntervalSince1970, forKey: "breakUntil")
            }
        }
        Shared.defaults.set(try? JSONEncoder().encode(ledger), forKey: key)
    }
    func finishRest() {
        guard let until, Date() >= until else { return }
        self.until = nil
        Shared.defaults.removeObject(forKey: "breakUntil")
    }
}
