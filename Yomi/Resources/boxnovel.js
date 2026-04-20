(() => {
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __commonJS = (cb, mod) => function __require() {
    return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
  };

  // scripts/plugins-src/boxnovel.ts
  var require_boxnovel = __commonJS({
    "scripts/plugins-src/boxnovel.ts"() {
      var BASE_URL = "https://boxnovel.com";
      var plugin = {
        popularNovels(pageNo) {
          const url = `${BASE_URL}/novel/page/${pageNo}/?m_orderby=views`;
          const html = SOURCE.fetch(url);
          const $ = cheerio.load(html);
          const novels = [];
          $("div.page-item-detail.manga").each((_i, el) => {
            const $el = $(el);
            const $a = $el.find(".post-title a").last();
            const title = $a.text().trim();
            const path = ($a.attr("href") || "").replace(BASE_URL, "");
            const cover = $el.find("img").attr("data-src") || $el.find("img").attr("src") || "";
            if (title && path) novels.push({ name: title, path, cover });
          });
          return novels;
        },
        searchNovels(query, pageNo) {
          const url = `${BASE_URL}/page/${pageNo}/?s=${encodeURIComponent(query)}&post_type=wp-manga`;
          const html = SOURCE.fetch(url);
          const $ = cheerio.load(html);
          const novels = [];
          $("div.row.c-tabs-item__content").each((_i, el) => {
            const $el = $(el);
            const $a = $el.find(".post-title a").last();
            const title = $a.text().trim();
            const path = ($a.attr("href") || "").replace(BASE_URL, "");
            const cover = $el.find("img").attr("data-src") || $el.find("img").attr("src") || "";
            if (title && path) novels.push({ name: title, path, cover });
          });
          return novels;
        },
        parseNovel(novelPath) {
          const url = `${BASE_URL}${novelPath}`;
          const html = SOURCE.fetch(url);
          const $ = cheerio.load(html);
          const name = $("div.post-title h1").text().trim() || $("title").text().split("|")[0].trim();
          const cover = $("div.summary_image img").attr("data-src") || $("div.summary_image img").attr("src") || "";
          const author = $("div.author-content a").first().text().trim() || "";
          const summary = $("div.summary__content").text().trim() || "";
          const statusText = $("div.post-status").find(".summary-content").last().text().trim() || "Ongoing";
          const chapters = [];
          $("li.wp-manga-chapter").each((i, el) => {
            const $el = $(el);
            const $a = $el.find("a");
            const chName = $a.text().trim();
            const chHref = $a.attr("href") || "";
            const chPath = chHref.replace(BASE_URL, "");
            if (chName && chPath) {
              chapters.push({
                id: chPath,
                path: chPath,
                name: chName,
                chapterNumber: i + 1,
                releaseDate: $el.find("span.chapter-release-date").text().trim()
              });
            }
          });
          chapters.reverse();
          return { name, path: novelPath, cover, author, summary, status: statusText, chapters };
        },
        parseChapter(chapterPath) {
          const url = `${BASE_URL}${chapterPath}`;
          const html = SOURCE.fetch(url);
          const $ = cheerio.load(html);
          return $("div.reading-content").html() || $("div.text-left").html() || "";
        }
      };
      globalThis.plugin = plugin;
    }
  });
  require_boxnovel();
})();
