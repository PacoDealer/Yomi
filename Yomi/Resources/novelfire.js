const BASE_URL = "https://novelfire.net";

// ─── Format B plugin object ───────────────────────────────────────────────────
// Verified selectors (live, 2026-04-05):
//   Popular/ranking: /ranking
//     Item: li.novel-item
//     Title: h2.title.text2row > a  (text + href)  [ranking page]
//     Cover: figure.cover img[data-src]  (relative path like /server-1/shadow-slave.jpg)
//   Novel detail: /book/{slug}
//     Cover: div.fixed-img figure.cover img[src]  (absolute URL)
//     Title: h1.novel-title
//     Author: div.author a
//     Status: strong.ongoing or strong.completed
//     Chapters link: a.grdbtn.chapter-latest-container[href] → /book/{slug}/chapters
//   Chapter list: /book/{slug}/chapters?page={N}
//     Items: ul.chapter-list > li > a
//     Chapter path: a[href]
//     Chapter name: strong.chapter-title text
//     Chapter number: span.chapter-no text
//   Chapter content: /book/{slug}/chapter-{N}
//     Content: div#chapter-container.d-chapter-content

var plugin = {

  popularNovels: function(pageNo, options) {
    var url = BASE_URL + "/ranking?page=" + pageNo;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    var novels = [];

    $("li.novel-item").each(function(i, el) {
      var $a = el.find("h2.title a, h4.novel-title a").first();
      var title = $a.text().trim();
      var href = $a.attr("href") || el.find("a").first().attr("href") || "";
      // href is relative like /book/shadow-slave
      var path = href.startsWith("/") ? href : "/" + href;
      var cover = el.find("img").attr("data-src") || el.find("img").attr("src") || "";
      if (cover && !cover.startsWith("http")) cover = BASE_URL + cover;
      if (title && path) novels.push({ name: title, path: path, cover: cover });
    });

    return novels;
  },

  parseNovel: function(novelPath) {
    // novelPath = "/book/shadow-slave"
    var url = BASE_URL + novelPath;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);

    var name = $("h1.novel-title").text().trim() ||
               $("title").text().split("-")[0].trim();

    var cover = $("div.fixed-img figure.cover img").attr("src") ||
                $("div.novel-info img").attr("src") || "";
    if (cover && !cover.startsWith("http")) {
      cover = BASE_URL + cover;
    }

    var author = $("div.author a").first().text().trim() ||
                 $("span.author a").first().text().trim() || "";

    var statusText = $("strong.ongoing").text().trim() ||
                     $("strong.completed").text().trim() ||
                     $("strong.hiatus").text().trim() ||
                     $("span.status").text().trim() ||
                     $("div.status").text().trim() || "";
    var status = statusText || "Ongoing";

    var summary = $("div.summary").text().trim() ||
                  $("div.novel-synopsis").text().trim() ||
                  $("section.summary").text().trim() ||
                  $("div.description").text().trim() ||
                  $("div.novel-summary").text().trim() || "";

    // Fetch chapter list from /book/{slug}/chapters (paginated, newest-first)
    // Try page=1 first; fall back to page=0; fall back to detail page inline chapters.
    var chapters = [];

    function parseChaptersFromHTML(html) {
      var $c = cheerio.load(html);
      var chapItems = $c("ul.chapter-list li a, ol.chapter-list li a");
      if (!chapItems.length) chapItems = $c("li.chapter-item a");
      if (!chapItems.length) chapItems = $c("div.chapter-list a");
      if (!chapItems.length) chapItems = $c("a[href*='/chapter-']");
      var items = [];
      chapItems.each(function(i, el) {
        var chPath = $c(el).attr("href") || "";
        if (chPath && !chPath.startsWith("/") && !chPath.startsWith("http")) chPath = "/" + chPath;
        if (chPath.startsWith(BASE_URL)) chPath = chPath.slice(BASE_URL.length);
        // Skip pagination links and non-chapter hrefs
        if (!chPath.includes("/chapter") && !chPath.match(/\/ch-?\d/)) return;
        var chName = $c(el).find("strong.chapter-title, span.chapter-title").text().trim() ||
                     $c(el).text().trim();
        var chNoText = $c(el).find("span.chapter-no, span.chno").text().trim();
        var chNo = parseFloat(chNoText) || parseFloat((chPath.match(/chapter-?([\d.]+)/i) || [])[1]) || (i + 1);
        if (chPath && chName) items.push({ id: chPath, path: chPath, name: chName, chapterNumber: chNo });
      });
      return items;
    }

    var chapUrl = BASE_URL + novelPath + "/chapters?page=1";
    chapters = parseChaptersFromHTML(SOURCE.fetch(chapUrl));
    if (!chapters.length) {
      chapters = parseChaptersFromHTML(SOURCE.fetch(BASE_URL + novelPath + "/chapters?page=0"));
    }
    if (!chapters.length) {
      chapters = parseChaptersFromHTML(html); // fall back to detail page
    }

    return {
      name: name,
      path: novelPath,
      cover: cover,
      author: author,
      summary: summary,
      status: status,
      chapters: chapters
    };
  },

  // Chapter content: div#chapter-container.d-chapter-content
  parseChapter: function(chapterPath) {
    // chapterPath = "/book/shadow-slave/chapter-1"
    var url = BASE_URL + chapterPath;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    var content = $("#chapter-container").html() || "";
    return content;
  },

  // Search: GET /search?keyword={term}  (returns novel-list with novel-item)
  searchNovels: function(searchTerm, pageNo) {
    var url = BASE_URL + "/search?keyword=" + encodeURIComponent(searchTerm) + "&page=" + pageNo;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    var novels = [];

    $("li.novel-item").each(function(i, el) {
      var $a = el.find("a[href*='/book/']").first();
      var title = el.find("h4.novel-title").text().trim() || $a.attr("title") || "";
      var href = $a.attr("href") || "";
      var path = href.startsWith("/") ? href : "/" + href;
      var cover = el.find("img").attr("data-src") || el.find("img").attr("src") || "";
      if (cover && !cover.startsWith("http")) cover = BASE_URL + cover;
      if (title && path) novels.push({ name: title, path: path, cover: cover });
    });

    return novels;
  }
};
