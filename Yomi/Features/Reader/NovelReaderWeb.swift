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
    }

    struct Options: Equatable {
        var infinite: Bool
        var swipe: Bool
        var taps: Int
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
        call("yomi.setOptions(o)", ["o": ["infinite": options.infinite, "swipe": options.swipe, "taps": options.taps]])
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
        default:
            break
        }
    }

    static let messageNames = ["ready", "tap", "swipe", "current", "progress", "complete", "needNext", "dropped"]
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

        let webView = WKWebView(frame: .zero, configuration: config)
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
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        controller.setStyle(css)
        controller.setOptions(options)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        for name in NovelReaderController.messageNames {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let controller: NovelReaderController
        init(controller: NovelReaderController) { self.controller = controller }

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
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes">
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
        """

    /// The reader controller. Posts: ready, tap, swipe("next"|"prev"), current(id), progress({id,pct}),
    /// complete(id), needNext(afterId), dropped(id).
    static let source = #"""
    (function () {
      'use strict';
      if ('scrollRestoration' in history) { history.scrollRestoration = 'manual'; }
      var root = document.getElementById('yomi-chapters');
      var opts = { infinite: true, swipe: true, taps: 1 };
      var currentId = null;
      var completed = {};
      var askedAfter = null;       // last chapter id we asked Swift to append after
      var noMore = false;          // Swift said there's nothing to append
      var retryAt = 0;
      var progressTimer = null, trimTimer = null;
      var lastScrollAt = 0, touching = false;

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
        return s;
      }

      // Percent through a chapter: 0 = its top at the top of the screen, 1 = its bottom at the bottom.
      function percentOf(s) {
        var range = s.offsetHeight - window.innerHeight;
        if (range <= 0) return 1;
        return clamp((window.scrollY - s.offsetTop) / range);
      }

      function update() {
        var list = sections();
        if (!list.length) return;
        var y = window.scrollY, vh = window.innerHeight;
        var line = y + vh * 0.3;
        var cur = list[0];
        for (var i = 0; i < list.length; i++) { if (list[i].offsetTop <= line) cur = list[i]; }
        if (cur.dataset.id !== currentId) {
          var prev = currentId ? find(currentId) : null;
          if (prev) post('progress', { id: prev.dataset.id, pct: percentOf(prev) });
          currentId = cur.dataset.id;
          post('current', currentId);
        }
        for (var j = 0; j < list.length; j++) {
          var s = list[j], id = s.dataset.id;
          if (completed[id]) continue;
          var seen = (y + vh - s.offsetTop) / Math.max(1, s.offsetHeight);
          if (seen >= 0.9) { completed[id] = true; post('complete', id); }
        }
        if (opts.infinite && !noMore && Date.now() >= retryAt) {
          var last = list[list.length - 1];
          if (askedAfter !== last.dataset.id && y + vh > last.offsetTop + last.offsetHeight - vh * 1.5) {
            askedAfter = last.dataset.id;
            post('needNext', askedAfter);
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

      // Keep at most ~4 chapters: drop ones well above the reader, only while nothing is moving,
      // and shift the scroll position by the removed height so the text on screen doesn't jump.
      function trim() {
        if (touching || Date.now() - lastScrollAt < 600) { trimTimer = setTimeout(trim, 700); return; }
        var list = sections();
        var cur = currentId ? find(currentId) : null;
        if (!cur || list.length <= 4) return;
        var first = list[0];
        if (first === cur || first.offsetTop + first.offsetHeight > window.scrollY - window.innerHeight) return;
        var before = cur.offsetTop;
        var id = first.dataset.id;
        first.remove();
        window.scrollBy(0, cur.offsetTop - before);
        delete completed[id];
        post('dropped', id);
      }

      var scheduled = false;
      function schedule() {
        if (scheduled) return;
        scheduled = true;
        requestAnimationFrame(function () { scheduled = false; update(); });
      }

      window.addEventListener('scroll', function () { lastScrollAt = Date.now(); schedule(); }, { passive: true });
      window.addEventListener('resize', schedule, { passive: true });
      window.addEventListener('load', schedule, { passive: true });

      // ── Gestures ─────────────────────────────────────────────────────────
      // Tap = DOM click. WebKit sends no click after a touch that scrolled; we also ignore the click after
      // a move of more than 8 px, a touch that stopped a fling, or one that dismisses a text selection.
      var touch = null, ignoreClick = false, lastTapAt = 0;
      function hasSelection() { var s = window.getSelection && window.getSelection(); return !!(s && String(s).length); }
      function zoomed() { return window.visualViewport && window.visualViewport.scale > 1.01; }

      document.addEventListener('touchstart', function (e) {
        touching = true;
        if (e.touches.length !== 1) { touch = null; ignoreClick = true; return; }
        var t = e.touches[0];
        touch = { x: t.clientX, y: t.clientY, t: Date.now(), dx: 0, dy: 0, sel: hasSelection() };
        ignoreClick = Date.now() - lastScrollAt < 150 || touch.sel;
      }, { passive: true });

      document.addEventListener('touchmove', function (e) {
        if (!touch || e.touches.length !== 1) return;
        var t = e.touches[0];
        touch.dx = t.clientX - touch.x;
        touch.dy = t.clientY - touch.y;
        if (Math.abs(touch.dx) > 8 || Math.abs(touch.dy) > 8) ignoreClick = true;
      }, { passive: true });

      function endTouch(cancelled) {
        touching = false;
        var t = touch; touch = null;
        if (cancelled || !t || !opts.swipe || t.sel || zoomed() || hasSelection()) return;
        var adx = Math.abs(t.dx), ady = Math.abs(t.dy);
        // Horizontal, clearly not a scroll, and not from the left edge (iOS uses it for "back").
        if (t.x > 24 && adx > Math.max(90, window.innerWidth * 0.25) && adx > 2 * ady && Date.now() - t.t < 800) {
          post('swipe', t.dx < 0 ? 'next' : 'prev');
        }
      }
      document.addEventListener('touchend', function () { endTouch(false); }, { passive: true });
      document.addEventListener('touchcancel', function () { endTouch(true); }, { passive: true });

      document.addEventListener('click', function (e) {
        if (e.target && e.target.closest && e.target.closest('a')) e.preventDefault();
        if (ignoreClick) { ignoreClick = false; return; }
        if (opts.taps === 2) {
          var now = Date.now();
          if (now - lastTapAt < 400) { lastTapAt = 0; post('tap'); } else { lastTapAt = now; }
          return;
        }
        post('tap');
      }, true);

      // ── API for Swift ────────────────────────────────────────────────────
      window.yomi = {
        setStyle: function (css) { document.getElementById('yomi-style').textContent = css; schedule(); },
        setOptions: function (o) { opts = o; schedule(); },
        show: function (ch, pct) {
          root.innerHTML = '';
          completed = {}; askedAfter = null; noMore = false; retryAt = 0; currentId = null;
          var s = build(ch, false);
          root.appendChild(s);
          var go = function () {
            var range = s.offsetHeight - window.innerHeight;
            window.scrollTo(0, s.offsetTop + (pct > 0.01 && range > 0 ? pct * range : 0));
          };
          go();
          requestAnimationFrame(function () { go(); update(); });
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
          if (s) window.scrollTo(0, s.offsetTop);
        }
      };
      post('ready');
    })();
    """#
}
