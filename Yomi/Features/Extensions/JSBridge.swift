import Foundation
import JavaScriptCore

// Module-level CF-block tracking — keyed by JSContext identity, guarded by _cfLock.
nonisolated private let _cfLock = NSLock()
nonisolated(unsafe) private var _cfBlockedByContext: [ObjectIdentifier: String] = [:]

/// Request timeout for SOURCE.fetch, mirrored from AppSettings.shared.requestTimeout on MainActor
/// (AppSettings didSet) — read from inside Task.detached JS execution, where reading
/// AppSettings.shared directly is unsafe (see CLAUDE.md's concurrency rules).
nonisolated(unsafe) var jsBridgeRequestTimeout: TimeInterval = 30

// MARK: - Novel Result Types

struct NovelItem {
    var name: String
    var path: String
    var cover: String?
}

struct JSNovelChapter {
    var name: String
    var path: String
    var chapterNumber: Double?
    var releaseTime: String?
}

struct SourceNovel {
    var path: String
    var name: String
    var cover: String?
    var author: String?
    var summary: String?
    var status: String?
    var chapters: [JSNovelChapter]
}

// MARK: - JSBridge

/// Executes JavaScript plugin functions and maps results to Swift models.
/// Supports four plugin formats:
///   Format A — Yomi/Manga: global functions getMangaList / getChapterList / getPageList
///   Format B — LNReader/Novel: global `plugin` object with popularNovels / parseNovel / parseChapter / searchNovels
///   Format C — Paperback: Source subclass from paperback-extensions-common; adapted via getHomePageSections
///   Format D — Mangayomi JS: class DefaultExtension extends MProvider + mangayomiSources[]; evaluateScript drain
final class JSBridge {

    // nonisolated(unsafe): JSContext is only ever accessed from background threads
    // via nonisolated methods — never from the main actor.
    nonisolated(unsafe) private let context: JSContext

    // Set by getChapterList() for Mangayomi plugins — detail metadata extracted
    // from the same getDetail() call so MangaDetailView can update synopsis/cover/status.
    nonisolated(unsafe) var lastMangayomiMeta: (summary: String?, status: String?, coverURL: URL?)? = nil

    // MARK: - Init

    nonisolated init?(scriptURL: URL) {
        guard
            let source = try? String(contentsOf: scriptURL, encoding: .utf8),
            let ctx    = JSContext()
        else { return nil }

        context = ctx
        context.exceptionHandler = { _, exception in
            print("❌ JSBridge exception:", exception?.toString() ?? "unknown")
        }
        JSBridge.injectShims(into: ctx)
        ctx.evaluateScript(source)
        JSBridge.injectPaperbackAdapter(into: ctx)
        JSBridge.injectLNReaderAdapter(into: ctx)
        JSBridge.injectMangayomiAdapter(into: ctx)
    }

    /// true when the loaded script exposes a `plugin` global with `popularNovels` (LNReader format)
    nonisolated var isLNReaderPlugin: Bool {
        guard
            let plugin = context.objectForKeyedSubscript("plugin"),
            !plugin.isUndefined, !plugin.isNull,
            let fn = plugin.objectForKeyedSubscript("popularNovels"),
            !fn.isUndefined, !fn.isNull
        else { return false }
        return true
    }

    /// true when the plugin exposes a Mangayomi-format `source` object (detected by __mangayomiSource global)
    nonisolated var isMangayomiPlugin: Bool {
        guard
            let flag = context.objectForKeyedSubscript("__mangayomiSource"),
            !flag.isUndefined, !flag.isNull
        else { return false }
        return true
    }

    /// If the last _fetchSync call for this context was Cloudflare-blocked, returns the blocked URL.
    nonisolated var cfBlockedURL: String? {
        _cfLock.lock(); defer { _cfLock.unlock() }
        return _cfBlockedByContext[ObjectIdentifier(context)]
    }

    nonisolated func clearCFBlock() {
        _cfLock.lock()
        _cfBlockedByContext.removeValue(forKey: ObjectIdentifier(context))
        _cfLock.unlock()
    }

    deinit {
        _cfLock.lock()
        _cfBlockedByContext.removeValue(forKey: ObjectIdentifier(context))
        _cfLock.unlock()
    }

    /// After evaluating the plugin script, check for LNReader-format plugins and:
    /// 1. Bridge parseNovelAndChapters → parseNovel (LNReader uses the former)
    /// 2. Wrap all async plugin methods so they return synchronously (using Promise microtask flush)
    nonisolated private static func injectLNReaderAdapter(into ctx: JSContext) {
        ctx.evaluateScript("""
        (function(global) {
            // LNReader v3 compiled plugins export via module.exports (CommonJS)
            // instead of setting globalThis.plugin directly.
            if (!global.plugin) {
                var _me = (typeof module !== 'undefined' && module && module.exports) ? module.exports : null;
                if (_me && typeof _me.popularNovels === 'function') {
                    global.plugin = _me;
                } else if (_me && _me.default && typeof _me.default.popularNovels === 'function') {
                    global.plugin = _me.default;
                }
            }

            var p = global.plugin;
            if (!p || typeof p !== 'object') return;

            // LNReader uses parseNovelAndChapters; Yomi bridge calls parseNovel.
            if (typeof p.parseNovelAndChapters === 'function' && typeof p.parseNovel !== 'function') {
                p.parseNovel = function(path) { return p.parseNovelAndChapters(path); };
            }
            // Note: async wrapping via _resolve is NOT done here.
            // Swift callers use evaluateScript + JSContextDrainMicrotasks to flush Promises.
        })(this);
        """)
    }

    /// After evaluating the plugin script, inspect exports for a Paperback Source subclass
    /// and wire up Yomi-compatible global functions (getMangaList, searchManga, etc.).
    nonisolated private static func injectPaperbackAdapter(into ctx: JSContext) {
        ctx.evaluateScript("""
        (function(global) {
            // Detect paperback-extensions-common Source base class
            var pbCommon = (function() {
                try { return require('paperback-extensions-common'); } catch(e) { return null; }
            })();
            if (!pbCommon || !pbCommon.Source) return;

            // Find a Paperback Source subclass in exports
            var SourceClass = null;
            var allExports = typeof exports !== 'undefined' ? exports : {};
            var keys = Object.keys(allExports);
            for (var i = 0; i < keys.length; i++) {
                var val = allExports[keys[i]];
                if (typeof val === 'function' && val.prototype instanceof pbCommon.Source) {
                    SourceClass = val;
                    break;
                }
            }
            if (!SourceClass) return;

            // Mark as Paperback plugin
            global.__pbSourceId = SourceClass.name || 'PBSource';

            // Instantiate the source
            var instance;
            try { instance = new SourceClass(global.cheerio); } catch(e) { return; }

            // Helper: resolve a Promise synchronously (works because SOURCE.fetch is sync)
            function _resolve(val) {
                if (val && typeof val.then === 'function') {
                    var result;
                    val.then(function(v) { result = v; });
                    return result;
                }
                return val;
            }

            // ------------------------------------------------------------------
            // getMangaList(page) → collect items from getHomePageSections callback
            // ------------------------------------------------------------------
            global.getMangaList = function(page) {
                var items = [];
                var done = false;
                try {
                    var p = instance.getHomePageSections(function(section) {
                        var sItems = section && section.items ? section.items : [];
                        sItems.forEach(function(tile) {
                            if (!tile || !tile.id) return;
                            items.push({
                                id:       tile.id,
                                path:     tile.id,
                                title:    tile.title && tile.title.text ? tile.title.text : (tile.title || tile.id),
                                coverURL: tile.image && tile.image.value ? tile.image.value : (tile.image || null),
                                summary:  null,
                                author:   null,
                                artist:   null,
                                status:   'ongoing',
                                genres:   []
                            });
                        });
                        return Promise.resolve();
                    }, []);
                    _resolve(p);
                } catch(e) {}
                return items;
            };

            // ------------------------------------------------------------------
            // searchManga(query, page) → getSearchResults
            // ------------------------------------------------------------------
            global.searchManga = function(query, page) {
                var items = [];
                try {
                    var searchReq = { title: query, parameters: {} };
                    var p = instance.getSearchResults(searchReq, { page: page || 1 });
                    var paged = _resolve(p);
                    var results = paged && paged.results ? paged.results : [];
                    results.forEach(function(r) {
                        if (!r) return;
                        var id = r.mangaId || r.id || '';
                        items.push({
                            id:       id,
                            path:     id,
                            title:    r.title && r.title.text ? r.title.text : (r.title || id),
                            coverURL: r.image && r.image.value ? r.image.value : (r.image || null),
                            summary:  null,
                            author:   null,
                            artist:   null,
                            status:   'ongoing',
                            genres:   []
                        });
                    });
                } catch(e) {}
                return items;
            };

            // ------------------------------------------------------------------
            // getChapterList(mangaPath) → getChapters(mangaPath)
            // Chapter path encodes mangaId|chapterId for later getPageList call
            // ------------------------------------------------------------------
            global.getChapterList = function(mangaPath) {
                var chapters = [];
                try {
                    var p = instance.getChapters(mangaPath);
                    var raw = _resolve(p);
                    if (!Array.isArray(raw)) return [];
                    raw.forEach(function(ch, i) {
                        var cid = ch.id || String(i);
                        chapters.push({
                            id:            mangaPath + '|' + cid,
                            path:          mangaPath + '|' + cid,
                            name:          ch.title || ch.name || ('Chapter ' + (ch.chapNum || i)),
                            chapterNumber: ch.chapNum || 0,
                            scanlator:     ch.group || ch.scanlator || null
                        });
                    });
                } catch(e) {}
                return chapters;
            };

            // ------------------------------------------------------------------
            // getPageList(chapterPath) → getChapterDetails(mangaId, chapterId)
            // chapterPath is "mangaId|chapterId" as encoded above
            // ------------------------------------------------------------------
            global.getPageList = function(chapterPath) {
                try {
                    var sep = chapterPath.indexOf('|');
                    if (sep === -1) return [];
                    var mangaId   = chapterPath.substring(0, sep);
                    var chapterId = chapterPath.substring(sep + 1);
                    var p = instance.getChapterDetails(mangaId, chapterId);
                    var details = _resolve(p);
                    return details && details.pages ? details.pages : [];
                } catch(e) { return []; }
            };

        })(this);
        """)
    }

