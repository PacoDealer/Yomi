import SwiftUI
import StoreKit
import Kingfisher

/// Split out of ChapterReaderView.swift (S183, #106): the scrolling readers (webtoon strip, continuous horizontal), chapter boundary card, zoom, and page loading/retry.

// MARK: - WebtoonReaderView

struct WebtoonReaderView: View {
    let pages: [String]
    /// The active chapter's id. Page ids include it (#254), so a page keeps its identity when it moves from
    /// "next chapter" to "current chapter" at a crossing.
    let chapterKey: String
    @Binding var currentPage: Int
    @Binding var showOverlay: Bool
    var nextChapter: Chapter? = nil
    var nextPages: [String] = []
    var boundaryTitles: (finished: String, next: String)? = nil
    var onNeedsNextChapterPreload: (() -> Void)? = nil
    var onCrossedIntoNextChapter: ((Int) -> Void)? = nil

    @State private var visibleId: String? = nil
    @State private var isAutoScrolling = false
    /// When auto-scroll turns itself off (Settings → "Stop auto-scroll after"); nil = runs until stopped.
    @State private var autoScrollEnds: Date? = nil
    @State private var settings = AppSettings.shared
    @State private var scroller = StripScroller()
    /// Last page the strip reported, from either source (`scrollPosition` or visibility) — reported once.
    @State private var observedId: String? = nil
    @State private var viewSize: CGSize = .zero
    @GestureState private var isHolding = false
    /// Chapters already scrolled through in this reader session (#254, Mihon's webtoon model). They stay above the
    /// current chapter so a crossing never removes or rebuilds anything on screen: the next chapter's pages were
    /// already in the list under the same ids and simply become "current". Off-screen pages drop their images
    /// (`StripPageImage.onDisappear`), so this costs little. Cleared when the reader jumps to a chapter instead.
    @State private var earlier: [StripSegment] = []
    /// The chapter a crossing is moving to, until the parent switches `chapterKey` to it.
    @State private var crossingTo: String? = nil

    private var nextKey: String? { nextChapter.map { "\($0.id)" } }

    /// Everything in the strip, top to bottom, with ids that never change for the same page.
    private var items: [StripItem] {
        var out: [StripItem] = []
        for segment in earlier where segment.key != chapterKey {
            out += segment.pages.enumerated().map { StripItem(id: Self.pageId(segment.key, $0.offset), url: $0.element) }
            out.append(StripItem(id: "b\(segment.key)", boundary: (segment.finished, segment.next)))
        }
        out += pages.enumerated().map { StripItem(id: Self.pageId(chapterKey, $0.offset), url: $0.element) }
        if let boundaryTitles, let nextKey {
            out.append(StripItem(id: "b\(chapterKey)", boundary: boundaryTitles))
            out += nextPages.enumerated().map { StripItem(id: Self.pageId(nextKey, $0.offset), url: $0.element) }
        }
        return out
    }

    nonisolated static func pageId(_ key: String, _ index: Int) -> String { "p\(key):\(index)" }

