# Yomi — iOS Manga & Novel Reader

A clean, fast manga, manhwa, manhua and light novel reader for iOS. Plugin-based architecture — community repos provide hundreds of sources, and Yomi never touches your traffic.

---

## Quick Start

1. Download **Yomi** from the App Store
2. Go to the **Plugins** tab → tap **+** → **Add Repository**
3. Add a repo URL from the table below, then install a plugin from the catalog

Done. Open **Browse**, pick a source, and start reading.

---

## Plugin Repositories

| Repository | Content | URL |
|---|---|---|
| **Yomi Catalog** | Manga + novels *(pre-installed)* | `https://yomi-plugins.web.app/index.json` |
| **LNReader Novels** | 500+ novel sources, 18 languages | `https://raw.githubusercontent.com/LNReader/lnreader-plugins/master/dist/plugins.min.json` |

> More repositories coming soon. Open an issue to suggest one.

---

## How to Add a Repository

1. Open the **Plugins** tab in Yomi
2. Tap **+** in the top-right corner
3. Tap **Add Repository**
4. Paste a URL from the table above (or tap **Add** next to a featured repo)
5. Tap **Add** — the catalog refreshes automatically
6. Find a plugin in the catalog and tap **Install**
7. Go to **Browse** → your new source appears there

---

## What are Plugins?

Plugins are small JavaScript files that teach Yomi how to browse and read from a specific website. They run entirely **on your device** — Yomi never proxies your requests or stores your credentials.

Adding a repository subscribes you to a plugin catalog (a JSON index file). You can add, remove, or update individual plugins at any time from the Plugins tab.

---

## Suwayomi (Advanced)

Connect Yomi to a self-hosted [Suwayomi Server](https://github.com/Suwayomi/Suwayomi-Server) to access 1000+ Mihon/Keiyoushi sources without any extra plugins.

1. Run Suwayomi Server on your Mac or a home server
2. In Yomi → **Settings** → **Suwayomi Server**, enter your server URL (e.g. `http://192.168.1.x:4567`)
3. Your Suwayomi sources appear in **Browse**

---

## Tachiyomi / Mihon Import

Migrate your existing library in seconds:

1. In Mihon, go to **More → Backup → Create backup** and save the `.tachibk` file
2. In Yomi → **More → Backup → Import from Tachiyomi / Mihon**
3. Select the `.tachibk` file — your library and read history are imported automatically

---

## Contributing

- Bug reports: [open an issue](https://github.com/PacoDealer/Yomi/issues)
- Plugin issues: check the source website first — plugins can't fix broken sites
- Feature requests: issues welcome

---

## License

MIT
