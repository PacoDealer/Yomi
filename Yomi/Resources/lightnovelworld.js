// @name        LightNovelWorld
// @version     1.0.0
// @lang        en
// @description Large catalog of translated light novels and web novels
// @icon        https://www.lightnovelworld.co/favicon.ico
// @nsfw        false

const BASE_URL = "https://www.lightnovelworld.co";

var plugin = {

  popularNovels: function(pageNo, options) {
    var url = BASE_URL + "/novel/genre-all-25060123/popular?page=" + pageNo;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    var novels = [];
    $("ul.novel-list li.novel-item").each(function(i, el) {
      var $a = el.find("a.cover-wrap");
      var path  = $a.attr("href") || "";
      var title = el.find("h4.novel-title").text().trim() || el.find("a").attr("title") || "";
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
      var title = el.find("h4.novel-title").text().trim() || el.find("a").attr("title") || "";
      var cover = el.find("img").attr("data-src") || el.find("img").attr("src") || "";
      if (title && path) novels.push({ name: title, path: path, cover: cover });
    });
    return novels;
  },

  parseNovel: function(novelPath) {
    var url = BASE_URL + novelPath;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);

    var name   = $("h1.novel-title").text().trim() || $("title").text().trim();
    var cover  = $("figure.cover img").attr("data-src") || $("figure.cover img").attr("src") || "";
    var author = $("span[itemprop='author']").text().trim()
              || $("div.author a").text().trim() || "";
    var status = $("div.header-stats span[class*='status']").text().trim()
              || $("div.novel-stats span").first().text().trim() || "Ongoing";
    var summary = $("div.summary div.content, div[class*='summary'] p").text().trim() || "";

    var genres = [];
    $("div.categories a, ul.genre-list a").each(function(i, el) {
      var g = el.text().trim();
      if (g) genres.push(g);
    });

    // Chapters are paginated — fetch the chapter list page
    var chapHtml = SOURCE.fetch(url + "/chapters");
    var $c = cheerio.load(chapHtml);
    var chapters = [];
    $c("ul.chapter-list li a, ul.chapters li a").each(function(i, el) {
      var chName = el.find("strong, span.chapter-title").text().trim() || el.text().trim();
      var chPath = el.attr("href") || "";
      if (chName && chPath) {
        chapters.push({ name: chName, path: chPath, chapterNumber: i + 1 });
      }
    });

    return { path: novelPath, name: name, cover: cover, author: author, summary: summary, status: status, genres: genres, chapters: chapters };
  },

  parseChapter: function(chapterPath) {
    var url = BASE_URL + chapterPath;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    var content = $("div#chapter-container, div.chapter-content, div[class*='chapter-text']").html()
               || $("div.content").html() || "";
    return content;
  }
};
