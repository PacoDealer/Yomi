// Verified live 2026-05-19. Domain migrated: aquareader.net → aquareader.org.
// Madara WordPress theme. Chapter lists are AJAX-loaded via admin-ajax.php on this site.

const BASE_URL = "https://aquareader.org";

// ── getMangaList ──────────────────────────────────────────────────────────────
// Popular list: /manga/?page=N&order=popular
// Card container: div.page-item-detail
// Title + path: div.post-title.font-title h3.h5 > a  (text + href)
// Cover: div.item-thumb img.img-responsive[src]  (absolute URL, 350px variant)
// Chapter list on card: NOT used — fetched in getChapterList
function getMangaList(page) {
  var url = BASE_URL + "/manga/?page=" + page + "&order=popular";
  var html = SOURCE.fetch(url);
  var $ = cheerio.load(html);
  var results = [];

  $("div.page-item-detail").each(function(i, el) {
    var $titleLink = el.find("div.post-title h3 a, div.post-title.font-title h3 a").first();
    var title = $titleLink.text().trim();
    var href = $titleLink.attr("href") || "";
    var path = href.replace(BASE_URL, "").replace("https://aquareader.net", "");
    var cover = el.find("div.item-thumb img").attr("src") || "";
    if (title && path) {
      results.push({
        id: path,
        path: path,
        title: title,
        coverURL: cover,
        summary: "",
        author: "",
        artist: "",
        status: "Ongoing",
        genres: []
      });
    }
  });

  return results;
}

// ── getChapterList ────────────────────────────────────────────────────────────
// Detail page: /manga/{slug}/
// Madara-based sites load chapters via AJAX on this domain — static HTML has no li.wp-manga-chapter.
// Strategy:
//   1. Fetch detail page, try static li.wp-manga-chapter parse (works on some Madara installs).
//   2. If empty, extract post ID from #manga-chapters-holder[data-id] and POST to admin-ajax.php.
//   3. Parse the AJAX response HTML the same way.
function getChapterList(mangaPath) {
  var url = BASE_URL + mangaPath;
  var html = SOURCE.fetch(url);
  var $ = cheerio.load(html);
  var chapters = [];

  function parseChapterNodes(root) {
    root("li.wp-manga-chapter").each(function(i, el) {
      var $a = root(el).find("a").first();
      var name = $a.text().trim();
      var href = $a.attr("href") || "";
      var path = href.replace(BASE_URL, "").replace("https://aquareader.net", "");
      var numMatch = name.match(/[\d]+\.?[\d]*/);
      var chapterNumber = numMatch ? parseFloat(numMatch[0]) : (i + 1);
      if (name && path) {
        chapters.push({ id: path, path: path, name: name, chapterNumber: chapterNumber });
      }
    });
  }

  parseChapterNodes($);

  if (chapters.length === 0) {
    // AJAX fallback — standard Madara pattern
    var postId = $("#manga-chapters-holder").attr("data-id") ||
                 $("[id='manga-chapters-holder']").attr("data-id") || "";
    if (!postId) {
      // Try extracting from inline JS or meta
      var idMatch = html.match(/manga_id['":\s]+(\d+)/);
      postId = idMatch ? idMatch[1] : "";
    }
    if (postId) {
      var ajaxHTML = SOURCE.fetch(BASE_URL + "/wp-admin/admin-ajax.php", {
        method: "POST",
        body: "action=manga_get_chapters&manga=" + postId,
        headers: { "Content-Type": "application/x-www-form-urlencoded", "X-Requested-With": "XMLHttpRequest" }
      });
      var $$ = cheerio.load(ajaxHTML);
      parseChapterNodes($$);
    }
  }

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
// Results: same page-item-detail structure (search results page)
// Cover: img.img-responsive[src]
function searchManga(query, page) {
  var url = BASE_URL + "/?s=" + encodeURIComponent(query) + "&post_type=wp-manga&paged=" + page;
  var html = SOURCE.fetch(url);
  var $ = cheerio.load(html);
  var results = [];

  $("div.page-item-detail, div.c-tabs-item").each(function(i, el) {
    var $titleLink = el.find("div.post-title a, .post-title a").first();
    var title = $titleLink.text().trim();
    var href = $titleLink.attr("href") || "";
    var path = href.replace(BASE_URL, "").replace("https://aquareader.net", "");
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
        status: "Ongoing",
        genres: []
      });
    }
  });

  return results;
}
