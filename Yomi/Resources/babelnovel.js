(() => {
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __commonJS = (cb, mod) => function __require() {
    return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
  };

  // scripts/plugins-src/babelnovel.ts
  var require_babelnovel = __commonJS({
    "scripts/plugins-src/babelnovel.ts"() {
      var API = "https://babelnovel.com/api";
      function fetchJSON(url) {
        const raw = SOURCE.fetch(url);
        try {
          return JSON.parse(raw);
        } catch (e) {
          return null;
        }
      }
      var plugin = {
        popularNovels(pageNo) {
          const data = fetchJSON(`${API}/books?bookType=0&page=${pageNo - 1}&pageSize=20&sort=POPULAR`);
          if (!data || !data.data) return [];
          return data.data.map((book) => ({
            name: book.name || book.tranName || "",
            path: `/books/${book.id}`,
            cover: book.cover || ""
          }));
        },
        searchNovels(query, pageNo) {
          const data = fetchJSON(
            `${API}/books?bookType=0&page=${pageNo - 1}&pageSize=20&sort=POPULAR&name=${encodeURIComponent(query)}`
          );
          if (!data || !data.data) return [];
          return data.data.map((book) => ({
            name: book.name || book.tranName || "",
            path: `/books/${book.id}`,
            cover: book.cover || ""
          }));
        },
        parseNovel(novelPath) {
          var _a;
          const bookId = novelPath.replace("/books/", "");
          const data = fetchJSON(`${API}/books/${bookId}?fields=id,name,cover,briefIntroduction,author,status`);
          const book = (data == null ? void 0 : data.data) || data || {};
          const name = book.name || book.tranName || "";
          const cover = book.cover || "";
          const author = ((_a = book.author) == null ? void 0 : _a.name) || "";
          const summary = book.briefIntroduction || "";
          const statusText = book.status === 2 ? "Completed" : "Ongoing";
          const chapData = fetchJSON(`${API}/books/${bookId}/chapters?page=0&pageSize=100&orderBy=NO&order=ASC`);
          const chapList = (chapData == null ? void 0 : chapData.data) || [];
          const chapters = chapList.map((ch, i) => ({
            id: `/books/${bookId}/chapters/${ch.id}`,
            path: `/books/${bookId}/chapters/${ch.id}`,
            name: ch.name || `Chapter ${i + 1}`,
            chapterNumber: ch.no || i + 1,
            releaseDate: ch.publishAt ? new Date(ch.publishAt).toISOString() : ""
          }));
          return { name, path: novelPath, cover, author, summary, status: statusText, chapters };
        },
        parseChapter(chapterPath) {
          var _a;
          const data = fetchJSON(`${API}${chapterPath}`);
          const content = ((_a = data == null ? void 0 : data.data) == null ? void 0 : _a.content) || (data == null ? void 0 : data.content) || "";
          return content.split("\n").map((line) => line.trim()).filter((line) => line.length > 0).map((line) => `<p>${line}</p>`).join("");
        }
      };
      globalThis.plugin = plugin;
    }
  });
  require_babelnovel();
})();
