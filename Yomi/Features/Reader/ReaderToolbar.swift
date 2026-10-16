import SwiftUI

// MARK: - Custom reader toolbar (L3c, Tachimanga v5.1 "Customizable Reader Toolbar" + v5.2 quick actions)
//
// The manga reader's bottom bar shows the buttons picked here, in this order (`AppSettings.readerToolbarItems`).
// The default is the pre-L3c bar: previous + next chapter. A button that doesn't apply to what's open (two-page spreads
// in long strip, comments on a source without them) is left out at that moment, not removed from the list.

enum ReaderToolbarItem: String, CaseIterable, Identifiable {
    case previousChapter, nextChapter, bookmark, markPreviousRead, readingMode, spreads, cropBorders, sharePage, comments

    static let defaults = [ReaderToolbarItem.previousChapter, .nextChapter].map(\.rawValue)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .previousChapter:  "Previous chapter"
        case .nextChapter:      "Next chapter"
        case .bookmark:         "Bookmark chapter"
        case .markPreviousRead: "Mark previous as read"
        case .readingMode:      "Reading mode"
        case .spreads:          "Two-page spreads"
        case .cropBorders:      "Crop borders"
        case .sharePage:        "Share page"
        case .comments:         "Comments"
        }
    }

    var systemImage: String {
        switch self {
        case .previousChapter:  "backward.end.fill"
        case .nextChapter:      "forward.end.fill"
        case .bookmark:         "bookmark"
        case .markPreviousRead: "checkmark.circle"
        case .readingMode:      "book.pages"
        case .spreads:          "book"
        case .cropBorders:      "crop"
        case .sharePage:        "square.and.arrow.up"
        case .comments:         "bubble.left.and.bubble.right"
        }
    }

    /// The saved list, unknown values dropped.
    static func current(_ settings: AppSettings) -> [ReaderToolbarItem] {
        settings.readerToolbarItems.compactMap(ReaderToolbarItem.init(rawValue:))
    }
}

// MARK: - Editor (reader settings sheet + More → Settings → Manga & Webtoon)

struct ReaderToolbarEditor: View {
    @State private var settings = AppSettings.shared
    @State private var editMode = EditMode.active

    private var shown: [ReaderToolbarItem] { ReaderToolbarItem.current(settings) }
    private var hidden: [ReaderToolbarItem] { ReaderToolbarItem.allCases.filter { !shown.contains($0) } }

    var body: some View {
        CalmList {
            Section {
                if shown.isEmpty {
                    Text("No buttons — only the page count shows.").foregroundStyle(.secondary)
                }
                ForEach(shown) { item in
                    Label(item.title, systemImage: item.systemImage)
                }
                .onMove { from, to in
                    var items = shown.map(\.rawValue)
                    items.move(fromOffsets: from, toOffset: to)
                    settings.readerToolbarItems = items
                }
                .onDelete { offsets in
                    var items = shown.map(\.rawValue)
                    items.remove(atOffsets: offsets)
                    settings.readerToolbarItems = items
                }
            } header: { CalmSectionHeader("In the toolbar") } footer: {
                Text("Drag to reorder. A button that doesn't apply to what you're reading — two-page spreads in long strip, comments on a source without them — is hidden there.")
            }

            if !hidden.isEmpty {
                Section(calm: "More buttons") {
                    ForEach(hidden) { item in
                        Button {
                            settings.readerToolbarItems = shown.map(\.rawValue) + [item.rawValue]
                        } label: {
                            HStack {
                                Label(item.title, systemImage: item.systemImage)
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(item.title)")
                    }
                }
            }

            if settings.readerToolbarItems != ReaderToolbarItem.defaults {
                Section {
                    Button("Reset to Default") { settings.readerToolbarItems = ReaderToolbarItem.defaults }
                }
            }
        }
        // A row added while editing gets no delete/drag handles (SwiftUI, sim S172): rebuild the list on add/remove.
        .id(shown.count)
        .environment(\.editMode, $editMode)
        .navigationTitle("Toolbar")
        .navigationBarTitleDisplayMode(.inline)
    }
}
