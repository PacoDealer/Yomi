// @name BoxNovel
// @version 1.0.0
// @lang en
// @description Large novel catalog using the Madara WordPress theme.
// @icon https://boxnovel.com/wp-content/uploads/2018/09/cropped-boxnovel_logo_icon-1-32x32.png
// @nsfw false

declare const SOURCE: { fetch(url: string): string };
declare const cheerio: { load(html: string): any };

const BASE_URL = 'https://boxnovel.com';

const plugin = {
  popularNovels(pageNo: number): any[] {
    const url = `${BASE_URL}/novel/page/${pageNo}/?m_orderby=views`;
    const html = SOURCE.fetch(url);
    const $ = cheerio.load(html);
    const novels: any[] = [];
    $('div.page-item-detail.manga').each((_i: number, el: any) => {
      const $el = $(el);
      const $a = $el.find('.post-title a').last();
      const title = $a.text().trim();
      const path = ($a.attr('href') || '').replace(BASE_URL, '');
      const cover = $el.find('img').attr('data-src') || $el.find('img').attr('src') || '';
      if (title && path) novels.push({ name: title, path, cover });
    });
    return novels;
  },

  searchNovels(query: string, pageNo: number): any[] {
    const url = `${BASE_URL}/page/${pageNo}/?s=${encodeURIComponent(query)}&post_type=wp-manga`;
    const html = SOURCE.fetch(url);
    const $ = cheerio.load(html);
    const novels: any[] = [];
    $('div.row.c-tabs-item__content').each((_i: number, el: any) => {
      const $el = $(el);
      const $a = $el.find('.post-title a').last();
      const title = $a.text().trim();
      const path = ($a.attr('href') || '').replace(BASE_URL, '');
      const cover = $el.find('img').attr('data-src') || $el.find('img').attr('src') || '';
      if (title && path) novels.push({ name: title, path, cover });
    });
    return novels;
  },

  parseNovel(novelPath: string): any {
    const url = `${BASE_URL}${novelPath}`;
    const html = SOURCE.fetch(url);
    const $ = cheerio.load(html);

    const name = $('div.post-title h1').text().trim() || $('title').text().split('|')[0].trim();
    const cover = $('div.summary_image img').attr('data-src') || $('div.summary_image img').attr('src') || '';
    const author = $('div.author-content a').first().text().trim() || '';
    const summary = $('div.summary__content').text().trim() || '';
    const statusText = $('div.post-status').find('.summary-content').last().text().trim() || 'Ongoing';

    // Chapters are loaded via AJAX — grab whatever is pre-rendered
    const chapters: any[] = [];
    $('li.wp-manga-chapter').each((i: number, el: any) => {
      const $el = $(el);
      const $a = $el.find('a');
      const chName = $a.text().trim();
      const chHref = $a.attr('href') || '';
      const chPath = chHref.replace(BASE_URL, '');
      if (chName && chPath) {
        chapters.push({
          id: chPath,
          path: chPath,
          name: chName,
          chapterNumber: i + 1,
          releaseDate: $el.find('span.chapter-release-date').text().trim(),
        });
      }
    });
    chapters.reverse();

    return { name, path: novelPath, cover, author, summary, status: statusText, chapters };
  },

  parseChapter(chapterPath: string): string {
    const url = `${BASE_URL}${chapterPath}`;
    const html = SOURCE.fetch(url);
    const $ = cheerio.load(html);
    return $('div.reading-content').html() || $('div.text-left').html() || '';
  },
};

(globalThis as any).plugin = plugin;
