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

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Library", systemImage: "books.vertical", value: 0) {
                LibraryView()
            }
            Tab("Browse", systemImage: "safari", value: 1) {
                BrowseView()
            }
            Tab("History", systemImage: "clock", value: 2) {
                HistoryView()
            }
            Tab("Updates", systemImage: "arrow.clockwise", value: 3) {
                NavigationStack {
                    UpdatesView()
                }
            }
            Tab("More", systemImage: "ellipsis.circle", value: 4) {
                MoreView()
            }
        }
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
