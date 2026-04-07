import SwiftUI

@main
struct YomiApp: App {

    @State private var settings = AppSettings.shared
    @State private var showOnboarding = !AppSettings.shared.hasSeenOnboarding

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
        }
    }
}
