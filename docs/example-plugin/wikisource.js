// Yomi example extension — Wikisource (https://en.wikisource.org), a library of public-domain and freely licensed texts.
//
// Why Wikisource: it has an official API meant for programs (MediaWiki Action API), so an app may use it. Project
// Gutenberg's website forbids automated access and Standard Ebooks keeps most of its feeds for patrons, so neither
// fits a plugin. Texts on Wikisource are public domain or CC BY-SA — Yomi shows the source link on every chapter.
//
// This is a "Format B" (LNReader-style) novel plugin: one global `plugin` object with four functions. Yomi calls them
// from a background thread; SOURCE.fetch is synchronous and returns the response body as a string. See
// docs/EXTENSIONS.md for the whole contract. License: MPL-2.0, like the rest of the repository.

var API = "https://en.wikisource.org/w/api.php";
var SITE = "https://en.wikisource.org/wiki/";
// Wikimedia asks every API client to identify itself: https://meta.wikimedia.org/wiki/User-Agent_policy
var HEADERS = { "User-Agent": "YomiWikisourceExample/1.0 (https://github.com/PacoDealer/Yomi)" };
var PAGE_SIZE = 40;

function api(params) {
  var query = "format=json&formatversion=2";
  for (var key in params) query += "&" + key + "=" + encodeURIComponent(params[key]);
  var body = SOURCE.fetch(API + "?" + query, { headers: HEADERS });
  return JSON.parse(body);
}

// A work's main page has no "/" in its title; "Title/Chapter 1" is a chapter of it.
function isWork(title) {
  return title.indexOf("/") === -1;
}

// Cover thumbnails for up to 50 titles in one request. Most works have none — an empty cover is fine.
function covers(titles) {
  var result = {};
  if (titles.length === 0) return result;
  var data = api({ action: "query", prop: "pageimages", pithumbsize: 400, titles: titles.slice(0, 50).join("|") });
  ((data.query && data.query.pages) || []).forEach(function (page) {
    if (page.thumbnail) result[page.title] = page.thumbnail.source;
  });
  return result;
}

function toItems(titles) {
  var art = covers(titles);
  return titles.map(function (title) {
    return { name: title, path: title, cover: art[title] || "" };
  });
}

// Category listings page with a continuation token, not a page number. The JS context lives as long as the source is
// open, so remembering the tokens here lets page N be asked for again without walking from page 1. One map per feed.
var continueTokens = { popular: { 1: "" }, latest: { 1: "" } };

