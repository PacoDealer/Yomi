# Writing a Yomi extension

Yomi ships with no sources. People add **repositories** (a link to a list of plugins), install the plugins they want,
and Yomi runs them. This guide shows how to write a plugin, host it, and test it — with a complete, working example:
[`docs/example-plugin/wikisource.js`](example-plugin/wikisource.js), a novel source for
[Wikisource](https://en.wikisource.org)'s public-domain library.

> **What belongs in a plugin.** Only sources you are allowed to use: public-domain or openly licensed works, sites
> that offer an API for programs, or your own server. Read the site's terms first — for example, Project Gutenberg's
> website forbids automated access, and Standard Ebooks keeps most of its catalog feeds for patrons. This repository
> does not host plugins for other sites, and Yomi never suggests a repository to its users.

## Three kinds of repositories

| Kind | What you add in Yomi | Runs as |
|---|---|---|
| **Yomi / LNReader plugins** (this guide) | a link to a `.json` plugin list | JavaScript in JavaScriptCore |
| Mihon / Keiyoushi extensions | a link to `index.min.json` or `index.pb` | Kotlin, on the phone's embedded JVM |
| OPDS, Kavita, Komga | a server address | Yomi's own clients |

To use a repository: **Browse → Extensions → ⋯ → Add Repository**, paste the link, then tap **Add** next to a plugin.

## The plugin list (`index.json`)

A JSON array; one entry per plugin. The example's [`index.json`](example-plugin/index.json):

```json
[
  {
    "id": "org.wikisource.example",
    "name": "Wikisource (example)",
    "version": "1.0.0",
    "language": "en",
    "description": "Public-domain and freely licensed books from en.wikisource.org …",
    "iconURL": "https://en.wikisource.org/static/favicon/wikisource.ico",
    "fileURL": "https://raw.githubusercontent.com/PacoDealer/Yomi/main/docs/example-plugin/wikisource.js",
    "isNSFW": false,
    "kind": "novel",
    "sha256": "<sha-256 of the .js file, hex>",
    "site": "https://en.wikisource.org"
  }
]
```

- `id` must stay the same forever — it is how Yomi knows an update is the same plugin.
- `version`: raise it when the file changes; Yomi offers **Update** when it is higher than the installed one.
- `kind`: `"novel"` or `"manga"`. `isNSFW: true` hides the plugin unless the user turned on adult extensions.
- `sha256`: optional but strongly recommended. Yomi refuses a download whose bytes don't match, so a broken mirror or
  a tampered file never replaces a working plugin. Compute it with `shasum -a 256 plugin.js`. **Update it every time
  the file changes**, or nobody can install the new version.
- The repository URL must end in `.json`. Any static host works (GitHub raw, GitHub Pages, Firebase Hosting, your
  own server); Yomi also checks that the download is JavaScript that parses, not an error page.

## What a plugin can use

Each plugin runs in its own JavaScriptCore context, off the main thread. There is no DOM, no `window`, no
`localStorage`. Available:

- **`SOURCE.fetch(url, options)`** — a *synchronous* HTTP request; returns the response body as a string.
  `options`: `{ method: "GET" | "POST", headers: { … }, body: "…" }`. When a response is a Cloudflare check page,
  Yomi notices it and offers the user its in-app browser to pass the check.
- **`fetchApi(url, options)`** — the LNReader-style async version, returning a Promise of a fetch-like Response
  (`text()`, `json()`, `status`, `ok`, `url`, `headers.get()`).
- **`cheerio`** (real cheerio 1.2), **`dayjs`**, **`htmlparser2`**, `URL`, `URLSearchParams`, `atob`, `TextEncoder`,
  `setTimeout`, `console.log`.
- Global variables live as long as the source is open — useful for caching (the example remembers pagination tokens).

## Novel plugins ("Format B", the LNReader shape)

Define one global object called `plugin`:

```js
var plugin = {
  popularNovels: function (pageNo, options) { … },   // Browse. options.showLatestNovels === true → "Latest" tab
  searchNovels: function (searchTerm, pageNo) { … },  // Search all sources
  parseNovel: function (novelPath) { … },             // Detail page + chapter list
  parseChapter: function (chapterPath) { … }          // Chapter text
};
```

| Function | Returns |
|---|---|
| `popularNovels`, `searchNovels` | `[{ name, path, cover }]` — `path` is whatever your `parseNovel` needs; `cover` may be `""` |
| `parseNovel` | `{ name, path, cover, author, summary, status, genres, chapters: [{ name, path, chapterNumber, releaseTime }] }` |
| `parseChapter` | an HTML string |

- Return the **whole** chapter list **in reading order** (oldest first) with `chapterNumber` counting up. Yomi keys a
  novel's chapters by their position in that list, so read progress follows position: never drop or reorder chapters
  between calls, and add new ones at the end.
- Chapter HTML is shown in Yomi's reader with its own fonts, themes and margins — return the text, not the page.
  Remove site navigation, ads and comment widgets. Scripts in it never run (the reader has a strict
  Content-Security-Policy).
- Pages are numbered from 1. Return `[]` when there are no more.
- Plugins written for [LNReader](https://github.com/LNReader/lnreader-plugins) (`module.exports`/`exports.default`,
  `parseNovelAndChapters`, async functions) also work; Yomi adapts them.

## Manga plugins ("Format A")

Global functions:

```js
function getMangaList(page) { … }            // Browse → [{ id, path, title, coverURL, summary, author, artist, status, genres }]
function searchManga(query, page) { … }      // Search → same shape
function getLatestManga(page) { … }          // optional; adds a "Latest" tab
function getChapterList(mangaPath) { … }     // → [{ id, path, name, chapterNumber, scanlator }]
function getPageList(chapterPath) { … }      // → ["https://…/page1.jpg", …]
```

`id`, `path` and `title`/`name` are required; everything else is optional. `status` is one of `ongoing`, `completed`,
`hiatus`, `cancelled`. Give every chapter a numeric `chapterNumber` (12, 12.5): Yomi sorts chapters and finds the next
one to read by it. Keep chapter `id`s stable — a chapter whose `id` changes is a new chapter to Yomi (since S188 it
moves the read state over when exactly one old and one new chapter share a number read from their names, but don't rely on it).

## Testing

1. **In Node, against the live site** — [`example-plugin/test.mjs`](example-plugin/test.mjs) loads Yomi's own
   cheerio bundle (`Yomi/Resources/yomi-js-libs.js`) and a curl-backed `SOURCE.fetch`, then calls each function:

   ```bash
   node docs/example-plugin/test.mjs
   ```

   Copy it for your plugin and change the checks. Node is faster than JavaScriptCore, so also time your functions:
   anything that fetches once per chapter inside `parseNovel` will feel slow in the app.

2. **In Yomi** — serve the folder from your Mac and add it as a repository in the simulator (`localhost` reaches the
   Mac):

   ```bash
   cd docs/example-plugin && python3 -m http.server 8765
   ```

   Make a copy of `index.json` whose `fileURL` is `http://localhost:8765/wikisource.js`, then add
   `http://localhost:8765/index.json` in **Add Repository**. Raise `version` in the copy to test the update path.

## The example, step by step

[`wikisource.js`](example-plugin/wikisource.js) uses the [MediaWiki Action API](https://www.mediawiki.org/wiki/API:Main_page):

- **Browse:** `list=categorymembers` on *Category:Novels* (A–Z for Popular, newest-added for Latest), continuing with
  `cmcontinue` tokens kept in a global.
- **Search:** `list=search`, keeping only main works (titles without `/`).
- **Covers:** one `prop=pageimages` request per page of results; most works have none.
- **Detail:** `action=parse` on the work's page; chapters are the links to its subpages in page order, without the
  pages that only group others ("Volume 1" when "Volume 1/Chapter 1" is also listed).
- **Chapter:** `action=parse` on the subpage, with Wikisource's header, footer and edit links removed and a source link
  added at the end (the texts are public domain or CC BY-SA).
- It sends a descriptive `User-Agent`, as [Wikimedia asks of every API client](https://meta.wikimedia.org/wiki/User-Agent_policy).

Known limit, kept on purpose to keep the example short: works split deeper than volume → chapter (Les Misérables:
Volume → Book → Chapter) list their Book pages as chapters.

## Licence

Yomi is MPL-2.0. The example plugin is under the same licence — copy it freely as a starting point.
