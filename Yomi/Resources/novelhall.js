(() => {
  // scripts/plugins-src/novelhall.ts
  var BASE_URL = "https://www.novelhall.com";
  var plugin = {
    popularNovels(pageNo) {
      const url = `${BASE_URL}/\u6700\u53D7\u6B22\u8FCE\u7684\u5C0F\u8BF4-1/${pageNo}.html`;
      const fallback = `${BASE_URL}/all-novel/views/${pageNo}/`;
      const html = SOURCE.fetch(fallback);
      const $ = cheerio.load(html);
      const novels = [];
      $("div.section3 ul li, table.display tbody tr").each((_i, el) => {
        const $el = $(el);
        const $a = $el.find("a").first();
        const title = $a.text().trim();
        const href = $a.attr("href") || "";
        const path = href.startsWith("http") ? href.replace(BASE_URL, "") : href;
        const cover = $el.find("img").attr("src") || "";
        if (title && path) novels.push({ name: title, path, cover });
      });
      return novels;
    },
    searchNovels(query, _pageNo) {
      const url = `${BASE_URL}/index.php?s=so&module=book&keyword=${encodeURIComponent(query)}`;
      const html = SOURCE.fetch(url);
      const $ = cheerio.load(html);
      const novels = [];
      $("table.display tbody tr").each((_i, el) => {
        const $el = $(el);
        const $a = $el.find("td a").first();
        const title = $a.text().trim();
        const href = $a.attr("href") || "";
        const path = href.startsWith("http") ? href.replace(BASE_URL, "") : href;
        if (title && path) novels.push({ name: title, path, cover: "" });
      });
      return novels;
    },
    parseNovel(novelPath) {
      const url = `${BASE_URL}${novelPath}`;
      const html = SOURCE.fetch(url);
      const $ = cheerio.load(html);
      const name = $("h1").first().text().trim() || $("title").text().split("-")[0].trim();
      const cover = $("div.book-img img, .book-info img").attr("src") || "";
      const author = $("span.blue a").first().text().trim() || $('meta[name="author"]').attr("content") || "";
      const summary = $("div.intro p").first().text().trim() || $("div.description").text().trim() || "";
      const statusText = $("span.gray").filter((_i, el) => {
        return $(el).text().includes("\u5B8C\u7ED3") || $(el).text().includes("\u8FDE\u8F7D");
      }).text().includes("\u5B8C\u7ED3") ? "Completed" : "Ongoing";
      const chapters = [];
      $("div#morelist ul li a, div.chapter-list li a").each((i, el) => {
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
      return $("div#htmlContent, div.entry-content").html() || "";
    }
  };
  globalThis.plugin = plugin;
})();
