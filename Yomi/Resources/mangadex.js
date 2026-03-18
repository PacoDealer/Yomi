// MangaDex plugin for Yomi — Format A (Manga)
// Uses SOURCE.fetch(url) injected by JSBridge

function getMangaList(page) {
    try {
        var offset = (page - 1) * 20;
        var url = "https://api.mangadex.org/manga"
            + "?limit=20"
            + "&offset=" + offset
            + "&order[followedCount]=desc"
            + "&contentRating[]=safe"
            + "&contentRating[]=suggestive"
            + "&includes[]=cover_art"
            + "&includes[]=author"
            + "&includes[]=artist";

        var body = SOURCE.fetch(url);
        var json = JSON.parse(body);

        if (!json || !json.data) { return []; }

        return json.data.map(function(manga) {
            var attrs = manga.attributes || {};
            var rels  = manga.relationships || [];

            // Title: prefer English, fall back to first available value
            var titleObj = attrs.title || {};
            var title = titleObj.en;
            if (!title) {
                var keys = Object.keys(titleObj);
                title = keys.length > 0 ? titleObj[keys[0]] : manga.id;
            }

            // Cover URL
            var coverURL = null;
            var coverRel = findRel(rels, "cover_art");
            if (coverRel && coverRel.attributes && coverRel.attributes.fileName) {
                coverURL = "https://uploads.mangadex.org/covers/"
                    + manga.id + "/" + coverRel.attributes.fileName;
            }

            // Author / Artist
            var authorRel = findRel(rels, "author");
            var author = authorRel && authorRel.attributes ? authorRel.attributes.name : null;

            var artistRel = findRel(rels, "artist");
            var artist = artistRel && artistRel.attributes ? artistRel.attributes.name : null;

            // Genres (tags with group == "genre")
            var genres = (attrs.tags || [])
                .filter(function(tag) {
                    return tag.attributes && tag.attributes.group === "genre";
                })
                .map(function(tag) {
                    return (tag.attributes.name && tag.attributes.name.en) || "";
                })
                .filter(function(g) { return g.length > 0; });

            // Summary
            var descObj = attrs.description || {};
            var summary = descObj.en || "";

            return {
                id:        manga.id,
                path:      "/manga/" + manga.id,
                title:     title,
                coverURL:  coverURL,
                summary:   summary,
                author:    author,
                artist:    artist,
                status:    attrs.status || "unknown",
                genres:    genres
            };
        });
    } catch (e) {
        console.log("getMangaList error: " + e);
        return [];
    }
}

function getChapterList(mangaPath) {
    try {
        var parts = mangaPath.split("/");
        var mangaId = parts[parts.length - 1];

        var limit = 100;
        var offset = 0;
        var allChapters = [];

        while (true) {
            var url = "https://api.mangadex.org/manga/" + mangaId + "/feed"
                + "?limit=" + limit
                + "&offset=" + offset
                + "&translatedLanguage[]=en"
                + "&translatedLanguage[]=es"
                + "&translatedLanguage[]=es-la"
                + "&translatedLanguage[]=pt-br"
                + "&translatedLanguage[]=pt"
                + "&order[chapter]=asc";

            var body = SOURCE.fetch(url);
            var json = JSON.parse(body);

            if (!json || !json.data || json.data.length === 0) { break; }

            for (var i = 0; i < json.data.length; i++) {
                var chapter = json.data[i];
                var attrs = chapter.attributes || {};
                var chapterNum = attrs.chapter ? parseFloat(attrs.chapter) : null;
                if (chapterNum !== null && isNaN(chapterNum)) { chapterNum = null; }
                var name = attrs.title && attrs.title.trim().length > 0
                    ? attrs.title
                    : (attrs.chapter ? "Chapter " + attrs.chapter : "Chapter");

                allChapters.push({
                    id:            chapter.id,
                    path:          "/chapter/" + chapter.id,
                    name:          name,
                    chapterNumber: chapterNum
                });
            }

            if (json.data.length < limit) { break; }
            offset += limit;
            if (offset > 2000) { break; }
        }

        return allChapters;
    } catch (e) {
        console.log("getChapterList error: " + e);
        return [];
    }
}

function getPageList(chapterPath) {
    try {
        var parts = chapterPath.split("/");
        var chapterId = parts[parts.length - 1];

        var url = "https://api.mangadex.org/at-home/server/" + chapterId;
        var body = SOURCE.fetch(url);
        var json = JSON.parse(body);

        if (!json || !json.chapter || !json.chapter.data) { return []; }

        var base = json.baseUrl;
        var hash = json.chapter.hash;

        return json.chapter.data.map(function(filename) {
            return base + "/data/" + hash + "/" + filename;
        });
    } catch (e) {
        console.log("getPageList error: " + e);
        return [];
    }
}

function searchManga(query, page) {
    try {
        var offset = (page - 1) * 20;
        var url = "https://api.mangadex.org/manga"
            + "?title=" + encodeURIComponent(query)
            + "&limit=20"
            + "&offset=" + offset
            + "&includes[]=cover_art"
            + "&contentRating[]=safe"
            + "&contentRating[]=suggestive"
            + "&contentRating[]=erotica"
            + "&order[relevance]=desc";

        var body = SOURCE.fetch(url);
        var json = JSON.parse(body);

        if (!json || !json.data) { return []; }

        return json.data.map(function(manga) {
            var attrs = manga.attributes || {};
            var rels  = manga.relationships || [];

            // Title: prefer English, fall back to first available value
            var titleObj = attrs.title || {};
            var title = titleObj.en;
            if (!title) {
                var keys = Object.keys(titleObj);
                title = keys.length > 0 ? titleObj[keys[0]] : manga.id;
            }

            // Cover URL
            var coverURL = null;
            var coverRel = findRel(rels, "cover_art");
            if (coverRel && coverRel.attributes && coverRel.attributes.fileName) {
                coverURL = "https://uploads.mangadex.org/covers/"
                    + manga.id + "/" + coverRel.attributes.fileName;
            }

            // Author / Artist
            var authorRel = findRel(rels, "author");
            var author = authorRel && authorRel.attributes ? authorRel.attributes.name : null;

            var artistRel = findRel(rels, "artist");
            var artist = artistRel && artistRel.attributes ? artistRel.attributes.name : null;

            // Genres (tags with group == "genre")
            var genres = (attrs.tags || [])
                .filter(function(tag) {
                    return tag.attributes && tag.attributes.group === "genre";
                })
                .map(function(tag) {
                    return (tag.attributes.name && tag.attributes.name.en) || "";
                })
                .filter(function(g) { return g.length > 0; });

            // Summary
            var descObj = attrs.description || {};
            var summary = descObj.en || "";

            return {
                id:       manga.id,
                path:     "/manga/" + manga.id,
                title:    title,
                coverURL: coverURL,
                summary:  summary,
                author:   author,
                artist:   artist,
                status:   attrs.status || "unknown",
                genres:   genres
            };
        });
    } catch (e) {
        console.log("searchManga error: " + e);
        return [];
    }
}

// Utility: find first relationship of a given type
function findRel(relationships, type) {
    for (var i = 0; i < relationships.length; i++) {
        if (relationships[i].type === type) { return relationships[i]; }
    }
    return null;
}
