import SwiftUI
import UIKit
import Kingfisher
import BackgroundTasks
import os

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
    // The library couldn't be opened at launch (DatabaseFailureView) — nothing to refresh.
    guard appDatabase != nil else { return task.setTaskCompleted(success: false) }
    if AppSettings.shared.backgroundAutoRefreshEnabled {
        scheduleBackgroundRefresh()
    }
    // iOS must hear "completed" exactly once, and right away when time runs out (S189 audit): the refresh used to
    // keep going past the deadline, and an app that overruns gets fewer background runs.
    let done = OSAllocatedUnfairLock(initialState: false)
    let complete: @Sendable (Bool) -> Void = { success in
        let first = done.withLock { finished in
            defer { finished = true }
            return !finished
        }
        if first { task.setTaskCompleted(success: success) }
    }
    let refreshTask = Task {
        await UpdatesViewModel.shared.refresh(includeKeiyoushi: false)
        complete(!Task.isCancelled)
    }
    task.expirationHandler = {
        refreshTask.cancel()
        complete(false)
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        SafeMode.clearStalePasscode()
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
                localizedTitle: String(localized: "Continue Reading"),
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

    // MARK: - Rotation lock (Settings → Appearance → "Follow device")

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppSettings.shared.rotationFollowDevice ? .allButUpsideDown : .portrait
    }

    // MARK: - CloudKit sync push (S102)

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {}

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard appDatabase != nil else { return completionHandler(.failed) }
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
    @State private var showOnboarding = !AppSettings.shared.hasSeenOnboarding && !Self.readerFixture
    @State private var isLocked = AppSettings.shared.appLockEnabled && !Self.readerFixture

    #if DEBUG
    private static var readerFixture: Bool { ReaderFixture.isRequested }
    #else
    private static let readerFixture = false
    #endif

    /// The app, or the UI-test reader fixture when launched with `-yomiReaderFixture` (Debug only).
    @ViewBuilder private var rootView: some View {
        #if DEBUG
        if Self.readerFixture { if ReaderFixture.isManga { ReaderFixture.MangaRootView() } else { ReaderFixture.RootView() } } else { ContentView() }
        #else
        ContentView()
        #endif
    }
    @Environment(\.scenePhase) private var scenePhase

    /// False while the library couldn't be opened — every *Queries call force-unwraps `appDatabase`, so nothing that
    /// reads it may start until it is (S185: `DatabaseFailureView` replaces the old launch `fatalError`).
    @State private var databaseOpen: Bool

    init() {
        let opened = DatabaseManager.shared.open()
        _databaseOpen = State(initialValue: opened)
        // Start watching the network now, so the first download already knows whether it's on Wi-Fi.
        _ = NetworkMonitor.shared
        if opened { Self.startDatabaseServices() }
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
            // Keiyoushi covers come straight from the source's CDN and may need its Referer/Origin (S134).
            for (name, value) in KeiyoushiCovers.shared.headers(for: request.url) {
                request.setValue(value, forHTTPHeaderField: name)
            }
            request.setValue(CFBypassConstants.userAgent, forHTTPHeaderField: "User-Agent")
            // Keiyoushi pages: the bridge's token (S191), and its new port after the app was in the background (S144).
            return KeiyoushiBridge.bridgeImageRequest(request)
        }
        KingfisherManager.shared.defaultOptions += [.requestModifier(uaModifier)]
        // Kingfisher's memory cache defaults to a quarter of the RAM (2 GB on an iPhone 17) and counts decoded
        // bytes — ~57 MB per Asura page. A guard, not the S160 fix (the sim never fills it): 256 MB still keeps the
        // pages around the screen and the downsampled covers; the rest comes back from the disk cache.
        ImageCache.default.memoryStorage.config.totalCostLimit = 256 * 1024 * 1024
        let kfSessionConfig = URLSessionConfiguration.default
        kfSessionConfig.httpCookieStorage = .shared
        kfSessionConfig.httpShouldSetCookies = true
        kfSessionConfig.httpCookieAcceptPolicy = .always
        KingfisherManager.shared.downloader.sessionConfiguration = kfSessionConfig
    }

    /// Everything at launch that reads the library — run once it is open (at launch, or after Try Again).
    private static func startDatabaseServices() {
        #if DEBUG
        ExtensionManager.shared.seedBundledPlugins()
        LNReaderHarness.startIfRequested()
        KeiyoushiPageProbe.startIfRequested()
        CloudSyncSelfTest.startIfRequested()
        #endif
        // Re-start the sync engine on cold launch if the user already turned it on in a prior
        // session — AppSettings' didSet only fires on an in-session toggle flip, not on load.
        if AppSettings.shared.cloudSyncEnabled {
            Task { await CloudSyncManager.shared.enable() }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if databaseOpen {
                    rootView
                } else {
                    DatabaseFailureView(error: DatabaseManager.shared.openError) {
                        guard DatabaseManager.shared.open() else { return }
                        Self.startDatabaseServices()
                        databaseOpen = true
                    }
                }
            }
                .preferredColorScheme(settings.colorScheme)
                .tint(Color(hex: settings.accentColor))
                .fullScreenCover(isPresented: Binding(
                    get: { databaseOpen && (isLocked || showOnboarding) },
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
            guard databaseOpen else { return }
            if phase == .active {
                Task { await KeiyoushiBridge.shared.resumeIfPaused() }
                Task { await NotificationManager.shared.checkAuthorizationStatus() }
                NotificationManager.shared.cancelReadingReminder()
                if settings.cloudSyncEnabled {
                    // Starts sync too if the launch found no iCloud account yet (S191, audit #6).
                    Task { await CloudSyncManager.shared.resume() }
                }
            }
            if phase == .background {
                // iOS suspends the on-device extension bridge's socket anyway; pausing keeps extensions loaded
                // and lets the next Keiyoushi call restart serving on a fresh port.
                KeiyoushiBridge.shared.pause()
                if settings.appLockEnabled { isLocked = true }
                if settings.backgroundAutoRefreshEnabled { scheduleBackgroundRefresh() }
                Task { await LibraryViewModel.refreshWidget() }
                if settings.iCloudAutoBackup {
                    Task { await BackupManager.shared.uploadToICloud() }
                }
                if settings.localAutoBackup {
                    Task { await BackupManager.shared.saveLocalBackupIfDue() }
                }
                if settings.cloudSyncEnabled {
                    Task { await CloudSyncManager.shared.syncNow() }
                }
                if settings.readingReminderEnabled {
                    let days = settings.readingReminderDays
                    let safe = SafeMode.filter
                    Task {
                        let title = await Task.detached {
                            (try? MangaQueries.fetchRecentlyRead(limit: 20))?.first(where: safe.allows)?.title
                                ?? (try? NovelQueries.fetchRecentlyRead(limit: 20))?.first(where: safe.allows)?.title
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
