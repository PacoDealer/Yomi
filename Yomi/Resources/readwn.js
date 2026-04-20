(() => {
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __commonJS = (cb, mod) => function __require() {
    return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
  };

  // scripts/plugins-src/readwn.ts
  var require_readwn = __commonJS({
    "scripts/plugins-src/readwn.ts"() {
      var BASE_URL = "https://www.readwn.com";
      var plugin = {
        popularNovels(pageNo) {
          const url = `${BASE_URL}/list/all/all-newstime-${pageNo}.html`;
          const html = SOURCE.fetch(url);
          const $ = cheerio.load(html);
          const novels = [];
          $("li.novel-item").each((_i, el) => {
            const $el = $(el);
            const $a = $el.find("h4 a, .novel-title a").first();
            const title = $a.text().trim();
            const href = $a.attr("href") || "";
            const path = href.startsWith("http") ? href.replace(BASE_URL, "") : href;
            const cover = $el.find("img").attr("data-src") || $el.find("img").attr("src") || "";
            if (title && path) novels.push({ name: title, path, cover });
          });
          return novels;
        },
        searchNovels(query, pageNo) {
          const url = `${BASE_URL}/search.html?searchkey=${encodeURIComponent(query)}&page=${pageNo}`;
          const html = SOURCE.fetch(url);
          const $ = cheerio.load(html);
          const novels = [];
          $("li.novel-item, div.novel-list li").each((_i, el) => {
            const $el = $(el);
            const $a = $el.find("h4 a, .novel-title a").first();
            const title = $a.text().trim();
            const href = $a.attr("href") || "";
            const path = href.startsWith("http") ? href.replace(BASE_URL, "") : href;
            const cover = $el.find("img").attr("data-src") || $el.find("img").attr("src") || "";
            if (title && path) novels.push({ name: title, path, cover });
          });
          return novels;
        },
        parseNovel(novelPath) {
          const url = `${BASE_URL}${novelPath}`;
          const html = SOURCE.fetch(url);
          const $ = cheerio.load(html);
          const name = $("h1.novel-title").text().trim() || $("title").text().split("|")[0].trim();
          const cover = $("figure.cover img").attr("data-src") || $("figure.cover img").attr("src") || $("img.novel-cover").attr("src") || "";
          const author = $("span.author a, .info-meta .author a").first().text().trim() || "";
          const summary = $("div.synopsis p").text().trim() || $("div.summary p").text().trim() || "";
          const statusText = $("span.status").first().text().trim() || "Ongoing";
          const chapters = [];
          $("div.chapter-list ul li a, ul.chapter-list li a").each((i, el) => {
            const $a = $(el);
            const chName = $a.text().trim();
            const href = $a.attr("href") || "";
            const chPath = href.startsWith("http") ? href.replace(BASE_URL, "") : href;
            if (chName && chPath) {
              chapters.push({ id: chPath, path: chPath, name: chName, chapterNumber: i + 1, releaseDate: "" });
            }
          });
          return { name, path: novelPath, cover, author, summary, status: statusText, chapters };
        },
        parseChapter(chapterPath) {
          const url = `${BASE_URL}${chapterPath}`;
          const html = SOURCE.fetch(url);
          const $ = cheerio.load(html);
          return $("div.chapter-content, div#chapter-article").html() || "";
        }
      };
      globalThis.plugin = plugin;
    }
  });
  require_readwn();
})();
