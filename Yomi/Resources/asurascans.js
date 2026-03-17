// Last verified: 2026-03-16
// Asura Scans may change their HTML structure — update selectors if broken.
// Site: https://asuracomic.net

var BASE_URL = "https://asuracomic.net";

// MARK: - String helpers

function between(str, open, close) {
    var start = str.indexOf(open);
    if (start === -1) return "";
    start += open.length;
    var end = str.indexOf(close, start);
    if (end === -1) return "";
    return str.substring(start, end);
}

function betweenAll(str, open, close) {
    var results = [];
    var cursor = 0;
    while (true) {
        var start = str.indexOf(open, cursor);
        if (start === -1) break;
        start += open.length;
        var end = str.indexOf(close, start);
        if (end === -1) break;
        results.push(str.substring(start, end));
        cursor = end + close.length;
    }
    return results;
}

function attr(tag, name) {
    var key = name + '="';
    var start = tag.indexOf(key);
    if (start === -1) {
        key = name + "='";
        start = tag.indexOf(key);
        if (start === -1) return "";
        var end = tag.indexOf("'", start + key.length);
        return end === -1 ? "" : tag.substring(start + key.length, end);
    }
    var end = tag.indexOf('"', start + key.length);
    return end === -1 ? "" : tag.substring(start + key.length, end);
}

function stripTags(html) {
    var result = "";
    var inTag = false;
    for (var i = 0; i < html.length; i++) {
        if (html[i] === "<") { inTag = true; continue; }
        if (html[i] === ">") { inTag = false; continue; }
        if (!inTag) result += html[i];
    }
    return result.trim();
}

function parseChapterNumber(name) {
    var lower = name.toLowerCase();
    var idx = lower.indexOf("chapter");
    if (idx !== -1) {
        var rest = lower.substring(idx + 7).trim();
        var num = parseFloat(rest);
        if (!isNaN(num)) return num;
    }
    var num = parseFloat(name);
    return isNaN(num) ? null : num;
}

// MARK: - getMangaList