    /// (chapter key, page index) from a page id; nil for boundary cards.
    nonisolated static func parse(_ id: String) -> (key: String, index: Int)? {
        guard id.hasPrefix("p"), let colon = id.lastIndex(of: ":"), let index = Int(id[id.index(after: colon)...])
        else { return nil }
        return (String(id[id.index(after: id.startIndex)..<colon]), index)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: settings.readerScrollIndicator) {
                LazyVStack(spacing: 0) {
                    // One ForEach over stable ids: a page that moves from the next chapter to the current one is the
                    // same view (two ForEach blocks made SwiftUI rebuild it and reload its image at the crossing).
                    ForEach(items) { item in
                        if let url = item.url {
                            pageImage(url).id(item.id)
                        } else if let titles = item.boundary {
                            ChapterBoundaryCard(finishedTitle: titles.finished, nextTitle: titles.next, axis: .vertical)
                                .id(item.id)
                        }
                    }
                }
                .padding(.horizontal, CGFloat(settings.webtoonHorizontalPadding))
                .scrollTargetLayout()
                .background(EnclosingScrollViewFinder { scroller.scrollView = $0 })
            }
            .scrollPosition(id: $visibleId, anchor: .top)
            // `scrollPosition(id:)` only follows the reader's own finger; tap zones and scroll-while-held move the
            // scroll view in code and it never updates (F16, sim). Visibility does — used only then: at rest a sliver
            // of the previous page under the status bar counts as visible, one page before the `.top` anchor's.
            .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.01) { ids in
                guard scroller.isDriving else { return }
                let parsed = ids.compactMap(Self.parse)
                func top(_ key: String?) -> Int? { parsed.filter { $0.key == key }.map(\.index).min() }
                if let page = top(chapterKey) { observe(Self.pageId(chapterKey, page)) }
                else if let nextKey, let page = top(nextKey) { observe(Self.pageId(nextKey, page)) }
            }
            .onAppear {
                if currentPage > 0 {
                    proxy.scrollTo(Self.pageId(chapterKey, currentPage), anchor: .top)
                }
            }
            .onChange(of: visibleId) { _, id in
                if let id { observe(id) }
            }
            .onChange(of: chapterKey) { _, key in
                // A crossing keeps the chapters above; any other chapter change (Next button, chapter list) starts over.
                if key != crossingTo { earlier = [] }
                crossingTo = nil
            }
            .onChange(of: currentPage) { _, new in
                // Two-way sync with the overlay's progress slider — scrolling
                // updates currentPage above, this reflects slider drags back
                // into the scroll position. Guarded so it's a no-op when the
                // change originated from the scroll itself (including a crossing).
                let newId = Self.pageId(chapterKey, new)
                guard newId != visibleId, newId != observedId else { return }
                withMotion { proxy.scrollTo(newId, anchor: .top) }
            }
        }
        .modifier(ReaderZoom(scrollAxis: .vertical, pinchEnabled: settings.readerPinchZoom && !isHolding))
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
        .onTapGesture(coordinateSpace: .local) { p in
            switch ReaderTapZones.strip(settings.stripTapZoneLayout, at: p, in: viewSize) {
            case .back:    scroller.page(by: -0.75)
            case .forward: scroller.page(by: 0.75)
            case .menu:    withMotion(.easeInOut(duration: 0.2)) { showOverlay.toggle() }
            }
        }
        // Long press (F16): auto-scroll on/off (the pre-F16 behaviour, default) · scroll while held · page menu
        // (on each page, see `pageImage`). Only the chosen gesture is live.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6)
                .onEnded { _ in
                    withMotion(.easeInOut(duration: 0.2)) { isAutoScrolling.toggle() }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                },
            including: settings.stripLongPress == "autoScroll" ? .all : .subviews
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .updating($isHolding) { value, state, _ in
                    if case .second(true, _) = value { state = true }
                },
            including: settings.stripLongPress == "hold" ? .all : .subviews
        )
        .onChange(of: isHolding) { _, holding in
            if holding { scroller.startHold() } else { scroller.stopHold() }
        }
        .overlay(alignment: .bottom) {
            if isAutoScrolling {
                Label {
                    if let autoScrollEnds, autoScrollEnds > .now {
                        Text("Auto-scroll · \(Text(timerInterval: Date.now...autoScrollEnds, countsDown: true))")
                            .monospacedDigit()
                    } else {
                        Text("Auto-scroll")
                    }
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 60)
                    .transition(Motion.pop)
            }
        }
        .motion(.easeInOut(duration: 0.2), value: isAutoScrolling)
        .task(id: isAutoScrolling) {
            guard isAutoScrolling else { autoScrollEnds = nil; return }
            let minutes = settings.autoScrollStopMinutes
            autoScrollEnds = minutes > 0 ? Date.now.addingTimeInterval(Double(minutes) * 60) : nil
            while !Task.isCancelled && isAutoScrolling {
                try? await Task.sleep(for: .milliseconds(Int(settings.autoScrollSpeed * 1000)))
                guard !Task.isCancelled && isAutoScrolling else { break }
                if let ends = autoScrollEnds, Date.now >= ends {
                    withMotion(.easeInOut(duration: 0.2)) { isAutoScrolling = false }
                    break
                }
                guard let cur = visibleId.flatMap(Self.parse), cur.key == chapterKey else { break }
                let nextIdx = cur.index + 1
                guard nextIdx < pages.count else { isAutoScrolling = false; break }
                visibleId = Self.pageId(chapterKey, nextIdx)
            }
        }
        .onDisappear { isAutoScrolling = false; scroller.stopHold() }
    }

    private func observe(_ id: String) {
        guard id != observedId, let (key, idx) = Self.parse(id) else { return }
        observedId = id
        if key == chapterKey {
            currentPage = idx
            if nextChapter == nil, pages.count > 0, idx >= pages.count - 3 {
                onNeedsNextChapterPreload?()
            }
        } else if key == nextKey, let boundaryTitles {
            // Keep the chapter being left above, in the same update as the parent's switch, so nothing on screen
            // changes. Earlier chapters (scrolled back up into) don't change the active chapter.
            earlier.append(StripSegment(key: chapterKey, pages: pages,
                                        finished: boundaryTitles.finished, next: boundaryTitles.next))
            crossingTo = key
            onCrossedIntoNextChapter?(idx)
        }
    }

    private func pageImage(_ url: String) -> some View {
        StripPageImage(url: url, axis: .vertical)
            .readerPageMenu(url: url, enabled: settings.stripLongPress == "pageMenu")
    }
}

