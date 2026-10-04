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
    @State private var listen = ListenPlayer.shared
    @State private var showListenPlayer = false
    @State private var listenReader: ListenReaderTarget?
    /// The device's light/dark setting — the Automatic theme follows it (S142).
    @Environment(\.colorScheme) private var colorScheme

    private var palette: YomiTokens.CanvasColors { settings.canvasColors(for: colorScheme) }

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
        // Listening carries on outside the reader (S143): Apple Music's mini-player spot.
        .tabViewBottomAccessory(isEnabled: listen.isActive && listen.readersOpen == 0) {
            ListenMiniPlayer(onOpen: { showListenPlayer = true }, inTabBar: true)
        }
        .sheet(isPresented: $showListenPlayer) {
            ListenPlayerView(onOpenReader: { listenReader = ListenReaderTarget.current() })
        }
        .fullScreenCover(item: $listenReader) { target in
            NavigationStack {
                TextReaderView(novel: target.novel, bridge: target.bridge, chapters: target.chapters,
                               startIndex: target.index)   // its Back button dismisses the cover
            }
            .tint(Color(hex: settings.accentColor))
        }
        // The legacy "pure black" tab-bar override is gone (S142): Midnight is the true-black theme,
        // and the old switch had no UI left, so anyone who had it on was stuck with it.
        .environment(\.yomiCanvas, palette)
        .background(palette.bg.ignoresSafeArea())
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

/// The novel being listened to, to open in the reader from the tab-bar player.
struct ListenReaderTarget: Identifiable {
    let id = UUID()
    let novel: Novel
    let bridge: JSBridge
    let chapters: [NovelChapter]
    let index: Int

    static func current() -> ListenReaderTarget? {
        let p = ListenPlayer.shared
        guard let novel = p.novel, let bridge = p.bridge, p.chapters.indices.contains(p.chapterIndex) else { return nil }
        // Open at the sentence being read, not wherever the chapter list last had it.
        var chapters = p.chapters
        chapters[p.chapterIndex].lastScrollPercent = p.progress
        return ListenReaderTarget(novel: novel, bridge: bridge, chapters: chapters, index: p.chapterIndex)
    }
}

#Preview {
    ContentView()
}
