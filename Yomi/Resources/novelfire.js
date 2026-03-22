// NovelFire plugin for Yomi — Format B (LNReader)
// Uses SOURCE.fetch(url) and cheerio.load(html) injected by JSBridge

var plugin = {
    id:   "novelfire",
    name: "NovelFire",
    site: "https://novelfire.net",

    // -----------------------------------------------------------------------
    // popularNovels(pageNo) → [{name, path, cover}]
    // -----------------------------------------------------------------------
    popularNovels: function(pageNo, options) {
        try {
            var page = pageNo || 1;
            var url  = "https://novelfire.net/sort/top-rated?page=" + page;
            var html = SOURCE.fetch(url);
            var $    = cheerio.load(html);
            var results = [];

            $(".novel-item, .book-item").each(function(i, el) {
                var $el   = $(el);
                var $link = $el.find(".novel-title a, h3.title a, a.novel-title").first();
                if (!$link.length) { $link = $el.find("a").first(); }

                var name  = $link.text().trim();
                var path  = $link.attr("href") || "";
                var $img  = $el.find("img.cover, .book-img img, img").first();
                var cover = $img.attr("data-src") || $img.attr("src") || "";

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
            var url = novelPath.indexOf("http") === 0
                ? novelPath
                : "https://novelfire.net" + novelPath;

            var html = SOURCE.fetch(url);
            var $    = cheerio.load(html);

            // Metadata
            var name = $("h1.novel-title").first().text().trim()
                    || $(".book-title").first().text().trim()
                    || $("h1").first().text().trim();

            var $coverImg = $(".novel-cover img, .book-cover img, .cover img").first();
            var cover = $coverImg.attr("data-src") || $coverImg.attr("src") || "";

            var author = $(".author a").first().text().trim()
                      || $("[itemprop='author']").first().text().trim()
                      || $(".author").first().text().trim()
                      || "";

            var summary = $(".novel-synopsis").first().text().trim()
                       || $(".book-desc").first().text().trim()
                       || $("[itemprop='description']").first().text().trim()
                       || "";

            var status = "unknown";
            var $statusEl = $(".header-stats .ongoing, .header-stats .completed, .header-stats .hiatus, .novel-status, .book-status").first();
            var statusTxt = $statusEl.text().trim().toLowerCase();
            if (!statusTxt) {
                // Fallback: scan all spans for status keywords
                $("span, .label, .badge").each(function(i, el) {
                    var t = $(el).text().trim().toLowerCase();
                    if (t === "ongoing" || t === "completed" || t === "hiatus") {
                        statusTxt = t;
                    }
                });
            }
            if (statusTxt.indexOf("ongoing") !== -1)   { status = "ongoing";   }
            if (statusTxt.indexOf("completed") !== -1) { status = "completed"; }
            if (statusTxt.indexOf("hiatus") !== -1)    { status = "hiatus";    }

            // Extract slug from URL for chapter list
            var slug = extractSlug(url);

            // Extract book ID from HTML (for potential API use)
            var bookId = $("[data-bookid]").attr("data-bookid") || "";
            if (!bookId) {
                $("script").each(function(i, el) {
                    if (bookId) { return; }
                    var src = $(el).html() || "";
                    var m = src.match(/["\']?bookId["\']?\s*[=:]\s*["\']?(\d+)["\']?/);
                    if (m) { bookId = m[1]; }
                });
            }

            // Fetch chapters — paginate through /chapters pages
            var chapters = [];
            var chPage   = 1;
            var maxPages = 50; // safety cap

            while (chPage <= maxPages) {
                var chUrl  = "https://novelfire.net/book/" + slug + "/chapters?page=" + chPage;
                var chHtml = "";
                try { chHtml = SOURCE.fetch(chUrl); } catch (fetchErr) { break; }
                if (!chHtml) { break; }

                var $ch   = cheerio.load(chHtml);
                var items = $ch(".chapter-item a, li.chapter a, .chapter-list a, ul.chapter-list li a");

                if (!items.length) { break; }

                items.each(function(i, el) {
                    var $a    = $ch(el);
                    var chPath = $a.attr("href") || "";
                    var chName = $a.text().trim();
                    if (!chPath || !chName) { return; }

                    var chNum = extractChapterNumber(chName) || (chapters.length + 1);

                    chapters.push({
                        id:            slug + "-" + (chapters.length + 1),
                        path:          chPath,
                        name:          chName,
                        chapterNumber: chNum
                    });
                });

                // Check if there's a next page
                var hasNext = $ch(".pagination .next, a[rel='next'], .page-next").length > 0;
                if (!hasNext) { break; }
                chPage++;
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
            var url = chapterPath.indexOf("http") === 0
                ? chapterPath
                : "https://novelfire.net" + chapterPath;

            var html = SOURCE.fetch(url);
            var $    = cheerio.load(html);

            // Remove ads and noise
            $("script, .ad-zone, .ads, .ad-container, .adsbox, " +
              ".chapter-comments, .comment-section, " +
              ".c-ads, [id*='google'], [class*='adsbygoogle']").remove();

            var content = $("#chapter-container").first().html()
                       || $(".chapter-content").first().html()
                       || $(".text-left").first().html()
                       || $(".reading-content").first().html()
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
            var url   = "https://novelfire.net/search?keyword=" + query + "&page=" + page;
            var html  = SOURCE.fetch(url);
            var $     = cheerio.load(html);
            var results = [];

            $(".novel-item, .book-item").each(function(i, el) {
                var $el   = $(el);
                var $link = $el.find(".novel-title a, h3.title a, a.novel-title").first();
                if (!$link.length) { $link = $el.find("a").first(); }

                var name  = $link.text().trim();
                var path  = $link.attr("href") || "";
                var $img  = $el.find("img.cover, .book-img img, img").first();
                var cover = $img.attr("data-src") || $img.attr("src") || "";

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
// Helpers
// -----------------------------------------------------------------------

// Extract slug from URL: https://novelfire.net/book/{slug}/... → slug
function extractSlug(url) {
    var parts = url.replace(/\/$/, "").split("/");
    for (var i = 0; i < parts.length; i++) {
        if (parts[i] === "book" && i + 1 < parts.length) {
            return parts[i + 1];
        }
    }
    return "";
}

// Extract chapter number from title: "Chapter 42 — Some Title" → 42
function extractChapterNumber(title) {
    var m = title.match(/chapter\s+(\d+(?:\.\d+)?)/i);
    if (m) { return parseFloat(m[1]); }
    m = title.match(/^(\d+(?:\.\d+)?)/);
    if (m) { return parseFloat(m[1]); }
    return null;
}
