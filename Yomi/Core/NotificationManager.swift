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

    // MARK: - Privacy

    /// True while the user has App Lock or Secure Screen on.
    ///
    /// Both settings exist to keep what they read off an unattended screen, and a notification
    /// preview is exactly that — shown on the lock screen with no authentication, the same threat
    /// model Known Issue #68 already fixed for the Home Screen widget. Titles are replaced with a
    /// neutral string rather than suppressing the notification entirely, so the user still learns
    /// there's something new (and the tap-through still deep-links correctly, behind App Lock).
    private var shouldHideTitles: Bool {
        AppSettings.shared.appLockEnabled || AppSettings.shared.secureScreenEnabled
    }

    // MARK: - Schedule

    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            isAuthorized = settings.authorizationStatus == .authorized
        }
    }

    func scheduleReadingReminder(lastReadTitle: String?, afterDays: Int) {
        guard isAuthorized else { return }
        cancelReadingReminder()

        let content = UNMutableNotificationContent()
        content.title = "Time to read"
        if let title = lastReadTitle, !shouldHideTitles {
            content.body = "Continue \(title)?"
        } else {
            content.body = "Your reading list is waiting."
        }
        content.sound = .default

        var components = DateComponents()
        components.hour = 10
        let fireDate = Calendar.current.date(byAdding: .day, value: afterDays, to: Date()) ?? Date()
        let fireDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: fireDate)
        components.year  = fireDateComponents.year
        components.month = fireDateComponents.month
        components.day   = fireDateComponents.day

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "yomi.readingReminder",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    func cancelReadingReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["yomi.readingReminder"])
    }

    func scheduleChapterNotification(mangaTitle: String, newCount: Int,
                                      mediaId: String? = nil, mediaType: String = "manga") {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = shouldHideTitles ? "Yomi" : mangaTitle
        content.body  = "\(newCount) new chapter\(newCount == 1 ? "" : "s") available"
        content.sound = .default
        if let id = mediaId {
            content.userInfo = ["mediaId": id, "mediaType": mediaType]
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let safeTitle = mangaTitle.filter { $0.isLetter || $0.isNumber || $0 == " " }.prefix(60)
        let identifier = "yomi.update.\(safeTitle)"
        let request = UNNotificationRequest(identifier: identifier,
                                            content: content,
                                            trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }
}
