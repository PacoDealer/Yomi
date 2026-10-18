import SwiftUI
import StoreKit
import Kingfisher

/// Split out of ChapterReaderView.swift (S183, #106): the paged readers (horizontal + vertical) and their single-page view.

// MARK: - MangaReaderView

struct MangaReaderView: View {
    let pages: [String]
    @Binding var currentPage: Int
    @Binding var showOverlay: Bool
    var isRTL: Bool = true

    @State private var settings = AppSettings.shared
    @State private var viewportIsLandscape = false
    @State private var isZoomed = false
    @State private var viewSize: CGSize = .zero

    // MARK: - Double-page spreads
    //
    // "double"/"automatic" group pages into spreads (`PageSpreads`, F17: cover alone, wide pages alone, shapes must
    // match). currentPage keeps its normal meaning everywhere else (progress, resume, scrubber) — it's just an index
    // into `pages`. TabView only ever selects/produces spread-start indices via `spreadSelection`, a proxy binding
    // that snaps any raw page index down to the start of its enclosing spread. Groups change as page shapes are
    // learned; the page on screen stays on screen.

    private var isDoubleActive: Bool {
        switch settings.pageLayout {
        case "double":    return true
        case "automatic": return viewportIsLandscape
        default:          return false
        }
    }

    private var spreadGroups: [[Int]] {
        guard isDoubleActive, pages.count > 1 else { return pages.indices.map { [$0] } }
        _ = PageShapes.changes.count   // re-pair when a shape is learned
        return PageSpreads.groups(count: pages.count, aspect: { PageShapes.aspect(pages[$0]).map(Double.init) },
                                  coverAlone: settings.doublePageCoverAlone)
    }

    private func spreadStart(for page: Int) -> Int {
        spreadGroups.first(where: { $0.contains(page) })?.first ?? page
    }

    private var spreadSelection: Binding<Int> {
        Binding(
            get: { spreadStart(for: currentPage) },
            set: { currentPage = $0 }
        )
    }