var plugin = {
  id: "org.wikisource.example",
  name: "Wikisource (example)",
  site: "https://en.wikisource.org",
  version: "1.0.0",

  // Browse. Yomi calls this for both tabs: "Popular" (options.showLatestNovels unset) and "Latest" (set to true).
  // Wikisource has no popularity ranking, so Popular = the "Novels" category A–Z and Latest = most recently added.
  popularNovels: function (pageNo, options) {
    var feed = options && options.showLatestNovels ? "latest" : "popular";
    var tokens = continueTokens[feed];
    for (var page = 1; page < pageNo && tokens[page + 1] === undefined; page++) {
      if (tokens[page] === undefined || tokens[page] === null) return [];
      plugin._novelsPage(feed, page);
    }
    if (tokens[pageNo] === undefined || tokens[pageNo] === null) return [];
    return toItems(plugin._novelsPage(feed, pageNo));
  },

  _novelsPage: function (feed, pageNo) {
    var tokens = continueTokens[feed];
    var params = { action: "query", list: "categorymembers", cmtitle: "Category:Novels", cmnamespace: 0,
                   cmlimit: PAGE_SIZE };
    if (feed === "latest") { params.cmsort = "timestamp"; params.cmdir = "desc"; }
    if (tokens[pageNo]) params.cmcontinue = tokens[pageNo];
    var data = api(params);
    tokens[pageNo + 1] = data["continue"] ? data["continue"].cmcontinue : null;
    return data.query.categorymembers.map(function (m) { return m.title; }).filter(isWork);
  },

  searchNovels: function (searchTerm, pageNo) {
    var data = api({ action: "query", list: "search", srsearch: searchTerm, srnamespace: 0, srlimit: PAGE_SIZE,
                     sroffset: (pageNo - 1) * PAGE_SIZE });
    var seen = {};
    var titles = data.query.search.map(function (r) { return r.title; }).filter(function (title) {
      if (!isWork(title) || seen[title]) return false;
      seen[title] = true;
      return true;
    });
    return toItems(titles);
  },

  // Detail page + chapter list. Chapters are the work's subpages, in the order the main page links them.
  parseNovel: function (novelPath) {
    var parsed = api({ action: "parse", page: novelPath, prop: "text", redirects: 1 }).parse;
    var title = parsed.title;
    var $ = cheerio.load(parsed.text);

    var author = $("a[href^='/wiki/Author:']").first().text().trim();
    // The notes box carries inline CSS and a "sister projects" link list; .text() would return those too.
    $("style, script, .plainSister, .sisterproject, .wst-sister").remove();
    var notes = $(".wst-header-notes, .header_notes, #header_notes").first().text().replace(/\s+/g, " ").trim();

    var chapters = plugin._subpages($, title);
    // Some works link only their volumes from the main page; their chapters are listed one level down. Works split
    // deeper than that (Les Misérables: Volume → Book → Chapter) show their Book pages as chapters — walking further
    // would cost one request per Book every time the work is opened, so this example stops here.
    // Only bare volume links count ("Volume 1", not "Volume 1 · Chapter 1" — those are already chapters).
    var onlyVolumes = chapters.length > 0 && chapters.every(function (c) {
      return c.name.indexOf(" · ") === -1 && /^(volume|book|part)\b/i.test(c.name);
    });
    if (onlyVolumes) {
      var expanded = [];
      chapters.forEach(function (volume) {
        var page = api({ action: "parse", page: volume.path, prop: "text", redirects: 1 }).parse;
        var inner = plugin._subpages(cheerio.load(page.text), volume.path);
        expanded = expanded.concat(inner.length > 0 ? inner : [volume]);
      });
      chapters = expanded;
    }
    // A short work (a story, a poem) is a single page: it is its own only chapter.
    if (chapters.length === 0) chapters = [{ name: title, path: title }];

    return {
      name: title,
      path: title,
      cover: covers([title])[title] || "",
      author: author,
      summary: notes,
      status: "Completed",
      chapters: chapters.map(function (c, i) {
        return { name: c.name, path: c.path, chapterNumber: i + 1 };
      })
    };
  },

  // Links to "<prefix>/…" in page order, without pages that only group others ("Volume 1" when
  // "Volume 1/Chapter 1" is also linked).
  _subpages: function ($, prefix) {
    var list = [];
    var seen = {};
    $("a[href^='/wiki/']").each(function (i, el) {
      var href = $(el).attr("href").split("#")[0];
      var target = decodeURIComponent(href.slice("/wiki/".length)).replace(/_/g, " ");
      if (target.indexOf(prefix + "/") !== 0 || seen[target]) return;
      seen[target] = true;
      list.push({ name: target.slice(prefix.length + 1).replace(/\//g, " · "), path: target });
    });
    return list.filter(function (c) {
      return !list.some(function (other) { return other.path.indexOf(c.path + "/") === 0; });
    });
  },

  // Chapter text as HTML. Wikisource's navigation header, footer and edit links are removed; the novel reader styles
  // the rest itself.
  parseChapter: function (chapterPath) {
    var parsed = api({ action: "parse", page: chapterPath, prop: "text", redirects: 1 }).parse;
    var $ = cheerio.load(parsed.text);
    $(".ws-noexport, .wst-header, .ws-header, #headertemplate, .mw-editsection, .licenseContainer, " +
      ".wst-licensecontainer, .noprint, style, link, script").remove();
    var body = $(".mw-parser-output").html() || $.html();
    return body + '<p><small>Source: <a href="' + SITE + encodeURIComponent(chapterPath.replace(/ /g, "_")) +
      '">Wikisource</a></small></p>';
  }
};
