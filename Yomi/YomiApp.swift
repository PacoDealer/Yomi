import SwiftUI
import UIKit
import Kingfisher
import BackgroundTasks

// MARK: - Background refresh

let backgroundRefreshTaskId = "com.yomi.refresh"

/// Submits the next BGAppRefreshTask request. iOS decides the actual fire time (typically hours
/// out, based on usage patterns) — `earliestBeginDate` is a lower bound, not a schedule.
func scheduleBackgroundRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: backgroundRefreshTaskId)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
    try? BGTaskScheduler.shared.submit(request)
}

/// Handler for `com.yomi.refresh`, registered at launch. Reuses the exact same library-wide
/// update check the Updates tab's manual refresh/pull-to-refresh runs (`UpdatesViewModel.refresh()`)
/// — background auto-download (if enabled) is wired inside that same code path, not here.
func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
    if AppSettings.shared.backgroundAutoRefreshEnabled {
        scheduleBackgroundRefresh()
    }
    let refreshTask = Task {
        await UpdatesViewModel.shared.refresh()
        task.setTaskCompleted(success: true)
    }
    task.expirationHandler = {
        refreshTask.cancel()
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundRefreshTaskId, using: nil) { task in
            handleBackgroundRefresh(task as! BGAppRefreshTask)
        }
        // Required by CKSyncEngine (see Yomi/CLOUDKIT_SYNC_DESIGN.md) — only registered when the user
        // has actually turned sync on, so the capability stays dormant for everyone else. This does
        // NOT turn sync into a real-time feature: Yomi still only visibly syncs on foreground/
        // background (see the scenePhase handling below); this just lets CKSyncEngine opportunistically
        // process a silent push if iOS happens to deliver one while the app is backgrounded.
        if AppSettings.shared.cloudSyncEnabled {
            application.registerForRemoteNotifications()
        }
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

    // MARK: - CloudKit sync push (S102)

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {}

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            await CloudSyncManager.shared.handleRemoteNotification()
            completionHandler(.newData)
        }
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
        // Covers and reader pages on Cloudflare-protected sources (e.g. AquaManga) 403 without this.
        // Two separate things are both required, not just the UA:
        // 1. cf_clearance is bound to the UA that solved the challenge — CFBypassView copies it into
        //    HTTPCookieStorage.shared, so every outgoing request's UA must match CFBypassConstants.userAgent.
        // 2. Kingfisher's ImageDownloader defaults to URLSessionConfiguration.ephemeral, which has its
        //    own private in-memory cookie store — HTTPCookieStorage.shared is invisible to it regardless
        //    of the UA. Repointing its session config at .shared makes it actually see the cf_clearance
        //    cookie CFBypassView wrote there.
        let uaModifier = AnyModifier { request in
            var request = request
            request.setValue(CFBypassConstants.userAgent, forHTTPHeaderField: "User-Agent")
            return request
        }
        KingfisherManager.shared.defaultOptions += [.requestModifier(uaModifier)]
        let kfSessionConfig = URLSessionConfiguration.default
        kfSessionConfig.httpCookieStorage = .shared
        kfSessionConfig.httpShouldSetCookies = true
        kfSessionConfig.httpCookieAcceptPolicy = .always
        KingfisherManager.shared.downloader.sessionConfiguration = kfSessionConfig

        // Re-start the sync engine on cold launch if the user already turned it on in a prior
        // session — AppSettings' didSet only fires on an in-session toggle flip, not on load.
        if AppSettings.shared.cloudSyncEnabled {
            Task { await CloudSyncManager.shared.enable() }
        }
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
                .overlay {
                    // .inactive fires during the app-switch snapshot/transition, before
                    // .background — this is what actually hides content from the App Switcher.
                    if settings.secureScreenEnabled && scenePhase != .active {
                        SecureScreenCover()
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await NotificationManager.shared.checkAuthorizationStatus() }
                NotificationManager.shared.cancelReadingReminder()
                if settings.cloudSyncEnabled {
                    Task { await CloudSyncManager.shared.syncNow() }
                }
            }
            if phase == .background {
                if settings.appLockEnabled { isLocked = true }
                if settings.backgroundAutoRefreshEnabled { scheduleBackgroundRefresh() }
                if settings.iCloudAutoBackup {
                    Task { await BackupManager.shared.uploadToICloud() }
                }
                if settings.cloudSyncEnabled {
                    Task { await CloudSyncManager.shared.syncNow() }
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

// MARK: - SecureScreenCover

/// Covers the window whenever the scene isn't `.active` (App Switcher, incoming call, etc.)
/// so Yomi's content — reading history included — never appears in a system snapshot.
private struct SecureScreenCover: View {
    var body: some View {
        ZStack {
            YomiTokens.Canvas.ink.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                Image("OnboardingIcon")
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                Text("Yomi")
                    .font(YomiTokens.Font.grotesk(20, weight: .semibold))
                    .foregroundStyle(YomiTokens.Canvas.ink.textPrimary)
            }
        }
        .transition(.opacity)
    }
}
