import SwiftUI

@main
struct YomiApp: App {
    @State private var settings = AppSettings.shared
    @State private var showOnboarding = !AppSettings.shared.hasSeenOnboarding

    init() {
        try? DatabaseManager.shared.setup()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(settings.colorScheme)
                .tint(Color(hex: settings.accentColor))
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView()
                }
        }
    }
}
