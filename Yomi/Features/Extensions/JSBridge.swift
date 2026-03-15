import Foundation
import JavaScriptCore

// MARK: - Novel Result Types

struct NovelItem {
    var name: String
    var path: String
    var cover: String?
}

struct NovelChapter {
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
    var chapters: [NovelChapter]
}

// MARK: - JSBridge

/// Executes JavaScript plugin functions and maps results to Swift models.
/// Supports two formats:
///   Format A — Yomi/Manga: global functions getMangaList / getChapterList / getPageList
///   Format B — LNReader/Novel: global `plugin` object with popularNovels / parseNovel / parseChapter / searchNovels
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

    // MARK: - Shims

    nonisolated private static func injectShims(into ctx: JSContext) {
        injectConsole(into: ctx)
        injectStorage(into: ctx)
        injectSourceFetch(into: ctx)
        injectCheerio(into: ctx)
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

    /// SOURCE.fetch(url, options?) — synchronous HTTP GET via DispatchSemaphore
    nonisolated private static func injectSourceFetch(into ctx: JSContext) {
        let fetch: @convention(block) (String, JSValue?) -> String = { urlString, options in
            guard let url = URL(string: urlString) else { return "" }
            var request = URLRequest(url: url, timeoutInterval: 30)
            // Apply optional headers: { headers: { "X-Key": "value" } }
            if let opts = options, !opts.isUndefined, !opts.isNull,
               let headers = opts.objectForKeyedSubscript("headers"),
               !headers.isUndefined, !headers.isNull,
               let dict = headers.toDictionary() as? [String: Any] {
                for (key, value) in dict {
                    request.setValue("\(value)", forHTTPHeaderField: key)
                }
            }
            var body = ""
            let sem = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: request) { data, _, _ in
                if let data = data { body = String(data: data, encoding: .utf8) ?? "" }
                sem.signal()
            }.resume()
            sem.wait()
            return body
        }
        let source = JSValue(newObjectIn: ctx)
        source?.setObject(fetch, forKeyedSubscript: "fetch" as NSString)
        ctx.setObject(source, forKeyedSubscript: "SOURCE" as NSString)
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

            // Select nodes matching selectorStr within ctx (handles comma + descendant combinator)
            function select(ctx, selectorStr) {
                if (!selectorStr) return [];
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
                var segs = selectorStr.trim().split(/\s+/);
                var pool = descendants(ctx);
                var s0 = parseSimple(segs[0]);
                var matched = pool.filter(function(n) { return matchesSimple(n, s0); });
                for (var s = 1; s < segs.length; s++) {
                    var si = parseSimple(segs[s]);
                    var next = [];
                    for (var m = 0; m < matched.length; m++) {
                        var d = descendants(matched[m]);
                        for (var di = 0; di < d.length; di++) {
                            if (matchesSimple(d[di], si) && next.indexOf(d[di]) === -1) next.push(d[di]);
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
                        for (var i = 0; i < nodes.length; i++) fn(i, wrap([nodes[i]]));
                        return obj;
                    },
                    map: function(fn) {
                        var r = [];
                        for (var i = 0; i < nodes.length; i++) r.push(fn(i, wrap([nodes[i]])));
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

    // MARK: - Plugin API — Manga (Format A)

    nonisolated func getMangaList(page: Int, sourceId: String) -> [Manga] {
        let result = context
            .objectForKeyedSubscript("getMangaList")?
            .call(withArguments: [page])
        return JSBridge.parseMangaArray(result, sourceId: sourceId)
    }

    nonisolated func getChapterList(mangaPath: String, mangaId: String) -> [Chapter] {
        let result = context
            .objectForKeyedSubscript("getChapterList")?
            .call(withArguments: [mangaPath])
        return JSBridge.parseChapterArray(result, mangaId: mangaId)
    }

    nonisolated func getPageList(chapterPath: String) -> [String] {
        let result = context
            .objectForKeyedSubscript("getPageList")?
            .call(withArguments: [chapterPath])
        return result?.toArray() as? [String] ?? []
    }

    // MARK: - Plugin API — Novel (Format B)

    nonisolated func popularNovels(page: Int) -> [NovelItem] {
        let result = context
            .objectForKeyedSubscript("plugin")?
            .objectForKeyedSubscript("popularNovels")?
            .call(withArguments: [page, JSValue(nullIn: context) as Any])
        return JSBridge.parseNovelItems(result)
    }

    nonisolated func searchNovels(query: String, page: Int) -> [NovelItem] {
        let result = context
            .objectForKeyedSubscript("plugin")?
            .objectForKeyedSubscript("searchNovels")?
            .call(withArguments: [query, page])
        return JSBridge.parseNovelItems(result)
    }

    nonisolated func parseNovel(path: String) -> SourceNovel? {
        let result = context
            .objectForKeyedSubscript("plugin")?
            .objectForKeyedSubscript("parseNovel")?
            .call(withArguments: [path])
        guard let dict = result?.toDictionary() as? [String: Any] else { return nil }
        let chapters: [NovelChapter] = (dict["chapters"] as? [[String: Any]] ?? []).compactMap {
            guard let name = $0["name"] as? String, let cPath = $0["path"] as? String else { return nil }
            return NovelChapter(
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
        let result = context
            .objectForKeyedSubscript("plugin")?
            .objectForKeyedSubscript("parseChapter")?
            .call(withArguments: [path])
        return result?.toString() ?? ""
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
                inLibrary:     false,
                isLocal:       false,
                lastReadAt:    nil,
                lastUpdatedAt: nil
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
                isRead:        false,
                isDownloaded:  false,
                readAt:        nil,
                progress:      0.0
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
