// Royal Road plugin for Yomi — Format B (LNReader)
// Uses SOURCE.fetch(url) and cheerio.load(html) injected by JSBridge

var plugin = {
    id:   "royalroad",
    name: "Royal Road",
    site: "https://www.royalroad.com",

    // -----------------------------------------------------------------------
    // popularNovels(pageNo) → [{name, path, cover}]
    // -----------------------------------------------------------------------
    popularNovels: function(pageNo, options) {
        try {
            var page = pageNo || 1;
            var url  = "https://www.royalroad.com/fictions/best-rated?page=" + page;
            var html = SOURCE.fetch(url);
            var $    = cheerio.load(html);
            var results = [];

            $(".fiction-list-item, .row.fiction-item").each(function(i, el) {
                var $el   = $(el);
                var $link = $el.find("h2.fiction-title a").first();
                var name  = $link.text().trim();
                var path  = $link.attr("href") || "";
                var cover = $el.find("img.thumbnail").attr("src") || "";

                if (name && path) {
                    results.push({ name: name, path: path, cover: cover });
                }
            });

            return results;
        } catch (e) {
            console.log("popularNovels error: " + e);
            return [];
        }
    },

    // -----------------------------------------------------------------------
    // parseNovel(novelPath) → {name, path, cover, author, summary, status, chapters}
    // -----------------------------------------------------------------------
    parseNovel: function(novelPath) {
        try {
            var url  = "https://www.royalroad.com" + novelPath;
            var html = SOURCE.fetch(url);
            var $    = cheerio.load(html);

            // Metadata
            var name    = $("h1.font-white").first().text().trim()
                       || $(".fiction-title").first().text().trim();
            var cover   = $(".cover-art-container img").attr("src")
                       || $("img.thumbnail").first().attr("src")
                       || "";
            var author  = $("span[property='name']").first().text().trim()
                       || $("a[property='author']").first().text().trim()
                       || "";
            var summary = $("div[property='description']").first().text().trim()
                       || $(".description").first().text().trim()
                       || "";

            // Status: look for label containing "Ongoing" or "Completed"
            var status  = "unknown";
            $(".label, .fiction-status").each(function(i, el) {
                var txt = $(el).text().trim().toLowerCase();
                if (txt.indexOf("ongoing") !== -1)   { status = "ongoing";   }
                if (txt.indexOf("completed") !== -1) { status = "completed"; }
                if (txt.indexOf("hiatus") !== -1)    { status = "hiatus";    }
            });

            // Extract fiction ID from path for chapter URLs
            // path format: /fiction/{fictionId}/{slug}
            var fictionId = "";
            var pathParts = novelPath.split("/");
            for (var i = 0; i < pathParts.length; i++) {
                if (pathParts[i] === "fiction" && i + 1 < pathParts.length) {
                    fictionId = pathParts[i + 1];
                    break;
                }
            }

            // Try to extract chapters from embedded JSON in <script> tags
            var chapters = [];
            var scripts  = $("script");
            var jsonFound = false;

            scripts.each(function(i, el) {
                if (jsonFound) { return; }
                var src = $(el).html() || "";

                // Pattern: window.chapters = [...];
                var match = src.match(/window\.chapters\s*=\s*(\[[\s\S]*?\]);/);
                if (!match) {
                    // Pattern: __chapters = [...];
                    match = src.match(/__chapters\s*=\s*(\[[\s\S]*?\]);/);
                }
                if (!match) {
                    // Pattern: "chapters": [...] inside a larger JSON object
                    match = src.match(/"chapters"\s*:\s*(\[[\s\S]*?\])\s*[,}]/);
                }

                if (match) {
                    try {
                        var arr = JSON.parse(match[1]);
                        if (Array.isArray(arr) && arr.length > 0) {
                            for (var j = 0; j < arr.length; j++) {
                                var ch      = arr[j];
                                var chId    = String(ch.id || ch.chapterId || j);
                                var chTitle = ch.title || ch.name || ("Chapter " + (j + 1));
                                var chSlug  = ch.slug || slugify(chTitle);
                                var chPath  = "/fiction/" + fictionId
                                            + "/chapter/" + chId
                                            + "/" + chSlug;
                                var chNum   = ch.order != null ? ch.order : (j + 1);

                                chapters.push({
                                    id:            chId,
                                    path:          chPath,
                                    name:          chTitle,
                                    chapterNumber: chNum
                                });
                            }
                            jsonFound = true;
                        }
                    } catch (parseErr) {
                        console.log("chapter JSON parse error: " + parseErr);
                    }
                }
            });

            // Fallback: parse chapter table from HTML
            if (!jsonFound) {
                var idx = 1;
                $("table#chapters tbody tr, .chapter-row").each(function(i, el) {
                    var $row  = $(el);
                    var $link = $row.find("a[href*='/chapter/']").first();
                    if (!$link.length) { return; }

                    var chPath  = $link.attr("href") || "";
                    var chTitle = $link.text().trim() || ("Chapter " + idx);
                    // Extract chapter ID from path: /fiction/{id}/chapter/{chapterId}/...
                    var chId    = "";
                    var cParts  = chPath.split("/");
                    for (var k = 0; k < cParts.length; k++) {
                        if (cParts[k] === "chapter" && k + 1 < cParts.length) {
                            chId = cParts[k + 1];
                            break;
                        }
                    }
                    if (!chId) { chId = String(idx); }

                    chapters.push({
                        id:            chId,
                        path:          chPath,
                        name:          chTitle,
                        chapterNumber: idx
                    });
                    idx++;
                });
            }

            return {
                name:     name,
                path:     novelPath,
                cover:    cover,
                author:   author,
                summary:  summary,
                status:   status,
                chapters: chapters
            };
        } catch (e) {
            console.log("parseNovel error: " + e);
            return { name: "", path: novelPath, cover: "", author: "", summary: "", status: "unknown", chapters: [] };
        }
    },

    // -----------------------------------------------------------------------
    // parseChapter(chapterPath) → String (HTML content only)
    // -----------------------------------------------------------------------
    parseChapter: function(chapterPath) {
        try {
            var url  = "https://www.royalroad.com" + chapterPath;
            var html = SOURCE.fetch(url);
            var $    = cheerio.load(html);

            // Remove ads and scripts from content
            $(".ads-container, .announcement, script, .chapter-comments").remove();

            var content = $("div.chapter-inner").first().html()
                       || $("div.chapter-content").first().html()
                       || "";

            return content;
        } catch (e) {
            console.log("parseChapter error: " + e);
            return "";
        }
    },

    // -----------------------------------------------------------------------
    // searchNovels(searchTerm, pageNo) → [{name, path, cover}]
    // -----------------------------------------------------------------------
    searchNovels: function(searchTerm, pageNo) {
        try {
            var page  = pageNo || 1;
            var query = encodeURIComponent(searchTerm || "");
            var url   = "https://www.royalroad.com/fictions/search?title=" + query + "&page=" + page;
            var html  = SOURCE.fetch(url);
            var $     = cheerio.load(html);
            var results = [];

            $(".fiction-list-item, .row.fiction-item").each(function(i, el) {
                var $el   = $(el);
                var $link = $el.find("h2.fiction-title a").first();
                var name  = $link.text().trim();
                var path  = $link.attr("href") || "";
                var cover = $el.find("img.thumbnail").attr("src") || "";

                if (name && path) {
                    results.push({ name: name, path: path, cover: cover });
                }
            });

            return results;
        } catch (e) {
            console.log("searchNovels error: " + e);
            return [];
        }
    }
};

// -----------------------------------------------------------------------
// Utility: basic slug (used when chapter JSON has no slug field)
// -----------------------------------------------------------------------
function slugify(str) {
    return (str || "")
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "");
}
