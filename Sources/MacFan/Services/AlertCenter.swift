import Foundation
import MacFanCore
import UserNotifications

/// Notifies when the CPU/GPU stays above the user's threshold, or the battery gets hot.
///
/// Alerts must be rare to stay meaningful: a condition has to persist for `sustain`
/// before it fires, and each kind is quiet for `cooldown` afterwards.
final class AlertCenter {
    private enum Kind: Hashable {
        case processor
        case battery
    }

    private let sustain: TimeInterval = 30
    private let cooldown: TimeInterval = 15 * 60
    private let batteryLimit = SensorCategory.battery.thresholds.hot

    private var since: [Kind: Date] = [:]
    private var lastSent: [Kind: Date] = [:]

    /// Notifications need an app bundle; `swift run` binaries have none.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func requestAuthorization() async -> Bool {
        guard let center else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func evaluate(_ snapshot: HardwareSnapshot, preferences: Preferences, unit: TemperatureUnit) {
        guard preferences.alertsEnabled else {
            since.removeAll()
            return
        }

        if let hottest = snapshot.hottest(in: [.cpu, .gpu]) {
            check(.processor, isActive: hottest.celsius >= preferences.alertThreshold, at: snapshot.date) {
                (
                    String(localized: "\(hottest.sensor.name) is at \(unit.format(hottest.celsius))"),
                    String(localized: "It's been running hot for a while. Quit heavy apps you aren't using, and keep the vents clear.")
                )
            }
        }

        if let battery = snapshot.hottest(in: [.battery]) {
            check(.battery, isActive: battery.celsius >= batteryLimit, at: snapshot.date) {
                (
                    String(localized: "Battery is warm (\(unit.format(battery.celsius)))"),
                    String(localized: "Heat ages batteries. Move your Mac somewhere cooler, and avoid charging it under heavy load.")
                )
            }
        }
    }

    private func check(_ kind: Kind, isActive: Bool, at now: Date, message: () -> (title: String, body: String)) {
        guard isActive else {
            since[kind] = nil
            return
        }
        let start = since[kind] ?? now
        since[kind] = start

        guard now.timeIntervalSince(start) >= sustain,
              now.timeIntervalSince(lastSent[kind] ?? .distantPast) >= cooldown
        else { return }

        lastSent[kind] = now
        let (title, body) = message()
        post(title: title, body: body)
    }

    private func post(title: String, body: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
