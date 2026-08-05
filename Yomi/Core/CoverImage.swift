import SwiftUI
import Kingfisher

/// Drop-in replacement for AsyncImage on manga/novel covers.
/// KFImage provides disk + memory cache; covers load instantly after first fetch.
struct CoverImage: View {
    let url: URL?

    var body: some View {
        KFImage(url)
            .placeholder { Rectangle().fill(Color.secondary.opacity(0.3)) }
            .fade(duration: 0.2)
            .resizable()
            .aspectRatio(2/3, contentMode: .fill)
            .coverAspectSized()
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