/// A chapter already read past in the long strip (see `WebtoonReaderView.earlier`).
struct StripSegment {
    let key: String
    let pages: [String]
    let finished: String
    let next: String
}

/// One row of the long strip: a page, or the card between two chapters.
struct StripItem: Identifiable {
    let id: String
    var url: String? = nil
    var boundary: (finished: String, next: String)? = nil
}

// MARK: - ChapterBoundaryCard
//
// The Tachimanga-style mid-scroll transition marker: rendered directly inside the reader's
// scroll content (not a floating overlay) so continuous/webtoon reading flows straight from one
// chapter into the next with no tap.

struct ChapterBoundaryCard: View {
    let finishedTitle: String
    let nextTitle: String
    enum Axis { case vertical, horizontal }
    var axis: Axis = .vertical

    var body: some View {
        Group {
            switch axis {
            case .vertical:
                content.frame(maxWidth: .infinity).padding(.vertical, 40)
            case .horizontal:
                content.frame(width: 220).frame(maxHeight: .infinity)
            }
        }
        .background(Color.black)
    }

    private var content: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Finished: \(finishedTitle)")
                    .font(YomiTokens.Font.mono(12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 40, height: 1)

            Text("Current: \(nextTitle)")
                .font(YomiTokens.Font.grotesk(17, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - ReaderZoom
//
// Pinch-zoom for the scrolling modes (webtoon, continuous; #200). The whole scroll view is scaled, so scrolling keeps
// working while zoomed; the pinch anchors at the fingers (PacoDealer S149: zoom wherever you want), one finger pans across
// the scroll direction, a tap zooms back out.

struct ReaderZoom: ViewModifier {
    let scrollAxis: Axis
    /// Off: no pinch (Settings → Pinch to zoom, or long strip while a finger holds it scrolling — L3c).
    var pinchEnabled = true

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var size: CGSize = .zero

    private var isZoomed: Bool { scale > 1.01 }

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = min(max(lastScale * value.magnification, 1), 4)
                        // Keep the point that was under the fingers under them: screen = centre + point * scale + offset.
                        let fx = value.startLocation.x - size.width / 2, fy = value.startLocation.y - size.height / 2
                        let px = (fx - lastOffset.width) / lastScale, py = (fy - lastOffset.height) / lastScale
                        offset = clamped(CGSize(width: fx - px * scale, height: fy - py * scale))
                    }
                    .onEnded { _ in
                        lastScale = scale
                        lastOffset = offset
                        if !isZoomed { reset() }
                    },
                including: pinchEnabled ? .all : .subviews
            )
            // Across the scroll direction only; along it, the scroll view itself moves.
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        var o = lastOffset
                        if scrollAxis == .vertical { o.width += value.translation.width } else { o.height += value.translation.height }
                        offset = clamped(o)
                    }
                    .onEnded { _ in lastOffset = offset },
                including: isZoomed ? .all : .subviews
            )
            .gesture(TapGesture().onEnded { withMotion(.spring(duration: 0.3)) { reset() } },
                     including: isZoomed ? .all : .subviews)
    }

    private func clamped(_ o: CGSize) -> CGSize {
        let maxX = (scale - 1) * size.width / 2, maxY = (scale - 1) * size.height / 2
        return CGSize(width: min(max(o.width, -maxX), maxX), height: min(max(o.height, -maxY), maxY))
    }

    private func reset() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }
}

