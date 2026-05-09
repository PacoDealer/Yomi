import SwiftUI
import UIKit

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(
                    settings.theme == "Dark"  ? .dark  :
                    settings.theme == "Light" ? .light : nil
                )
                .tint(Color(hex: settings.accentColor))
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView()
                }
                .fullScreenCover(isPresented: $isLocked) {
                    AppLockView {
                        isLocked = false
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, settings.appLockEnabled {
                isLocked = true
            }
        }
    }
}
