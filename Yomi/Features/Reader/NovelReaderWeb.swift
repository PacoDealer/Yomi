import SwiftUI
import WebKit

// MARK: - NovelReaderController
//
// The novel reader keeps ONE WKWebView for its whole lifetime (S133, RESEARCH §23.3). Chapters are
// `<section data-id>` blocks inside it, put there by a small JS controller (`NovelReaderScript.source`);
// Swift never rebuilds the web view to change chapter. That is the fix for "Next chapter does nothing"
// (bug #1): the old reader only showed a new chapter if SwiftUI happened to tear the web view down, which
// a fast (downloaded / preloaded) load skipped. Gestures live in JS too: taps use the DOM `click` event,
// which WebKit doesn't send after a touch that scrolled, so a short drag no longer opens the menu (#3).

@MainActor
final class NovelReaderController {
    enum Event {
        case tap
        case swipe(next: Bool)
        /// The chapter under the reading line changed (infinite scroll crossed a boundary).
        case current(id: String)
        case progress(id: String, percent: Double)
        /// 90 % of the chapter has been on screen.
        case complete(id: String)
        /// Infinite scroll is near the end of the last chapter in the document.
        case needNext(afterId: String)
        /// A chapter far above the reading position was removed from the document.
        case dropped(id: String)
        /// Pages mode: the page on screen, 1-based within its chapter.
        case page(id: String, page: Int, pages: Int)
        /// "Listen from Here" in the text-selection menu (S143).
        case listenFromHere
    }

    struct Options: Equatable {
        var infinite: Bool
        var swipe: Bool
        var taps: Int
        /// Pages mode (S136): text in screen-wide columns, turned by native scroll-view paging.
        var pages: Bool = false
    }

    fileprivate weak var webView: WKWebView?
    var onEvent: @MainActor (Event) -> Void = { _ in }

    private var isReady = false
    private var pending: [(String, [String: Any])] = []
    fileprivate var appliedCSS: String?
    private var appliedOptions: Options?

    /// Replaces the document with one chapter and scrolls to `restorePercent` of it.
    func show(id: String, title: String, html: String, restorePercent: Double) {
        call("yomi.show(ch, pct)", ["ch": ["id": id, "title": title, "html": html], "pct": restorePercent])
    }

    /// Appends the next chapter below the last one (infinite scroll).
    func append(id: String, title: String, html: String) {
        call("yomi.append(ch)", ["ch": ["id": id, "title": title, "html": html]])
    }

    /// There's nothing more to append, or it failed — `retry` lets JS ask again later.
    func appendUnavailable(retry: Bool) {
        call("yomi.appendUnavailable(retry)", ["retry": retry])
    }

    func scrollToChapter(id: String) {
        call("yomi.scrollToChapter(id)", ["id": id])
    }

    // MARK: Listening (S143) — the page mirrors ListenPlayer; see `tts*` in the script.

    /// The sentences ListenPlayer speaks for a chapter; the page finds each one's text to highlight it.
    func ttsSet(id: String, sentences: [String]) {
        call("yomi.ttsSet(id, list)", ["id": id, "list": sentences])
    }

    /// Highlights sentence `index` (if `show`) and keeps it on screen unless the reader touched the page lately.
    func ttsMark(id: String, index: Int, show: Bool) {
        call("yomi.ttsMark(id, i, show)", ["id": id, "i": index, "show": show])
    }

    func ttsClear() {
        call("yomi.ttsClear()", [:])
    }

    /// Makes room for the mini-player at the bottom of pages-mode pages.
    func setListening(_ on: Bool) {
        guard on != appliedListening else { return }
        appliedListening = on
        call("yomi.setListening(on)", ["on": on])
    }
    private var appliedListening = false

    /// Index of the first sentence on screen in chapter `id` (after `ttsSet`); 0 when unknown.
    func ttsFirstVisible(id: String) async -> Int {
        (await evaluate("return yomi.ttsFirstVisible(id)", ["id": id]) as? NSNumber)?.intValue ?? 0
    }

    /// The chapter id where the text selection is, or nil.
    func selectionChapterId() async -> String? {
        await evaluate("return yomi.selectionChapter()", [:]) as? String
    }

    /// Index of the sentence (of chapter `id`, after `ttsSet`) where the selection starts; clears the selection.
    func ttsSelectionIndex(id: String) async -> Int {
        (await evaluate("return yomi.ttsSelectionIndex(id)", ["id": id]) as? NSNumber)?.intValue ?? 0
    }