// MARK: - ContinuousHorizontalReaderView

struct ContinuousHorizontalReaderView: View {
    let pages: [String]
    @Binding var currentPage: Int
    @Binding var showOverlay: Bool
    var isRTL: Bool = false
    var nextChapter: Chapter? = nil
    var nextPages: [String] = []
    var boundaryTitles: (finished: String, next: String)? = nil
    var onNeedsNextChapterPreload: (() -> Void)? = nil
    var onCrossedIntoNextChapter: ((Int) -> Void)? = nil

    @State private var visibleId: String? = nil
    @State private var settings = AppSettings.shared
    @State private var viewSize: CGSize = .zero

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: settings.readerScrollIndicator) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, url in
                        pageImage(url)
                            .id("cur:\(index)")
                    }
                    if let boundaryTitles {
                        ChapterBoundaryCard(finishedTitle: boundaryTitles.finished, nextTitle: boundaryTitles.next, axis: .horizontal)
                            .id("boundary")
                        ForEach(Array(nextPages.enumerated()), id: \.offset) { index, url in
                            pageImage(url)
                                .id("next:\(index)")
                        }
                    }
                }
                .scrollTargetLayout()
            }
            // RTL on the ScrollView itself, not just its stack: with only the stack flipped the scroll view
            // still starts at its left edge = the LAST page (#198).
            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
            .scrollPosition(id: $visibleId, anchor: .center)
            .onAppear {
                if currentPage > 0 {
                    visibleId = "cur:\(currentPage)"
                }
            }
            .onChange(of: visibleId) { _, id in
                guard let id else { return }
                if id.hasPrefix("cur:"), let idx = Int(id.dropFirst(4)) {
                    currentPage = idx
                    if nextChapter == nil, pages.count > 0, idx >= pages.count - 3 {
                        onNeedsNextChapterPreload?()
                    }
                } else if id.hasPrefix("next:"), let idx = Int(id.dropFirst(5)) {
                    onCrossedIntoNextChapter?(idx)
                }
            }
            .onChange(of: currentPage) { _, new in
                let newId = "cur:\(new)"
                guard newId != visibleId else { return }
                withMotion { proxy.scrollTo(newId, anchor: .center) }
            }
        }
        .modifier(ReaderZoom(scrollAxis: .horizontal, pinchEnabled: settings.readerPinchZoom))
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
        // One page per screen, so tap zones step a page (strip zones, F16); the scroll follows `currentPage`.
        .onTapGesture(coordinateSpace: .local) { p in
            switch ReaderTapZones.strip(settings.stripTapZoneLayout, at: p, in: viewSize, isRTL: isRTL) {
            case .back:    step(-1)
            case .forward: step(1)
            case .menu:    withMotion(.easeInOut(duration: 0.2)) { showOverlay.toggle() }
            }
        }
    }

    private func step(_ delta: Int) {
        let target = min(max(currentPage + delta, 0), pages.count - 1)
        guard target != currentPage else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        currentPage = target
    }

    private func pageImage(_ url: String) -> some View {
        // Fit each page inside the screen. Height-only fit made a portrait page ~1.5x wider than a phone, so
        // the sides were cut off (#199).
        StripPageImage(url: url, axis: .horizontal)
            .readerPageMenu(url: url)
            .containerRelativeFrame([.horizontal, .vertical])
    }
}


