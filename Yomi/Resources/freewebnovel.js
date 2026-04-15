// @name        FreeWebNovel
// @version     1.0.0
// @lang        en
// @description Free web novel reader with a large catalog of translated Asian novels
// @icon        https://freewebnovel.com/favicon.ico
// @nsfw        false

const BASE_URL = "https://freewebnovel.com";

var plugin = {

  popularNovels: function(pageNo, options) {
    var url = BASE_URL + "/sort/most-popular/?page=" + pageNo;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    var novels = [];
    $("div.li-row").each(function(i, el) {
      var $a = el.find("div.txt h3.tit a");
      var title = $a.text().trim();
      var path  = $a.attr("href") || "";
      var cover = el.find("div.pic img").attr("src") || "";
      if (cover && !cover.startsWith("http")) cover = BASE_URL + cover;
      if (title && path) novels.push({ name: title, path: path, cover: cover });
    });
    return novels;
  },

  searchNovels: function(searchTerm, pageNo) {
    var url = BASE_URL + "/search/";
    var html = SOURCE.fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: "searchkey=" + encodeURIComponent(searchTerm)
    });
    var $ = cheerio.load(html);
    var novels = [];
    $("div.li-row").each(function(i, el) {
      var $a = el.find("div.txt h3.tit a");
      var title = $a.text().trim();
      var path  = $a.attr("href") || "";
      var cover = el.find("div.pic img").attr("src") || "";
      if (cover && !cover.startsWith("http")) cover = BASE_URL + cover;
      if (title && path) novels.push({ name: title, path: path, cover: cover });
    });
    return novels;
  },

  parseNovel: function(novelPath) {
    var url = BASE_URL + novelPath;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);

    var name    = $("h1.tit").text().trim() || $("title").text().trim();
    var cover   = $("div.pic img").attr("src") || "";
    if (cover && !cover.startsWith("http")) cover = BASE_URL + cover;
    var author  = $("div.author a").text().trim() || $("span.author a").text().trim() || "";
    var summary = $("div.inner").text().trim() || $("div[class*='desc']").text().trim() || "";
    var status  = $("div.infos span.status").text().trim() || "Ongoing";

    var genres = [];
    $("div.infos a[href*='/genre/']").each(function(i, el) {
      var g = el.text().trim();
      if (g) genres.push(g);
    });

    var chapters = [];
    $("ul#chapter-list li a, div#chapter-list li a, ul.chapter-list li a").each(function(i, el) {
      var chName = el.text().trim();
      var chPath = el.attr("href") || "";
      if (chName && chPath) {
        chapters.push({
          name: chName,
          path: chPath,
          chapterNumber: i + 1
        });
      }
    });
    // Chapters on site are newest-first; reverse for reading order
    chapters.reverse();

    return { path: novelPath, name: name, cover: cover, author: author, summary: summary, status: status, genres: genres, chapters: chapters };
  },

  parseChapter: function(chapterPath) {
    var url = BASE_URL + chapterPath;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    // Main content container
    var content = $("div.txt div[class*='content'], div#chapterContent, div.chapter-content").html()
               || $("div.txt").html()
               || "";
    return content;
  }
};