    var body: some View {
        ZStack {
            TabView(selection: spreadSelection) {
                ForEach(spreadGroups, id: \.self) { group in
                    spreadContent(group)
                        .tag(group.first!)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .scrollDisabled(isZoomed)   // zoomed in: one finger pans the page instead of turning it
            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
            .ignoresSafeArea()
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { viewportIsLandscape = geo.size.width > geo.size.height }
                        .onChange(of: geo.size) { _, newSize in
                            viewportIsLandscape = newSize.width > newSize.height
                        }
                }
            }

        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
        .onTapGesture(coordinateSpace: .local) { handleTap(at: $0, in: viewSize) }
        .onChange(of: currentPage) { _, _ in isZoomed = false }
        // Shapes of downloaded pages (and web pages already cached) before they're reached, so spreads pair right.
        .task(id: isDoubleActive ? pages : []) { if isDoubleActive { await PageShapes.learn(pages) } }
    }

    @ViewBuilder
    private func spreadContent(_ group: [Int]) -> some View {
        if group.count == 2 {
            // "Invert double pages" (L3c): the pair swaps sides; reading order (and `currentPage`) stays the same.
            let (first, second) = settings.doublePageInvert ? (group[1], group[0]) : (group[0], group[1])
            HStack(spacing: 0) {
                MangaPageView(url: pages[first], isZoomed: $isZoomed).readerPageMenu(url: pages[first])
                MangaPageView(url: pages[second], isZoomed: $isZoomed).readerPageMenu(url: pages[second])
            }
        } else {
            MangaPageView(url: pages[group[0]], isZoomed: $isZoomed).readerPageMenu(url: pages[group[0]])
        }
    }

    // MARK: - Tap zone actions
    //
    // Moves by a whole spread (1 or 2 pages) so it always lands on a valid TabView tag.

    private func moveSpread(forward: Bool) {
        let groups = spreadGroups
        guard let idx = groups.firstIndex(where: { $0.first == spreadStart(for: currentPage) }) else { return }
        let targetIdx = forward ? min(idx + 1, groups.count - 1) : max(idx - 1, 0)
        let next = groups[targetIdx].first!
        if next != currentPage {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withMotion(.easeInOut(duration: 0.3)) { currentPage = next }   // slide, like novel Pages mode
        }
    }

    private func tapMenu() {
        withMotion(.easeInOut(duration: 0.2)) { showOverlay.toggle() }
    }

    // MARK: - Tap zones
    //
    // Resolved from the tap location instead of an overlay of tap views: an overlay sits on top of
    // the pages and swallows pinch + swipe (#200 — pinch never worked on device). Geometry: `ReaderTapZones.paged`.

    private func handleTap(at p: CGPoint, in size: CGSize) {
        // Zoomed in: a tap zooms back out rather than turning the page under your finger.
        if isZoomed { withMotion(.spring(duration: 0.3)) { isZoomed = false }; return }
        switch ReaderTapZones.paged(settings.tapZoneLayout, at: p, in: size, isRTL: isRTL) {
        case .back:    moveSpread(forward: false)
        case .forward: moveSpread(forward: true)
        case .menu:    tapMenu()
        }
    }
}

// MARK: - MangaPageView (single page with pinch-to-zoom; tap zooms back out)

private struct MangaPageView: View {
    let url: String
    /// Shared with the reader: true while this page is pinched in (TabView paging is off); the reader sets it
    /// back to false on a tap or a page change, which zooms the page out.
    @Binding var isZoomed: Bool

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var loadFailed = false
    @State private var attempt = 0
    @State private var settings = AppSettings.shared
    /// Margins + background colour (F17), from `PageLooks`; nil until the page has been measured.
    @State private var look: PageLook?
    /// Loaded and being measured: hidden for that moment when cropping, so the margins don't flash before the crop.
    @State private var measuring = false
    /// Shows the page again (from cache) so a setting turned on mid-chapter measures the page on screen.
    @State private var reload = 0

    var body: some View {
        GeometryReader { geo in
            // KFImage, not AsyncImage: page hosts behind Cloudflare (e.g. AquaManga) need the same
            // UA-matching requestModifier YomiApp.swift registers globally on KingfisherManager —
            // AsyncImage uses a bare URLSession with no way to attach that, so it 403s silently.
            Group {
                if loadFailed {
                    PageRetryButton { attempt = 0; loadFailed = false }
                } else {
                    KFImage(source: PageNames.source(url))
                        .readerPage()
                        .placeholder {
                            ProgressView()
                                .tint(ReaderBackdrop.isLight(settings.readerBackground) ? .black : .white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .onSuccess { result in
                            let size = result.image.size
                            if size.height > 0 { PageShapes.remember(url, size.width / size.height) }
                            guard look == nil, settings.cropBorders || settings.readerBackground == "automatic" else { return }
                            let page = url
                            measuring = true
                            Task {
                                let measured = await PageLooks.look(for: page, image: result.image)
                                if page == url { look = measured }
                                measuring = false
                            }
                        }
                        .onFailure { _ in
                            Task {
                                if await PageRetry.shouldRetry(url, attempt: attempt) { attempt += 1 } else { loadFailed = true }
                            }
                        }
                        .resizable()
                        .modifier(PageCrop(crop: settings.cropBorders ? look?.crop : nil, aspect: PageShapes.aspect(url)))
                        .opacity(settings.cropBorders && measuring ? 0 : 1)
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .id("\(attempt)-\(reload)")
            .onChange(of: url) { _, new in loadFailed = false; attempt = 0; look = PageLooks.cached(new) }
            .onChange(of: settings.cropBorders) { if look == nil { reload += 1 } }
            .onChange(of: settings.readerBackground) { if look == nil { reload += 1 } }
            .onAppear { if look == nil { look = PageLooks.cached(url) } }
            .background { pageBackground(landscape: geo.size.width > geo.size.height) }
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = min(max(lastScale * value.magnification, 1.0), 4.0)
                        // Zoom around the fingers, not the page centre: keep the content point that was under the
                        // pinch's start location under it. Position on screen = centre + point * scale + offset.
                        let f = CGPoint(x: value.startLocation.x - geo.size.width / 2,
                                        y: value.startLocation.y - geo.size.height / 2)
                        let px = (f.x - lastOffset.width) / lastScale, py = (f.y - lastOffset.height) / lastScale
                        offset = clamped(CGSize(width: f.x - px * scale, height: f.y - py * scale), in: geo.size)
                        if scale > 1.0, !isZoomed { isZoomed = true }
                    }
                    .onEnded { _ in
                        lastScale = scale
                        lastOffset = offset
                        if scale <= 1.0 { resetZoom() }
                    },
                including: settings.readerPinchZoom ? .all : .subviews
            )
            // Pan only while zoomed: a drag gesture on the page at 1x steals the page swipe from the TabView.
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        offset = clamped(CGSize(width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height), in: geo.size)
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    },
                including: isZoomed ? .all : .subviews
            )
            .onChange(of: isZoomed) { _, zoomed in
                if !zoomed { withMotion(.spring(duration: 0.3)) { resetZoom() } }
            }
        }
    }