// MARK: - Page load retry (S144)

/// After a page fails to load: a Keiyoushi page waits until the bridge serves again (it stops while Yomi is in the
/// background and comes back on a new port — PacoDealer: "the first page appeared and the rest did not load"), any
/// other page gets a short pause for a network blip. Then it's tried again, up to 3 times, before showing Retry.
enum PageRetry {
    /// Posted with the page URL on a page's first failure; the reader refetches the list if it came from the cache.
    static let pageFailed = Notification.Name("YomiReaderPageFailed")

    static func shouldRetry(_ url: String, attempt: Int) async -> Bool {
        guard attempt < 3 else { return false }
        if attempt == 0 { NotificationCenter.default.post(name: pageFailed, object: url) }
        // Not while Yomi is in the background: iOS suspends us there, and the attempts would be used up for nothing.
        while UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(500))
        }
        if KeiyoushiBridge.isBridgeImage(URL(string: url)) {
            return (try? await KeiyoushiBridge.shared.servingPort()) != nil
        }
        try? await Task.sleep(for: .seconds(Double(attempt + 1)))
        return true
    }
}

/// A page that gave up: tap to load it again.
struct PageRetryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.title2)
                Text("Page didn't load · Tap to retry")
                    .font(.footnote)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


/// One page in the long strip / continuous horizontal readers. Used to stay a grey placeholder forever on failure.
/// Loads through KingfisherManager itself instead of KFImage (S145): a very tall page must never reach the screen
/// in one piece, and KFImage could show it without calling `onSuccess`, so the strips weren't always made.
private struct StripPageImage: View {
    let url: String
    let axis: Axis
    @State private var attempt = 0
    @State private var failed = false
    @State private var pieces: [UIImage]? = nil
    @State private var settings = AppSettings.shared

    var body: some View {
        page.onChange(of: url) { pieces = nil; failed = false; attempt = 0 }
            .onChange(of: settings.cropBordersStrip) { pieces = nil }   // load again, cut (or not)
    }

    /// The crop this page is drawn with (F17, long strip + continuous), when known.
    private var crop: CGRect? { settings.cropBordersStrip ? PageLooks.cached(url)?.crop : nil }

