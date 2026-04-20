// @name MTLNovel
// @version 1.0.0
// @lang en
// @description Machine-translated Chinese and Korean web novels. Large catalog.
// @icon https://www.mtlnovel.com/wp-content/uploads/2018/10/mtlnovel_com_logo_text-2-150x150.png
// @nsfw false

declare const SOURCE: { fetch(url: string): string };
declare const cheerio: { load(html: string): any };

const BASE_URL = 'https://www.mtlnovel.com';

const plugin = {
  popularNovels(pageNo: number): any[] {
    const url = `${BASE_URL}/novel-list/?sort=views&order=desc&pg=${pageNo}`;
    const html = SOURCE.fetch(url);
    const $ = cheerio.load(html);
    const novels: any[] = [];
    $('div.box.col-tip.col-sm-6').each((_i: number, el: any) => {
      const $el = $(el);
      const $a = $el.find('a.list-title').first();
      const title = $a.text().trim();
      const href = $a.attr('href') || '';
      const path = href.replace(BASE_URL, '') || href;
      const cover = $el.find('amp-img, img').attr('src') || '';
      if (title && path) novels.push({ name: title, path, cover });
    });
    return novels;
  },

  searchNovels(query: string, pageNo: number): any[] {
    const url = `${BASE_URL}/?s=${encodeURIComponent(query)}&pg=${pageNo}`;
    const html = SOURCE.fetch(url);
    const $ = cheerio.load(html);
    const novels: any[] = [];
    $('div.box.col-tip.col-sm-6').each((_i: number, el: any) => {
      const $el = $(el);
      const $a = $el.find('a.list-title').first();
      const title = $a.text().trim();
      const href = $a.attr('href') || '';
      const path = href.replace(BASE_URL, '') || href;
      const cover = $el.find('amp-img, img').attr('src') || '';
      if (title && path) novels.push({ name: title, path, cover });
    });
    return novels;
  },

  parseNovel(novelPath: string): any {
    const url = `${BASE_URL}${novelPath}`;
    const html = SOURCE.fetch(url);
    const $ = cheerio.load(html);

    const name = $('h1.entry-title').text().trim() || $('title').text().split('|')[0].trim();
    const cover = $('div.nov-head amp-img, div.nov-head img').attr('src') || '';
    const author = $('span.author').text().replace('Author:', '').trim() || '';
    const summary = $('div.desc p').text().trim() || $('div.summary').text().trim() || '';
    const statusText = $('span.status').text().trim() || 'Ongoing';

    const chapters: any[] = [];
    $('div.ch-list a, ul.chapter-list a').each((i: number, el: any) => {
      const $a = $(el);
      const chName = $a.text().trim();
      const href = $a.attr('href') || '';
      const chPath = href.replace(BASE_URL, '') || href;
      if (chName && chPath) {
        chapters.push({
          id: chPath,
          path: chPath,
          name: chName,
          chapterNumber: i + 1,
          releaseDate: '',
        });
      }
    });

    return { name, path: novelPath, cover, author, summary, status: statusText, chapters };
  },

  parseChapter(chapterPath: string): string {
    const url = `${BASE_URL}${chapterPath}`;
    const html = SOURCE.fetch(url);
    const $ = cheerio.load(html);
    return $('div.par').html() || $('div#chp-raw').html() || $('div.entry-content').html() || '';
  },
};

(globalThis as any).plugin = plugin;
