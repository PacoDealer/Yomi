(() => {
  // scripts/plugins-src/lightnovelpub.ts
  var BASE_URL = "https://www.lightnovelpub.vip";
  var plugin = {
    popularNovels(pageNo) {
      const url = `${BASE_URL}/browse/genre-all-25060123/order-popular/status-all?pg=${pageNo}`;
      const html = SOURCE.fetch(url);
      const $ = cheerio.load(html);
      const novels = [];
      $("li.novel-item").each((_i, el) => {
        const $el = $(el);
        const $a = $el.find(".novel-title a");
        const title = $a.text().trim();
        const path = $a.attr("href") || "";
        const cover = $el.find("img").attr("data-src") || $el.find("img").attr("src") || "";
        if (title && path) novels.push({ name: title, path, cover });
      });
      return novels;
    },
    searchNovels(query, pageNo) {
      const url = `${BASE_URL}/search?input=${encodeURIComponent(query)}&page=${pageNo}`;
      const html = SOURCE.fetch(url);
      const $ = cheerio.load(html);
      const novels = [];
      $("li.novel-item").each((_i, el) => {
        const $el = $(el);
        const $a = $el.find(".novel-title a");
        const title = $a.text().trim();
        const path = $a.attr("href") || "";
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
      const cover = $("figure.cover img").attr("data-src") || $("figure.cover img").attr("src") || "";
      const author = $('span[itemprop="author"]').text().trim() || $("a.author").text().trim() || "";
      const summary = $("p.summary").text().trim() || $("div.summary").text().trim() || "";
      const statusText = $("span.status").first().text().trim() || "Ongoing";
      const chapters = [];
      $("ul.chapter-list li").each((i, el) => {
        const $el = $(el);
        const $a = $el.find("a");
        const chName = $a.find(".chapter-title").text().trim() || $a.text().trim();
        const chPath = $a.attr("href") || "";
        if (chName && chPath) {
          chapters.push({
            id: chPath,
            path: chPath,
            name: chName,
            chapterNumber: i + 1,
            releaseDate: $el.find("time").attr("datetime") || ""
          });
        }
      });
      return { name, path: novelPath, cover, author, summary, status: statusText, chapters };
    },
    parseChapter(chapterPath) {
      const url = `${BASE_URL}${chapterPath}`;
      const html = SOURCE.fetch(url);
      const $ = cheerio.load(html);
      return $("div.chapter-content").html() || $("div#chapter-container").html() || "";
    }
  };
  globalThis.plugin = plugin;
})();
