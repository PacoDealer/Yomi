// Verified live 2026-08-04. Domain migrated: aquareader.net → aquareader.org.
// Site was rebuilt on a custom theme (no longer Madara WordPress) — archive/detail pages use
// new "aqua-*" markup. Only the search results page and the chapter reader page kept the old
// Madara-style markup, so those two selector sets are unchanged.
// NOTE: this domain sits behind Cloudflare, but SOURCE.fetch's plain UA/headers pass through
// fine (verified: 200 OK, full HTML, no "Just a moment" interstitial) — no CF bypass needed here.

const BASE_URL = "https://aquareader.org";

// ── getMangaList ──────────────────────────────────────────────────────────────
// Popular list: /manga/?page=N&order=popular
// Card: article.aqua-archive-card
// Title + path: h3.aqua-archive-card__title > a  (text + href)
// Cover: img.aqua-archive-card__cover[src]
// Status: span.manga-status  (e.g. "Ongoing", "Completed")
function getMangaList(page) {
  var url = BASE_URL + "/manga/?page=" + page + "&order=popular";
  var html = SOURCE.fetch(url);
  var $ = cheerio.load(html);
  var results = [];

  $("article.aqua-archive-card").each(function(i, el) {
    var $titleLink = el.find("h3.aqua-archive-card__title a").first();
    var title = $titleLink.text().trim();
    var href = $titleLink.attr("href") || el.find("a.aqua-archive-card__cover-link").attr("href") || "";
    var path = href.replace(BASE_URL, "");
    var cover = el.find("img.aqua-archive-card__cover").attr("src") || "";
    var status = el.find("span.manga-status").text().trim().toLowerCase();
    if (title && path) {
      results.push({
        id: path,
        path: path,
        title: title,
        coverURL: cover,
        summary: "",
        author: "",
        artist: "",
        status: status || "unknown",
        genres: []
      });
    }
  });

  return results;
}

// ── getChapterList ────────────────────────────────────────────────────────────
// Detail page: /manga/{slug}/
// Chapter list is server-rendered directly on the detail page (no AJAX needed here).
// Item: a.aqua-ch-item[href] > span.aqua-ch-item__name (chapter name text)
function getChapterList(mangaPath) {
  var url = BASE_URL + mangaPath;
  var html = SOURCE.fetch(url);
  var $ = cheerio.load(html);
  var chapters = [];

  $("a.aqua-ch-item").each(function(i, el) {
    var $el = $(el);
    var name = $el.find("span.aqua-ch-item__name").first().text().trim();
    var href = $el.attr("href") || "";
    var path = href.replace(BASE_URL, "");
    var numMatch = name.match(/[\d]+\.?[\d]*/);
    var chapterNumber = numMatch ? parseFloat(numMatch[0]) : (i + 1);
    if (name && path) {
      chapters.push({ id: path, path: path, name: name, chapterNumber: chapterNumber });
    }
  });

  // Site lists newest-first; reverse for ascending order
  chapters.reverse();
  return chapters;
}

// ── getPageList ───────────────────────────────────────────────────────────────
// Chapter reader: /manga/{slug}/{slug}/chapter-N/
// Page images: div.page-break img.wp-manga-chapter-img
// Cover loaded via src (no lazy src here — server-side rendered)
function getPageList(chapterPath) {
  var url = BASE_URL + chapterPath;
  var html = SOURCE.fetch(url);
  var $ = cheerio.load(html);
  var pages = [];

  $("div.page-break img").each(function(i, el) {
    var src = el.attr("src") || el.attr("data-src") || el.attr("data-lazy-src") || "";
    src = src.trim();
    if (src && src.startsWith("http")) pages.push(src);
  });

  return pages;
}

// ── searchManga ───────────────────────────────────────────────────────────────
// Search: GET /?s={query}&post_type=wp-manga
// Results page kept the old Madara markup — unaffected by the archive/detail redesign.
// Cover: img.img-responsive[src]
// NOTE: results live in div.row.c-tabs-item__content — one per result. The single outer
// div.c-tabs-item wraps ALL results, so matching on it directly only ever finds the first.
function searchManga(query, page) {
  var url = BASE_URL + "/?s=" + encodeURIComponent(query) + "&post_type=wp-manga&paged=" + page;
  var html = SOURCE.fetch(url);
  var $ = cheerio.load(html);
  var results = [];

  $("div.row.c-tabs-item__content").each(function(i, el) {
    var $titleLink = el.find("div.post-title a, .post-title a").first();
    var title = $titleLink.text().trim();
    var href = $titleLink.attr("href") || "";
    var path = href.replace(BASE_URL, "");
    var cover = el.find("img.img-responsive").attr("src") || "";
    if (title && path) {
      results.push({
        id: path,
        path: path,
        title: title,
        coverURL: cover,
        summary: "",
        author: "",
        artist: "",
        status: "unknown",
        genres: []
      });
    }
  });

  return results;
}
