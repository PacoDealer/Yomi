// @name BabelNovel
// @version 1.0.0
// @lang en
// @description 500k+ translated novels via JSON API. No HTML scraping required.
// @icon https://babelnovel.com/favicon.ico
// @nsfw false

declare const SOURCE: { fetch(url: string): string };
declare const cheerio: { load(html: string): any };

const API = 'https://babelnovel.com/api';
const BASE_URL = 'https://babelnovel.com';

function fetchJSON(url: string): any {
  const raw = SOURCE.fetch(url);
  try { return JSON.parse(raw); } catch { return null; }
}

const plugin = {
  popularNovels(pageNo: number): any[] {
    const data = fetchJSON(`${API}/books?bookType=0&page=${pageNo - 1}&pageSize=20&sort=POPULAR`);
    if (!data || !data.data) return [];
    return (data.data as any[]).map((book: any) => ({
      name: book.name || book.tranName || '',
      path: `/books/${book.id}`,
      cover: book.cover || '',
    }));
  },

  searchNovels(query: string, pageNo: number): any[] {
    const data = fetchJSON(
      `${API}/books?bookType=0&page=${pageNo - 1}&pageSize=20&sort=POPULAR&name=${encodeURIComponent(query)}`
    );
    if (!data || !data.data) return [];
    return (data.data as any[]).map((book: any) => ({
      name: book.name || book.tranName || '',
      path: `/books/${book.id}`,
      cover: book.cover || '',
    }));
  },

  parseNovel(novelPath: string): any {
    // novelPath = "/books/{id}"
    const bookId = novelPath.replace('/books/', '');
    const data = fetchJSON(`${API}/books/${bookId}?fields=id,name,cover,briefIntroduction,author,status`);
    const book = data?.data || data || {};

    const name = book.name || book.tranName || '';
    const cover = book.cover || '';
    const author = book.author?.name || '';
    const summary = book.briefIntroduction || '';
    const statusText = book.status === 2 ? 'Completed' : 'Ongoing';

    // Fetch first page of chapters
    const chapData = fetchJSON(`${API}/books/${bookId}/chapters?page=0&pageSize=100&orderBy=NO&order=ASC`);
    const chapList: any[] = chapData?.data || [];
    const chapters = chapList.map((ch: any, i: number) => ({
      id: `/books/${bookId}/chapters/${ch.id}`,
      path: `/books/${bookId}/chapters/${ch.id}`,
      name: ch.name || `Chapter ${i + 1}`,
      chapterNumber: ch.no || i + 1,
      releaseDate: ch.publishAt ? new Date(ch.publishAt).toISOString() : '',
    }));

    return { name, path: novelPath, cover, author, summary, status: statusText, chapters };
  },

  parseChapter(chapterPath: string): string {
    // chapterPath = "/books/{bookId}/chapters/{chapterId}"
    const data = fetchJSON(`${API}${chapterPath}`);
    const content = data?.data?.content || data?.content || '';
    // Content is plain text paragraphs separated by \n — wrap in <p> tags
    return content
      .split('\n')
      .map((line: string) => line.trim())
      .filter((line: string) => line.length > 0)
      .map((line: string) => `<p>${line}</p>`)
      .join('');
  },
};

(globalThis as any).plugin = plugin;
