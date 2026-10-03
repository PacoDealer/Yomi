# Yomi — iOS Manga & Novel Reader

A clean, fast manga, manhwa, manhua and light novel reader for iOS. Extensible architecture — community source repositories provide hundreds of reading sources.

---

## Quick Start

Yomi comes with no sources. You add **repositories** by link, then add the extensions you want from them.

1. Open **Yomi** → **Browse** → **Extensions**
2. Tap **Add Repository** (or **⋯ → Add Repository**) and paste a repository link from below
3. Tap **Add** next to any extension, then open **Browse → Sources**

---

## Source Repositories

| | **Yomi Catalog** | **LNReader Novels** | **Keiyoushi** |
|---|---|---|---|
| **Content** | Curated manga + novels | 500+ light novel sources | 1000+ manga sources |
| **Languages** | EN | 18+ languages | All |

### Yomi Catalog
```
https://yomi-plugins.web.app/index.json
```

### LNReader Novels
```
https://raw.githubusercontent.com/LNReader/lnreader-plugins/plugins/v3.0.0/.dist/plugins.min.json
```

### Keiyoushi (1000+ manga)
Keiyoushi (Mihon) extensions run on the phone. Add its repository like any other:
```
https://github.com/keiyoushi/extensions/raw/repo/index.pb
```

---

## How to Add a Repository

1. Copy a repository link (above, or from the project that publishes it)
2. In Yomi: **Browse → Extensions → ⋯ → Add Repository** — paste the link → **Add**
3. Every extension in that repository appears under **Available** — tap **Add**
4. Updates show up under **Updates**; swipe left on an extension to delete it
5. Manage repositories in **⋯ → Repositories** or **More → Settings → Repositories** (swipe left to remove one)

---

## Migrate from Tachiyomi / Mihon

1. In Mihon: **More → Backup → Create backup** → save the `.tachibk` file
2. In Yomi: **More → Backup → Import from Tachiyomi / Mihon**
3. Select the file — library and read history are imported automatically

---

## Contributing

- Bug reports: [open an issue](https://github.com/PacoDealer/Yomi/issues)
- Feature requests: issues welcome
- Source bugs: check the source website directly first

---

## License

MIT
