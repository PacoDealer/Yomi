// @name BabelNovel
// @version 1.1.0
// @lang en
// @description 500k+ translated novels via JSON API.
// @icon https://babelnovel.com/favicon.ico
// @nsfw false

declare const SOURCE: { fetch(url: string, options?: any): string };
declare const cheerio: { load(html: string): any };

const API = 'https://babelnovel.com/api';
const BASE_URL = 'https://babelnovel.com';

const JSON_HEADERS = {
  'Accept': 'application/json, text/plain, */*',
  'Origin': BASE_URL,
  'Referer': BASE_URL + '/',
  'X-Requested-With': 'XMLHttpRequest',
};

function fetchJSON(url: string): any {
  const raw = SOURCE.fetch(url, { headers: JSON_HEADERS });
  if (!raw || raw.trimStart().startsWith('<')) return null;
  try { return JSON.parse(raw); } catch { return null; }
}

function mapBook(book: any): { name: string; path: string; cover: string } {
  return {
    name: book.name || book.tranName || book.title || '',
    path: `/books/${book.id || book.bookId}`,
    cover: book.cover || book.coverUrl || '',
  };
}

const plugin = {
  popularNovels(pageNo: number): any[] {
    const data = fetchJSON(`${API}/books?bookType=0&page=${pageNo - 1}&pageSize=20&sort=POPULAR`);
    if (!data) return [];
    const list: any[] = data.data || data.books || data.list || (Array.isArray(data) ? data : []);
    return list.filter(Boolean).map(mapBook).filter(b => b.name && b.path);
  },

  searchNovels(query: string, pageNo: number): any[] {
    const data = fetchJSON(
      `${API}/books?bookType=0&page=${pageNo - 1}&pageSize=20&sort=POPULAR&name=${encodeURIComponent(query)}`
    );
    if (!data) return [];
    const list: any[] = data.data || data.books || data.list || (Array.isArray(data) ? data : []);
    return list.filter(Boolean).map(mapBook).filter(b => b.name && b.path);
  },

  parseNovel(novelPath: string): any {
    const bookId = novelPath.replace('/books/', '');
    const data = fetchJSON(`${API}/books/${bookId}?fields=id,name,cover,briefIntroduction,author,status`);
    const book = data?.data || data || {};

    const name = book.name || book.tranName || book.title || '';
    const cover = book.cover || book.coverUrl || '';
    const author = book.author?.name || book.authorName || '';
    const summary = book.briefIntroduction || book.intro || book.description || '';
    const statusText = book.status === 2 || book.status === 'COMPLETED' ? 'Completed' : 'Ongoing';

    const chapData = fetchJSON(`${API}/books/${bookId}/chapters?page=0&pageSize=100&orderBy=NO&order=ASC`);
    const chapList: any[] = chapData?.data || chapData?.chapters || chapData?.list || (Array.isArray(chapData) ? chapData : []);
    const chapters = chapList.map((ch: any, i: number) => ({
      id: `/books/${bookId}/chapters/${ch.id || ch.chapterId}`,
      path: `/books/${bookId}/chapters/${ch.id || ch.chapterId}`,
      name: ch.name || ch.chapterName || `Chapter ${i + 1}`,
      chapterNumber: ch.no || ch.chapterNo || i + 1,
      releaseDate: ch.publishAt ? new Date(ch.publishAt).toISOString() : '',
    }));

    return { name, path: novelPath, cover, author, summary, status: statusText, chapters };
  },

  parseChapter(chapterPath: string): string {
    const data = fetchJSON(`${API}${chapterPath}`);
    const content = data?.data?.content || data?.content || data?.text || '';
    return content
      .split('\n')
      .map((line: string) => line.trim())
      .filter((line: string) => line.length > 0)
      .map((line: string) => `<p>${line}</p>`)
      .join('');
  },
};

(globalThis as any).plugin = plugin;