    private func evaluate(_ body: String, _ args: [String: Any]) async -> Any? {
        guard isReady, let webView else { return nil }
        return try? await webView.callAsyncJavaScript(body, arguments: args, contentWorld: .page)
    }

    /// Cheap to call on every SwiftUI update: only a changed stylesheet reaches the page. The old reader
    /// replaced `<style>` on every scroll tick, restyling the whole chapter mid-scroll (§23.1).
    func setStyle(_ css: String) {
        guard css != appliedCSS else { return }
        appliedCSS = css
        call("yomi.setStyle(css)", ["css": css])
    }

    func setOptions(_ options: Options) {
        guard options != appliedOptions else { return }
        appliedOptions = options
        call("yomi.setOptions(o)", ["o": ["infinite": options.infinite, "swipe": options.swipe, "taps": options.taps,
                                          "pages": options.pages]])
    }

    fileprivate func markReady() {
        isReady = true
        let queued = pending
        pending = []
        for (body, args) in queued { call(body, args) }
    }

    private func call(_ body: String, _ args: [String: Any]) {
        guard isReady, let webView else {
            pending.append((body, args))
            return
        }
        webView.callAsyncJavaScript(body, arguments: args, in: nil, in: .page, completionHandler: nil)
    }

    fileprivate func receive(_ name: String, _ body: Any) {
        switch name {
        case "ready":
            markReady()
        case "tap":
            onEvent(.tap)
        case "swipe":
            onEvent(.swipe(next: (body as? String) == "next"))
        case "current":
            if let id = body as? String { onEvent(.current(id: id)) }
        case "progress":
            if let d = body as? [String: Any], let id = d["id"] as? String, let pct = (d["pct"] as? NSNumber)?.doubleValue {
                onEvent(.progress(id: id, percent: pct))
            }
        case "complete":
            if let id = body as? String { onEvent(.complete(id: id)) }
        case "needNext":
            if let id = body as? String { onEvent(.needNext(afterId: id)) }
        case "dropped":
            if let id = body as? String { onEvent(.dropped(id: id)) }
        case "page":
            if let d = body as? [String: Any], let id = d["id"] as? String,
               let page = (d["page"] as? NSNumber)?.intValue, let pages = (d["pages"] as? NSNumber)?.intValue {
                onEvent(.page(id: id, page: page, pages: pages))
            }
        default:
            break
        }
    }

    static let messageNames = ["ready", "tap", "swipe", "current", "progress", "complete", "needNext", "dropped", "page"]
}

// MARK: - ReaderWebView

struct ReaderWebView: UIViewRepresentable {
    let controller: NovelReaderController
    let css: String
    let options: NovelReaderController.Options
    /// BCP 47 language of the source, for `<html lang>` — WebKit only hyphenates justified text with one.
    var lang: String? = nil

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = []
        // Non-persistent store: all chapters share an about:blank origin, and a persistent one made iOS
        // offer "Restore scroll position" on every load.
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(ReaderFontSchemeHandler(), forURLScheme: ReaderFontSchemeHandler.scheme)
        let proxy = MessageProxy(coordinator: context.coordinator)
        for name in NovelReaderController.messageNames {
            config.userContentController.add(proxy, name: name)
        }

        let webView = ReaderWKWebView(frame: .zero, configuration: config)
        webView.onListenFromHere = { [weak controller] in controller?.onEvent(.listenFromHere) }
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        #if DEBUG
        webView.isInspectable = true
        #endif

