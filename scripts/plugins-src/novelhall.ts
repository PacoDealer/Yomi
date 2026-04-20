// @name NovelHall
// @version 1.0.0
// @lang en
// @description Clean catalog of translated Chinese and Korean web novels.
// @icon https://www.novelhall.com/favicon.ico
// @nsfw false

declare const SOURCE: { fetch(url: string): string };
declare const cheerio: { load(html: string): any };

const BASE_URL = 'https://www.novelhall.com';

const plugin = {
  popularNovels(pageNo: number): any[] {
    const url = `${BASE_URL}/最受欢迎的小说-1/${pageNo}.html`;
    const fallback = `${BASE_URL}/all-novel/views/${pageNo}/`;
    const html = SOURCE.fetch(fallback);
    const $ = cheerio.load(html);
    const novels: any[] = [];
    $('div.section3 ul li, table.display tbody tr').each((_i: number, el: any) => {
      const $el = $(el);
      const $a = $el.find('a').first();
      const title = $a.text().trim();
      const href = $a.attr('href') || '';
      const path = href.startsWith('http') ? href.replace(BASE_URL, '') : href;
      const cover = $el.find('img').attr('src') || '';
      if (title && path) novels.push({ name: title, path, cover });
    });
    return novels;
  },

  searchNovels(query: string, _pageNo: number): any[] {
    const url = `${BASE_URL}/index.php?s=so&module=book&keyword=${encodeURIComponent(query)}`;
    const html = SOURCE.fetch(url);
    const $ = cheerio.load(html);
    const novels: any[] = [];
    $('table.display tbody tr').each((_i: number, el: any) => {
      const $el = $(el);
      const $a = $el.find('td a').first();
      const title = $a.text().trim();
      const href = $a.attr('href') || '';
      const path = href.startsWith('http') ? href.replace(BASE_URL, '') : href;
      if (title && path) novels.push({ name: title, path, cover: '' });
    });
    return novels;
  },

  parseNovel(novelPath: string): any {
    const url = `${BASE_URL}${novelPath}`;
    const html = SOURCE.fetch(url);
    const $ = cheerio.load(html);

    const name = $('h1').first().text().trim() || $('title').text().split('-')[0].trim();
    const cover = $('div.book-img img, .book-info img').attr('src') || '';
    const author = $('span.blue a').first().text().trim() ||
                   $('meta[name="author"]').attr('content') || '';
    const summary = $('div.intro p').first().text().trim() ||
                    $('div.description').text().trim() || '';
    const statusText = $('span.gray').filter((_i: number, el: any) => {
      return $(el).text().includes('完结') || $(el).text().includes('连载');
    }).text().includes('完结') ? 'Completed' : 'Ongoing';

    const chapters: any[] = [];
    $('div#morelist ul li a, div.chapter-list li a').each((i: number, el: any) => {
      const $a = $(el);
      const chName = $a.text().trim();
      const href = $a.attr('href') || '';
      const chPath = href.startsWith('http') ? href.replace(BASE_URL, '') : href;
      if (chName && chPath) {
        chapters.push({ id: chPath, path: chPath, name: chName, chapterNumber: i + 1, releaseDate: '' });
      }
    });

    return { name, path: novelPath, cover, author, summary, status: statusText, chapters };
  },

  parseChapter(chapterPath: string): string {
    const url = `${BASE_URL}${chapterPath}`;
    const html = SOURCE.fetch(url);
    const $ = cheerio.load(html);
    return $('div#htmlContent, div.entry-content').html() || '';
  },
};

(globalThis as any).plugin = plugin;