    @ViewBuilder private var page: some View {
        if failed {
            PageRetryButton { attempt = 0; failed = false }
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(maxWidth: axis == .vertical ? .infinity : nil, maxHeight: axis == .horizontal ? .infinity : nil)
        } else if let pieces {
            let layout = axis == .vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                ForEach(pieces.indices, id: \.self) { i in
                    Image(uiImage: pieces[i])
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(maxWidth: axis == .vertical ? .infinity : nil, maxHeight: axis == .horizontal ? .infinity : nil)
            // A decoded 900x16000 Asura page is ~57 MB and the lazy stack kept every page it had built until the
            // reader closed (S160, sim: 20 pages took the app from 908 MB to 1,964 MB). Let go of it off screen; the
            // placeholder keeps the page's size and the page loads again from cache on the way back.
            .onDisappear { self.pieces = nil }
        } else {
            placeholder
                .task(id: LoadKey(url: url, attempt: attempt, crop: settings.cropBordersStrip)) { await load() }
        }
    }

    /// A refetched list (D12b) gives the same slot a new URL: start that page over. Done here and NOT with `.id(url)`
    /// on the page: a second id inside the strip's page id hid it from `scrollPosition`, so the current page
    /// never changed while scrolling (found S168 — counter stuck, saved position too).
    private struct LoadKey: Equatable { let url: String; let attempt: Int; let crop: Bool }

    /// The lazy stack throws a page's state away once it is far off screen, so scrolling back meets a placeholder
    /// again. It must be exactly as big as the page was, or everything below it jumps (a long-strip page is ~10x
    /// taller than the old 2:3 box: pages seemed to skip, and scrolling up fought back — PacoDealer, S151).
    @ViewBuilder private var placeholder: some View {
        let box = Rectangle().fill(Color.gray.opacity(0.2))
        if let aspect = PageShapes.aspect(url) {
            // The page as it will be drawn, cropped or not.
            box.aspectRatio(crop.map { aspect * $0.width / $0.height } ?? aspect, contentMode: .fit)
                .frame(maxWidth: axis == .vertical ? .infinity : nil, maxHeight: axis == .horizontal ? .infinity : nil)
        } else if axis == .vertical {
            // Never seen: a full screen, so a flick can't pass several unloaded pages that then grow behind you.
            box.containerRelativeFrame(.vertical)
                .frame(maxWidth: .infinity)
                .overlay { ProgressView().tint(.white) }
        } else {
            box.aspectRatio(2 / 3, contentMode: .fit)
                .frame(maxHeight: .infinity)
        }
    }

    private func load() async {
        guard let source = PageNames.source(url) else { failed = true; return }
        do {
            let result = try await KingfisherManager.shared.retrieveImage(with: source, options: KFImage.readerPageOptions)
            var image = result.image
            if image.size.height > 0 { PageShapes.remember(url, image.size.width / image.size.height) }
            if settings.cropBordersStrip, let rect = await PageLooks.look(for: url, image: image).crop, let cg = image.cgImage {
                let source = image
                image = await Task.detached(priority: .userInitiated) {
                    UIImage(cgImage: cg.cropped(to: rect), scale: source.scale, orientation: source.imageOrientation)
                }.value
            }
            let vertical = axis == .vertical
            let page = image
            let cut = await Task.detached(priority: .userInitiated) { vertical ? Self.strips(of: page) : nil }.value
            if Task.isCancelled { return }
            pieces = cut ?? [image]
        } catch {
            if Task.isCancelled { return }   // scrolled away; .task starts again when the page comes back
            if await PageRetry.shouldRetry(url, attempt: attempt) { attempt += 1 } else { failed = true }
        }
    }

    /// A very tall page drawn as one view is taller than the GPU can draw and shows up BLACK (S145: Keiyoushi's
    /// Asura extension stitches each chapter part into one 900x16000 image = 21,000+ px on screen). Cut it into
    /// strips. Each strip is drawn into its own bitmap: a plain `cropping` crop of an ImageIO-backed page made
    /// ImageIO decode every strip AGAIN into buffers of its own that outlived the views (S160: 20 pages = 1.3 GB
    /// of ImageIO memory). Copied strips are freed with the view; the source page is left to Kingfisher's cache.
    nonisolated static func strips(of image: UIImage) -> [UIImage]? {
        guard let cg = image.cgImage, cg.height > 4096 else { return nil }
        let step = 2048
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        return stride(from: 0, to: cg.height, by: step).compactMap { y in
            let height = min(step, cg.height - y)
            guard let crop = cg.cropping(to: CGRect(x: 0, y: y, width: cg.width, height: height)),
                  let context = CGContext(data: nil, width: cg.width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: cg.width, height: height))
            return context.makeImage().map { UIImage(cgImage: $0, scale: image.scale, orientation: image.imageOrientation) }
        }
    }
}
