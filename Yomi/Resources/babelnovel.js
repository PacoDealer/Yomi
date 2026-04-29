(() => {
  // scripts/plugins-src/babelnovel.ts
  var API = "https://babelnovel.com/api";
  var BASE_URL = "https://babelnovel.com";
  var JSON_HEADERS = {
    "Accept": "application/json, text/plain, */*",
    "Origin": BASE_URL,
    "Referer": BASE_URL + "/",
    "X-Requested-With": "XMLHttpRequest"
  };
  function fetchJSON(url) {
    const raw = SOURCE.fetch(url, { headers: JSON_HEADERS });
    if (!raw || raw.trimStart().startsWith("<")) return null;
    try {
      return JSON.parse(raw);
    } catch (e) {
      return null;
    }
  }
  function mapBook(book) {
    return {
      name: book.name || book.tranName || book.title || "",
      path: `/books/${book.id || book.bookId}`,
      cover: book.cover || book.coverUrl || ""
    };
  }
  var plugin = {
    popularNovels(pageNo) {
      const data = fetchJSON(`${API}/books?bookType=0&page=${pageNo - 1}&pageSize=20&sort=POPULAR`);
      if (!data) return [];
      const list = data.data || data.books || data.list || (Array.isArray(data) ? data : []);
      return list.filter(Boolean).map(mapBook).filter((b) => b.name && b.path);
    },
    searchNovels(query, pageNo) {
      const data = fetchJSON(
        `${API}/books?bookType=0&page=${pageNo - 1}&pageSize=20&sort=POPULAR&name=${encodeURIComponent(query)}`
      );
      if (!data) return [];
      const list = data.data || data.books || data.list || (Array.isArray(data) ? data : []);
      return list.filter(Boolean).map(mapBook).filter((b) => b.name && b.path);
    },
    parseNovel(novelPath) {
      var _a;
      const bookId = novelPath.replace("/books/", "");
      const data = fetchJSON(`${API}/books/${bookId}?fields=id,name,cover,briefIntroduction,author,status`);
      const book = (data == null ? void 0 : data.data) || data || {};
      const name = book.name || book.tranName || book.title || "";
      const cover = book.cover || book.coverUrl || "";
      const author = ((_a = book.author) == null ? void 0 : _a.name) || book.authorName || "";
      const summary = book.briefIntroduction || book.intro || book.description || "";
      const statusText = book.status === 2 || book.status === "COMPLETED" ? "Completed" : "Ongoing";
      const chapData = fetchJSON(`${API}/books/${bookId}/chapters?page=0&pageSize=100&orderBy=NO&order=ASC`);
      const chapList = (chapData == null ? void 0 : chapData.data) || (chapData == null ? void 0 : chapData.chapters) || (chapData == null ? void 0 : chapData.list) || (Array.isArray(chapData) ? chapData : []);
      const chapters = chapList.map((ch, i) => ({
        id: `/books/${bookId}/chapters/${ch.id || ch.chapterId}`,
        path: `/books/${bookId}/chapters/${ch.id || ch.chapterId}`,
        name: ch.name || ch.chapterName || `Chapter ${i + 1}`,
        chapterNumber: ch.no || ch.chapterNo || i + 1,
        releaseDate: ch.publishAt ? new Date(ch.publishAt).toISOString() : ""
      }));
      return { name, path: novelPath, cover, author, summary, status: statusText, chapters };
    },
    parseChapter(chapterPath) {
      var _a;
      const data = fetchJSON(`${API}${chapterPath}`);
      const content = ((_a = data == null ? void 0 : data.data) == null ? void 0 : _a.content) || (data == null ? void 0 : data.content) || (data == null ? void 0 : data.text) || "";
      return content.split("\n").map((line) => line.trim()).filter((line) => line.length > 0).map((line) => `<p>${line}</p>`).join("");
    }
  };
  globalThis.plugin = plugin;
})();
