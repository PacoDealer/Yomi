function getMangaList(page) {
  return [
    {
      id: "berserk",
      path: "/manga/berserk",
      title: "Berserk",
      coverURL: "https://uploads.mangadex.org/covers/801513ba-a712-498c-8f57-cae55b38cc92/5ba2b576-aca8-4f52-9e6e-e0d08278b7e7.jpg",
      summary: "Guts is a skilled swordsman who joins forces with a mercenary group called the Band of the Hawk.",
      author: "Kentaro Miura",
      artist: "Kentaro Miura",
      status: "hiatus",
      genres: ["Action", "Dark Fantasy", "Adventure"]
    },
    {
      id: "vinland-saga",
      path: "/manga/vinland-saga",
      title: "Vinland Saga",
      coverURL: "https://uploads.mangadex.org/covers/a77742b1-befd-49a4-bff5-1ad4e6b0ef7b/d46d9b29-93e8-4d13-b9f3-b06d3da5dd77.jpg",
      summary: "Young Thorfinn grew up listening to the stories of old sailors who had been to Vinland.",
      author: "Makoto Yukimura",
      artist: "Makoto Yukimura",
      status: "ongoing",
      genres: ["Action", "Historical", "Adventure"]
    }
  ];
}

function getChapterList(mangaPath) {
  return [
    { id: "ch-1", path: mangaPath + "/chapter/1", name: "Chapter 1", chapterNumber: 1.0 },
    { id: "ch-2", path: mangaPath + "/chapter/2", name: "Chapter 2", chapterNumber: 2.0 },
    { id: "ch-3", path: mangaPath + "/chapter/3", name: "Chapter 3", chapterNumber: 3.0 }
  ];
}

function getPageList(chapterPath) {
  return [
    "https://picsum.photos/seed/p1/800/1200",
    "https://picsum.photos/seed/p2/800/1200",
    "https://picsum.photos/seed/p3/800/1200"
  ];
}
