(() => {
  // scripts/plugins-src/mtlnovel.ts
  var BASE_URL = "https://www.mtlnovel.com";
  var plugin = {
    popularNovels(pageNo) {
      const url = `${BASE_URL}/novel-list/?sort=views&order=desc&pg=${pageNo}`;
      const html = SOURCE.fetch(url);
      const $ = cheerio.load(html);
      const novels = [];
      $("div.box.col-tip.col-sm-6").each((_i, el) => {
        const $el = $(el);
        const $a = $el.find("a.list-title").first();
        const title = $a.text().trim();
        const href = $a.attr("href") || "";
        const path = href.replace(BASE_URL, "") || href;
        const cover = $el.find("amp-img, img").attr("src") || "";
        if (title && path) novels.push({ name: title, path, cover });
      });
      return novels;
    },
    searchNovels(query, pageNo) {
      const url = `${BASE_URL}/?s=${encodeURIComponent(query)}&pg=${pageNo}`;
      const html = SOURCE.fetch(url);
      const $ = cheerio.load(html);
      const novels = [];
      $("div.box.col-tip.col-sm-6").each((_i, el) => {
        const $el = $(el);
        const $a = $el.find("a.list-title").first();
        const title = $a.text().trim();
        const href = $a.attr("href") || "";
        const path = href.replace(BASE_URL, "") || href;
        const cover = $el.find("amp-img, img").attr("src") || "";
        if (title && path) novels.push({ name: title, path, cover });
      });
      return novels;
    },
    parseNovel(novelPath) {
      const url = `${BASE_URL}${novelPath}`;
      const html = SOURCE.fetch(url);
      const $ = cheerio.load(html);
      const name = $("h1.entry-title").text().trim() || $("title").text().split("|")[0].trim();
      const cover = $("div.nov-head amp-img, div.nov-head img").attr("src") || "";
      const author = $("span.author").text().replace("Author:", "").trim() || "";
      const summary = $("div.desc p").text().trim() || $("div.summary").text().trim() || "";
      const statusText = $("span.status").text().trim() || "Ongoing";
      const chapters = [];
      $("div.ch-list a, ul.chapter-list a").each((i, el) => {
        const $a = $(el);
        const chName = $a.text().trim();
        const href = $a.attr("href") || "";
        const chPath = href.replace(BASE_URL, "") || href;
        if (chName && chPath) {
          chapters.push({
            id: chPath,
            path: chPath,
            name: chName,
            chapterNumber: i + 1,
            releaseDate: ""
          });
        }
      });
      return { name, path: novelPath, cover, author, summary, status: statusText, chapters };
    },
    parseChapter(chapterPath) {
      const url = `${BASE_URL}${chapterPath}`;
      const html = SOURCE.fetch(url);
      const $ = cheerio.load(html);
      return $("div.par").html() || $("div#chp-raw").html() || $("div.entry-content").html() || "";
    }
  };
  globalThis.plugin = plugin;
})();
