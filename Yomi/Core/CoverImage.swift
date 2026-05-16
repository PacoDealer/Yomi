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
    }
}
