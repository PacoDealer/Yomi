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
        try? DatabaseManager.shared.setup()
        ExtensionManager.shared.seedBundledPlugins()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
