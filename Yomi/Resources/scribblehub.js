// ScribbleHub plugin for Yomi — Format B (LNReader)
// Uses SOURCE.fetch(url, options) and cheerio.load(html) injected by JSBridge

var plugin = {
    id:   "scribblehub",
    name: "ScribbleHub",
    site: "https://www.scribblehub.com",

    // -----------------------------------------------------------------------
    // popularNovels(pageNo) → [{name, path, cover}]
    // -----------------------------------------------------------------------
    popularNovels: function(pageNo, options) {
        try {
            var page = pageNo || 1;
            var url  = "https://www.scribblehub.com/series-ranking/?sort=views&order=weekly&pg=" + page;
            var html = SOURCE.fetch(url);
            var $    = cheerio.load(html);
            var results = [];

            $("div.search_main_box, .fiction_list .search-li").each(function(i, el) {
                var $el   = $(el);
                var $link = $el.find(".search_title a, .fiction_title a").first();
                var name  = $link.text().trim();
                var path  = $link.attr("href") || "";
                var cover = $el.find(".search_img img").attr("src") || "";

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
            // novelPath may be a full URL or a relative path
            var url = novelPath.indexOf("http") === 0
                ? novelPath
                : "https://www.scribblehub.com" + novelPath;

            var html = SOURCE.fetch(url);
            var $    = cheerio.load(html);

            // Metadata
            var name    = $(".fic_title").first().text().trim();
            var cover   = $(".fic-header img").attr("src")
                       || $(".fic_image img").attr("src")
                       || "";
            var author  = $(".auth_name_fic a").first().text().trim()
                       || $(".auth_name_fic").first().text().trim()
                       || "";
            var summary = $(".wi_fic_desc .p-5").first().text().trim()
                       || $(".wi_fic_desc").first().text().trim()
                       || $(".desc").first().text().trim()
                       || "";

            var status  = "unknown";
            var statusTxt = $(".fic_state").first().text().trim().toLowerCase();
            if (statusTxt.indexOf("ongoing") !== -1)   { status = "ongoing";   }
            if (statusTxt.indexOf("completed") !== -1) { status = "completed"; }
            if (statusTxt.indexOf("hiatus") !== -1)    { status = "hiatus";    }

            // Extract series ID — try multiple locations
            var seriesId = "";

            // 1. form hidden input
            var mypostid = $("form#form_chapters_ajax input[name='mypostid']").attr("value")
                        || $("input[name='mypostid']").attr("value")
                        || "";
            if (mypostid) { seriesId = mypostid; }

            // 2. data-id attribute on various containers
            if (!seriesId) {
                var dataId = $("[data-id]").first().attr("data-id") || "";
                if (dataId) { seriesId = dataId; }
            }

            // 3. Extract from URL: /series/{id}/{slug}/
            if (!seriesId) {
                var parts = url.split("/");
                for (var i = 0; i < parts.length; i++) {
                    if (parts[i] === "series" && i + 1 < parts.length) {
                        seriesId = parts[i + 1];
                        break;
                    }
                }
            }

            // Extract nonce from inline scripts
            var nonce = "";
            $("script").each(function(i, el) {
                if (nonce) { return; }
                var src = $(el).html() || "";
                var m = src.match(/wi_nonce\s*[=:]\s*["']([^"']+)["']/);
                if (m) { nonce = m[1]; }
                if (!nonce) {
                    m = src.match(/"nonce"\s*:\s*"([^"]+)"/);
                    if (m) { nonce = m[1]; }
                }
            });

            // Fetch chapter list via AJAX POST
            var chapters = [];
            if (seriesId) {
                var postBody = "action=wi_gettocchp&strSID=" + seriesId
                             + "&order=asc&nonce=" + encodeURIComponent(nonce);
                var ajaxHTML = "";
                try {
                    ajaxHTML = SOURCE.fetch(
                        "https://www.scribblehub.com/wp-admin/admin-ajax.php",
                        {
                            method:  "POST",
                            headers: { "Content-Type": "application/x-www-form-urlencoded" },
                            body:    postBody
                        }
                    );
                } catch (ajaxErr) {
                    console.log("AJAX chapter fetch error: " + ajaxErr);
                }

                if (ajaxHTML) {
                    var $toc = cheerio.load(ajaxHTML);
                    var idx  = 1;
                    $toc("li.toc_w a").each(function(i, el) {
                        var $a    = $toc(el);
                        var chUrl = $a.attr("href") || "";
                        var chName = $a.text().trim() || ("Chapter " + idx);

                        if (chUrl) {
                            // Use full URL as path for ScribbleHub chapters
                            chapters.push({
                                id:            seriesId + "-" + idx,
                                path:          chUrl,
                                name:          chName,
                                chapterNumber: idx
                            });
                            idx++;
                        }
                    });
                }
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
            // chapterPath is a full URL for ScribbleHub
            var url = chapterPath.indexOf("http") === 0
                ? chapterPath
                : "https://www.scribblehub.com" + chapterPath;

            var html = SOURCE.fetch(url);
            var $    = cheerio.load(html);

            // Remove ads and noise
            $(".ad-zone, .ad-container, script, .wi-notice, #growfooter").remove();

            var content = $("#chp_rawc").first().html()
                       || $(".chp_raw").first().html()
                       || $(".chapter-content").first().html()
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
            var url   = "https://www.scribblehub.com/?s=" + query
                      + "&post_type=fictionposts&pg=" + page;
            var html  = SOURCE.fetch(url);
            var $     = cheerio.load(html);
            var results = [];

            $("div.search_main_box, .fiction_list .search-li").each(function(i, el) {
                var $el   = $(el);
                var $link = $el.find(".search_title a, .fiction_title a").first();
                var name  = $link.text().trim();
                var path  = $link.attr("href") || "";
                var cover = $el.find(".search_img img").attr("src") || "";

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
