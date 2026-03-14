//
//  ContentView.swift
//  Yomi
//
//  Created by Martin Gamberg on 13/03/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Library", systemImage: "books.vertical") {
                LibraryView()
            }
            Tab("Browse", systemImage: "safari") {
                BrowseView()
            }
            Tab("History", systemImage: "clock") {
                HistoryView()
            }
            Tab("More", systemImage: "ellipsis.circle") {
                MoreView()
            }
        }
    }
}

#Preview {
    ContentView()
}