function getMangaList(page) {
    try {
        var url = BASE_URL + "/series?page=" + page;
        var html = SOURCE.fetch(url);

        // Each series card is an <a> tag wrapping a card block inside the grid
        // Isolate the grid container first
        var grid = between(html, 'class="grid', '</main>');
        if (!grid) grid = html;

        var results = [];
        var cards = betweenAll(grid, "<a href=", "</a>");

        for (var i = 0; i < cards.length; i++) {
            var card = cards[i];

            // Extract href (path)
            var path = "";
            var hrefEnd = card.indexOf('"', 1);
            if (card[0] === '"') {
                path = card.substring(1, hrefEnd);
            } else if (card[0] === "'") {
                hrefEnd = card.indexOf("'", 1);
                path = card.substring(1, hrefEnd);
            }

            if (!path || path.indexOf("/series/") === -1) continue;

            // Ensure relative path
            if (path.indexOf("http") === 0) {
                path = path.replace(BASE_URL, "");
            }

            // Extract cover image src
            var imgTag = between(card, "<img", ">");
            var coverURL = attr(imgTag, "src");
            if (!coverURL) coverURL = attr(imgTag, "data-src");

            // Extract title — try alt attribute first, then span text
            var title = attr(imgTag, "alt");
            if (!title) {
                var spanContent = between(card, "<span", "</span>");
                title = stripTags("<span" + spanContent + "</span>");
            }
            if (!title) continue;

            var id = path.replace(/\//g, "-").replace(/^-/, "");

            results.push({
                id:       id,
                path:     path,
                title:    title.trim(),
                coverURL: coverURL,
                summary:  "",
                author:   "",
                artist:   "",
                status:   "ongoing",
                genres:   []
            });
        }

        return results;
    } catch (e) {
        console.log("asurascans getMangaList error: " + e);
        return [];
    }
}

// MARK: - getChapterList

function getChapterList(mangaPath) {
    try {
        var url = BASE_URL + mangaPath;
        var html = SOURCE.fetch(url);

        // Chapter list is inside a div containing chapter links
        // Look for the chapter list container
        var listSection = between(html, 'class="pl-4 py-2 border', "</div>");
        if (!listSection) {
            // Fallback: grab all chapter anchor tags
            listSection = html;
        }

        var results = [];
        // Each chapter row is an <a> pointing to /series/slug/chapter/N
        var anchors = betweenAll(html, "<a href=\"" + BASE_URL + "/series", "</a>");
        if (anchors.length === 0) {
            anchors = betweenAll(html, "<a href=\"/series", "</a>");
        }

        for (var i = 0; i < anchors.length; i++) {
            var anchor = anchors[i];

            // Reconstruct the full tag to parse href
            var fullTag = "<a href=\"" + (anchor.indexOf("http") === 0 ? "" : BASE_URL) + anchor;
            var href = attr(fullTag, "href");
            if (!href) continue;
            if (href.indexOf("/chapter/") === -1) continue;

            var path = href.replace(BASE_URL, "");
            var name = stripTags(between(anchor, ">", "</a>"));
            if (!name) {
                // Try finding text after the closing >
                var gtIdx = anchor.indexOf(">");
                if (gtIdx !== -1) {
                    name = stripTags(anchor.substring(gtIdx + 1));
                }
            }
            if (!name) name = "Chapter";

            var chapterNumber = parseChapterNumber(name);
            var id = path.replace(/\//g, "-").replace(/^-/, "");

            results.push({
                id:            id,
                path:          path,
                name:          name.trim(),
                chapterNumber: chapterNumber
            });
        }

        // Deduplicate by path
        var seen = {};
        var deduped = [];
        for (var j = 0; j < results.length; j++) {
            if (!seen[results[j].path]) {
                seen[results[j].path] = true;
                deduped.push(results[j]);
            }
        }

        // Newest first (already in page order; reverse if ascending)
        return deduped;
    } catch (e) {
        console.log("asurascans getChapterList error: " + e);
        return [];
    }
}

// MARK: - getPageList

function getPageList(chapterPath) {
    try {
        var url = BASE_URL + chapterPath;
        var html = SOURCE.fetch(url);

        // Chapter images are <img> tags inside the reader container
        // The reader div typically has class containing "reader" or "chapter-content"
        var readerDiv = between(html, 'class="w-full mx-auto center', "</div>");
        if (!readerDiv) readerDiv = between(html, 'id="readerarea"', "</div>");
        if (!readerDiv) readerDiv = html;

        var urls = [];
        var cursor = 0;

        while (true) {
            var imgStart = readerDiv.indexOf("<img", cursor);
            if (imgStart === -1) break;
            var imgEnd = readerDiv.indexOf(">", imgStart);
            if (imgEnd === -1) break;
            var tag = readerDiv.substring(imgStart, imgEnd + 1);

            var src = attr(tag, "src");
            if (!src) src = attr(tag, "data-src");

            if (src && src.indexOf("http") === 0) {
                // Filter out icons/logos — chapter images are typically large
                var lower = src.toLowerCase();
                if (lower.indexOf("cdn") !== -1 ||
                    lower.indexOf("chapter") !== -1 ||
                    lower.indexOf("/manga/") !== -1 ||
                    lower.indexOf("comic") !== -1) {
                    urls.push(src);
                }
            }

            cursor = imgEnd + 1;
        }

        return urls;
    } catch (e) {
        console.log("asurascans getPageList error: " + e);
        return [];
    }
}

// MARK: - searchManga

function searchManga(query, page) {
    try {
        var url = BASE_URL + "/series?search=" + encodeURIComponent(query) + "&page=" + page;
        var html = SOURCE.fetch(url);

        var grid = between(html, 'class="grid', '</main>');
        if (!grid) grid = html;

        var results = [];
        var cards = betweenAll(grid, "<a href=", "</a>");

        for (var i = 0; i < cards.length; i++) {
            var card = cards[i];

            var path = "";
            var hrefEnd = card.indexOf('"', 1);
            if (card[0] === '"') {
                path = card.substring(1, hrefEnd);
            } else if (card[0] === "'") {
                hrefEnd = card.indexOf("'", 1);
                path = card.substring(1, hrefEnd);
            }

            if (!path || path.indexOf("/series/") === -1) continue;

            if (path.indexOf("http") === 0) {
                path = path.replace(BASE_URL, "");
            }

            var imgTag = between(card, "<img", ">");
            var coverURL = attr(imgTag, "src");
            if (!coverURL) coverURL = attr(imgTag, "data-src");

            var title = attr(imgTag, "alt");
            if (!title) {
                var spanContent = between(card, "<span", "</span>");
                title = stripTags("<span" + spanContent + "</span>");
            }
            if (!title) continue;

            var id = path.replace(/\//g, "-").replace(/^-/, "");

            results.push({
                id:       id,
                path:     path,
                title:    title.trim(),
                coverURL: coverURL,
                summary:  "",
                author:   "",
                artist:   "",
                status:   "ongoing",
                genres:   []
            });
        }

        return results;
    } catch (e) {
        console.log("asurascans searchManga error: " + e);
        return [];
    }
}
