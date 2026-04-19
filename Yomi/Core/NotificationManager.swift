import Foundation
import UserNotifications

// MARK: - NotificationManager

@Observable
final class NotificationManager {

    // MARK: - Singleton

    static let shared = NotificationManager()
    init() { }

    // MARK: - State

    var isAuthorized: Bool = false

    // MARK: - Permission

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            await MainActor.run { isAuthorized = granted }
        } catch {
            isAuthorized = false
        }
    }

    // MARK: - Schedule

    func scheduleChapterNotification(mangaTitle: String, newCount: Int) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = mangaTitle
        content.body  = "\(newCount) new chapter\(newCount == 1 ? "" : "s") available"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let safeTitle = mangaTitle.filter { $0.isLetter || $0.isNumber || $0 == " " }.prefix(60)
        let identifier = "yomi.update.\(safeTitle)"
        let request = UNNotificationRequest(identifier: identifier,
                                            content: content,
                                            trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }
}
