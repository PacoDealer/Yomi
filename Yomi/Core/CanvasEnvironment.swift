import SwiftUI

// MARK: - Canvas environment
//
// Threads the resolved YomiTokens.CanvasColors (bg/surfaces/text) down to any
// view without each one re-reading AppSettings.shared. Set once in ContentView
// from `settings.canvasColors`; read anywhere via `@Environment(\.yomiCanvas)`.

private struct YomiCanvasKey: EnvironmentKey {
    static let defaultValue: YomiTokens.CanvasColors = YomiTokens.Canvas.ink
}

extension EnvironmentValues {
    var yomiCanvas: YomiTokens.CanvasColors {
        get { self[YomiCanvasKey.self] }
        set { self[YomiCanvasKey.self] = newValue }
    }
}

// MARK: - Canvas-backed List

/// Repaints a `List`'s chrome with the active canvas instead of the system's own grouped-list
/// grays. The ScrollView-based screens (Settings/More/Insights/Downloads) already do this by hand
/// with `.background(canvas.bg.ignoresSafeArea())`, but a `List` paints its own opaque background
/// above that, so a List-based screen stays cool system gray no matter what canvas is selected —
/// most obviously wrong on Paper/Sepia, whose palette is warm cream everywhere else
/// (Known Issues #115/#116).
///
/// One modifier rather than a copy per screen: the tracker screens alone are 5 identical Lists.
struct YomiListCanvas: ViewModifier {
    @Environment(\.yomiCanvas) private var canvas

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(canvas.bg.ignoresSafeArea())
    }
}

extension View {
    /// Applies the active canvas to a `List`'s background. See `YomiListCanvas`.
    func yomiListCanvas() -> some View { modifier(YomiListCanvas()) }

}

/// S142 calm settings list: plain style on the canvas, rows without separators or cell backgrounds
/// (Martin, S141: no list separators anywhere). Row modifiers on the `List` itself don't reach its rows —
/// they're applied through a `Group` around the content, which hands them to every section and row.
struct CalmList<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        List {
            Group { content }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        // Grouped, not plain: plain pins section titles, which then sat over the rows scrolling under them.
        // With the canvas background and clear rows it looks the same, minus the sticky headers.
        .listStyle(.grouped)
        .yomiListCanvas()
    }
}

extension Section where Parent == CalmSectionHeader, Content: View, Footer == EmptyView {
    /// `Section("Title") { … }` for calm lists.
    init(calm title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { CalmSectionHeader(title) })
    }
}

/// Bold section title for calm lists — sentence case, primary colour, not the small grey caps of a grouped list.
struct CalmSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(canvas.textPrimary)
            .textCase(nil)
            .padding(.top, 12)
    }
}
