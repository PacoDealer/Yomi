// @name        LightNovelPub
// @version     1.0.0
// @lang        en
// @description Large catalog of translated light novels and web novels
// @icon        https://www.lightnovelpub.com/favicon.ico
// @nsfw        false
// Selectors verified: 2026-04-14 against lightnovelpub.com

const BASE_URL = "https://www.lightnovelpub.com";

var plugin = {

  popularNovels: function(pageNo, options) {
    var url = BASE_URL + "/browse/genre-all-25060123/order-popular/status-all?page=" + pageNo;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    var novels = [];
    $("ul.novel-list li.novel-item").each(function(i, el) {
      var $a = el.find("a.cover-wrap");
      var path  = $a.attr("href") || "";
      var title = el.find("h4.novel-title").text().trim();
      var cover = el.find("img").attr("data-src") || el.find("img").attr("src") || "";
      if (title && path) novels.push({ name: title, path: path, cover: cover });
    });
    return novels;
  },

  searchNovels: function(searchTerm, pageNo) {
    var url = BASE_URL + "/search?keywords=" + encodeURIComponent(searchTerm) + "&page=" + pageNo;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    var novels = [];
    $("ul.novel-list li.novel-item").each(function(i, el) {
      var $a = el.find("a.cover-wrap");
      var path  = $a.attr("href") || "";
      var title = el.find("h4.novel-title").text().trim();
      var cover = el.find("img").attr("data-src") || el.find("img").attr("src") || "";
      if (title && path) novels.push({ name: title, path: path, cover: cover });
    });
    return novels;
  },

  parseNovel: function(novelPath) {
    var url = BASE_URL + novelPath;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);

    var title   = $("h1.novel-title").text().trim() || $("h1").first().text().trim();
    var cover   = $("figure.cover img").attr("data-src") || $("figure.cover img").attr("src") || "";
    var author  = $("div.author a").first().text().trim();
    var summary = $("div.summary div.content").text().trim() || $("div.novel-body p").text().trim();
    var status  = $("div.header-stats span.ongoing, div.header-stats span.completed").first().text().trim();

    var chapters = [];
    // Try to get chapter list from the novel page directly
    $("ul.chapter-list li").each(function(i, el) {
      var $a = el.find("a");
      var chPath  = $a.attr("href") || "";
      var chName  = $a.find("span.chapter-title").text().trim() || $a.text().trim();
      var chNo    = parseFloat($a.find("span.chapter-no").text().replace(/[^0-9.]/g, "")) || null;
      if (chName && chPath) {
        chapters.push({ id: chPath, path: chPath, name: chName, chapterNumber: chNo });
      }
    });

    // If chapter list not inline, fetch from paginated chapters endpoint
    if (chapters.length === 0) {
      var novelId = novelPath.replace(/\//g, "").replace(/[^a-z0-9-]/gi, "");
      var chUrl = BASE_URL + novelPath + "chapters/";
      var chHtml = SOURCE.fetch(chUrl);
      var $ch = cheerio.load(chHtml);
      $ch("ul.chapter-list li, li.chapter-item").each(function(i, el) {
        var $a = el.find("a");
        var chPath  = $a.attr("href") || "";
        var chName  = $a.find("span.chapter-title").text().trim() || $a.text().trim();
        var chNo    = parseFloat($a.find("span.chapter-no").text().replace(/[^0-9.]/g, "")) || null;
        if (chName && chPath) {
          chapters.push({ id: chPath, path: chPath, name: chName, chapterNumber: chNo });
        }
      });
    }

    return {
      path:     novelPath,
      name:     title,
      cover:    cover,
      author:   author,
      summary:  summary,
      status:   status,
      chapters: chapters
    };
  },

  parseChapter: function(chapterPath) {
    var url = BASE_URL + chapterPath;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    // Main chapter content container
    var content = $("div.chapter-content");
    if (content.text().trim().length === 0) {
      content = $("div#chapter-content, article.chapter-content");
    }
    return content.html() || "<p>Chapter content unavailable.</p>";
  }
};
