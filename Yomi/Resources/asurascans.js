// Verified live 2026-04-05 against api.asurascans.com
// Format A — global functions (getMangaList, getChapterList, getPageList, searchManga)
// Pure JSON API — no HTML scraping, no cheerio.

const BASE = "https://api.asurascans.com";

// ── Helpers ──────────────────────────────────────────────────────────────────

function apiGet(path) {
  var url = BASE + path;
  var raw = SOURCE.fetch(url, {
    headers: {
      "Origin": "https://asurascans.com",
      "Referer": "https://asurascans.com/"
    }
  });
  return JSON.parse(raw);
}

function stripHtml(html) {
  return (html || "").replace(/<[^>]*>/g, "").trim();
}

function mapItem(item) {
  return {
    id:       String(item.id || ""),
    path:     item.slug || "",
    title:    item.title || "",
    coverURL: item.cover || "",
    summary:  stripHtml(item.description || ""),
    author:   item.author || "",
    artist:   item.artist || "",
    status:   item.status || "",
    genres:   (item.genres || []).map(function(g) { return g.name; }).join(", ")
  };
}

function splitPath(chapterPath) {
  var idx = chapterPath.indexOf("/");
  return {
    seriesSlug:  chapterPath.substring(0, idx),
    chapterSlug: chapterPath.substring(idx + 1)
  };
}

// ── getMangaList ─────────────────────────────────────────────────────────────
// GET /api/search?page={page}&order=popular

function getMangaList(page) {
  var json = apiGet("/api/search?page=" + page + "&order=popular");
  var items = json.data || json.results || json || [];
  var results = [];
  for (var i = 0; i < items.length; i++) {
    results.push(mapItem(items[i]));
  }
  return results;
}

// ── searchManga ──────────────────────────────────────────────────────────────
// GET /api/search?q={query}&page={page}

function searchManga(query, page) {
  var json = apiGet("/api/search?q=" + encodeURIComponent(query) + "&page=" + page);
  var items = json.data || json.results || json || [];
  var results = [];
  for (var i = 0; i < items.length; i++) {
    results.push(mapItem(items[i]));
  }
  return results;
}

// ── getChapterList ───────────────────────────────────────────────────────────
// GET /api/series/{slug}/chapters?limit=100&page={page}
// Pages while json.meta.has_more === true, cap 50 iterations.

function getChapterList(mangaPath) {
  var chapters = [];
  var page = 1;
  var cap = 50;

  while (cap-- > 0) {
    var json = apiGet("/api/series/" + mangaPath + "/chapters?limit=100&page=" + page);
    var items = json.data || json.results || json || [];

    for (var i = 0; i < items.length; i++) {
      var ch = items[i];
      var num = ch.number || "";
      var name = ch.title
        ? ("Ch. " + num + " - " + ch.title)
        : ("Ch. " + num);
      chapters.push({
        id:            String(ch.id || ""),
        path:          mangaPath + "/" + (ch.slug || String(ch.id)),
        name:          name,
        chapterNumber: parseFloat(num) || 0
      });
    }

    var hasMore = json.meta && json.meta.has_more;
    if (!hasMore) break;
    page++;
  }

  // Sort ascending by chapter number
  chapters.sort(function(a, b) { return a.chapterNumber - b.chapterNumber; });
  return chapters;
}

// ── getPageList ──────────────────────────────────────────────────────────────
// chapterPath = "{seriesSlug}/{chapterSlug}"
// GET /api/series/{seriesSlug}/chapters/{chapterSlug}
// Response: json.data.chapter.pages — [{url, width, height}]

function getPageList(chapterPath) {
  var parts = splitPath(chapterPath);
  var json = apiGet("/api/series/" + parts.seriesSlug + "/chapters/" + parts.chapterSlug);
  var pages = (json.data && json.data.chapter && json.data.chapter.pages) || [];
  var urls = [];
  for (var i = 0; i < pages.length; i++) {
    if (pages[i].url) urls.push(pages[i].url);
  }
  return urls;
}
