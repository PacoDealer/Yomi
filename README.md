# Yomi — iOS Manga & Novel Reader

A clean, fast manga, manhwa, manhua and light novel reader for iOS. Extensible architecture — community source repositories provide hundreds of reading sources.

---

## Quick Start

1. Open **Yomi** on your device
2. Go to **Browse** → **Extensions** → tap **+** → **Add Repository**
3. Add a repository from the table below, install a source, then open **Browse → Sources**

---

## Source Repositories

Three choices depending on what you want to read:

| | **Yomi Catalog** | **LNReader Novels** | **Keiyoushi** |
|---|---|---|---|
| **Content** | Curated manga + novels | 500+ light novel sources | 1000+ manga sources |
| **Languages** | EN | 18+ languages | All |
| **Setup** | URL pre-configured | Add URL below | Add address below |

### Yomi Catalog — URL pre-configured
Hand-picked, high-quality sources for manga and novels. The catalog URL is added by default — just open Browse → Extensions and install.

### LNReader Novels
```
https://raw.githubusercontent.com/LNReader/lnreader-plugins/plugins/v3.0.0/.dist/plugins.min.json
```
Copy this URL → Browse → Extensions → **+** → **Add Repository** → paste → **Add**

### Keiyoushi (1000+ manga)
Keiyoushi extensions run through a [Suwayomi Server](https://github.com/Suwayomi/Suwayomi-Server) — Yomi runs a shared one so you don't have to host your own:
```
https://TODO-fill-in-after-deploying.example
```
<!-- TODO: replace with the real Cloudflare Tunnel public hostname from SuwayomiServer-Deploy/DEPLOY.md Step 1/7 before publishing this README. -->
Copy this address → Yomi → **Settings → Sources & Servers → Suwayomi Server** → paste → **Test Connection**

Prefer full control (or the shared server is down)? [Self-host your own](https://github.com/Suwayomi/Suwayomi-Server#getting-started) and paste its address instead — same field.

---

## How to Add a Repository

1. Open **Browse** → **Extensions**
2. Tap **+** → **Add Repository**
3. Tap **Add** next to a featured repo — or paste a custom URL and tap **Add**
4. The catalog refreshes automatically
5. Find a source in the list and tap **Install**
6. Go to **Browse → Sources** → your new source appears in the list

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
