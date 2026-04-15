// @name        NovelBin
// @version     1.0.0
// @lang        en
// @description Massive library of translated web novels and light novels
// @icon        https://novelbin.me/favicon.ico
// @nsfw        false

const BASE_URL = "https://novelbin.me";

var plugin = {

  popularNovels: function(pageNo, options) {
    var url = BASE_URL + "/sort/novelbin-popular?page=" + pageNo;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    var novels = [];
    $("div.list-novel div.row").each(function(i, el) {
      var $a = el.find("h3.novel-title a");
      var title = $a.text().trim();
      var path  = $a.attr("href") || "";
      // Make path relative
      if (path.startsWith(BASE_URL)) path = path.slice(BASE_URL.length);
      var cover = el.find("img[data-src]").attr("data-src") || el.find("img").attr("src") || "";
      if (title && path) novels.push({ name: title, path: path, cover: cover });
    });
    return novels;
  },

  searchNovels: function(searchTerm, pageNo) {
    var url = BASE_URL + "/search?keyword=" + encodeURIComponent(searchTerm) + "&page=" + pageNo;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    var novels = [];
    $("div.list-novel div.row").each(function(i, el) {
      var $a = el.find("h3.novel-title a");
      var title = $a.text().trim();
      var path  = $a.attr("href") || "";
      if (path.startsWith(BASE_URL)) path = path.slice(BASE_URL.length);
      var cover = el.find("img[data-src]").attr("data-src") || el.find("img").attr("src") || "";
      if (title && path) novels.push({ name: title, path: path, cover: cover });
    });
    return novels;
  },

  parseNovel: function(novelPath) {
    var url = novelPath.startsWith("http") ? novelPath : BASE_URL + novelPath;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);

    var name    = $("h3.title").text().trim() || $("title").text().trim();
    var cover   = $("div.book img").attr("data-src") || $("div.book img").attr("src") || "";
    var author  = $("li.author a").text().trim() || $("div.info-meta li").first().text().replace("Author:", "").trim() || "";
    var status  = $("li.status a").text().trim() || "Ongoing";
    var summary = $("div.desc-text").text().trim() || "";

    var genres = [];
    $("li.categories a, div.info-meta li a[href*='genre']").each(function(i, el) {
      var g = el.text().trim();
      if (g) genres.push(g);
    });

    // Chapter list via AJAX endpoint
    var novelId = "";
    var idMatch = html.match(/data-novel-id=['"](\d+)['"]/);
    if (idMatch) novelId = idMatch[1];

    var chapters = [];
    if (novelId) {
      var chapHtml = SOURCE.fetch(BASE_URL + "/ajax/chapter-archive?novelId=" + novelId);
      var $c = cheerio.load(chapHtml);
      $c("ul.list-chapter li a").each(function(i, el) {
        var chName = el.attr("title") || el.text().trim();
        var chPath = el.attr("href") || "";
        if (chPath.startsWith(BASE_URL)) chPath = chPath.slice(BASE_URL.length);
        if (chName && chPath) chapters.push({ name: chName, path: chPath, chapterNumber: i + 1 });
      });
    } else {
      // Fallback: scrape visible chapter list
      $("ul#list-chapter li a, div.list-chapter a").each(function(i, el) {
        var chName = el.attr("title") || el.text().trim();
        var chPath = el.attr("href") || "";
        if (chPath.startsWith(BASE_URL)) chPath = chPath.slice(BASE_URL.length);
        if (chName && chPath) chapters.push({ name: chName, path: chPath, chapterNumber: i + 1 });
      });
    }

    return { path: novelPath, name: name, cover: cover, author: author, summary: summary, status: status, genres: genres, chapters: chapters };
  },

  parseChapter: function(chapterPath) {
    var url = chapterPath.startsWith("http") ? chapterPath : BASE_URL + chapterPath;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    var content = $("div#chr-content, div.chr-c, div[id*='content']").html()
               || $("div.chapter-c").html() || "";
    return content;
  }
};
