// Comick.io plugin for Yomi — Format A (Manga)
// Uses SOURCE.fetch(url) injected by JSBridge

var CDN_BASE = "https://meo.comick.pictures/";

function statusLabel(code) {
    if (code === 1) { return "ongoing";   }
    if (code === 2) { return "completed"; }
    if (code === 3) { return "cancelled"; }
    if (code === 4) { return "hiatus";    }
    return "unknown";
}

function fixCover(url) {
    if (!url) { return null; }
    if (url.indexOf("http") === 0) { return url; }
    return CDN_BASE + url;
}

function mapComic(comic) {
    var hid    = comic.hid || comic.slug || "";
    var title  = comic.title || comic.name || "";
    var cover  = fixCover(comic.cover_url || comic.cover || "");
    var summary = comic.desc || comic.description || "";
    var status  = statusLabel(comic.status);
    var genres  = [];
    if (Array.isArray(comic.genres)) {
        genres = comic.genres.map(function(g) {
            return (typeof g === "string") ? g : (g.name || g.label || "");
        }).filter(function(g) { return g.length > 0; });
    }

    return {
        id:       hid,
        path:     "/comic/" + hid,
        title:    title,
        coverURL: cover,
        summary:  summary,
        author:   "",
        artist:   "",
        status:   status,
        genres:   genres
    };
}

// ---------------------------------------------------------------------------
// getMangaList(page) → [{id, path, title, coverURL, summary, author, artist, status, genres}]
// ---------------------------------------------------------------------------
function getMangaList(page) {
    try {
        var p   = page || 1;
        var url = "https://api.comick.fun/v1.0/comics?type=manga&trending=true&page=" + p + "&limit=20";
        var raw = SOURCE.fetch(url);
        var json = JSON.parse(raw);

        // Response may be { rank: [...] } or a direct array
        var list = [];
        if (Array.isArray(json)) {
            list = json;
        } else if (json && Array.isArray(json.rank)) {
            list = json.rank;
        } else if (json && Array.isArray(json.data)) {
            list = json.data;
        }

        return list.map(mapComic);
    } catch (e) {
        console.log("getMangaList error: " + e);
        return [];
    }
}

// ---------------------------------------------------------------------------
// getChapterList(mangaPath, mangaId) → [{id, path, name, chapterNumber}]
// ---------------------------------------------------------------------------
function getChapterList(mangaPath, mangaId) {
    try {
        // mangaPath: "/comic/{hid}"
        var parts = (mangaPath || "").split("/");
        var hid   = parts[parts.length - 1];
        if (!hid) { return []; }

        var allChapters = [];
        var page        = 1;
        var maxPages    = 50; // cap at 5000 chapters

        while (page <= maxPages) {
            var url = "https://api.comick.fun/comic/" + hid
                    + "/chapters?lang=en&page=" + page + "&limit=100";
            var raw  = SOURCE.fetch(url);
            var json = JSON.parse(raw);

            var batch = [];
            if (json && Array.isArray(json.chapters)) {
                batch = json.chapters;
            } else if (Array.isArray(json)) {
                batch = json;
            }

            if (batch.length === 0) { break; }

            for (var i = 0; i < batch.length; i++) {
                var ch    = batch[i];
                var chid  = ch.hid || "";
                var chap  = ch.chap || "";
                var chNum = chap !== "" ? parseFloat(chap) : null;
                if (chNum !== null && isNaN(chNum)) { chNum = null; }

                var chName = chap ? "Chapter " + chap : "Chapter";
                if (ch.title && ch.title.trim().length > 0) {
                    chName = chName + " — " + ch.title.trim();
                }

                allChapters.push({
                    id:            chid,
                    path:          "/chapter/" + chid,
                    name:          chName,
                    chapterNumber: chNum
                });
            }

            if (batch.length < 100) { break; }
            page++;
        }

        // Sort ascending by chapterNumber (nulls last)
        allChapters.sort(function(a, b) {
            if (a.chapterNumber === null && b.chapterNumber === null) { return 0; }
            if (a.chapterNumber === null) { return 1; }
            if (b.chapterNumber === null) { return -1; }
            return a.chapterNumber - b.chapterNumber;
        });

        return allChapters;
    } catch (e) {
        console.log("getChapterList error: " + e);
        return [];
    }
}

// ---------------------------------------------------------------------------
// getPageList(chapterPath) → [urlString]
// ---------------------------------------------------------------------------
function getPageList(chapterPath) {
    try {
        // chapterPath: "/chapter/{chid}"
        var parts = (chapterPath || "").split("/");
        var chid  = parts[parts.length - 1];
        if (!chid) { return []; }

        var url  = "https://api.comick.fun/chapter/" + chid;
        var raw  = SOURCE.fetch(url);
        var json = JSON.parse(raw);

        var images = [];
        if (json && json.chapter && Array.isArray(json.chapter.images)) {
            images = json.chapter.images;
        } else if (json && Array.isArray(json.images)) {
            images = json.images;
        }

        return images.map(function(img) {
            var imgUrl = (typeof img === "string") ? img : (img.url || "");
            return imgUrl.indexOf("http") === 0 ? imgUrl : CDN_BASE + imgUrl;
        }).filter(function(u) { return u.length > 0; });
    } catch (e) {
        console.log("getPageList error: " + e);
        return [];
    }
}

// ---------------------------------------------------------------------------
// searchManga(query, page) → [{id, path, title, coverURL, summary, author, artist, status, genres}]
// ---------------------------------------------------------------------------
function searchManga(query, page) {
    try {
        var p   = page || 1;
        var url = "https://api.comick.fun/v1.0/comics?q="
                + encodeURIComponent(query || "")
                + "&page=" + p + "&limit=20";
        var raw  = SOURCE.fetch(url);
        var json = JSON.parse(raw);

        var list = [];
        if (Array.isArray(json)) {
            list = json;
        } else if (json && Array.isArray(json.data)) {
            list = json.data;
        } else if (json && Array.isArray(json.rank)) {
            list = json.rank;
        }

        return list.map(mapComic);
    } catch (e) {
        console.log("searchManga error: " + e);
        return [];
    }
}
