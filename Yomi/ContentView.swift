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
    @State private var updatesVM = UpdatesViewModel.shared
    @AppStorage("tabViewCustomization") private var customization = TabViewCustomization()

    /// Visible tabs in the user's chosen order — CustomizeTabsView is iPhone's only way to
    /// reorder/hide tabs, since the system's own sidebar-editing UI never renders in compact
    /// width (see ROADMAP.md's S108 finding). "more" is never hidden (see AppSettings.hiddenTabIDs).
    private var visibleTabIDs: [YomiTabID] {
        settings.tabOrder.compactMap { YomiTabID(rawValue: $0) }
            .filter { !settings.hiddenTabIDs.contains($0.rawValue) }
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            ForEach(visibleTabIDs, id: \.self) { id in
                tabContent(for: id)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($customization)
        .toolbarBackground(
            settings.pureBlack ? Color.black : Color.clear,
            for: .tabBar
        )
        .toolbarBackground(
            settings.pureBlack ? .visible : .automatic,
            for: .tabBar
        )
        .environment(\.yomiCanvas, settings.blendedCanvasColors)
        .background(settings.blendedCanvasColors.bg.ignoresSafeArea())
        .onOpenURL { url in TrackerManager.route(url: url) }
    }

    @TabContentBuilder<Int>
    private func tabContent(for id: YomiTabID) -> some TabContent<Int> {
        switch id {
        case .library:
            Tab("Library", systemImage: "books.vertical", value: AppRouter.tabLibrary) {
                LibraryView()
            }
            .customizationID("com.Yomi.Library")

        case .browse:
            Tab("Browse", systemImage: "safari", value: AppRouter.tabBrowse) {
                BrowseView()
            }
            .customizationID("com.Yomi.Browse")

        case .history:
            Tab("History", systemImage: "clock", value: AppRouter.tabHistory) {
                HistoryView()
            }
            .customizationID("com.Yomi.History")

        case .updates:
            Tab("Updates", systemImage: "arrow.clockwise", value: AppRouter.tabUpdates) {
                NavigationStack {
                    UpdatesView()
                }
            }
            .badge(updatesVM.totalCount)
            .customizationID("com.Yomi.Updates")

        case .more:
            Tab("More", systemImage: "ellipsis.circle", value: AppRouter.tabMore) {
                MoreView()
            }
            .customizationID("com.Yomi.More")
        }
    }
}

#Preview {
    ContentView()
}
