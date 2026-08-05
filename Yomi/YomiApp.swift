import SwiftUI
import UIKit
import Kingfisher

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.shortcutItems = [
            UIApplicationShortcutItem(
                type: "com.yomi.continueReading",
                localizedTitle: "Continue Reading",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "book.fill")
            ),
            UIApplicationShortcutItem(
                type: "com.yomi.browse",
                localizedTitle: "Browse",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "safari.fill")
            )
        ]
        return true
    }

    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        handleShortcut(shortcutItem)
        completionHandler(true)
    }

    // Called when user taps a delivered notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let mediaId = userInfo["mediaId"] as? String,
           let mediaType = userInfo["mediaType"] as? String {
            DispatchQueue.main.async {
                appRouter.selectedTab = AppRouter.tabLibrary
                if mediaType == "novel" {
                    appRouter.pendingOpenNovelId = mediaId
                } else {
                    appRouter.pendingOpenMangaId = mediaId
                }
            }
        }
        completionHandler()
    }

    // Allow notifications to display while app is in foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    private func handleShortcut(_ item: UIApplicationShortcutItem) {
        DispatchQueue.main.async {
            switch item.type {
            case "com.yomi.continueReading":
                appRouter.selectedTab = AppRouter.tabLibrary
            case "com.yomi.browse":
                appRouter.selectedTab = AppRouter.tabBrowse
            default:
                break
            }
        }
    }
}

// MARK: - YomiApp

@main
struct YomiApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var settings = AppSettings.shared
    @State private var showOnboarding = !AppSettings.shared.hasSeenOnboarding
    @State private var isLocked = AppSettings.shared.appLockEnabled
    @Environment(\.scenePhase) private var scenePhase

    init() {
        try? DatabaseManager.shared.setup()
        #if DEBUG
        ExtensionManager.shared.seedBundledPlugins()
        #endif
        // Covers on Cloudflare-protected sources (e.g. AquaManga) 403 without this — cf_clearance
        // is bound to the UA that solved the challenge, and that UA must match SOURCE.fetch's.
        let uaModifier = AnyModifier { request in
            var request = request
            request.setValue(CFBypassConstants.userAgent, forHTTPHeaderField: "User-Agent")
            return request
        }
        KingfisherManager.shared.defaultOptions += [.requestModifier(uaModifier)]
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(settings.colorScheme)
                .tint(Color(hex: settings.accentColor))
                .fullScreenCover(isPresented: Binding(
                    get: { isLocked || showOnboarding },
                    set: { isPresented in
                        if !isPresented {
                            isLocked = false
                            showOnboarding = false
                        }
                    }
                )) {
                    // Chaining two separate .fullScreenCover modifiers on the same view is
                    // unreliable in SwiftUI (only one presentation slot per view identity) —
                    // merged into one cover with priority: lock screen first, then onboarding.
                    if isLocked {
                        AppLockView { isLocked = false }
                    } else {
                        OnboardingView()
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await NotificationManager.shared.checkAuthorizationStatus() }
                NotificationManager.shared.cancelReadingReminder()
            }
            if phase == .background {
                if settings.appLockEnabled { isLocked = true }
                if settings.iCloudAutoBackup {
                    Task { await BackupManager.shared.uploadToICloud() }
                }
                if settings.readingReminderEnabled {
                    let days = settings.readingReminderDays
                    Task {
                        let title = await Task.detached {
                            (try? MangaQueries.fetchRecentlyRead(limit: 1))?.first?.title
                                ?? (try? NovelQueries.fetchRecentlyRead(limit: 1))?.first?.title
                        }.value
                        NotificationManager.shared.scheduleReadingReminder(
                            lastReadTitle: title,
                            afterDays: days
                        )
                    }
                }
            }
        }
    }
}
