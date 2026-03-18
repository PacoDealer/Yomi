// Last verified: 2026-03-18
// Aqua Manga uses WordPress Madara theme — update selectors if broken.
// Site: https://aquamanga.com

var BASE_URL = "https://aquamanga.com";

// MARK: - String helpers

function between(str, open, close) {
    var start = str.indexOf(open);
    if (start === -1) return "";
    start += open.length;
    var end = str.indexOf(close, start);
    if (end === -1) return "";
    return str.substring(start, end);
}

// Works on cheerio elements: data-src first, fallback to named attr
function attr($el, name) {
    var val = $el.attr("data-src");
    if (val && val.trim()) return val.trim();
    return ($el.attr(name) || "").trim();
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

// MARK: - getMangaList

function getMangaList(page) {
    try {
        var url = BASE_URL + "/manga/?page=" + page + "&order=update";
        var html = SOURCE.fetch(url, {});
        var $ = cheerio.load(html);
        var results = [];

        $("div.page-item-detail").each(function(i, el) {
            var $el = $(el);
            var $a = $el.find("a").first();
            var path = ($a.attr("href") || "").trim();
            if (!path) return;

            // id = last non-empty path segment (slug)
            var parts = path.replace(/\/$/, "").split("/");
            var id = parts[parts.length - 1];
            if (!id) return;

            var $img = $el.find("img").first();
            var coverURL = attr($img, "src");
            var title = ($img.attr("alt") || "").trim() ||
                        $el.find(".post-title a").first().text().trim();
            if (!title) return;

            results.push({
                id:       id,
                path:     path,
                title:    title,
                coverURL: coverURL,
                summary:  "",
                author:   "",
                artist:   "",
                status:   "ongoing",
                genres:   []
            });
        });

        return JSON.stringify(results);
    } catch (e) {
        console.log("aquamanga getMangaList error: " + e);
        return JSON.stringify([]);
    }
}

// MARK: - getChapterList

function getChapterList(mangaPath) {
    try {
        var html = SOURCE.fetch(mangaPath, {});
        var $ = cheerio.load(html);
        var results = [];

        $("ul.version-chap li.wp-manga-chapter").each(function(i, el) {
            var $el = $(el);
            var $a = $el.find("a").first();
            var path = ($a.attr("href") || "").trim();
            if (!path) return;

            var name = $a.text().trim();
            if (!name) return;

            var parts = path.replace(/\/$/, "").split("/");
            var id = parts[parts.length - 1];
            if (!id) return;

            var m = name.match(/[\d.]+/);
            var chapterNumber = m ? parseFloat(m[0]) : null;

            results.push({
                id:            id,
                path:          path,
                name:          name,
                chapterNumber: chapterNumber
            });
        });

        // Deduplicate by path
        var seen = {};
        var deduped = [];
        for (var i = 0; i < results.length; i++) {
            if (!seen[results[i].path]) {
                seen[results[i].path] = true;
                deduped.push(results[i]);
            }
        }

        return JSON.stringify(deduped);
    } catch (e) {
        console.log("aquamanga getChapterList error: " + e);
        return JSON.stringify([]);
    }
}

// MARK: - getPageList

function getPageList(chapterPath) {
    try {
        var html = SOURCE.fetch(chapterPath, {});
        var $ = cheerio.load(html);
        var urls = [];
        var seen = {};

        $("div.reading-content img").each(function(i, el) {
            var $img = $(el);
            var src = attr($img, "src");
            if (src && !seen[src]) {
                seen[src] = true;
                urls.push(src);
            }
        });

        return JSON.stringify(urls);
    } catch (e) {
        console.log("aquamanga getPageList error: " + e);
        return JSON.stringify([]);
    }
}

// MARK: - searchManga

function searchManga(query, page) {
    try {
        var url = BASE_URL + "/?s=" + encodeURIComponent(query) +
                  "&post_type=wp-manga&paged=" + page;
        var html = SOURCE.fetch(url, {});
        var $ = cheerio.load(html);
        var results = [];

        $("div.page-item-detail").each(function(i, el) {
            var $el = $(el);
            var $a = $el.find("a").first();
            var path = ($a.attr("href") || "").trim();
            if (!path) return;

            var parts = path.replace(/\/$/, "").split("/");
            var id = parts[parts.length - 1];
            if (!id) return;

            var $img = $el.find("img").first();
            var coverURL = attr($img, "src");
            var title = ($img.attr("alt") || "").trim() ||
                        $el.find(".post-title a").first().text().trim();
            if (!title) return;

            results.push({
                id:       id,
                path:     path,
                title:    title,
                coverURL: coverURL,
                summary:  "",
                author:   "",
                artist:   "",
                status:   "ongoing",
                genres:   []
            });
        });

        return JSON.stringify(results);
    } catch (e) {
        console.log("aquamanga searchManga error: " + e);
        return JSON.stringify([]);
    }
}
