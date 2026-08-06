import SwiftUI
import Kingfisher

/// Drop-in replacement for AsyncImage on manga/novel covers.
/// KFImage provides disk + memory cache; covers load instantly after first fetch.
struct CoverImage: View {
    let url: URL?

    // `Color.secondary` only tracks system light/dark mode, not the app's own canvas —
    // a manga/novel with no cover art rendered a plain system-gray box regardless of which
    // canvas preset was selected, the one part of the screen that visibly ignored it.
    @Environment(\.yomiCanvas) private var canvas

    var body: some View {
        KFImage(url)
            .placeholder { Rectangle().fill(canvas.surface2) }
            .fade(duration: 0.2)
            .resizable()
            .aspectRatio(2/3, contentMode: .fill)
            .coverAspectSized()
            // Kingfisher's placeholder builder snapshots once at mount and doesn't live-repaint
            // on an environment-only change (verified: correct from a fresh launch, stale after
            // switching canvas mid-session without one) — forcing view identity to depend on the
            // canvas name makes Kingfisher treat a switch as a brand-new view instead.
            .id(canvas.name)
    }
}

extension View {
    /// Locks a cover image to a deterministic 2:3 box driven by the proposed width.
    /// `.aspectRatio(_, contentMode: .fill)` alone falls back to the content's own
    /// intrinsic size whenever the parent proposes an unbounded height (a `LazyVGrid`
    /// cell with only the column width fixed, or a `.frame(width:)` with no height) —
    /// that made grid cells resize per-image instead of sharing one uniform height.
    func coverAspectSized() -> some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay { self }
            .clipped()
    }
}