        controller.webView = webView
        controller.appliedCSS = css
        webView.loadHTMLString(NovelReaderScript.shell(css: css, lang: lang), baseURL: nil)
        controller.setOptions(options)
        applyPaging(to: webView, context: context)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        controller.setStyle(css)
        controller.setOptions(options)
        applyPaging(to: webView, context: context)
    }

    /// Pages mode turns pages with the scroll view's own paging, so a page follows the finger (Martin picked
    /// "Slide"). Pinch zoom is off there: a zoomed page breaks the column layout (size is a setting instead).
    private func applyPaging(to webView: WKWebView, context: Context) {
        let scroll = webView.scrollView
        if scroll.isPagingEnabled != options.pages {
            scroll.isPagingEnabled = options.pages
            scroll.showsHorizontalScrollIndicator = false
            scroll.alwaysBounceVertical = !options.pages
            scroll.pinchGestureRecognizer?.isEnabled = !options.pages
        }
        context.coordinator.yieldToEdgeSwipe(scroll)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        for name in NovelReaderController.messageNames {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let controller: NovelReaderController
        init(controller: NovelReaderController) { self.controller = controller }

        private weak var linkedPop: UIGestureRecognizer?

        /// A drag that starts on the left screen edge is "back" (`.swipeBackEnabled()`), not a page turn: the
        /// web view's pan waits for the navigation controller's edge recognizer to fail. Swipes that start
        /// anywhere else turn pages — Apple Books' split. The recognizer exists only once the view is in a window.
        func yieldToEdgeSwipe(_ scroll: UIScrollView) {
            guard linkedPop == nil else { return }
            var responder: UIResponder? = scroll
            while let r = responder, !(r is UINavigationController) { responder = r.next }
            guard let pop = (responder as? UINavigationController)?.interactivePopGestureRecognizer else {
                DispatchQueue.main.async { [weak self, weak scroll] in
                    if let self, let scroll, scroll.window != nil, self.linkedPop == nil { self.yieldToEdgeSwipe(scroll) }
                }
                return
            }
            scroll.panGestureRecognizer.require(toFail: pop)
            linkedPop = pop
        }

        // Chapter HTML is scraped from third-party sites. Our own loadHTMLString resolves to about:blank;
        // anything else (a link in the chapter, a redirect) is a real navigation and is cancelled (#95).
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            decisionHandler(url == nil || url?.absoluteString == "about:blank" ? .allow : .cancel)
        }

        func receive(_ message: WKScriptMessage) {
            controller.receive(message.name, message.body)
        }
    }

    /// Adds "Listen from Here" to the text-selection menu (ArcReader has it; S143). WebKit builds its edit menu
    /// through the responder chain's `buildMenu(with:)`.
    final class ReaderWKWebView: WKWebView {
        var onListenFromHere: (() -> Void)?

        override func buildMenu(with builder: any UIMenuBuilder) {
            super.buildMenu(with: builder)
            guard onListenFromHere != nil else { return }
            let listen = UIAction(title: "Listen from Here", image: UIImage(systemName: "speaker.wave.2")) { [weak self] _ in
                self?.onListenFromHere?()
            }
            builder.insertSibling(UIMenu(options: .displayInline, children: [listen]), afterMenu: .standardEdit)
        }
    }

    /// WKUserContentController retains its handlers; the proxy keeps that from retaining the coordinator.
    private final class MessageProxy: NSObject, WKScriptMessageHandler {
        weak var coordinator: Coordinator?
        init(coordinator: Coordinator) { self.coordinator = coordinator }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            coordinator?.receive(message)
        }
    }
}

// MARK: - NovelReaderScript