    // MARK: - Format D: Mangayomi JS shims + adapter

    /// Pre-eval: injects Client, Document/Element classes and String utilities for Mangayomi plugins.
    nonisolated private static func injectMangayomiShims(into ctx: JSContext) {
        ctx.evaluateScript(#"""
        (function(global) {
            'use strict';

            // ── Client ──────────────────────────────────────────────────────────
            function Client() {}
            Client.prototype.get = function(url, headers) {
                headers = headers || {};
                var body = SOURCE._fetchSync(url, 'GET', null, JSON.stringify(headers));
                return Promise.resolve({ body: body, status: 200 });
            };
            Client.prototype.post = function(url, headers, body) {
                headers = headers || {};
                var bodyStr = body ? (typeof body === 'string' ? body : JSON.stringify(body)) : null;
                var resp = SOURCE._fetchSync(url, 'POST', bodyStr, JSON.stringify(headers));
                return Promise.resolve({ body: resp, status: 200 });
            };
            Client.prototype.request = function(url, options) {
                options = options || {};
                var method  = (options.method  || 'GET').toUpperCase();
                var headers = options.headers  || {};
                var body    = options.body     || null;
                var bodyStr = body ? (typeof body === 'string' ? body : JSON.stringify(body)) : null;
                var resp = SOURCE._fetchSync(url, method, bodyStr, JSON.stringify(headers));
                return Promise.resolve({ body: resp, status: 200 });
            };
            global.Client = Client;

            // ── Document / Element ───────────────────────────────────────────────
            // _nullEl is returned for empty/missing selections so callers never get null.
            var _nullEl;
            _nullEl = {
                text: '', outerHtml: '', innerHTML: '', id: '', className: '',
                src: '', href: '',
                attr: function() { return ''; },
                get getSrc() { return ''; },
                get getHref() { return ''; },
                select: function() { return []; },
                selectFirst: function() { return _nullEl; },
                children: [],
                hasClass: function() { return false; },
                nextElement: null, previousElement: null,
                isNull: true, isNotEmpty: false,
                toString: function() { return ''; }
            };
            // Patch self-references (can't reference _nullEl before assignment in the literal)
            _nullEl.nextElement = _nullEl;
            _nullEl.previousElement = _nullEl;

            // Wrap a cheerio collection into a Mangayomi-compatible Element object.
            // jq is a cheerio wrapper object (has .text(), .attr(), .find(), .each(), etc.)
            // getSrc / getHref are getter properties (not methods) — Mangayomi plugins access
            // them as `el.getSrc` not `el.getSrc()`.
            function _mkEl(jq) {
                if (!jq || jq.length === 0) return _nullEl;
                var el = {};
                Object.defineProperties(el, {
                    text:        { get: function() { return jq.text() || ''; } },
                    outerHtml:   { get: function() { return jq.html() || ''; } },
                    innerHTML:   { get: function() { return jq.html() || ''; } },
                    id:          { get: function() { return jq.attr('id')    || ''; } },
                    className:   { get: function() { return jq.attr('class') || ''; } },
                    src:         { get: function() { return jq.attr('src')   || ''; } },
                    href:        { get: function() { return jq.attr('href')  || ''; } },
                    getSrc:      { get: function() { return jq.attr('src')   || ''; } },
                    getHref:     { get: function() { return jq.attr('href')  || ''; } },
                    isNull:      { get: function() { return jq.length === 0; } },
                    isNotEmpty:  { get: function() { return jq.length > 0;  } },
                    children: {
                        get: function() {
                            var r = [], kids = jq.children();
                            for (var i = 0; i < kids.length; i++) r.push(_mkEl(kids.eq(i)));
                            return r;
                        }
                    },
                    parent:          { get: function() { return _mkEl(jq.parent()); } },
                    nextElement:     { get: function() { return _mkEl(jq.next());   } },
                    previousElement: { get: function() { return _mkEl(jq.prev());   } }
                });
                el.attr       = function(name) { return jq.attr(name) || ''; };
                el.hasClass   = function(cls)  { return jq.hasClass(cls); };
                el.select     = function(sel)  {
                    var r = [], found = jq.find(sel);
                    for (var i = 0; i < found.length; i++) r.push(_mkEl(found.eq(i)));
                    return r;
                };
                el.selectFirst = function(sel) { return _mkEl(jq.find(sel).first()); };
                el.toString    = function()    { return jq.html() || ''; };
                return el;
            }

            function Document(html) {
                this._$ = cheerio.load(html || '');
            }
            Document.prototype.select = function(sel) {
                // .eq(i), not each()'s raw DOM node — _mkEl needs a cheerio selection (.text(), .attr()…).
                var r = [], found = this._$(sel);
                for (var i = 0; i < found.length; i++) r.push(_mkEl(found.eq(i)));
                return r;
            };
            Document.prototype.selectFirst = function(sel) {
                return _mkEl(this._$(sel).first());
            };
            global.Document = Document;

            // ── String utilities ─────────────────────────────────────────────────
            if (!String.prototype.substringAfter) {
                String.prototype.substringAfter = function(s) {
                    var i = this.indexOf(s); return i === -1 ? '' : this.slice(i + s.length);
                };
            }
            if (!String.prototype.substringAfterLast) {
                String.prototype.substringAfterLast = function(s) {
                    var i = this.lastIndexOf(s); return i === -1 ? '' : this.slice(i + s.length);
                };
            }
            if (!String.prototype.substringBefore) {
                String.prototype.substringBefore = function(s) {
                    var i = this.indexOf(s); return i === -1 ? '' + this : this.slice(0, i);
                };
            }
            if (!String.prototype.substringBeforeLast) {
                String.prototype.substringBeforeLast = function(s) {
                    var i = this.lastIndexOf(s); return i === -1 ? '' + this : this.slice(0, i);
                };
            }
            if (!String.prototype.substringBetween) {
                String.prototype.substringBetween = function(from, to) {
                    return this.substringAfter(from).substringBefore(to);
                };
            }

            // ── Preferences stub ─────────────────────────────────────────────────
            var _prefs = {};
            global.Preferences = {
                get: function(k) { return Object.prototype.hasOwnProperty.call(_prefs, k) ? _prefs[k] : null; },
                set: function(k, v) { _prefs[k] = v; }
            };

            // ── MProvider base class ──────────────────────────────────────────────
            // Current Mangayomi plugins use: class DefaultExtension extends MProvider { ... }
            // The host sets instance.source = mangayomiSources[0] after instantiation.
            function MProvider() {}
            global.MProvider = MProvider;

            // ── SharedPreferences ────────────────────────────────────────────────
            // Mangayomi plugins call: new SharedPreferences().get("key")
            var _sharedPrefs = {};
            function SharedPreferences() {}
            SharedPreferences.prototype.get = function(k) {
                return Object.prototype.hasOwnProperty.call(_sharedPrefs, k) ? _sharedPrefs[k] : null;
            };
            SharedPreferences.prototype.set = function(k, v) { _sharedPrefs[k] = v; };
            global.SharedPreferences = SharedPreferences;

        })(this);
        """#)
    }

    /// Post-eval: detects a Mangayomi source and sets the __mangayomiSource sentinel.
    /// Two formats are supported:
    ///   Legacy: plain `source` object with getPopular/getDetail methods
    ///   Current: `class DefaultExtension extends MProvider` + `mangayomiSources` array
    /// All actual method calls go through Swift's evaluateScript (see callMangayomiGetList
    /// etc.) so that native async/await microtasks drain before Swift reads the result.
    nonisolated private static func injectMangayomiAdapter(into ctx: JSContext) {
        ctx.evaluateScript("""
        (function(global) {
            var src = null;

            // Legacy format: plain `source` object (const at top-level → lexical, use typeof)
            try {
                if (typeof source !== 'undefined' && source !== null &&
                    typeof source.getPopular === 'function' && typeof source.getDetail === 'function') {
                    src = source;
                }
            } catch(e) {}

            // Current Mangayomi format: class DefaultExtension extends MProvider + mangayomiSources[]
            if (!src) {
                try {
                    if (typeof DefaultExtension !== 'undefined' &&
                        typeof mangayomiSources !== 'undefined' &&
                        Array.isArray(mangayomiSources) && mangayomiSources.length > 0) {
                        var meta = mangayomiSources[0];
                        // Normalize: mangayomiSources uses "langs" array; instance.source needs "lang" string
                        if (!meta.lang && meta.langs && meta.langs.length > 0) {
                            meta.lang = meta.langs[0];
                        }
                        var inst = new DefaultExtension();
                        inst.source = meta;
                        if (typeof inst.getPopular === 'function' || typeof inst.getDetail === 'function') {
                            src = inst;
                        }
                    }
                } catch(e) {}
            }

            if (!src) return;

            // Sentinel — isMangayomiPlugin reads __mangayomiSource
            global.__mangayomiSource = src;

            // Expose which "latest" method this source has (Swift reads __mgy_latestMethod)
            global.__mgy_latestMethod = typeof src.getLatestUpdates === 'function'
                ? 'getLatestUpdates'
                : (typeof src.getLatest === 'function' ? 'getLatest' : null);
            global.__mgy_hasLatest = !!global.__mgy_latestMethod;

        })(this);
        """)
    }

    // MARK: - Shims

    nonisolated private static func injectShims(into ctx: JSContext) {
        injectSyncPromise(into: ctx)   // Must be first — replaces global Promise before any plugin code runs
        injectConsole(into: ctx)
        injectStorage(into: ctx)
        injectSourceFetch(into: ctx)
        injectCheerio(into: ctx)       // Bundled libs: cheerio, dayjs, htmlparser2 + URL/atob/TextEncoder/setTimeout polyfills
        injectWebAPIs(into: ctx)       // FormData (+ URL fallback if the bundle is missing)
        injectRequireShim(into: ctx)
        injectMangayomiShims(into: ctx)
    }

    /// URL + URLSearchParams — JSC has no Web APIs, but LNReader plugins call new URL(href, base).
    nonisolated private static func injectWebAPIs(into ctx: JSContext) {
        ctx.evaluateScript(#"""
        (function(global) {
            // The bundled core-js URL/URLSearchParams (yomi-js-libs.js) normally exist already; this hand-written
            // pair is only a fallback. FormData is always installed here.
            var hasURL = typeof global.URL === 'function';

            function URL(input, base) {
                var str = String(input);
                var href = /^[a-zA-Z][a-zA-Z0-9+\-.]*:\/\//.test(str)
                    ? str
                    : (base ? URL._resolve(str, typeof base === 'string' ? base : (base.href || String(base))) : str);
                this._init(href);
            }

            URL._resolve = function(rel, base) {
                var m = base.match(/^((?:[a-zA-Z][a-zA-Z0-9+\-.]*:)?\/\/[^/?#]*)([^?#]*)/);
                if (!m) return rel;
                var origin = m[1], basePath = m[2];
                if (rel.charAt(0) === '/') return origin + rel;
                if (rel.charAt(0) === '?' || rel.charAt(0) === '#') return origin + basePath + rel;
                var dir = basePath.replace(/\/[^/]*$/, '/');
                var parts = (dir + rel).split('/'), out = [];
                for (var i = 0; i < parts.length; i++) {
                    if (parts[i] === '..') { if (out.length > 1) out.pop(); }
                    else if (parts[i] !== '.') out.push(parts[i]);
                }
                return origin + out.join('/');
            };

            URL.prototype._init = function(href) {
                var m = href.match(/^([a-zA-Z][a-zA-Z0-9+\-.]*:)\/\/([^/?#]*)([^?#]*)(\?[^#]*)?(#.*)?$/);
                if (m) {
                    this.protocol = m[1];
                    this.host     = m[2] || '';
                    var ci = this.host.lastIndexOf(':');
                    if (ci >= 0 && /^\d+$/.test(this.host.slice(ci + 1))) {
                        this.hostname = this.host.slice(0, ci);
                        this.port     = this.host.slice(ci + 1);
                    } else { this.hostname = this.host; this.port = ''; }
                    this.pathname = m[3] || '/';
                    this.search   = m[4] || '';
                    this.hash     = m[5] || '';
                    this.origin   = this.protocol + '//' + this.host;
                    this.href     = this.origin + this.pathname + this.search + this.hash;
                } else {
                    this.href = this.origin = this.pathname = href;
                    this.protocol = this.host = this.hostname = this.port = this.search = this.hash = '';
                }
            };

            URL.prototype.toString = function() { return this.href; };
            URL.prototype.toJSON   = function() { return this.href; };

            // URLSearchParams — minimal: get/set/append/toString, iterable entries
            function URLSearchParams(init) {
                this._p = [];
                if (!init) return;
                if (typeof init === 'string') {
                    var s = init.charAt(0) === '?' ? init.slice(1) : init;
                    var pairs = s.split('&');
                    for (var i = 0; i < pairs.length; i++) {
                        var eq = pairs[i].indexOf('=');
                        if (eq >= 0) {
                            this._p.push([decodeURIComponent(pairs[i].slice(0, eq).replace(/\+/g, ' ')),
                                          decodeURIComponent(pairs[i].slice(eq + 1).replace(/\+/g, ' '))]);
                        } else if (pairs[i]) {
                            this._p.push([decodeURIComponent(pairs[i].replace(/\+/g, ' ')), '']);
                        }
                    }
                }
            }
            URLSearchParams.prototype.append = function(k, v) { this._p.push([String(k), String(v)]); };
            URLSearchParams.prototype.get    = function(k) {
                for (var i = 0; i < this._p.length; i++) if (this._p[i][0] === k) return this._p[i][1];
                return null;
            };
            URLSearchParams.prototype.set = function(k, v) {
                for (var i = 0; i < this._p.length; i++) if (this._p[i][0] === k) { this._p[i][1] = String(v); return; }
                this.append(k, v);
            };
            URLSearchParams.prototype.toString = function() {
                return this._p.map(function(p) {
                    return encodeURIComponent(p[0]) + '=' + encodeURIComponent(p[1]);
                }).join('&');
            };

            // FormData — Madara/WordPress multisrc family (52+ LNReader plugins use this for AJAX POSTs)
            function FormData() { this._entries = []; }
            FormData.prototype.append = function(k, v) { this._entries.push([String(k), String(v)]); };
            FormData.prototype.get = function(k) {
                for (var i = 0; i < this._entries.length; i++) if (this._entries[i][0] === k) return this._entries[i][1];
                return null;
            };
            FormData.prototype.has = function(k) {
                for (var i = 0; i < this._entries.length; i++) if (this._entries[i][0] === k) return true;
                return false;
            };
            FormData.prototype.set = function(k, v) {
                for (var i = 0; i < this._entries.length; i++) {
                    if (this._entries[i][0] === k) { this._entries[i][1] = String(v); return; }
                }
                this.append(k, v);
            };
            FormData.prototype.toString = function() {
                return this._entries.map(function(e) {
                    return encodeURIComponent(e[0]) + '=' + encodeURIComponent(e[1]);
                }).join('&');
            };

            if (!hasURL) {
                global.URL             = URL;
                global.URLSearchParams = URLSearchParams;
            }
            if (typeof global.FormData !== 'function') global.FormData = FormData;
        })(this);
        """#)
    }

    /// Replaces the global Promise with a fully-synchronous implementation.
    ///
    /// Why: All SOURCE._fetchSync calls block synchronously (DispatchSemaphore). The resolved values
    /// are therefore available immediately — there is no actual async I/O. However, LNReader v3
    /// plugins compile async/await to __awaiter/__generator which chains .then() callbacks, and
    /// Mangayomi/Paperback adapters use a _resolve() helper that calls .then() and reads the result.
    /// Both patterns assume .then() callbacks fire synchronously when the Promise is already resolved.
    /// The native JSC Promise queues callbacks as microtasks (fired asynchronously), so these patterns
    /// always return undefined. Replacing Promise with a synchronous version fixes all three formats
    /// without requiring any microtask drain mechanism.
    nonisolated private static func injectSyncPromise(into ctx: JSContext) {
        ctx.evaluateScript(#"""
        (function(global) {
            'use strict';

            function SyncPromise(executor) {
                this._state = 'pending';
                this._value = undefined;
                this._callbacks = [];
                var self = this;

                function resolve(value) {
                    if (self._state !== 'pending') return;
                    // Unwrap thenables (handles Promise<Promise<T>> and chained returns)
                    if (value !== null && value !== undefined && typeof value.then === 'function') {
                        try { value.then(resolve, reject); } catch(e) { reject(e); }
                        return;
                    }
                    self._state = 'fulfilled';
                    self._value = value;
                    var cbs = self._callbacks;
                    self._callbacks = [];
                    for (var i = 0; i < cbs.length; i++) {
                        var cb = cbs[i];
                        if (typeof cb.onFulfilled === 'function') {
                            try { cb.resolve(cb.onFulfilled(value)); }
                            catch(e) { cb.reject(e); }
                        } else { cb.resolve(value); }
                    }
                }

                function reject(reason) {
                    if (self._state !== 'pending') return;
                    self._state = 'rejected';
                    self._value = reason;
                    var cbs = self._callbacks;
                    self._callbacks = [];
                    for (var i = 0; i < cbs.length; i++) {
                        var cb = cbs[i];
                        if (typeof cb.onRejected === 'function') {
                            try { cb.resolve(cb.onRejected(reason)); }
                            catch(e) { cb.reject(e); }
                        } else { cb.reject(reason); }
                    }
                }

                try { executor(resolve, reject); } catch(e) { reject(e); }
            }

            SyncPromise.prototype.then = function(onFulfilled, onRejected) {
                var self = this;
                var resolveChild, rejectChild;
                var child = new SyncPromise(function(res, rej) { resolveChild = res; rejectChild = rej; });

                if (self._state === 'fulfilled') {
                    if (typeof onFulfilled === 'function') {
                        try { resolveChild(onFulfilled(self._value)); }
                        catch(e) { rejectChild(e); }
                    } else { resolveChild(self._value); }
                } else if (self._state === 'rejected') {
                    if (typeof onRejected === 'function') {
                        try { resolveChild(onRejected(self._value)); }
                        catch(e) { rejectChild(e); }
                    } else { rejectChild(self._value); }
                } else {
                    self._callbacks.push({
                        onFulfilled: onFulfilled, onRejected: onRejected,
                        resolve: resolveChild, reject: rejectChild
                    });
                }
                return child;
            };

            SyncPromise.prototype.catch = function(onRejected) {
                return this.then(undefined, onRejected);
            };

            SyncPromise.prototype.finally = function(onFinally) {
                return this.then(
                    function(v) { if (typeof onFinally === 'function') onFinally(); return v; },
                    function(r) { if (typeof onFinally === 'function') onFinally(); throw r; }
                );
            };

            SyncPromise.resolve = function(value) {
                if (value instanceof SyncPromise) return value;
                return new SyncPromise(function(resolve) { resolve(value); });
            };

            SyncPromise.reject = function(reason) {
                return new SyncPromise(function(_, reject) { reject(reason); });
            };

            SyncPromise.all = function(promises) {
                if (!promises || promises.length === 0) return SyncPromise.resolve([]);
                var results = new Array(promises.length);
                var remaining = promises.length;
                return new SyncPromise(function(resolve, reject) {
                    for (var i = 0; i < promises.length; i++) {
                        (function(idx) {
                            SyncPromise.resolve(promises[idx]).then(
                                function(v) { results[idx] = v; if (--remaining === 0) resolve(results); },
                                reject
                            );
                        })(i);
                    }
                });
            };

            SyncPromise.allSettled = function(promises) {
                if (!promises || promises.length === 0) return SyncPromise.resolve([]);
                var results = new Array(promises.length);
                var remaining = promises.length;
                return new SyncPromise(function(resolve) {
                    for (var i = 0; i < promises.length; i++) {
                        (function(idx) {
                            SyncPromise.resolve(promises[idx]).then(
                                function(v) { results[idx] = {status:'fulfilled',value:v}; if (--remaining===0) resolve(results); },
                                function(r) { results[idx] = {status:'rejected',reason:r}; if (--remaining===0) resolve(results); }
                            );
                        })(i);
                    }
                });
            };

            SyncPromise.race = function(promises) {
                return new SyncPromise(function(resolve, reject) {
                    if (!promises || promises.length === 0) return;
                    for (var i = 0; i < promises.length; i++) {
                        SyncPromise.resolve(promises[i]).then(resolve, reject);
                    }
                });
            };

            SyncPromise.any = function(promises) {
                if (!promises || promises.length === 0)
                    return SyncPromise.reject(new Error('All promises were rejected'));
                var errors = new Array(promises.length);
                var remaining = promises.length;
                return new SyncPromise(function(resolve, reject) {
                    for (var i = 0; i < promises.length; i++) {
                        (function(idx) {
                            SyncPromise.resolve(promises[idx]).then(resolve, function(e) {
                                errors[idx] = e;
                                if (--remaining === 0) reject(errors);
                            });
                        })(i);
                    }
                });
            };

            global.Promise = SyncPromise;

        })(this);
        """#)
    }

    /// console.log / warn / error → Swift print()
    nonisolated private static func injectConsole(into ctx: JSContext) {
        let log:   @convention(block) (String) -> Void = { print("📋 JS log:",   $0) }
        let warn:  @convention(block) (String) -> Void = { print("⚠️  JS warn:",  $0) }
        let error: @convention(block) (String) -> Void = { print("❌ JS error:", $0) }
        let console = JSValue(newObjectIn: ctx)
        console?.setObject(log,   forKeyedSubscript: "log"   as NSString)
        console?.setObject(warn,  forKeyedSubscript: "warn"  as NSString)
        console?.setObject(error, forKeyedSubscript: "error" as NSString)
        ctx.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    /// localStorage / sessionStorage — pure in-memory JS objects
    nonisolated private static func injectStorage(into ctx: JSContext) {
        ctx.evaluateScript("""
        (function() {
            function makeStorage() {
                var _s = {};
                return {
                    getItem:    function(k)    { return Object.prototype.hasOwnProperty.call(_s, k) ? _s[k] : null; },
                    setItem:    function(k, v) { _s[k] = String(v); },
                    removeItem: function(k)    { delete _s[k]; },
                    clear:      function()     { _s = {}; }
                };
            }
            var localStorage    = makeStorage();
            var sessionStorage  = makeStorage();
            this.localStorage   = localStorage;
            this.sessionStorage = sessionStorage;
        }).call(this);
        """)
    }

    /// SOURCE.fetch(url, options?) — synchronous HTTP via DispatchSemaphore (GET and POST).
    /// JS wrapper routes through SOURCE._fetchSync(url, method, body, headersJSON).
    #if DEBUG
    /// Set by `LNReaderHarness` to print every plugin request.
    nonisolated(unsafe) static var debugLogFetches = false
    #endif

    nonisolated private static func injectSourceFetch(into ctx: JSContext) {
        let ctxID = ObjectIdentifier(ctx)
        /// One blocking request. Returns the body plus what a fetch() Response needs: status, final URL after
        /// redirects (Madara plugins compare it to the requested host to spot captcha redirects) and headers.
        func perform(_ urlString: String, _ method: String, _ body: String?, _ headersJSON: String?)
            -> (body: String, status: Int, url: String, headers: [String: String]) {
            guard let url = URL(string: urlString) else { return ("", 0, urlString, [:]) }
            var request = URLRequest(url: url, timeoutInterval: jsBridgeRequestTimeout)
            // Default headers — prevents Cloudflare/CDN blocks
            request.setValue(CFBypassConstants.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            // Plugin headers override defaults
            if let json = headersJSON,
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (key, value) in dict {
                    request.setValue("\(value)", forHTTPHeaderField: key)
                }
            }
            // Method + optional body
            request.httpMethod = method
            if method == "POST", let bodyStr = body {
                request.httpBody = bodyStr.data(using: .utf8)
            }
            var result = ""
            var status = 0
            var finalURL = urlString
            var responseHeaders: [String: String] = [:]
            var detectedCFURL: String? = nil
            let sem = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: request) { data, response, error in
                yomiLogNetwork(request, response: response, data: data, error: error)
                if let data = data {
                    result = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
                }
                if let http = response as? HTTPURLResponse {
                    status = http.statusCode
                    finalURL = http.url?.absoluteString ?? urlString
                    for (key, value) in http.allHeaderFields {
                        responseHeaders[String(describing: key).lowercased()] = String(describing: value)
                    }
                    let hasCFRay = http.allHeaderFields["CF-RAY"] != nil
                    let isErrorStatus = http.statusCode >= 400
                    let bodyHasCF = result.contains("Just a moment")
                        || result.contains("cf-mitigated")
                        || result.contains("Cloudflare Ray ID")
                        || result.contains("cf-browser-verification")
                        || result.contains("Attention Required! | Cloudflare")
                        || result.contains("Please enable cookies")
                    if hasCFRay || (isErrorStatus && bodyHasCF) { detectedCFURL = urlString }
                }
                sem.signal()
            }.resume()
            sem.wait()
            if let blocked = detectedCFURL {
                _cfLock.lock()
                _cfBlockedByContext[ctxID] = blocked
                _cfLock.unlock()
            }
            #if DEBUG
            if debugLogFetches {
                print("[JSBridge fetch] \(status) \(method) \(urlString)\(finalURL != urlString ? " -> \(finalURL)" : "") "
                      + "\(result.count) chars title=\(result.range(of: "<title>[^<]*", options: .regularExpression).map { String(result[$0].dropFirst(7).prefix(60)) } ?? "-")")
            }
            #endif
            return (result, status, finalURL, responseHeaders)
        }
        let fetchSync: @convention(block) (String, String, String?, String?) -> String = { url, method, body, headers in
            perform(url, method, body, headers).body
        }
        let fetchResponse: @convention(block) (String, String, String?, String?) -> [String: Any] = {
            url, method, body, headers in
            let r = perform(url, method, body, headers)
            return ["body": r.body, "status": r.status, "url": r.url, "headers": r.headers]
        }
        let source = JSValue(newObjectIn: ctx)
        source?.setObject(fetchSync, forKeyedSubscript: "_fetchSync" as NSString)
        source?.setObject(fetchResponse, forKeyedSubscript: "_fetchResponse" as NSString)
        ctx.setObject(source, forKeyedSubscript: "SOURCE" as NSString)
        // JS wrapper: reads options, delegates to Swift _fetchSync
        ctx.evaluateScript("""
        SOURCE.fetch = function(url, options) {
            options = options || {};
            var method  = (options.method || 'GET').toUpperCase();
            var body    = options.body    || null;
            var headers = options.headers || {};
            return SOURCE._fetchSync(url, method, body, JSON.stringify(headers));
        };

        // LNReader-compatible global fetchApi — wraps SOURCE._fetchSync, returns a Promise
        // so that LNReader async plugins can do: const html = await fetchApi(url).then(r=>r.text())
        this.fetchApi = function(url, options) {
            options = options || {};
            var method   = (options.method || 'GET').toUpperCase();
            var rawBody  = options.body;
            var origHdrs = options.headers || {};
            var headers, bodyStr;
            if (typeof URLSearchParams === 'function' && rawBody instanceof URLSearchParams) {
                // URLSearchParams body — sent as a form, like fetch() does (was JSON-stringified to "{}").
                bodyStr = rawBody.toString();
                headers = {}; for (var uk in origHdrs) headers[uk] = origHdrs[uk];
                if (!headers['Content-Type'] && !headers['content-type'])
                    headers['Content-Type'] = 'application/x-www-form-urlencoded;charset=UTF-8';
            } else if (rawBody && typeof rawBody === 'object' && rawBody._entries) {
                // FormData — serialize as application/x-www-form-urlencoded
                bodyStr = rawBody._entries.map(function(e) {
                    return encodeURIComponent(e[0]) + '=' + encodeURIComponent(e[1]);
                }).join('&');
                headers = {}; for (var hk in origHdrs) headers[hk] = origHdrs[hk];
                if (!headers['Content-Type'] && !headers['content-type'])
                    headers['Content-Type'] = 'application/x-www-form-urlencoded';
            } else {
                bodyStr = rawBody ? (typeof rawBody === 'string' ? rawBody : JSON.stringify(rawBody)) : null;
                headers = origHdrs;
            }
            return Promise.resolve(SOURCE._makeResponse(
                SOURCE._fetchResponse(url, method, bodyStr, JSON.stringify(headers)), url));
        };

        // A fetch()-style Response: real status/ok, final URL after redirects, headers.get().
        SOURCE._makeResponse = function(r, requestedURL) {
            var text = (r && r.body) || '';
            var hdrs = (r && r.headers) || {};
            var status = (r && r.status) || 0;
            return {
                ok:         status >= 200 && status < 300,
                status:     status,
                statusText: '',
                url:        (r && r.url) || requestedURL,
                redirected: !!(r && r.url && r.url !== requestedURL),
                headers: {
                    get: function(k) { var v = hdrs[String(k).toLowerCase()]; return v === undefined ? null : v; },
                    has: function(k) { return hdrs[String(k).toLowerCase()] !== undefined; }
                },
                text: function() { return Promise.resolve(text); },
                json: function() {
                    try { return Promise.resolve(JSON.parse(text)); }
                    catch(e) { return Promise.reject(e); }
                }
            };
        };

        // Plugin namespace — satisfies TypeScript `implements Plugin.PluginBase`
        this.Plugin = { PluginBase: function() {} };
        """)
    }

    /// The real JS libraries LNReader plugins are written against — cheerio 1.2.0, htmlparser2, dayjs — bundled by
    /// `scripts/build-js-libs.mjs` into `Resources/yomi-js-libs.js` (~400 KB). They replaced a hand-written cheerio
    /// that threw on `.remove()`/`.contents()`/`.get()` and ignored compound selectors, breaking ~half of LNReader's
    /// plugins (RESEARCH.md §22.4, §22.14). Read once per process; evaluated into every JSContext.
    nonisolated private static let jsLibsSource: String? = {
        guard let url = Bundle.main.url(forResource: "yomi-js-libs", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    nonisolated private static func injectCheerio(into ctx: JSContext) {
        guard let source = jsLibsSource else {
            print("[JSBridge] yomi-js-libs.js missing from the app bundle — cheerio unavailable")
            return
        }
        ctx.evaluateScript(source)
        // `global.cheerio.load` keeps the old stand-in's leniency: a selector the real parser rejects returns an
        // empty selection instead of throwing, which Yomi's own plugins were written against.
        ctx.evaluateScript(#"""
        (function(global) {
            var libs = global.__yomiLibs;
            if (!libs) return;
            // Yomi's own catalog plugins were written against the old stand-in, whose each()/map() handed the
            // callback a wrapped element (`el.find(...)`); real cheerio hands over the raw DOM node (what LNReader
            // plugins expect — they call $(el) or read el.attribs). Give raw nodes the few cheerio methods those
            // plugins call, forwarding to a real selection. Names that DOM nodes already have (children, parent,
            // next, prev, data…) are left alone, so LNReader plugins see exactly the nodes they expect.
            if (!libs.__nodeCompat) {
                libs.__nodeCompat = true;
                var wrap$ = libs.cheerio.load('');
                var proto = Object.getPrototypeOf(libs.cheerio.load('<p>x</p>')('p')[0]);
                while (Object.getPrototypeOf(proto) && Object.getPrototypeOf(proto) !== Object.prototype) {
                    proto = Object.getPrototypeOf(proto);
                }
                ['find', 'text', 'attr', 'html', 'hasClass', 'first', 'last', 'eq', 'each', 'map', 'filter', 'is',
                 'closest', 'parents', 'siblings', 'contents', 'toArray'].forEach(function(m) {
                    if (m in proto) return;
                    Object.defineProperty(proto, m, {
                        configurable: true, writable: true, enumerable: false,
                        value: function() { var w = wrap$(this); return w[m].apply(w, arguments); }
                    });
                });
            }
            global.cheerio = {
                load: function(html, options, isDocument) {
                    var $ = libs.cheerio.load(html == null ? '' : String(html), options, isDocument);
                    return new Proxy($, {
                        apply: function(target, thisArg, args) {
                            try { return Reflect.apply(target, thisArg, args); }
                            catch (e) { return target([]); }
                        }
                    });
                }
            };
        })(this);
        """#)
    }

    /// require() shim — supports: cheerio, he, node-fetch, axios. Unknown modules return {}.
    /// Also injects: module, exports, process globals for LNReader v2.x TS-compiled plugins.
    nonisolated private static func injectRequireShim(into ctx: JSContext) {
        ctx.evaluateScript("""
        (function(global) {
            var __moduleCache = {};

            function require(name) {
                if (__moduleCache[name]) return __moduleCache[name];

                var mod = { exports: {} };

                if (name === 'cheerio') {
                    mod.exports = global.cheerio || {};

                } else if (name === 'he') {
                    mod.exports = (function() {
                        var entities = {
                            'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"',
                            'apos': "'", 'nbsp': '\\u00A0', 'copy': '©',
                            'reg': '®', 'trade': '™', 'mdash': '—',
                            'ndash': '–', 'lsquo': '\\u2018', 'rsquo': '\\u2019',
                            'ldquo': '\\u201C', 'rdquo': '\\u201D', 'hellip': '…',
                            'euro': '€', 'pound': '£', 'yen': '¥',
                            'cent': '¢', 'deg': '°', 'plusmn': '±',
                            'times': '×', 'divide': '÷', 'frac12': '½',
                            'frac14': '¼', 'frac34': '¾', 'acute': '´',
                            'micro': 'µ', 'para': '¶', 'middot': '·',
                            'iquest': '¿', 'iexcl': '¡', 'szlig': 'ß'
                        };
                        function decode(str) {
                            if (typeof str !== 'string') return str;
                            return str.replace(/&([^;]+);/g, function(match, code) {
                                if (code.charAt(0) === '#') {
                                    var num = code.charAt(1) === 'x'
                                        ? parseInt(code.slice(2), 16)
                                        : parseInt(code.slice(1), 10);
                                    return isNaN(num) ? match : String.fromCharCode(num);
                                }
                                return entities[code] || match;
                            });
                        }
                        function encode(str) {
                            if (typeof str !== 'string') return str;
                            return str
                                .replace(/&/g, '&amp;')
                                .replace(/</g, '&lt;')
                                .replace(/>/g, '&gt;')
                                .replace(/"/g, '&quot;')
                                .replace(/'/g, '&#x27;');
                        }
                        return { decode: decode, encode: encode };
                    })();

                } else if (name === 'node-fetch' || name === 'node-fetch/src/index.js') {
                    mod.exports = function nodeFetch(url, options) {
                        var method = (options && options.method) ? options.method : 'GET';
                        var body   = (options && options.body)   ? options.body   : '';
                        var hdrs   = (options && options.headers)
                            ? JSON.stringify(options.headers) : '{}';
                        var responseText = SOURCE._fetchSync(url, method, body, hdrs);
                        return {
                            ok: true,
                            status: 200,
                            text:   function() { return Promise.resolve(responseText); },
                            json:   function() {
                                return Promise.resolve(JSON.parse(responseText));
                            }
                        };
                    };

                } else if (name === 'axios') {
                    mod.exports = {
                        get: function(url, config) {
                            var hdrs = (config && config.headers)
                                ? JSON.stringify(config.headers) : '{}';
                            var text = SOURCE._fetchSync(url, 'GET', '', hdrs);
                            return Promise.resolve({ data: text, status: 200 });
                        },
                        post: function(url, data, config) {
                            var hdrs = (config && config.headers)
                                ? JSON.stringify(config.headers) : '{}';
                            var body = typeof data === 'string' ? data : JSON.stringify(data);
                            var text = SOURCE._fetchSync(url, 'POST', body, hdrs);
                            return Promise.resolve({ data: text, status: 200 });
                        }
                    };

                } else if (name === 'paperback-extensions-common') {
                    // Paperback compatibility shim
                    // Provides the base Source class and App type-constructors
                    mod.exports = (function() {
                        // Request manager — wraps SOURCE._fetchSync synchronously.
                        // _fetchSync signature: (url, method, body, headersJSON) — 4 args.
                        function createRequestManager() {
                            return {
                                schedule: function(request) {
                                    var url = request.url || '';
                                    if (request.param) {
                                        url += (url.indexOf('?') === -1 ? '?' : '&') + request.param;
                                    }
                                    var method  = (request.method || 'GET').toUpperCase();
                                    var body    = request.data    ? JSON.stringify(request.data) : null;
                                    var headers = request.headers ? JSON.stringify(request.headers) : null;
                                    var text = SOURCE._fetchSync(url, method, body, headers);
                                    return Promise.resolve({ data: text, status: 200 });
                                }
                            };
                        }

                        // Base Source class — every Paperback plugin extends this.
                        // requestManager is set on construction so subclasses that call
                        // this.requestManager.schedule() without assigning it themselves work.
                        function Source(cheerio) {
                            this.cheerio = cheerio;
                            this.requestManager = createRequestManager();
                        }
                        function createRequest(opts) { return opts || {}; }
                        function createMangaTile(opts) {
                            return {
                                id:    opts.id || '',
                                image: (opts.image && opts.image.value) ? opts.image.value : (opts.image || ''),
                                title: (opts.title && opts.title.text)  ? opts.title.text  : (opts.title  || '')
                            };
                        }
                        function createIconText(opts) { return opts || {}; }
                        function createHomeSection(opts) {
                            return { id: opts.id, title: opts.title || '', type: opts.type, items: [], containsMoreItems: !!opts.containsMoreItems };
                        }
                        function createChapter(opts)        { return opts || {}; }
                        function createChapterDetails(opts) { return opts || {}; }
                        function createManga(opts)          { return opts || {}; }
                        function createSearchResult(opts)   { return opts || {}; }
                        function createPagedResults(opts)   { return opts || {}; }
                        function createTag(opts)            { return opts || {}; }
                        function createTagSection(opts)     { return opts || {}; }

                        var App = {
                            createRequestManager: createRequestManager,
                            createRequest: createRequest,
                            createMangaTile: createMangaTile,
                            createIconText: createIconText,
                            createHomeSection: createHomeSection,
                            createChapter: createChapter,
                            createChapterDetails: createChapterDetails,
                            createManga: createManga,
                            createSearchResult: createSearchResult,
                            createPagedResults: createPagedResults,
                            createTag: createTag,
                            createTagSection: createTagSection
                        };

                        return { Source: Source, App: App };
                    })();

                } else if (name === '@libs/storage') {
                    // LNReader storage utility — in-memory key-value store
                    var _lnStore = {};
                    mod.exports = {
                        storage: {
                            get: function(k) { return Object.prototype.hasOwnProperty.call(_lnStore, k) ? _lnStore[k] : null; },
                            set: function(k, v) { _lnStore[k] = v; }
                        }
                    };

                } else if (name === '@libs/filterInputs') {
                    mod.exports = { FilterTypes: {}, Filters: {} };

                } else if (name === '@libs/defaultCover') {
                    mod.exports = { defaultCover: '' };

                } else if (name === '@libs/fetch') {
                    // LNReader v3 fetch helper — plugin calls n.fetchApi(url, opts)
                    mod.exports = {
                        fetchApi: function(url, options) {
                            var method  = (options && options.method) ? options.method.toUpperCase() : 'GET';
                            var rawBody = (options && options.body) ? options.body : null;
                            var origHdrs = (options && options.headers) ? options.headers : {};
                            var bodyStr, hdrs;
                            if (typeof URLSearchParams === 'function' && rawBody instanceof URLSearchParams) {
                                bodyStr = rawBody.toString();
                                hdrs = {}; for (var uk in origHdrs) hdrs[uk] = origHdrs[uk];
                                if (!hdrs['Content-Type'] && !hdrs['content-type'])
                                    hdrs['Content-Type'] = 'application/x-www-form-urlencoded;charset=UTF-8';
                            } else if (rawBody && typeof rawBody === 'object' && rawBody._entries) {
                                // FormData — serialize as application/x-www-form-urlencoded
                                bodyStr = rawBody._entries.map(function(e) {
                                    return encodeURIComponent(e[0]) + '=' + encodeURIComponent(e[1]);
                                }).join('&');
                                hdrs = {}; for (var hk in origHdrs) hdrs[hk] = origHdrs[hk];
                                if (!hdrs['Content-Type'] && !hdrs['content-type'])
                                    hdrs['Content-Type'] = 'application/x-www-form-urlencoded';
                            } else {
                                bodyStr = rawBody ? (typeof rawBody === 'string' ? rawBody : JSON.stringify(rawBody)) : '';
                                hdrs = origHdrs;
                            }
                            return Promise.resolve(SOURCE._makeResponse(
                                SOURCE._fetchResponse(url, method, bodyStr, JSON.stringify(hdrs)), url));
                        },
                        // LNReader's fetchText resolves to the body, or '' on a failed request.
                        fetchText: function(url, init) {
                            return this.fetchApi(url, init).then(function(res) {
                                return res.ok ? res.text() : '';
                            });
                        }
                    };

                } else if (name === '@libs/novelStatus') {
                    mod.exports = {
                        NovelStatus: {
                            Ongoing: 'Ongoing', Completed: 'Completed', Unknown: 'Unknown',
                            Hiatus: 'Hiatus', OnHiatus: 'Hiatus',
                            Cancelled: 'Cancelled', Canceled: 'Cancelled'
                        }
                    };

                } else if (name === 'dayjs') {
                    // Real dayjs (+ customParseFormat, relativeTime, utc) from the bundled libraries.
                    mod.exports = global.__yomiLibs ? global.__yomiLibs.dayjs : function(d) { return new Date(d); };

                } else if (name === 'htmlparser2') {
                    mod.exports = global.__yomiLibs ? global.__yomiLibs.htmlparser2 : {};

                } else if (name === '@libs/isAbsoluteUrl') {
                    // LNReader exports `isUrlAbsolute`; the bare-function form stays callable for older plugins.
                    var isUrlAbsolute = function(url) {
                        var s = String(url); var c = s.indexOf('://'); return c > 0 && c < 20;
                    };
                    isUrlAbsolute.isUrlAbsolute = isUrlAbsolute;
                    mod.exports = isUrlAbsolute;

                } else if (name === '@/types/constants') {
                    // NovelFire only — compiled output rebinds the import variable; empty object is safe
                    mod.exports = {};

                } else {
                    // Unknown module — return empty exports, do not crash
                    mod.exports = {};
                }

                __moduleCache[name] = mod.exports;
                return mod.exports;
            }

            global.require = require;
            global.module  = { exports: {} };
            global.exports = global.module.exports;
            global.process = { env: { NODE_ENV: 'production' }, version: 'v18.0.0',
                               platform: 'ios', versions: {} };

        })(this);
        """)
    }

    // MARK: - Plugin API — Manga (Format A / C / D)

    nonisolated func getMangaList(page: Int, sourceId: String) -> [Manga] {
        if isMangayomiPlugin {
            return callMangayomiGetList(method: "getPopular", page: page, sourceId: sourceId)
        }
        let result = context
            .objectForKeyedSubscript("getMangaList")?
            .call(withArguments: [page])
        return JSBridge.parseMangaArray(result, sourceId: sourceId)
    }

    /// Returns the latest-updated manga list. Returns [] if the plugin doesn't support it.
    nonisolated func getLatestManga(page: Int, sourceId: String) -> [Manga] {
        if isMangayomiPlugin {
            guard let methodVal = context.objectForKeyedSubscript("__mgy_latestMethod"),
                  !methodVal.isUndefined, !methodVal.isNull,
                  let method = methodVal.toString(),
                  method != "undefined", method != "null"
            else { return [] }
            return callMangayomiGetList(method: method, page: page, sourceId: sourceId)
        }
        guard
            let fn = context.objectForKeyedSubscript("getLatestManga"),
            !fn.isUndefined, !fn.isNull, fn.isObject
        else { return [] }
        let result = fn.call(withArguments: [page])
        return JSBridge.parseMangaArray(result, sourceId: sourceId)
    }

    /// True if this plugin supports a latest-updates feed.
    nonisolated var supportsLatest: Bool {
        if isMangayomiPlugin {
            guard let flag = context.objectForKeyedSubscript("__mgy_hasLatest"),
                  !flag.isUndefined, !flag.isNull else { return false }
            return flag.toBool()
        }
        guard let fn = context.objectForKeyedSubscript("getLatestManga") else { return false }
        return !fn.isUndefined && !fn.isNull && fn.isObject
    }

    nonisolated func getChapterList(mangaPath: String, mangaId: String) -> [Chapter] {
        if isMangayomiPlugin {
            context.setObject(mangaPath as AnyObject, forKeyedSubscript: "__mgy_url" as NSString)
            // getDetail → extract chapters in JS to avoid toDictionary() type-cast failures
            // on complex JSC objects. Normalises all known field-name variants here.
            context.evaluateScript("""
            __mgy_result = undefined;
            __mgy_chapters = [];
            (function() {
                try {
                    var __r = __mangayomiSource.getDetail(__mgy_url);
                    if (__r && typeof __r.then === 'function') {
                        __r.then(function(v) { __mgy_result = v; });
                    } else { __mgy_result = __r; }
                } catch(e) { console.error('Mangayomi getDetail: ' + e); }
                if (!__mgy_result) return;
                var raw = __mgy_result.episodes || __mgy_result.chapters ||
                          __mgy_result.chapterList || __mgy_result.chapter_list || [];
                if (!Array.isArray(raw)) return;
                __mgy_chapters = raw.map(function(e, i) {
                    var url = e.url || e.link || e.id || e.href || e.path || '';
                    var name = e.name || e.title || ('Episode ' + (i + 1));
                    var scanlator = e.scanlator || e.team || null;
                    return { url: url, name: name, scanlator: scanlator };
                }).filter(function(e) { return e.url.length > 0; });
            })();
            """)
            guard let arr = context.objectForKeyedSubscript("__mgy_chapters"),
                  !arr.isUndefined, !arr.isNull,
                  let items = arr.toArray() as? [[String: Any]] else { return [] }
            // Cache manga metadata from the same getDetail result (no extra network call)
            context.evaluateScript("""
            __mgy_meta = (function() {
                if (!__mgy_result) return {};
                return {
                    summary: __mgy_result.description || __mgy_result.synopsis || __mgy_result.summary || null,
                    status:  __mgy_result.status || null,
                    cover:   __mgy_result.imageUrl || __mgy_result.cover || __mgy_result.thumbnail || null
                };
            })();
            """)
            if let meta = context.objectForKeyedSubscript("__mgy_meta")?.toDictionary() as? [String: Any] {
                let coverURL = (meta["cover"] as? String).flatMap { URL(string: $0) }
                lastMangayomiMeta = (
                    summary: meta["summary"] as? String,
                    status: meta["status"] as? String,
                    coverURL: coverURL
                )
            }
            return items.enumerated().compactMap { (index, ch) in
                let chURL = ch["url"] as? String ?? ""
                guard !chURL.isEmpty else { return nil }
                let name = ch["name"] as? String ?? "Episode \(index + 1)"
                let scanlator = ch["scanlator"] as? String
                return Chapter(
                    id: chURL, mangaId: mangaId, path: chURL, name: name,
                    chapterNumber: Double(index),
                    isRead: false, isDownloaded: false, downloadedAt: nil, readAt: nil,
                    progress: 0.0, readingSeconds: 0, lastPageRead: 0, scanlator: scanlator
                )
            }
        }
        let result = context
            .objectForKeyedSubscript("getChapterList")?
            .call(withArguments: [mangaPath])
        return JSBridge.parseChapterArray(result, mangaId: mangaId)
    }

    nonisolated func getPageList(chapterPath: String) -> [String] {
        if isMangayomiPlugin {
            context.setObject(chapterPath as AnyObject, forKeyedSubscript: "__mgy_url" as NSString)
            context.evaluateScript("""
            __mgy_result = undefined;
            (function() {
                try {
                    var __r = __mangayomiSource.getPageList(__mgy_url);
                    if (__r && typeof __r.then === 'function') {
                        __r.then(function(v) { __mgy_result = v; });
                    } else { __mgy_result = __r; }
                } catch(e) { console.error('Mangayomi getPageList: ' + e); }
            })();
            """)
            guard let raw = context.objectForKeyedSubscript("__mgy_result"),
                  !raw.isUndefined, !raw.isNull else { return [] }
            return raw.toArray()?.compactMap { $0 as? String }.filter { !$0.isEmpty } ?? []
        }
        let result = context
            .objectForKeyedSubscript("getPageList")?
            .call(withArguments: [chapterPath])
        return result?.toArray() as? [String] ?? []
    }

    // MARK: - Mangayomi (Format D) — evaluateScript callers

    /// Calls a Mangayomi list method (getPopular / getLatestUpdates / getLatest) via evaluateScript
    /// so that JSC drains native async/await microtasks before Swift reads the result.
    nonisolated private func callMangayomiGetList(method: String, page: Int, sourceId: String) -> [Manga] {
        context.setObject(page as AnyObject, forKeyedSubscript: "__mgy_p" as NSString)
        context.evaluateScript("""
        __mgy_result = undefined;
        (function() {
            try {
                var __r = __mangayomiSource['\(method)'](__mgy_p);
                if (__r && typeof __r.then === 'function') {
                    __r.then(function(v) { __mgy_result = v; });
                } else { __mgy_result = __r; }
            } catch(e) { console.error('Mangayomi \(method): ' + e); }
        })();
        """)
        guard let raw = context.objectForKeyedSubscript("__mgy_result"),
              !raw.isUndefined, !raw.isNull,
              let dict = raw.toDictionary() as? [String: Any],
              let list = dict["list"] as? [[String: Any]] else { return [] }
        return list.compactMap { JSBridge.parseMangayomiItem($0, sourceId: sourceId) }
    }

    /// Maps a Mangayomi list item `{link, name, imageUrl}` to a Manga model.
    nonisolated private static func parseMangayomiItem(_ item: [String: Any], sourceId: String) -> Manga? {
        let path: String
        if let link = item["link"] as? String, !link.isEmpty { path = link }
        else if let url = item["url"] as? String, !url.isEmpty { path = url }
        else { return nil }
        let title: String
        if let name = item["name"] as? String, !name.isEmpty { title = name }
        else if let t = item["title"] as? String, !t.isEmpty { title = t }
        else { return nil }
        let imageURLStr = item["imageUrl"] as? String ?? item["image"] as? String
        return Manga(
            id: path, path: path, sourceId: sourceId, title: title,
            coverURL: imageURLStr.flatMap { URL(string: $0) },
            summary: nil, author: nil, artist: nil,
            status: .unknown, genres: [],
            inLibrary: false, isLocal: false, lastReadAt: nil, lastUpdatedAt: nil, readingSeconds: 0
        )
    }

    // MARK: - Discussion URL (optional plugin export)

    /// Returns the URL string for the chapter's comment/discussion page, or nil if the plugin
    /// doesn't implement `getDiscussionURL(chapterPath)`.
    nonisolated func getDiscussionURL(chapterPath: String) -> URL? {
        guard
            let fn = context.objectForKeyedSubscript("getDiscussionURL"),
            !fn.isUndefined, !fn.isNull, fn.isObject
        else { return nil }
        let result = fn.call(withArguments: [chapterPath])
        guard let urlString = result?.toString(), !urlString.isEmpty,
              urlString != "undefined", urlString != "null"
        else { return nil }
        return URL(string: urlString)
    }

    // MARK: - Source URL (best-effort, no plugin changes required)

    /// Absolute URL of a chapter/manga's page on its origin site — backs the reader's
    /// "view source" icon. `path` is usually source-relative (each plugin strips its own
    /// `BASE_URL`/`BASE` constant before storing `path`), so this opportunistically reads that
    /// same top-level global back out of the JS context and re-prepends it. Not every plugin
    /// exposes a resolvable base this way — IIFE-bundled plugins (esbuild output, `var BASE_URL`
    /// stays lexically scoped) and pure-API sources (MangaDex, Comick — `path` is an id, not a
    /// URL segment) can't resolve one. Returns nil rather than guessing; callers should hide the
    /// icon in that case instead of showing a dead link.
    nonisolated func resolveSourceURL(path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        guard let result = context.evaluateScript(
            "(typeof BASE_URL !== 'undefined') ? BASE_URL : ((typeof BASE !== 'undefined') ? BASE : '')"
        ), let base = result.toString(), !base.isEmpty, base != "undefined" else { return nil }
        return URL(string: base + path)
    }

    // MARK: - Search

    nonisolated func searchManga(query: String, page: Int, sourceId: String) -> [Manga] {
        if isLNReaderPlugin { return [] }
        if isMangayomiPlugin {
            context.setObject(query as AnyObject, forKeyedSubscript: "__mgy_q" as NSString)
            context.setObject(page as AnyObject,  forKeyedSubscript: "__mgy_p" as NSString)
            context.evaluateScript("""
            __mgy_result = undefined;
            (function() {
                try {
                    if (typeof __mangayomiSource.search !== 'function') {
                        __mgy_result = { list: [] }; return;
                    }
                    var __r = __mangayomiSource.search(__mgy_q, __mgy_p, []);
                    if (__r && typeof __r.then === 'function') {
                        __r.then(function(v) { __mgy_result = v; });
                    } else { __mgy_result = __r; }
                } catch(e) { console.error('Mangayomi search: ' + e); }
            })();
            """)
            guard let raw = context.objectForKeyedSubscript("__mgy_result"),
                  !raw.isUndefined, !raw.isNull,
                  let dict = raw.toDictionary() as? [String: Any],
                  let list = dict["list"] as? [[String: Any]] else { return [] }
            return list.compactMap { JSBridge.parseMangayomiItem($0, sourceId: sourceId) }
        }
        guard
            let fn = context.objectForKeyedSubscript("searchManga"),
            !fn.isUndefined, !fn.isNull
        else { return [] }
        let result = fn.call(withArguments: [query, page])
        return JSBridge.parseMangaArray(result, sourceId: sourceId)
    }

    // MARK: - Plugin API — Novel (Format B)

    // MARK: - Async-safe plugin caller
    //
    // LNReader v3 plugins compile TypeScript async/await to __awaiter/__generator (Promise-based).
    // JSValue.call(withArguments:) returns the Promise immediately — `result` in our old _resolve
    // trick was set after we already returned `undefined` to Swift.
    //
    // Fix: use evaluateScript so JSC's internal drainMicrotasks() fires at the end of the call.
    // The entire async chain (fetchApi → response.text → parseNovels) resolves in that drain
    // because SOURCE._fetchSync is synchronous — no real async I/O, just Promise wrappers.
    // After evaluateScript returns, __lnr_result holds the resolved value.

    nonisolated private func callPluginMethod(_ name: String, argGlobals: [String]) {
        let argList = argGlobals.joined(separator: ", ")
        context.evaluateScript("""
        __lnr_result = undefined;
        __lnr_reject_reason = undefined;
        (function() {
            try {
                var __r = plugin['\(name)'](\(argList));
                if (__r && typeof __r.then === 'function') {
                    __lnr_debug_r = __r;
                    __r.then(function(v) { __lnr_result = v; }, function(e) { __lnr_reject_reason = String(e); });
                } else { __lnr_result = __r; }
            } catch(e) { __lnr_last_error = e; __lnr_reject_reason = String(e); console.error('plugin.\(name) error: ' + e); }
        })();
        """)
        // evaluateScript internally calls JSC's drainMicrotasks() before returning,
        // so __lnr_result is guaranteed to be set when we read it below.
    }

    /// What the last LNReader plugin call left in `__lnr_result`, for diagnosing an empty result that came with no
    /// error: "undefined" usually means a promise that never settled.
    nonisolated var lastResultSummary: String {
        context.evaluateScript("""
        (function(r) {
            if (r === undefined) return 'undefined (promise never settled?)';
            if (r === null) return 'null';
            if (Array.isArray(r)) return 'array(' + r.length + ')' + (r.length ? ' first=' + JSON.stringify(r[0]).slice(0, 160) : '');
            return typeof r + ' ' + JSON.stringify(r).slice(0, 160);
        })(__lnr_result)
        """)?.toString() ?? "?"
    }

    /// Why the last LNReader plugin call failed (a thrown error or rejected promise), if it did.
    nonisolated var lastPluginError: String? {
        guard let value = context.objectForKeyedSubscript("__lnr_reject_reason"), !value.isUndefined, !value.isNull
        else { return nil }
        return value.toString()
    }

    nonisolated func popularNovels(page: Int) -> [NovelItem] {
        context.setObject(page as AnyObject, forKeyedSubscript: "__lnr_p" as NSString)
        // LNReader popularNovels(page, options) — pass plugin's own filter defaults so
        // t.filters.genres.value / t.filters.type.value don't throw on null.
        context.evaluateScript("""
        __lnr_opts = {
            filters: (typeof plugin !== 'undefined' && plugin && plugin.filters) ? plugin.filters : {},
            showLatestNovels: false
        };
        """)
        callPluginMethod("popularNovels", argGlobals: ["__lnr_p", "__lnr_opts"])
        let raw = context.objectForKeyedSubscript("__lnr_result")
        return JSBridge.parseNovelItems(raw)
    }

    /// True when the LNReader plugin supports a latest-updated feed (all LNReader plugins do).
    nonisolated var supportsLatestNovels: Bool { isLNReaderPlugin }

    /// Fetches the latest-updated novel list from an LNReader plugin.
    nonisolated func latestNovels(page: Int) -> [NovelItem] {
        context.setObject(page as AnyObject, forKeyedSubscript: "__lnr_p" as NSString)
        context.evaluateScript("""
        __lnr_opts = {
            filters: (typeof plugin !== 'undefined' && plugin && plugin.filters) ? plugin.filters : {},
            showLatestNovels: true
        };
        """)
        callPluginMethod("popularNovels", argGlobals: ["__lnr_p", "__lnr_opts"])
        let raw = context.objectForKeyedSubscript("__lnr_result")
        return JSBridge.parseNovelItems(raw)
    }

    nonisolated func searchNovels(query: String, page: Int) -> [NovelItem] {
        context.setObject(query as AnyObject, forKeyedSubscript: "__lnr_q" as NSString)
        context.setObject(page as AnyObject,  forKeyedSubscript: "__lnr_p" as NSString)
        callPluginMethod("searchNovels", argGlobals: ["__lnr_q", "__lnr_p"])
        return JSBridge.parseNovelItems(context.objectForKeyedSubscript("__lnr_result"))
    }

    nonisolated func parseNovel(path: String) -> SourceNovel? {
        context.setObject(path as AnyObject, forKeyedSubscript: "__lnr_path" as NSString)
        callPluginMethod("parseNovel", argGlobals: ["__lnr_path"])
        guard let dict = context.objectForKeyedSubscript("__lnr_result")?.toDictionary() as? [String: Any] else { return nil }
        var rawChapters = dict["chapters"] as? [[String: Any]] ?? []
        // Paged plugins (Novel Fire, LnMTL, …) return `totalPages` and serve chapters through parsePage(path, page).
        // LNReader loads pages as you scroll; Yomi's chapter list is one list, so fetch them all (capped).
        if let totalPages = (dict["totalPages"] as? NSNumber)?.intValue, totalPages > 0 {
            let novelPath = dict["path"] as? String ?? path
            var paged: [[String: Any]] = []
            for page in 1...min(totalPages, 150) {
                context.setObject(novelPath as AnyObject, forKeyedSubscript: "__lnr_path" as NSString)
                context.setObject(String(page) as AnyObject, forKeyedSubscript: "__lnr_page" as NSString)
                callPluginMethod("parsePage", argGlobals: ["__lnr_path", "__lnr_page"])
                let pageDict = context.objectForKeyedSubscript("__lnr_result")?.toDictionary() as? [String: Any]
                guard let chapters = pageDict?["chapters"] as? [[String: Any]], !chapters.isEmpty else { break }
                paged.append(contentsOf: chapters)
            }
            if !paged.isEmpty { rawChapters = paged }
        }
        let chapters: [JSNovelChapter] = rawChapters.compactMap {
            guard let name = $0["name"] as? String, let cPath = $0["path"] as? String else { return nil }
            return JSNovelChapter(
                name:          name,
                path:          cPath,
                chapterNumber: $0["chapterNumber"] as? Double,
                releaseTime:   $0["releaseTime"]   as? String
            )
        }
        return SourceNovel(
            path:     dict["path"]    as? String ?? path,
            name:     dict["name"]    as? String ?? "",
            cover:    dict["cover"]   as? String,
            author:   dict["author"]  as? String,
            summary:  dict["summary"] as? String,
            status:   dict["status"]  as? String,
            chapters: chapters
        )
    }

    nonisolated func parseChapter(path: String) -> String {
        context.setObject(path as AnyObject, forKeyedSubscript: "__lnr_path" as NSString)
        callPluginMethod("parseChapter", argGlobals: ["__lnr_path"])
        return context.objectForKeyedSubscript("__lnr_result")?.toString() ?? ""
    }

    // MARK: - Parsers

    nonisolated private static func parseMangaArray(_ value: JSValue?, sourceId: String) -> [Manga] {
        guard let items = value?.toArray() as? [[String: Any]] else { return [] }
        return items.compactMap { dict in
            guard
                let id    = dict["id"]    as? String,
                let path  = dict["path"]  as? String,
                let title = dict["title"] as? String
            else { return nil }
            return Manga(
                id:            id,
                path:          path,
                sourceId:      sourceId,
                title:         title,
                coverURL:      (dict["coverURL"] as? String).flatMap { URL(string: $0) },
                summary:       dict["summary"] as? String,
                author:        dict["author"]  as? String,
                artist:        dict["artist"]  as? String,
                status:        MangaStatus(rawValue: dict["status"] as? String ?? "") ?? .unknown,
                genres:        dict["genres"]  as? [String] ?? [],
                inLibrary:      false,
                isLocal:        false,
                lastReadAt:     nil,
                lastUpdatedAt:  nil,
                readingSeconds: 0
            )
        }
    }

    nonisolated private static func parseChapterArray(_ value: JSValue?, mangaId: String) -> [Chapter] {
        guard let items = value?.toArray() as? [[String: Any]] else { return [] }
        return items.compactMap { dict in
            guard
                let id   = dict["id"]   as? String,
                let path = dict["path"] as? String,
                let name = dict["name"] as? String
            else { return nil }
            return Chapter(
                id:            id,
                mangaId:       mangaId,
                path:          path,
                name:          name,
                chapterNumber: dict["chapterNumber"] as? Double,
                isRead:          false,
                isDownloaded:    false,
                downloadedAt:    nil,
                readAt:          nil,
                progress:        0.0,
                readingSeconds:  0,
                lastPageRead:    0,
                scanlator:       dict["scanlator"] as? String
            )
        }
    }

    nonisolated private static func parseNovelItems(_ value: JSValue?) -> [NovelItem] {
        guard let items = value?.toArray() as? [[String: Any]] else { return [] }
        return items.compactMap { dict in
            guard
                let name = dict["name"] as? String,
                let path = dict["path"] as? String
            else { return nil }
            return NovelItem(name: name, path: path, cover: dict["cover"] as? String)
        }
    }
}
