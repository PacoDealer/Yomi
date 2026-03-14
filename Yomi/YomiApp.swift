//
//  YomiApp.swift
//  Yomi
//
//  Created by Martin Gamberg on 13/03/2026.
//

import SwiftUI

@main
struct YomiApp: App {
    init() {
        do {
            try DatabaseManager.shared.setup()
        } catch {
            print("❌ DatabaseManager setup failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
