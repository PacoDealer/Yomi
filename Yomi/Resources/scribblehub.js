const BASE_URL = "https://www.scribblehub.com";

// ─── Format B plugin object ───────────────────────────────────────────────────
// Verified selectors (live, 2026-04-05):
//   Popular list: div.search_main_box.mb
//   Title + path: div.search_title.mb > a  (text = title, href = full URL)
//   Cover: div.search_img.mb > img[src]  (absolute cdn.scribblehub.com URL)
//   Series ID: span element id="sid{N}" inside search_title
//   Chapter list: ol.toc_ol > li.toc_w > a.toc_a  (href + text)
//   Chapter content: div.chp_raw#chp_raw

var plugin = {

  popularNovels: function(pageNo, options) {
    var url = BASE_URL + "/series-ranking/?sort=1&order=2&pg=" + pageNo;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    var novels = [];

    $("div.search_main_box.mb").each(function(i, el) {
      var $titleLink = el.find("div.search_title a").first();
      var title = $titleLink.text().trim();
      var fullHref = $titleLink.attr("href") || "";
      // fullHref = "https://www.scribblehub.com/series/664073/rebirth-of-the-nephilim/"
      // path = relative: /series/664073/rebirth-of-the-nephilim/
      var path = fullHref.replace(BASE_URL, "") || fullHref;
      var cover = el.find("div.search_img img").attr("src") || "";
      if (title && path) novels.push({ name: title, path: path, cover: cover });
    });

    return novels;
  },

  parseNovel: function(novelPath) {
    // novelPath = "/series/664073/rebirth-of-the-nephilim/"
    var url = BASE_URL + novelPath;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);

    var name = $("div.fic_title").text().trim() ||
               $(".fic-desc h1").text().trim() ||
               $("title").text().split("|")[0].trim();

    // Cover: look for og:image meta or the thumbnail img
    var cover = $("meta[property='og:image']").attr("content") ||
                $("div.fic-img img").attr("src") ||
                $(".fic-thumb img").attr("src") || "";

    var author = $("span.auth a").first().text().trim() ||
                 $(".fic-author a").first().text().trim() || "";

    var summary = $("div.wi_fic_desc").text().trim() || "";

    var status = $("span.sb_content.completed, span.sb_content.ongoing, span.sb_content.hiatus")
      .first().text().trim() || "Ongoing";

    // Chapters come pre-rendered in ol.toc_ol (first page, newest first)
    var chapters = [];
    $("ol.toc_ol li.toc_w").each(function(i, el) {
      var $a = el.find("a.toc_a");
      var chName = $a.text().trim();
      var chHref = $a.attr("href") || "";
      // chHref = "https://www.scribblehub.com/read/664073-.../chapter/2272281/"
      var chPath = chHref.replace(BASE_URL, "");
      var order = parseInt(el.attr("order") || "0", 10);
      if (chName && chPath) {
        chapters.push({
          id: chPath,
          path: chPath,
          name: chName,
          chapterNumber: order,
          releaseDate: el.find("span.fic_date_pub").attr("title") || ""
        });
      }
    });

    // Chapters come newest-first; reverse for ascending order
    chapters.reverse();

    return {
      name: name,
      path: novelPath,
      cover: cover,
      author: author,
      summary: summary,
      status: status,
      chapters: chapters
    };
  },

  // Chapter content — verified: div.chp_raw#chp_raw
  parseChapter: function(chapterPath) {
    // chapterPath = "/read/664073-rebirth-of-the-nephilim/chapter/664075/"
    var url = BASE_URL + chapterPath;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    var content = $("div.chp_raw").html() || "";
    return content;
  },

  // Search — same search_main_box structure
  // URL: https://www.scribblehub.com/?s={query}&post_type=fictionposts
  searchNovels: function(searchTerm, pageNo) {
    var url = BASE_URL + "/?s=" + encodeURIComponent(searchTerm) + "&post_type=fictionposts&pg=" + pageNo;
    var html = SOURCE.fetch(url);
    var $ = cheerio.load(html);
    var novels = [];

    $("div.search_main_box.mb").each(function(i, el) {
      var $titleLink = el.find("div.search_title a").first();
      var title = $titleLink.text().trim();
      var fullHref = $titleLink.attr("href") || "";
      var path = fullHref.replace(BASE_URL, "") || fullHref;
      // Cover not reliably present on search page — use sid to build CDN URL
      var sidSpan = el.find("span[id^='sid']").attr("id") || "";
      var sid = sidSpan.replace("sid", "");
      var cover = sid
        ? "https://cdn.scribblehub.com/seriesimg/mid/" + (parseInt(sid,10) % 100) + "/mid_" + sid + ".jpg"
        : "";
      if (title && path) novels.push({ name: title, path: path, cover: cover });
    });

    return novels;
  }
};
