//
//  ContentView.swift
//  Yomi
//
//  Created by Martin Gamberg on 13/03/2026.
//

import SwiftUI

struct ContentView: View {
    @Bindable var router = appRouter
    @State private var settings = AppSettings.shared
    @AppStorage("tabViewCustomization") private var customization = TabViewCustomization()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Library", systemImage: "books.vertical", value: 0) {
                LibraryView()
            }
            .customizationID("com.Yomi.Library")

            Tab("Browse", systemImage: "safari", value: 1) {
                BrowseView()
            }
            .customizationID("com.Yomi.Browse")

            Tab("History", systemImage: "clock", value: 2) {
                HistoryView()
            }
            .customizationID("com.Yomi.History")

            Tab("Updates", systemImage: "arrow.clockwise", value: 3) {
                NavigationStack {
                    UpdatesView()
                }
            }
            .customizationID("com.Yomi.Updates")

            Tab("More", systemImage: "ellipsis.circle", value: 4) {
                MoreView()
            }
            .customizationID("com.Yomi.More")
        }
        .tabViewCustomization($customization)
        .toolbarBackground(
            settings.pureBlack ? Color.black : Color.clear,
            for: .tabBar
        )
        .toolbarBackground(
            settings.pureBlack ? .visible : .automatic,
            for: .tabBar
        )
    }
}

#Preview {
    ContentView()
}
