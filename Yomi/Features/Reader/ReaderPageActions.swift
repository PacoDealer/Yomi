import SwiftUI
import UIKit
import Photos
import Kingfisher

// MARK: - Reader tap zones (F16)
//
// Paged modes (right to left, left to right, vertical pages) and strip modes (long strip, continuous) have
// their own setting (Tachimanga v5, S142 backlog): a strip reader moves by scrolling, so the paged presets
// (thirds, Kindle…) don't map onto it.

enum ReaderTapZones {
    enum Action { case back, forward, menu }

    /// Paged layouts (`AppSettings.tapZoneLayout`). "Left"/"right" are physical screen sides: `isRTL` flips which
    /// one goes forward.
    static func paged(_ layout: String, at p: CGPoint, in size: CGSize, isRTL: Bool) -> Action {
        let w = size.width, h = size.height
        let left: Bool
        switch layout {
        case "disabled":
            return .menu
        case "lShaped":   // left column + bottom band go "left", top strip = menu, rest "right"
            if p.y < h * 0.12 { return .menu }
            left = p.x < w * 0.28 || p.y > h * 0.82
        case "kindle", "rightLeft":   // top strip = menu; thin left strip (Kindle) or half (Right-and-Left)
            if p.y < h * 0.12 { return .menu }
            left = p.x < w * (layout == "kindle" ? 0.2 : 0.5)
        default:          // "default" equal thirds / "sides" a.k.a. Edge (20 · 60 · 20)
            let edge: CGFloat = layout == "sides" ? 0.2 : 1.0 / 3.0
            if p.x < w * edge { left = true }
            else if p.x > w * (1 - edge) { left = false }
            else { return .menu }
        }
        return left == isRTL ? .forward : .back
    }

    /// Strip layouts (`AppSettings.stripTapZoneLayout`): "disabled" (every tap shows the menu) · "lShaped" (Mihon's
    /// LNavigation: top band + left middle go back, bottom band + right middle go forward, centre = menu) ·
    /// "topBottom" (top third back, bottom third forward). `isRTL` mirrors the L for right-to-left continuous.
    static func strip(_ layout: String, at p: CGPoint, in size: CGSize, isRTL: Bool = false) -> Action {
        guard size.width > 0, size.height > 0 else { return .menu }
        let x = isRTL ? 1 - p.x / size.width : p.x / size.width, y = p.y / size.height
        switch layout {
        case "lShaped":
            if y < 1.0 / 3.0 { return .back }
            if y > 2.0 / 3.0 { return .forward }
            if x < 1.0 / 3.0 { return .back }
            if x > 2.0 / 3.0 { return .forward }
            return .menu
        case "topBottom":
            if y < 1.0 / 3.0 { return .back }
            if y > 2.0 / 3.0 { return .forward }
            return .menu
        default:
            return .menu
        }
    }
}

// MARK: - StripScroller
//
// Offset-level control of the long strip's scroll view: tap zones move by most of a screen and "scroll while held"
// moves it smoothly every frame. SwiftUI's `scrollPosition(id:)` (which the strip already uses for the current page)
// only jumps to views, so the backing UIScrollView is looked up once and driven directly; its delegate still tells
// SwiftUI, so the current page keeps updating.

@MainActor
final class StripScroller {
    weak var scrollView: UIScrollView?
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var drivenUntil: CFTimeInterval = 0

    /// True while the strip moves because of code (hold, or a tap-zone scroll still animating) rather than a finger.
    var isDriving: Bool { link != nil || CACurrentMediaTime() < drivenUntil }

