import Foundation
import UserNotifications

enum NotificationService {
    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    static func notifyApplicationStatusChange(shiftTitle: String, status: ApplicationStatus) {
        let content = UNMutableNotificationContent()
        content.title = "Оновлення відгуку"
        content.body = "Зміна \(shiftTitle): статус — \(status.title.lowercased())"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "status-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }
}
