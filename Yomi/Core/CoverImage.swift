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
            .coverSized()
            .keiyoushiCoverFallback(url)
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
    /// The faint 0.5 pt outline Apple Music puts around artwork, so dark or white covers
    /// keep their edge on a matching background (S138, RESEARCH §26).
    func coverHairline(cornerRadius: CGFloat = YomiTokens.Radius.cover) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
    }

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

extension KFImage {
    /// Covers never show larger than a ~160 × 240 pt grid cell (the detail backdrop is blurred), but sources ship
    /// them at up to 5 MB / several megapixels. Full-size images were decoded on the main thread at render time
    /// (Kingfisher stores WebP in its disk cache as PNG and hands back an undecoded image) — the two hangs in the
    /// S134 Browse trace. Downsample to display size and decode off the main thread.
    /// KFImage also reads disk-cache hits synchronously by default, which ran that read + decode on main anyway
    /// (S135 trace: two ~270 ms hangs in `retrieveImageInDiskCache`); a disk hit now shows the placeholder for a frame.
    func coverSized() -> KFImage {
        setProcessor(DownsamplingImageProcessor(size: CGSize(width: 180, height: 270)))
            .scaleFactor(UITraitCollection.current.displayScale)
            .backgroundDecode()
            .loadDiskFileSynchronously(false)
    }

    /// Reader pages keep full resolution (pinch-zoom up to 4× on detailed art), so no downsampling. What cost the
    /// S136 Asura reader two ~330 ms hangs was elsewhere: `DefaultCacheSerializer` re-encodes any format it
    /// doesn't know — WebP — as PNG before writing the disk cache (`deflate` on several threads), and pages were
    /// decoded at render time. Store the downloaded bytes as-is (iOS decodes WebP natively), decode off main, and
    /// read disk hits asynchronously.
    func readerPage() -> KFImage {
        serialize(by: Self.originalDataSerializer)
            .backgroundDecode()
            .loadDiskFileSynchronously(false)
    }

    /// The same options for code that loads a reader page itself (`StripPageImage`, S145).
    static let readerPageOptions: KingfisherOptionsInfo = [.cacheSerializer(originalDataSerializer), .backgroundDecode]

    private static let originalDataSerializer: DefaultCacheSerializer = {
        var serializer = DefaultCacheSerializer()
        serializer.preferCacheOriginalData = true
        return serializer
    }()
}