    /// Moves by `fraction` of the visible height (negative = up), clamped to the content.
    func page(by fraction: CGFloat) {
        guard let sv = scrollView else { return }
        let target = clampedY(sv.contentOffset.y + sv.bounds.height * fraction, in: sv)
        guard abs(target - sv.contentOffset.y) > 1 else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        drivenUntil = CACurrentMediaTime() + 0.6   // setContentOffset's animation is ~0.3 s
        sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: target), animated: true)
    }

    /// Scrolls down at about a screen every 2 s while held (Tachimanga's "press and hold to scroll").
    func startHold() {
        guard link == nil, scrollView != nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        lastTick = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stopHold() {
        if link != nil { drivenUntil = CACurrentMediaTime() + 0.3 }
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let sv = scrollView else { stopHold(); return }
        defer { lastTick = link.timestamp }
        guard lastTick > 0 else { return }
        let dt = min(link.timestamp - lastTick, 0.05)
        let y = clampedY(sv.contentOffset.y + sv.bounds.height * 0.5 * dt, in: sv)
        sv.contentOffset.y = y
    }

    private func clampedY(_ y: CGFloat, in sv: UIScrollView) -> CGFloat {
        let top = -sv.adjustedContentInset.top
        let bottom = max(top, sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.height)
        return min(max(y, top), bottom)
    }
}

/// Put inside a ScrollView's content: hands back the UIScrollView that hosts it.
struct EnclosingScrollViewFinder: UIViewRepresentable {
    let found: (UIScrollView) -> Void

    func makeUIView(context: Context) -> FinderView { FinderView(found: found) }
    func updateUIView(_ uiView: FinderView, context: Context) {}

    final class FinderView: UIView {
        let found: (UIScrollView) -> Void
        init(found: @escaping (UIScrollView) -> Void) {
            self.found = found
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            var view = superview
            while let v = view, !(v is UIScrollView) { view = v.superview }
            if let sv = view as? UIScrollView { found(sv) }
        }
    }
}

// MARK: - Page menu (long press: Share · Save to Photos · Copy)

enum ReaderPageActions {
    /// Posted with a message for the reader's toast (`object` = String).
    static let toast = Notification.Name("ReaderPageActions.toast")

    static func image(for url: String) async -> UIImage? {
        guard let source = URL(string: url) else { return nil }
        return try? await KingfisherManager.shared.retrieveImage(with: source, options: KFImage.readerPageOptions).image
    }

    static func saveToPhotos(_ image: UIImage) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            say("Allow Yomi to add photos in Settings to save pages")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            say("Saved to Photos")
        } catch {
            say("Couldn't save the page")
        }
    }

    static func say(_ message: String) {
        NotificationCenter.default.post(name: toast, object: message)
    }
}

private struct ReaderPageMenu: ViewModifier {
    let url: String
    let enabled: Bool

    @State private var showMenu = false
    @State private var shareImage: UIImage? = nil

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showMenu = true
                },
                including: enabled ? .all : .subviews
            )
            .confirmationDialog("Page", isPresented: $showMenu, titleVisibility: .hidden) {
                Button("Share…") {
                    Task { if let image = await ReaderPageActions.image(for: url) { shareImage = image } else { failed() } }
                }
                Button("Save to Photos") {
                    Task { if let image = await ReaderPageActions.image(for: url) { await ReaderPageActions.saveToPhotos(image) } else { failed() } }
                }
                Button("Copy Image") {
                    Task {
                        guard let image = await ReaderPageActions.image(for: url) else { failed(); return }
                        UIPasteboard.general.image = image
                        ReaderPageActions.say("Page copied")
                    }
                }
            }
            .sheet(isPresented: Binding(get: { shareImage != nil }, set: { if !$0 { shareImage = nil } })) {
                if let shareImage {
                    ActivityView(items: [shareImage])
                        .presentationDetents([.medium, .large])
                        .ignoresSafeArea()
                }
            }
    }

    private func failed() { ReaderPageActions.say("The page isn't loaded yet") }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension View {
    /// Long press on a reader page opens Share / Save to Photos / Copy for that page. Off while `enabled` is false
    /// (long strip with long press set to auto-scroll or scroll-while-held).
    func readerPageMenu(url: String, enabled: Bool = true) -> some View {
        modifier(ReaderPageMenu(url: url, enabled: enabled))
    }
}
