const BASE_URL = "https://www.royalroad.com";

// ─── Format B plugin object ───────────────────────────────────────────────────
var plugin = {

  // Popular novels list — verified selector: div.fiction-list-item.row
  // Title: h2.fiction-title > a  (text + href for path)
  // Cover: figure > a > img[src]  (absolute URL from royalroadcdn.com)
  // Summary: hidden div#description-{id} — skip, not needed for list
  popularNovels: function(pageNo, options) {
    var url = BASE_URL + "/fictions/best-rated?page=" + pageNo;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    var novels = [];
    $("div.fiction-list-item").each(function(i, el) {
      var $a = el.find("h2.fiction-title a");
      var title = $a.text().trim();
      var path = $a.attr("href") || "";
      var cover = el.find("figure img").attr("src") || "";
      if (title && path) novels.push({ name: title, path: path, cover: cover });
    });
    return novels;
  },

  // Novel detail — verified selectors from fiction detail page
  // Chapters: table#chapters tr.chapter-row
  // Chapter link: td > a[href]  (first td)
  // Chapter name: td > a text (trimmed)
  // Chapter number: index (RR doesn't expose a clean float, use index)
  parseNovel: function(novelPath) {
    var url = BASE_URL + novelPath;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);

    var name = $("h1.font-white").text().trim() ||
               $("div.fiction-title").text().trim() ||
               $("title").text().replace("| Royal Road", "").trim();

    var cover = $("img.thumbnail").attr("src") ||
                $("figure.text-center img").attr("src") || "";

    var author = $("h4.font-white a").first().text().trim() ||
                 $(".author a").first().text().trim() || "";

    var statusText = $("span.label-warning, span.label-success, span.label-default")
      .filter(function(i, el) {
        var t = $(el).text().trim().toUpperCase();
        return t === "ONGOING" || t === "COMPLETED" || t === "HIATUS" || t === "STUB";
      }).first().text().trim() || "Ongoing";

    var summary = $("div.description div.hidden-content").text().trim() ||
                  $("div[property='description']").text().trim() || "";

    var chapters = [];
    $("table#chapters tr.chapter-row").each(function(i, el) {
      var $link = el.find("td a").first();
      var chName = $link.text().trim();
      var chPath = $link.attr("href") || "";
      if (chName && chPath) {
        chapters.push({
          id: chPath,
          path: chPath,
          name: chName,
          chapterNumber: i + 1,
          releaseDate: el.find("time").attr("datetime") || ""
        });
      }
    });

    return {
      name: name,
      path: novelPath,
      cover: cover,
      author: author,
      summary: summary,
      status: statusText,
      chapters: chapters
    };
  },

  // Chapter content — verified selector: div.chapter-inner.chapter-content
  parseChapter: function(chapterPath) {
    var url = BASE_URL + chapterPath;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    var content = $("div.chapter-inner.chapter-content").html() || "";
    return content;
  },

  // Search — same fiction-list-item structure as popular page
  searchNovels: function(searchTerm, pageNo) {
    var url = BASE_URL + "/fictions/search?title=" + encodeURIComponent(searchTerm) + "&page=" + pageNo;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    var novels = [];

    $("div.fiction-list-item").each(function(i, el) {
      var $a = el.find("h2.fiction-title a");
      var title = $a.text().trim();
      var path = $a.attr("href") || "";
      var cover = el.find("figure img").attr("src") || "";
      if (title && path) novels.push({ name: title, path: path, cover: cover });
    });

    return novels;
  }
};