enum NovelReaderScript {
    static func shell(css: String, lang: String? = nil) -> String {
        // Only a plain language tag goes into the attribute ("multi" and anything odd are left out).
        let langAttr = lang.flatMap { $0.range(of: #"^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$"#, options: .regularExpression) != nil
                                      && $0 != "multi" ? " lang=\"\($0)\"" : nil } ?? ""
        return """
        <!DOCTYPE html>
        <html\(langAttr)>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes, viewport-fit=cover">
        <style id="yomi-base">\(baseCSS)</style>
        <style id="yomi-style">\(css)</style>
        </head>
        <body>
        <main id="yomi-chapters"></main>
        <script>\(source)</script>
        </body>
        </html>
        """
    }

    /// Layout that doesn't depend on reader settings.
    private static let baseCSS = """
        * { box-sizing: border-box; }
        html, body { margin: 0; padding: 0; }
        /* manipulation: no double-tap zoom, so taps aren't delayed; pinch zoom still works. */
        body { -webkit-tap-highlight-color: transparent; touch-action: manipulation; }
        /* cursor:pointer makes iOS WebKit dispatch click for taps on plain text. */
        #yomi-chapters { cursor: pointer; min-height: 100vh; }
        .yomi-chapter + .yomi-chapter { margin-top: 3em; }
        .yomi-chapter-title {
            text-align: center; font-size: 0.8em; letter-spacing: 0.08em; text-transform: uppercase;
            opacity: 0.55; padding: 1.2em 0 1.6em; border-top: 1px solid currentColor;
            border-top-color: color-mix(in srgb, currentColor 20%, transparent);
        }
        img { max-width: 100%; height: auto; display: block; margin: 0.5em auto; }
        .yomi-mark { height: 0; margin: 0; padding: 0; }
        .yomi-end-card { display: none; }

        /* Pages mode (S136): screen-wide columns, overflowing sideways; the scroll view pages through them.
           Column k starts at m + k·100vw (padding m, column 100vw-2m, gap 2m), so every page is one screen
           wide. --m (margin) comes from the reader stylesheet; top/bottom leave room for the native chapter name
           and page number. */
        /* overflow only on html (it propagates to the viewport, which the scroll view pages); on body too, body
           would become its own scroll container and window.scrollX would never move. */
        html.yomi-pages { height: 100%; overflow-y: hidden; }
        html.yomi-pages body { height: 100%; }
        html.yomi-pages #yomi-chapters {
            height: 100vh; min-height: 0; max-width: none; margin: 0;
            padding: calc(env(safe-area-inset-top) + 34px) var(--m) calc(env(safe-area-inset-bottom) + 34px) var(--m);
            column-width: calc(100vw - 2 * var(--m)); column-gap: calc(2 * var(--m)); column-fill: auto;
        }
        /* Listening (S143): room for the mini-player under the text. */
        html.yomi-pages.yomi-listening #yomi-chapters { padding-bottom: calc(env(safe-area-inset-bottom) + 100px); }
        html.yomi-pages .yomi-chapter { break-before: column; }
        html.yomi-pages .yomi-chapter + .yomi-chapter { margin-top: 0; }
        html.yomi-pages img {
            break-inside: avoid; object-fit: contain;
            max-height: calc(100vh - env(safe-area-inset-top) - env(safe-area-inset-bottom) - 80px);
        }
        html.yomi-pages:not(.yomi-continue) .yomi-end-card {
            display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 1em;
            break-before: column; height: calc(100vh - env(safe-area-inset-top) - env(safe-area-inset-bottom) - 68px);
            text-align: center; opacity: 0.8;
        }
        .yomi-end-card button {
            font: inherit; color: inherit; background: color-mix(in srgb, currentColor 12%, transparent);
            border: 0; border-radius: 999px; padding: 0.6em 1.4em; cursor: pointer;
        }
        """

    /// The reader controller. Posts: ready, tap, swipe("next"|"prev"), current(id), progress({id,pct}),
    /// complete(id), needNext(afterId), dropped(id), page({id,page,pages}).
    /// Two layouts share one model — an ordered list of chapter sections and a reading position (chapter + percent):
    /// scroll (vertical) and pages (S136: horizontal columns, one screen per page, paged natively by the scroll view).
    static let source = #"""
    (function () {
      'use strict';
      if ('scrollRestoration' in history) { history.scrollRestoration = 'manual'; }
      var root = document.getElementById('yomi-chapters');
      var html = document.documentElement;
      var opts = { infinite: true, swipe: true, taps: 1, pages: false };
      var currentId = null;
      var completed = {};
      var askedAfter = null;       // last chapter id we asked Swift to append after
      var noMore = false;          // Swift said there's nothing to append
      var retryAt = 0;
      var progressTimer = null, trimTimer = null;
      var lastScrollAt = 0, touching = false, lastTouchAt = 0;
      var lastPage = null;         // "id:page/pages" last posted, to post page changes only

      function post(name, body) {
        try { window.webkit.messageHandlers[name].postMessage(body === undefined ? 1 : body); } catch (e) {}
      }
      function sections() { return Array.prototype.slice.call(root.querySelectorAll(':scope > section.yomi-chapter')); }
      function find(id) {
        var list = sections();
        for (var i = 0; i < list.length; i++) { if (list[i].dataset.id === id) return list[i]; }
        return null;
      }
      function clamp(x) { return x < 0 ? 0 : (x > 1 ? 1 : x); }

      function build(ch, withTitle) {
        var s = document.createElement('section');
        s.className = 'yomi-chapter';
        s.dataset.id = ch.id;
        var start = document.createElement('div'); start.className = 'yomi-mark yomi-start'; s.appendChild(start);
        if (withTitle && ch.title) {
          var t = document.createElement('div');
          t.className = 'yomi-chapter-title';
          t.textContent = ch.title;
          s.appendChild(t);
        }
        var body = document.createElement('div');
        body.className = 'yomi-chapter-body';
        body.innerHTML = ch.html;      // scripts in innerHTML don't run
        // Some sources inject a "Restore scroll position" button into their chapter HTML.
        var tw = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, null), n;
        while ((n = tw.nextNode())) {
          if (n.textContent.trim() === 'Restore scroll position' && n.parentElement) { n.parentElement.remove(); break; }
        }
        s.appendChild(body);
        var end = document.createElement('div'); end.className = 'yomi-mark yomi-end'; s.appendChild(end);
        // Pages mode with "continue" off: the chapter ends on a page of its own with a Next chapter button.
        var card = document.createElement('div');
        card.className = 'yomi-end-card';
        card.innerHTML = '<div>End of chapter</div><button type="button" class="yomi-next">Next chapter ›</button>';
        s.appendChild(card);
        return s;
      }

      // ── Geometry ─────────────────────────────────────────────────────────
      function pageW() { return window.innerWidth || 1; }
      function pageNow() { return Math.round(window.scrollX / pageW()); }
      function pageOf(el) { return Math.floor((el.getBoundingClientRect().left + window.scrollX + 1) / pageW()); }
      // First and last page of a section (pages mode). The end card counts as a page when it's shown.
      function span(s) {
        var a = pageOf(s.querySelector(':scope > .yomi-start'));
        var card = s.querySelector(':scope > .yomi-end-card');
        var lastEl = card && card.offsetHeight > 0 ? card : s.querySelector(':scope > .yomi-end');
        var b = Math.max(a, pageOf(lastEl));
        return { a: a, b: b, n: b - a + 1 };
      }
      // Percent through a chapter. Scroll: 0 = its top at the top of the screen, 1 = its bottom at the bottom.
      // Pages: first page = 0, last page = 1.
      function percentOf(s) {
        if (opts.pages) {
          var r = span(s);
          return r.n <= 1 ? 1 : clamp((pageNow() - r.a) / (r.n - 1));
        }
        var range = s.offsetHeight - window.innerHeight;
        if (range <= 0) return 1;
        return clamp((window.scrollY - s.offsetTop) / range);
      }
      function goTo(s, pct) {
        if (opts.pages) {
          var r = span(s);
          window.scrollTo((r.a + Math.round(clamp(pct) * (r.n - 1))) * pageW(), 0);
        } else {
          var range = s.offsetHeight - window.innerHeight;
          window.scrollTo(0, s.offsetTop + (pct > 0.01 && range > 0 ? pct * range : 0));
        }
      }
      // The chapter being read: scroll = the one crossing a line 30 % down the screen; pages = the one on screen.
      function currentSection(list) {
        var cur = list[0];
        if (opts.pages) {
          var p = pageNow();
          for (var i = 0; i < list.length; i++) { if (span(list[i]).a <= p) cur = list[i]; }
        } else {
          var line = window.scrollY + window.innerHeight * 0.3;
          for (var k = 0; k < list.length; k++) { if (list[k].offsetTop <= line) cur = list[k]; }
        }
        return cur;
      }

      function update() {
        var list = sections();
        if (!list.length) return;
        var cur = currentSection(list);
        if (cur.dataset.id !== currentId) {
          var prev = currentId ? find(currentId) : null;
          if (prev) post('progress', { id: prev.dataset.id, pct: percentOf(prev) });
          currentId = cur.dataset.id;
          post('current', currentId);
        }
        var last = list[list.length - 1];
        if (opts.pages) {
          var p = pageNow(), r = span(cur);
          var key = cur.dataset.id + ':' + (p - r.a + 1) + '/' + r.n;
          if (key !== lastPage) { lastPage = key; post('page', { id: cur.dataset.id, page: p - r.a + 1, pages: r.n }); }
          for (var j = 0; j < list.length; j++) {
            var sj = list[j], idj = sj.dataset.id;
            if (completed[idj]) continue;
            var rj = span(sj);
            if (p >= rj.b || (rj.n > 1 && (p - rj.a) / (rj.n - 1) >= 0.9)) { completed[idj] = true; post('complete', idj); }
          }
          if (opts.infinite && !noMore && Date.now() >= retryAt && askedAfter !== last.dataset.id && p >= span(last).b - 2) {
            askedAfter = last.dataset.id;
            post('needNext', askedAfter);
          }
        } else {
          var y = window.scrollY, vh = window.innerHeight;
          for (var m = 0; m < list.length; m++) {
            var s = list[m], id = s.dataset.id;
            if (completed[id]) continue;
            var seen = (y + vh - s.offsetTop) / Math.max(1, s.offsetHeight);
            if (seen >= 0.9) { completed[id] = true; post('complete', id); }
          }
          if (opts.infinite && !noMore && Date.now() >= retryAt) {
            if (askedAfter !== last.dataset.id && y + vh > last.offsetTop + last.offsetHeight - vh * 1.5) {
              askedAfter = last.dataset.id;
              post('needNext', askedAfter);
            }
          }
        }
        clearTimeout(progressTimer);
        progressTimer = setTimeout(function () {
          var c = currentId ? find(currentId) : null;
          if (c) post('progress', { id: currentId, pct: percentOf(c) });
        }, 400);
        clearTimeout(trimTimer);
        trimTimer = setTimeout(trim, 700);
      }

      // Keep at most ~4 chapters: drop ones well before the reader, only while nothing is moving, and shift the
      // position by what was removed so the text on screen doesn't jump.
      function trim() {
        if (touching || Date.now() - lastScrollAt < 600) { trimTimer = setTimeout(trim, 700); return; }
        var list = sections();
        var cur = currentId ? find(currentId) : null;
        if (!cur || list.length <= 4) return;
        var first = list[0];
        if (first === cur) return;
        var id = first.dataset.id;
        if (opts.pages) {
          var r = span(first);
          if (r.b >= pageNow() - 2) return;
          first.remove();
          window.scrollBy(-r.n * pageW(), 0);
        } else {
          if (first.offsetTop + first.offsetHeight > window.scrollY - window.innerHeight) return;
          var before = cur.offsetTop;
          first.remove();
          window.scrollBy(0, cur.offsetTop - before);
        }
        delete completed[id];
        post('dropped', id);
      }

      var scheduled = false;
      function schedule() {
        if (scheduled) return;
        scheduled = true;
        requestAnimationFrame(function () { scheduled = false; update(); });
      }

      // A style, size or mode change re-lays out everything: keep the reader on the same spot of the same chapter.
      function relayout(change) {
        var c = currentId ? find(currentId) : null;
        var pct = c ? percentOf(c) : 0;
        change();
        if (c) {
          goTo(c, pct);
          requestAnimationFrame(function () { goTo(c, pct); lastPage = null; update(); });
        } else {
          schedule();
        }
      }

      window.addEventListener('scroll', function () { lastScrollAt = Date.now(); schedule(); }, { passive: true });
      window.addEventListener('resize', function () { relayout(function () {}); }, { passive: true });
      window.addEventListener('load', schedule, { passive: true });

      // ── Gestures ─────────────────────────────────────────────────────────
      // Tap = DOM click. WebKit sends no click after a touch that scrolled; we also ignore the click after
      // a move of more than 8 px, a touch held longer than a tap (300 ms — a slow, short drag is a scroll
      // attempt: Martin S144 "still too sensitive to small scrolls"), a touch within 300 ms of scrolling
      // (stopping a fling), or one that dismisses a text selection.
      var touch = null, ignoreClick = false, lastTapAt = 0;
      function hasSelection() { var s = window.getSelection && window.getSelection(); return !!(s && String(s).length); }
      function zoomed() { return window.visualViewport && window.visualViewport.scale > 1.01; }

      document.addEventListener('touchstart', function (e) {
        touching = true; lastTouchAt = Date.now();
        if (e.touches.length !== 1) { touch = null; ignoreClick = true; return; }
        var t = e.touches[0];
        touch = { x: t.clientX, y: t.clientY, t: Date.now(), dx: 0, dy: 0, sel: hasSelection() };
        ignoreClick = Date.now() - lastScrollAt < 300 || touch.sel;
      }, { passive: true });

      document.addEventListener('touchmove', function (e) {
        lastTouchAt = Date.now();
        if (!touch || e.touches.length !== 1) return;
        var t = e.touches[0];
        touch.dx = t.clientX - touch.x;
        touch.dy = t.clientY - touch.y;
        if (Math.abs(touch.dx) > 8 || Math.abs(touch.dy) > 8) ignoreClick = true;
      }, { passive: true });

      // Scroll mode only: a sideways swipe changes chapter. In pages mode the scroll view turns the page.
      function endTouch(cancelled) {
        touching = false;
        var t = touch; touch = null;
        if (t && Date.now() - t.t > 300) ignoreClick = true;
        if (cancelled || !t || opts.pages || !opts.swipe || t.sel || zoomed() || hasSelection()) return;
        var adx = Math.abs(t.dx), ady = Math.abs(t.dy);
        // Horizontal, clearly not a scroll, and not from the left edge (iOS uses it for "back").
        if (t.x > 24 && adx > Math.max(90, window.innerWidth * 0.25) && adx > 2 * ady && Date.now() - t.t < 800) {
          post('swipe', t.dx < 0 ? 'next' : 'prev');
        }
      }
      document.addEventListener('touchend', function () { endTouch(false); }, { passive: true });
      document.addEventListener('touchcancel', function () { endTouch(true); }, { passive: true });

      // Pages: one page back/forward. Past the first/last page of the document, the previous/next chapter.
      function turn(dir) {
        var p = pageNow() + dir;
        var list = sections();
        var lastPageIndex = list.length ? span(list[list.length - 1]).b : 0;
        if (p < 0) { post('swipe', 'prev'); return; }
        if (p > lastPageIndex) { post('swipe', 'next'); return; }
        window.scrollTo({ left: p * pageW(), top: 0, behavior: 'smooth' });
      }

      function menuTap() {
        if (opts.taps === 2) {
          var now = Date.now();
          if (now - lastTapAt < 400) { lastTapAt = 0; post('tap'); } else { lastTapAt = now; }
          return;
        }
        post('tap');
      }

      document.addEventListener('click', function (e) {
        if (e.target && e.target.closest && e.target.closest('a')) e.preventDefault();
        if (ignoreClick) { ignoreClick = false; return; }
        if (e.target && e.target.closest && e.target.closest('.yomi-next')) { post('swipe', 'next'); return; }
        if (opts.pages) {
          var w = window.innerWidth;
          if (e.clientX < w * 0.3) { turn(-1); return; }
          if (e.clientX > w * 0.7) { turn(1); return; }
        }
        menuTap();
      }, true);

      // ── Listening (S143) ─────────────────────────────────────────────────
      // Swift sends the sentences it speaks; each one is found in the chapter's text by comparing letters and
      // digits only (Swift and WebKit decode entities and whitespace differently), searching forward from the
      // previous match. The highlight is a CSS Custom Highlight, so the DOM — and the layout — never change.
      var tts = { data: {}, id: null, sec: null, ranges: null };
      var alnum = /[\p{L}\p{N}]/u;
      function ttsKey(str) {
        var out = '';
        for (var i = 0; i < str.length; i++) { var c = str[i]; if (alnum.test(c)) out += c.toLowerCase()[0]; }
        return out;
      }
      function ttsRanges(id) {
        var s = find(id), list = tts.data[id];
        if (!s || !list) return null;
        if (tts.id === id && tts.sec === s && tts.ranges) return tts.ranges;
        var body = s.querySelector(':scope > .yomi-chapter-body');
        var nodes = [], map = [], chars = [];
        var tw = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, null), n;
        while ((n = tw.nextNode())) {
          var t = n.nodeValue, ni = nodes.length;
          nodes.push(n);
          for (var i = 0; i < t.length; i++) {
            var c = t[i];
            if (alnum.test(c)) { chars.push(c.toLowerCase()[0]); map.push(ni, i); }
          }
        }
        var K = chars.join(''), from = 0, out = [];
        for (var k = 0; k < list.length; k++) {
          var q = ttsKey(list[k]);
          if (!q) { out.push(null); continue; }
          var at = K.indexOf(q, from), len = q.length;
          if (at < 0) { var p = q.slice(0, 24); at = K.indexOf(p, from); len = p.length; }
          if (at < 0 || at - from > 4000) { out.push(null); continue; }
          var r = document.createRange();
          var sn = nodes[map[2 * at]], so = map[2 * at + 1];
          var e = at + len - 1, en = nodes[map[2 * e]], eo = map[2 * e + 1] + 1;
          // Take in the quote before and the punctuation after, within the same text node.
          while (so > 0 && /[^\s\p{L}\p{N}]/u.test(sn.nodeValue[so - 1])) so--;
          while (eo < en.nodeValue.length && /[^\s\p{L}\p{N}]/u.test(en.nodeValue[eo])) eo++;
          r.setStart(sn, so); r.setEnd(en, eo);
          out.push(r);
          from = at + len;
        }
        tts.id = id; tts.sec = s; tts.ranges = out;
        return out;
      }
      function firstRect(r) { var rs = r.getClientRects(); return rs.length ? rs[0] : r.getBoundingClientRect(); }
      // Keep the sentence being read on screen — unless the reader touched the page in the last 4 s or has text
      // selected (scrolling carried the selection and its menu away — S143).
      function reveal(r) {
        if (touching || Date.now() - lastTouchAt < 4000 || hasSelection()) return;
        var rect = firstRect(r);
        if (opts.pages) {
          var page = Math.floor((rect.left + window.scrollX + 1) / pageW());
          if (page !== pageNow()) window.scrollTo({ left: page * pageW(), top: 0, behavior: 'smooth' });
        } else {
          var vh = window.innerHeight;
          if (rect.top < vh * 0.12 || rect.bottom > vh * 0.7) {
            window.scrollTo({ top: window.scrollY + rect.top - vh * 0.3, left: 0, behavior: 'smooth' });
          }
        }
      }
      // One Highlight object whose range is swapped: replacing the registered Highlight each sentence left the old
      // ranges painted (WebKit didn't repaint them — S143 sim screenshot).
      var ttsHL = null;
      function ttsShow(r) {
        if (!(window.CSS && CSS.highlights && window.Highlight)) return;
        if (!ttsHL) { ttsHL = new Highlight(); CSS.highlights.set('yomi-tts', ttsHL); }
        ttsHL.clear();
        ttsHL.add(r);
      }
      function ttsClear() { if (ttsHL) ttsHL.clear(); }

      // ── API for Swift ────────────────────────────────────────────────────
      window.yomi = {
        setStyle: function (css) {
          relayout(function () { document.getElementById('yomi-style').textContent = css; });
        },
        setOptions: function (o) {
          var modeChanged = !!o.pages !== !!opts.pages || !!o.infinite !== !!opts.infinite;
          var apply = function () {
            opts = o;
            html.classList.toggle('yomi-pages', !!o.pages);
            html.classList.toggle('yomi-continue', !!o.infinite);
          };
          if (modeChanged) { askedAfter = null; noMore = false; relayout(apply); } else { apply(); schedule(); }
        },
        show: function (ch, pct) {
          root.innerHTML = '';
          completed = {}; askedAfter = null; noMore = false; retryAt = 0; currentId = null; lastPage = null;
          var s = build(ch, false);
          root.appendChild(s);
          window.scrollTo(0, 0);
          goTo(s, pct > 0.01 ? pct : 0);
          requestAnimationFrame(function () { goTo(s, pct > 0.01 ? pct : 0); update(); });
        },
        append: function (ch) {
          if (find(ch.id)) return;
          root.appendChild(build(ch, true));
          schedule();
        },
        appendUnavailable: function (retry) {
          if (retry) { askedAfter = null; retryAt = Date.now() + 5000; } else { noMore = true; }
        },
        scrollToChapter: function (id) {
          var s = find(id);
          if (s) goTo(s, 0);
        },
        ttsSet: function (id, list) {
          tts.data = {}; tts.data[id] = list; tts.id = null; tts.ranges = null;
        },
        ttsMark: function (id, i, show) {
          var rs = ttsRanges(id), r = rs && rs[i];
          if (!r) { ttsClear(); return; }
          if (show) ttsShow(r); else ttsClear();
          reveal(r);
        },
        ttsClear: function () { ttsClear(); tts.data = {}; tts.id = null; tts.ranges = null; },
        setListening: function (on) { relayout(function () { html.classList.toggle('yomi-listening', !!on); }); },
        ttsFirstVisible: function (id) {
          var rs = ttsRanges(id);
          if (!rs) return 0;
          for (var i = 0; i < rs.length; i++) {
            if (!rs[i]) continue;
            var rect = firstRect(rs[i]);
            if (opts.pages ? (rect.right > 0 && rect.left < window.innerWidth) : rect.bottom > 4) return i;
          }
          return 0;
        },
        selectionChapter: function () {
          var sel = window.getSelection();
          if (!sel || !sel.rangeCount || !sel.anchorNode) return null;
          var el = sel.anchorNode.nodeType === 1 ? sel.anchorNode : sel.anchorNode.parentElement;
          var s = el && el.closest('section.yomi-chapter');
          return s ? s.dataset.id : null;
        },
        ttsSelectionIndex: function (id) {
          var sel = window.getSelection(), rs = ttsRanges(id), found = 0;
          if (sel && sel.rangeCount && rs) {
            for (var i = 0; i < rs.length; i++) {
              if (rs[i] && rs[i].comparePoint(sel.anchorNode, sel.anchorOffset) <= 0) { found = i; break; }
            }
          }
          if (sel) sel.removeAllRanges();
          return found;
        }
      };
      post('ready');
    })();
    """#
}
