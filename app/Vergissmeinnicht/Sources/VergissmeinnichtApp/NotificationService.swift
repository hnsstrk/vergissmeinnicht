import Foundation
@preconcurrency import UserNotifications
import VergissmeinnichtKit

/// Verwaltet System-Notifications für überfällige Tasks.
///
/// Bewusst schlank: kein Daily-Scheduling, kein per-Task-Reminder. Beim App-Launch
/// (bzw. nach jedem Refresh) wird eine zusammenfassende Notification angezeigt,
/// wenn überfällige Pending-Tasks vorhanden sind und der User Notifications
/// in den Settings aktiviert hat. Wir nutzen einen Identifier pro Launch, damit
/// keine Notification-Flut entsteht.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    /// Schutz durch @MainActor; daher kein zusätzlicher Lock nötig (D7).
    private var lastNotifiedCount: Int = -1

    /// Fragt die Notification-Berechtigung an, falls noch nicht entschieden.
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Plant (oder unterdrückt) eine Zusammenfassungs-Notification für überfällige
    /// Pending-Tasks. Wird vom AppContainer nach jedem Refresh aufgerufen.
    func notifyOverdueIfNeeded(tasks: [TaskInfo]) async {
        let now = Date().timeIntervalSince1970
        let overdue = tasks.filter {
            $0.status == .pending
                && ($0.due.map { TimeInterval($0) < now } ?? false)
                && ($0.wait.map { TimeInterval($0) <= now } ?? true)
        }
        guard overdue.count > 0 else {
            lastNotifiedCount = 0
            return
        }
        // Nur senden, wenn sich die Anzahl seit letztem Lauf erhöht hat.
        guard overdue.count != lastNotifiedCount else { return }
        lastNotifiedCount = overdue.count

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Überfällige Aufgaben")
        content.body = String(
            localized: "Du hast \(overdue.count) überfällige Aufgabe(n)."
        )
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "vergissmeinnicht.overdue.summary",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
}
