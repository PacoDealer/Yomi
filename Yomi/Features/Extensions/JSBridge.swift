import Foundation
import JavaScriptCore

// Module-level CF-block tracking — keyed by JSContext identity, guarded by _cfLock.
nonisolated private let _cfLock = NSLock()
nonisolated(unsafe) private var _cfBlockedByContext: [ObjectIdentifier: String] = [:]

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

    // MARK: - Paperback format detection

    /// true when the plugin exports a Paperback-format Source class (detected by __pbSourceId global)
    nonisolated var isPaperbackPlugin: Bool {
        guard
            let flag = context.objectForKeyedSubscript("__pbSourceId"),
            !flag.isUndefined, !flag.isNull
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
                            var r = [];
                            jq.children().each(function(i, child) { r.push(_mkEl(child)); });
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
                    var r = [];
                    jq.find(sel).each(function(i, child) { r.push(_mkEl(child)); });
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
                var r = [];
                this._$(sel).each(function(i, el) { r.push(_mkEl(el)); });
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
        injectWebAPIs(into: ctx)       // URL, URLSearchParams — required by LNReader plugins
        injectCheerio(into: ctx)
        injectRequireShim(into: ctx)
        injectMangayomiShims(into: ctx)
    }

    /// URL + URLSearchParams — JSC has no Web APIs, but LNReader plugins call new URL(href, base).
    nonisolated private static func injectWebAPIs(into ctx: JSContext) {
        ctx.evaluateScript(#"""
        (function(global) {
            if (typeof global.URL === 'function') return;

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

            global.URL             = URL;
            global.URLSearchParams = URLSearchParams;
            global.FormData        = FormData;
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
    nonisolated private static func injectSourceFetch(into ctx: JSContext) {
        let ctxID = ObjectIdentifier(ctx)
        let fetchSync: @convention(block) (String, String, String?, String?) -> String = { urlString, method, body, headersJSON in
            guard let url = URL(string: urlString) else { return "" }
            var request = URLRequest(url: url, timeoutInterval: 30)
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
            var detectedCFURL: String? = nil
            let sem = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: request) { data, response, _ in
                if let data = data { result = String(data: data, encoding: .utf8) ?? "" }
                if let http = response as? HTTPURLResponse {
                    let hasCFRay = http.allHeaderFields["CF-RAY"] != nil
                    let is403 = http.statusCode == 403
                    let bodyHasCF = result.contains("Just a moment") || result.contains("cf-mitigated")
                    if hasCFRay || (is403 && bodyHasCF) { detectedCFURL = urlString }
                }
                sem.signal()
            }.resume()
            sem.wait()
            if let blocked = detectedCFURL {
                _cfLock.lock()
                _cfBlockedByContext[ctxID] = blocked
                _cfLock.unlock()
            }
            return result
        }
        let source = JSValue(newObjectIn: ctx)
        source?.setObject(fetchSync, forKeyedSubscript: "_fetchSync" as NSString)
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
            if (rawBody && typeof rawBody === 'object' && rawBody._entries) {
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
            var responseText = SOURCE._fetchSync(url, method, bodyStr, JSON.stringify(headers));
            return Promise.resolve({
                ok:     true,
                status: 200,
                text:   function() { return Promise.resolve(responseText); },
                json:   function() {
                    try { return Promise.resolve(JSON.parse(responseText)); }
                    catch(e) { return Promise.reject(e); }
                }
            });
        };

        // Plugin namespace — satisfies TypeScript `implements Plugin.PluginBase`
        this.Plugin = { PluginBase: function() {} };
        """)
    }

    /// Full cheerio shim — hand-written recursive descent HTML parser + CSS selector engine.
    /// Supports: tag, .class, #id, tag.class, tag[attr], tag[attr=val], descendant combinator, comma lists.
    /// Methods: text(), html(), attr(), find(), each(), map(), first(), last(), eq(), length, toArray(),
    ///          parent(), children(), is(), hasClass(), filter(), next(), prev()
    nonisolated private static func injectCheerio(into ctx: JSContext) {
        // Raw string literal: backslashes pass through unchanged — no double-escaping needed for JS regex.
        ctx.evaluateScript(#"""
        (function(global) {
            'use strict';

            // ── Void elements (never push onto stack) ───────────────────────────────
            var VOID = {area:1,base:1,br:1,col:1,embed:1,hr:1,img:1,input:1,
                        link:1,meta:1,param:1,source:1,track:1,wbr:1};

            // ── Node constructors ────────────────────────────────────────────────────
            function El(tag) { return {type:'el',tag:tag,attrs:{},children:[],parent:null}; }
            function Tx(t)   { return {type:'tx',text:t,children:[],parent:null}; }

            // ── HTML parser ──────────────────────────────────────────────────────────
            // Tokenises with indexOf + regex; builds a node tree; resilient to malformed HTML.
            function parse(html) {
                html = html || '';
                var root = El('#root');
                var stack = [root];
                var i = 0, n = html.length;

                function top() { return stack[stack.length - 1]; }

                function skipTo(str) {
                    var idx = html.indexOf(str, i);
                    i = (idx === -1) ? n : idx + str.length;
                }

                function appendChild(node) {
                    node.parent = top();
                    top().children.push(node);
                }

                while (i < n) {
                    var lt = html.indexOf('<', i);
                    if (lt === -1) {
                        var rem = html.slice(i);
                        if (rem) appendChild(Tx(rem));
                        break;
                    }
                    if (lt > i) appendChild(Tx(html.slice(i, lt)));
                    i = lt + 1;
                    if (i >= n) break;

                    // Comment
                    if (html.substr(i, 3) === '!--') { skipTo('-->'); continue; }
                    // Doctype / processing instruction
                    if (html[i] === '!') { skipTo('>'); continue; }

                    // Closing tag
                    if (html[i] === '/') {
                        var gt0 = html.indexOf('>', i);
                        var raw0 = html.slice(i + 1, gt0 === -1 ? n : gt0).trim().toLowerCase().split(/\s/)[0];
                        i = gt0 === -1 ? n : gt0 + 1;
                        for (var s0 = stack.length - 1; s0 > 0; s0--) {
                            if (stack[s0].tag === raw0) { stack.length = s0; break; }
                        }
                        continue;
                    }

                    // Opening tag — scan to '>' respecting quoted attribute values
                    var end = i;
                    var inQ = null;
                    while (end < n) {
                        var ch = html[end];
                        if (inQ) { if (ch === inQ) inQ = null; }
                        else if (ch === '"' || ch === "'") { inQ = ch; }
                        else if (ch === '>') break;
                        end++;
                    }
                    var rawTag = html.slice(i, end);
                    i = end + 1;

                    var selfClose = rawTag.slice(-1) === '/';
                    if (selfClose) rawTag = rawTag.slice(0, -1);

                    var nm = rawTag.match(/^([a-zA-Z][a-zA-Z0-9:_-]*)/);
                    if (!nm) continue;
                    var tag = nm[1].toLowerCase();

                    // Parse attributes
                    var attrs = {};
                    var rest = rawTag.slice(nm[0].length);
                    var aRe = /([a-zA-Z_:][a-zA-Z0-9_:.-]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]*)))?/g;
                    var am;
                    while ((am = aRe.exec(rest)) !== null) {
                        var av = am[2] !== undefined ? am[2]
                               : am[3] !== undefined ? am[3]
                               : (am[4] || '');
                        attrs[am[1].toLowerCase()] = av;
                    }

                    var el = El(tag);
                    el.attrs = attrs;
                    appendChild(el);

                    if (!selfClose && !VOID[tag]) {
                        stack.push(el);
                        // Raw text elements: consume verbatim until the matching close tag
                        if (tag === 'script' || tag === 'style') {
                            var close = '</' + tag;
                            var ci = html.toLowerCase().indexOf(close, i);
                            var rawTxt = ci === -1 ? html.slice(i) : html.slice(i, ci);
                            if (rawTxt) { var tx = Tx(rawTxt); tx.parent = el; el.children.push(tx); }
                            if (ci !== -1) {
                                var cgt = html.indexOf('>', ci);
                                i = cgt === -1 ? n : cgt + 1;
                            } else { i = n; }
                            stack.pop();
                        }
                    }
                }
                return root;
            }

            // ── All descendants in document order ────────────────────────────────────
            function descendants(node) {
                var out = [];
                var ch = node.children || [];
                for (var i = 0; i < ch.length; i++) {
                    out.push(ch[i]);
                    var sub = descendants(ch[i]);
                    for (var j = 0; j < sub.length; j++) out.push(sub[j]);
                }
                return out;
            }

            // ── CSS selector engine ──────────────────────────────────────────────────
            // Parses one simple selector token (tag, .class, #id, [attr], [attr=val], combinations).
            function parseSimple(sel) {
                var tag=null, id=null, cls=null, attr=null, attrVal=null, hasAttr=false;
                // [attr=val] or [attr]
                var am = sel.match(/\[([a-zA-Z_:][a-zA-Z0-9_:.-]*)(?:=["']?([^"'\]]*)["']?)?\]/);
                if (am) {
                    attr = am[1].toLowerCase(); hasAttr = true;
                    attrVal = am[2] !== undefined ? am[2] : null;
                    sel = sel.replace(am[0], '');
                }
                var im = sel.match(/#([\w-]+)/);
                if (im) { id = im[1]; sel = sel.replace(im[0], ''); }
                var cm = sel.match(/\.([\w-]+)/);
                if (cm) { cls = cm[1]; sel = sel.replace(cm[0], ''); }
                var tm = sel.match(/^([a-zA-Z][\w-]*)/);
                if (tm) { tag = tm[1].toLowerCase(); }
                return {tag:tag, id:id, cls:cls, attr:attr, attrVal:attrVal, hasAttr:hasAttr};
            }

            function matchesSimple(node, s) {
                if (node.type !== 'el' || node.tag === '#root') return false;
                if (s.tag && node.tag !== s.tag) return false;
                if (s.id  && node.attrs.id !== s.id) return false;
                if (s.cls && (node.attrs['class'] || '').split(/\s+/).indexOf(s.cls) === -1) return false;
                if (s.hasAttr) {
                    if (!(s.attr in node.attrs)) return false;
                    if (s.attrVal !== null && node.attrs[s.attr] !== s.attrVal) return false;
                }
                return true;
            }

            // Select nodes matching selectorStr within ctx.
            // Handles: comma lists, descendant combinator (space), child combinator (>).
            function select(ctx, selectorStr) {
                if (!selectorStr || typeof selectorStr !== 'string') return [];
                var parts = selectorStr.split(',');
                if (parts.length > 1) {
                    var r = [];
                    for (var p = 0; p < parts.length; p++) {
                        var sub = select(ctx, parts[p].trim());
                        for (var q = 0; q < sub.length; q++) {
                            if (r.indexOf(sub[q]) === -1) r.push(sub[q]);
                        }
                    }
                    return r;
                }
                // Tokenise into simple selectors + combinators ('>' or ' ')
                var raw = selectorStr.trim();
                var tokens = [], combinators = [];
                var re = /\s*>\s*|\s+/g, last = 0, rm;
                while ((rm = re.exec(raw)) !== null) {
                    tokens.push(raw.slice(last, rm.index).trim());
                    combinators.push(rm[0].indexOf('>') !== -1 ? '>' : ' ');
                    last = rm.index + rm[0].length;
                }
                tokens.push(raw.slice(last).trim());

                var pool = descendants(ctx);
                var s0 = parseSimple(tokens[0]);
                var matched = pool.filter(function(n) { return matchesSimple(n, s0); });
                for (var si = 1; si < tokens.length; si++) {
                    var sp = parseSimple(tokens[si]);
                    var comb = combinators[si - 1];
                    var next = [];
                    for (var mi = 0; mi < matched.length; mi++) {
                        if (comb === '>') {
                            // Child combinator: direct element children only
                            var ch = (matched[mi].children || []);
                            for (var ci = 0; ci < ch.length; ci++) {
                                if (ch[ci].type === 'el' && matchesSimple(ch[ci], sp) && next.indexOf(ch[ci]) === -1)
                                    next.push(ch[ci]);
                            }
                        } else {
                            // Descendant combinator
                            var d = descendants(matched[mi]);
                            for (var di = 0; di < d.length; di++) {
                                if (matchesSimple(d[di], sp) && next.indexOf(d[di]) === -1) next.push(d[di]);
                            }
                        }
                    }
                    matched = next;
                }
                return matched;
            }

            // ── Serialization ────────────────────────────────────────────────────────
            function textOf(node) {
                if (node.type === 'tx') return node.text || '';
                var out = '';
                var ch = node.children || [];
                for (var i = 0; i < ch.length; i++) out += textOf(ch[i]);
                return out;
            }

            function htmlOf(node) {
                var out = '';
                var ch = node.children || [];
                for (var i = 0; i < ch.length; i++) {
                    var c = ch[i];
                    if (c.type === 'tx') {
                        out += c.text || '';
                    } else {
                        var as = '';
                        for (var k in c.attrs) as += ' ' + k + '="' + c.attrs[k] + '"';
                        out += '<' + c.tag + as + '>' + htmlOf(c) + '</' + c.tag + '>';
                    }
                }
                return out;
            }

            // ── Cheerio wrapper ──────────────────────────────────────────────────────
            function wrap(nodes) {
                var obj = {
                    length: nodes.length,
                    text: function() {
                        return nodes.map(function(n) { return textOf(n); }).join('');
                    },
                    html: function() {
                        return nodes.length ? htmlOf(nodes[0]) : '';
                    },
                    attr: function(name) {
                        return nodes.length ? nodes[0].attrs[name.toLowerCase()] : undefined;
                    },
                    find: function(sel) {
                        var found = [];
                        for (var i = 0; i < nodes.length; i++) {
                            var sub = select(nodes[i], sel);
                            for (var j = 0; j < sub.length; j++) {
                                if (found.indexOf(sub[j]) === -1) found.push(sub[j]);
                            }
                        }
                        return wrap(found);
                    },
                    each: function(fn) {
                        for (var i = 0; i < nodes.length; i++) {
                            var w = wrap([nodes[i]]);
                            fn.call(w, i, w);
                        }
                        return obj;
                    },
                    map: function(fn) {
                        var r = [];
                        for (var i = 0; i < nodes.length; i++) {
                            var w = wrap([nodes[i]]);
                            r.push(fn.call(w, i, w));
                        }
                        return r;
                    },
                    first:   function() { return wrap(nodes.length ? [nodes[0]] : []); },
                    last:    function() { return wrap(nodes.length ? [nodes[nodes.length-1]] : []); },
                    eq: function(i) {
                        var idx = i < 0 ? nodes.length + i : i;
                        return wrap(idx >= 0 && idx < nodes.length ? [nodes[idx]] : []);
                    },
                    toArray: function() { return nodes.slice(); },
                    parent: function() {
                        var ps = [];
                        for (var i = 0; i < nodes.length; i++) {
                            var p = nodes[i].parent;
                            if (p && p.tag !== '#root' && ps.indexOf(p) === -1) ps.push(p);
                        }
                        return wrap(ps);
                    },
                    children: function(sel) {
                        var ch = [];
                        for (var i = 0; i < nodes.length; i++) {
                            var c = (nodes[i].children || []).filter(function(n) { return n.type === 'el'; });
                            for (var j = 0; j < c.length; j++) {
                                if (!sel || matchesSimple(c[j], parseSimple(sel))) ch.push(c[j]);
                            }
                        }
                        return wrap(ch);
                    },
                    is: function(sel) {
                        try { return nodes.length ? matchesSimple(nodes[0], parseSimple(sel)) : false; }
                        catch(e) { return false; }
                    },
                    hasClass: function(c) {
                        return nodes.length ? (nodes[0].attrs['class'] || '').split(/\s+/).indexOf(c) !== -1 : false;
                    },
                    filter: function(sel) {
                        if (typeof sel === 'string') {
                            var s = parseSimple(sel);
                            return wrap(nodes.filter(function(n) { return matchesSimple(n, s); }));
                        }
                        return wrap(nodes.filter(sel));
                    },
                    next: function() { return wrap([]); },
                    prev: function() { return wrap([]); }
                };
                return obj;
            }

            // ── Public API ───────────────────────────────────────────────────────────
            global.cheerio = {
                load: function(html) {
                    var root;
                    try { root = parse(html); } catch(e) { root = El('#root'); }
                    function $(selector) {
                        try {
                            if (!selector) return wrap([]);
                            if (typeof selector === 'object') {
                                // Raw DOM node (from each/map callback)
                                if (selector.type) return wrap([selector]);
                                // Already a wrap object — return as-is
                                if (typeof selector.find === 'function') return selector;
                                return wrap([]);
                            }
                            if (selector === '*') return wrap(descendants(root));
                            return wrap(select(root, selector));
                        } catch(e) { return wrap([]); }
                    }
                    $.root = function() { return wrap([root]); };
                    $.load = global.cheerio.load;
                    return $;
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
                            if (rawBody && typeof rawBody === 'object' && rawBody._entries) {
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
                            var text = SOURCE._fetchSync(url, method, bodyStr, JSON.stringify(hdrs));
                            return Promise.resolve({
                                ok: true,
                                status: 200,
                                text: function() { return Promise.resolve(text); },
                                json: function() { return Promise.resolve(JSON.parse(text)); }
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
                    // Minimal dayjs stub — supports subtract/add/format used by LNReader date parsing
                    mod.exports = (function() {
                        function Dayjs(d) { this._d = d ? new Date(d) : new Date(); }
                        var MS = { day: 864e5, week: 6048e5, month: 2592e6, year: 31536e6 };
                        Dayjs.prototype.subtract = function(n, u) { return new Dayjs(this._d.getTime() - n * (MS[u] || 864e5)); };
                        Dayjs.prototype.add      = function(n, u) { return new Dayjs(this._d.getTime() + n * (MS[u] || 864e5)); };
                        Dayjs.prototype.format   = function(fmt) {
                            var d = this._d;
                            if (!fmt) return d.toISOString();
                            var p = function(n) { return n < 10 ? '0' + n : '' + n; };
                            return fmt.replace('YYYY', d.getFullYear()).replace('MM', p(d.getMonth()+1))
                                      .replace('DD', p(d.getDate())).replace('HH', p(d.getHours()))
                                      .replace('mm', p(d.getMinutes())).replace('ss', p(d.getSeconds()));
                        };
                        Dayjs.prototype.toDate  = function() { return this._d; };
                        Dayjs.prototype.valueOf = function() { return this._d.getTime(); };
                        Dayjs.prototype.isValid = function() { return !isNaN(this._d.getTime()); };
                        function dayjs(d) { return new Dayjs(d); }
                        dayjs.extend = function() {};
                        return dayjs;
                    })();

                } else if (name === 'htmlparser2') {
                    mod.exports = (function() {
                        var VOID = {
                            area:1,base:1,br:1,col:1,embed:1,hr:1,img:1,
                            input:1,link:1,meta:1,param:1,source:1,track:1,wbr:true
                        };
                        function decode(s) {
                            if (!s || s.indexOf('&') === -1) return s;
                            return s.replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>')
                                .replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&apos;/g,"'")
                                .replace(/&nbsp;/g,' ')
                                .replace(/&#(\\d+);/g,function(_,n){return String.fromCharCode(parseInt(n,10));})
                                .replace(/&#x([0-9a-fA-F]+);/g,function(_,n){return String.fromCharCode(parseInt(n,16));});
                        }
                        function parseAttribs(s) {
                            var a={}, re=/([a-zA-Z_:][a-zA-Z0-9_:.-]*)\\s*(?:=\\s*(?:"([^"]*)"|'([^']*)'|(\\S+)))?/g, m;
                            while ((m=re.exec(s))!==null) {
                                var k=m[1].toLowerCase();
                                var v=m[2]!==undefined?m[2]:m[3]!==undefined?m[3]:m[4]!==undefined?m[4]:'';
                                a[k]=decode(v);
                            }
                            return a;
                        }
                        function Parser(h) { this._h=h||{}; this._buf=''; }
                        Parser.prototype.isVoidElement=function(t){return !!VOID[t.toLowerCase()];};
                        Parser.prototype.write=function(c){this._buf+=c;};
                        Parser.prototype.end=function(c) {
                            if(c) this._buf+=c;
                            var html=this._buf, h=this._h, pos=0, len=html.length;
                            while(pos<len) {
                                var lt=html.indexOf('<',pos);
                                if(lt===-1){var t=html.slice(pos);if(t&&h.ontext)h.ontext(decode(t));break;}
                                if(lt>pos){var tb=html.slice(pos,lt);if(tb&&h.ontext)h.ontext(decode(tb));}
                                pos=lt+1; if(pos>=len) break;
                                var ch=html[pos];
                                if(ch==='!'||ch==='?'){var e=html.indexOf('>',pos);pos=(e===-1?len-1:e)+1;continue;}
                                if(ch==='/'){
                                    var ge=html.indexOf('>',pos);if(ge===-1){pos=len;break;}
                                    var tn=html.slice(pos+1,ge).trim().split(/\\s/)[0].toLowerCase();
                                    if(tn&&h.onclosetag)h.onclosetag(tn);
                                    pos=ge+1;continue;
                                }
                                // opening tag — find closing > respecting quotes
                                var gt=-1,inQ=false,qc='';
                                for(var i=pos;i<len;i++){var x=html[i];if(inQ){if(x===qc)inQ=false;}
                                    else if(x==='"'||x==="'"){inQ=true;qc=x;}else if(x==='>'){gt=i;break;}}
                                if(gt===-1){pos=len;break;}
                                var raw=html.slice(pos,gt);
                                var sc=raw[raw.length-1]==='/';if(sc)raw=raw.slice(0,-1);
                                var si=raw.search(/\\s/),tag2,astr;
                                if(si===-1){tag2=raw.trim().toLowerCase();astr='';}
                                else{tag2=raw.slice(0,si).toLowerCase();astr=raw.slice(si);}
                                if(tag2){
                                    var attrs=parseAttribs(astr);
                                    if(h.onopentag)h.onopentag(tag2,attrs);
                                    if(sc||VOID[tag2]){if(h.onclosetag)h.onclosetag(tag2);}
                                    else if(tag2==='script'||tag2==='style'){
                                        var ct='</'+tag2,ci=html.toLowerCase().indexOf(ct,gt+1);
                                        if(ci!==-1){var cg=html.indexOf('>',ci);if(h.onclosetag)h.onclosetag(tag2);pos=cg!==-1?cg+1:len;continue;}
                                    }
                                }
                                pos=gt+1;
                            }
                            if(h.onend)h.onend();
                            this._buf='';
                        };
                        return { Parser:Parser, parseDocument:function(){return {};} };
                    })();

                } else if (name === '@libs/isAbsoluteUrl') {
                    mod.exports = function(url) {
                        var s = String(url); var c = s.indexOf('://'); return c > 0 && c < 20;
                    };

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
            context.evaluateScript("""
            __mgy_result = undefined;
            (function() {
                try {
                    var __r = __mangayomiSource.getDetail(__mgy_url);
                    if (__r && typeof __r.then === 'function') {
                        __r.then(function(v) { __mgy_result = v; });
                    } else { __mgy_result = __r; }
                } catch(e) { console.error('Mangayomi getDetail: ' + e); }
            })();
            """)
            guard let raw = context.objectForKeyedSubscript("__mgy_result"),
                  !raw.isUndefined, !raw.isNull,
                  let detail = raw.toDictionary() as? [String: Any] else { return [] }
            // Mangayomi uses "episodes" for chapters; some plugins use "chapters"
            let rawChapters = detail["episodes"] as? [[String: Any]]
                ?? detail["chapters"] as? [[String: Any]] ?? []
            return rawChapters.enumerated().compactMap { (index, ch) in
                let chURL = ch["url"] as? String ?? ch["link"] as? String ?? ""
                guard !chURL.isEmpty else { return nil }
                let name = ch["name"] as? String ?? "Episode \(index + 1)"
                return Chapter(
                    id: chURL, mangaId: mangaId, path: chURL, name: name,
                    chapterNumber: Double(index),
                    isRead: false, isDownloaded: false, downloadedAt: nil, readAt: nil,
                    progress: 0.0, readingSeconds: 0, lastPageRead: 0, scanlator: nil
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
        let chapters: [JSNovelChapter] = (dict["chapters"] as? [[String: Any]] ?? []).compactMap {
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
