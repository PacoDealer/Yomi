import Foundation

var failures = 0
func check<T: Equatable>(_ name: String, _ got: T, _ want: T) {
    let ok = got == want
    if !ok { failures += 1 }
    print("\(ok ? "ok  " : "FAIL") \(name)" + (ok ? "" : "\n  got  \(got)\n  want \(want)"))
}
func u(_ s: String) -> URL { URL(string: s)! }

// url(in:)
check("plain link", SharedLink.url(in: "https://asurascans.com/comics/x")?.host, "asurascans.com")
check("spaces around", SharedLink.url(in: "  https://a.com/x \n")?.path, "/x")
check("words are not a link", SharedLink.url(in: "solo leveling") == nil, true)
check("text with a link inside is not a link", SharedLink.url(in: "read https://a.com/x") == nil, true)
check("other schemes refused", SharedLink.url(in: "file:///etc/passwd") == nil, true)
check("yomi scheme refused", SharedLink.url(in: "yomi://open?id=1") == nil, true)

// sameSite
check("same host", SharedLink.sameSite(u("https://asurascans.com/comics/a"), home: "https://asurascans.com"), true)
check("www ignored", SharedLink.sameSite(u("https://www.mangafire.to/manga/a"), home: "https://mangafire.to"), true)
check("case ignored", SharedLink.sameSite(u("https://MangaFire.to/x"), home: "https://mangafire.to/"), true)
check("other host", SharedLink.sameSite(u("https://evil-asurascans.com/x"), home: "https://asurascans.com"), false)
check("subdomain is another site", SharedLink.sameSite(u("https://api.asurascans.com/x"), home: "https://asurascans.com"), false)
check("bad home", SharedLink.sameSite(u("https://a.com/x"), home: ""), false)

// novelPath — Yomi's own plugins: BASE_URL without a trailing slash, paths start with "/"
check("WeTried keeps leading slash",
      SharedLink.novelPath(link: u("https://wetriedtls.com/series/the-regressor/"), site: "https://wetriedtls.com"),
      "/series/the-regressor")
check("query and fragment dropped",
      SharedLink.novelPath(link: u("https://novelfire.net/book/abc?ref=x#top"), site: "https://novelfire.net"),
      "/book/abc")
check("www on the link only",
      SharedLink.novelPath(link: u("https://www.royalroad.com/fiction/1/x"), site: "https://www.royalroad.com"),
      "/fiction/1/x")
// LNReader plugins: site with a trailing slash, paths without a leading one
check("LNReader site with slash",
      SharedLink.novelPath(link: u("https://novelbin.me/novel-book/shadow-slave"), site: "https://novelbin.me/"),
      "novel-book/shadow-slave")
check("site with a path",
      SharedLink.novelPath(link: u("https://site.com/en/novel/x"), site: "https://site.com/en/"), "novel/x")
check("site path must be whole segment",
      SharedLink.novelPath(link: u("https://site.com/english/novel/x"), site: "https://site.com/en") == nil, true)
check("home page only = nothing", SharedLink.novelPath(link: u("https://novelfire.net/"), site: "https://novelfire.net") == nil, true)
check("other host = nothing", SharedLink.novelPath(link: u("https://other.net/book/a"), site: "https://novelfire.net") == nil, true)

// samePath
check("slashes ignored", SharedLink.samePath("/series/a/", "series/a"), true)
check("different paths", SharedLink.samePath("/series/a", "/series/b"), false)

// searchWords
check("slug with id", SharedLink.searchWords(from: u("https://site.com/manga/solo-leveling-12345")), "solo leveling")
check("chapter link → title part",
      SharedLink.searchWords(from: u("https://site.com/manga/omniscient-reader/chapter-12")), "omniscient reader")
check("short code id", SharedLink.searchWords(from: u("https://mangafire.to/manga/one-piecee.dkw")), "one piecee")
check("html page", SharedLink.searchWords(from: u("https://site.com/read/the-beginning-after-the-end.html")),
      "the beginning after the end")
check("underscores", SharedLink.searchWords(from: u("https://site.com/book/lord_of_mysteries")), "lord of mysteries")
check("number-only path → nothing", SharedLink.searchWords(from: u("https://site.com/123/456")), "")
check("keeps a numeric word inside", SharedLink.searchWords(from: u("https://site.com/series/2-kids-1-house")), "2 kids 1 house")

print(failures == 0 ? "all passed" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
