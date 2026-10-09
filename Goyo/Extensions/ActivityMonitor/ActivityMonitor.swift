import DeviceActivity
import Foundation

final class ActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity.rawValue == Shared.activityName else { return }
        let until = Shared.defaults.double(forKey: Shared.unlockUntilKey)
        // Ignore callbacks from a previously stopped schedule when a new unlock is active.
        guard until == 0 || until <= Date().timeIntervalSince1970 else { return }
        Locking.endUnlock()
    }
}