    /// The reader's background colour; "Automatic" uses the page's own margins once it has been measured (F17).
    @ViewBuilder private func pageBackground(landscape: Bool) -> some View {
        if settings.readerBackground == "automatic", let look {
            ReaderBackdrop.view(landscape ? look.landscape : look.portrait)
        } else {
            ReaderBackdrop.base(settings.readerBackground)
        }
    }

    /// Keeps the zoomed page covering the screen: no panning past its edges.
    private func clamped(_ o: CGSize, in size: CGSize) -> CGSize {
        let maxX = (scale - 1) * size.width / 2, maxY = (scale - 1) * size.height / 2
        return CGSize(width: min(max(o.width, -maxX), maxX), height: min(max(o.height, -maxY), maxY))
    }

    private func resetZoom() {
        scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero
        isZoomed = false
    }
}


// MARK: - VerticalPagedReaderView

struct VerticalPagedReaderView: View {
    let pages: [String]
    @Binding var currentPage: Int
    @Binding var showOverlay: Bool
    @State private var isZoomed = false
    @State private var settings = AppSettings.shared
    @State private var viewSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, url in
                    MangaPageView(url: url, isZoomed: $isZoomed)
                        .readerPageMenu(url: url)
                        .frame(width: geo.size.height, height: geo.size.width)
                        .rotationEffect(.degrees(-90))
                        .tag(index)
                }
            }
            .frame(width: geo.size.height, height: geo.size.width)
            .rotationEffect(.degrees(90))
            .frame(width: geo.size.width, height: geo.size.height)
            .tabViewStyle(.page(indexDisplayMode: .never))
            .scrollDisabled(isZoomed)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
        // Paged tap zones here too (F16; before, every tap only showed the menu). Left side = previous page.
        .onTapGesture(coordinateSpace: .local) { p in
            if isZoomed { isZoomed = false; return }
            switch ReaderTapZones.paged(settings.tapZoneLayout, at: p, in: viewSize, isRTL: false) {
            case .back:    step(-1)
            case .forward: step(1)
            case .menu:    withMotion(.easeInOut(duration: 0.2)) { showOverlay.toggle() }
            }
        }
        .onChange(of: currentPage) { _, _ in isZoomed = false }
    }

    private func step(_ delta: Int) {
        let target = min(max(currentPage + delta, 0), pages.count - 1)
        guard target != currentPage else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withMotion(.easeInOut(duration: 0.3)) { currentPage = target }
    }
}
