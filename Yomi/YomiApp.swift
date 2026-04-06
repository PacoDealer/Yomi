//
//  YomiApp.swift
//  Yomi
//
//  Created by Martin Gamberg on 13/03/2026.
//

import SwiftUI

@main
struct YomiApp: App {
    @State private var showOnboarding = !AppSettings.shared.hasSeenOnboarding

    init() {
        try? DatabaseManager.shared.setup()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(AppSettings.shared.colorScheme)
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView()
                }
        }
    }
}
