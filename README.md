# Yomi — iOS Manga & Novel Reader

A clean, fast manga, manhwa, manhua and light novel reader for iOS. It reads your own files (CBZ, ZIP, EPUB) and can be extended with repositories you add by link.

---

## Getting Started

Yomi is a reader. It comes with **no sources and no content**. You can read your own files, or add **repositories**
(lists of extensions published by other projects) by pasting their link.

### Read your own files
**Browse → On This iPhone → Local Files** — import CBZ, ZIP or EPUB files, or link a folder from the Files app.

### Add a repository
1. Copy a repository link (see the list below, or the project that publishes it)
2. In Yomi: **Browse → Extensions → Add Repository** (or **⋯ → Add Repository**) — paste the link → **Add**
3. Every extension in that repository appears under **Available** — tap **Add** on the ones you want
4. Open **Browse → Sources** and pick a source
5. Updates show up under **Updates**; swipe left on an extension to delete it
6. Manage repositories in **⋯ → Repositories** or **More → Settings → Repositories** (swipe left to remove one)

### Repositories that work with Yomi

Yomi reads three repository formats. These are the public ones it is tested with — they are run by their own
projects (the first one by this project), not shipped inside the app. You are responsible for the repositories you
add and for using sources you are allowed to use.

| Repository | What it has | Link to paste |
|---|---|---|
| Yomi Catalog | A small set of manga + novel plugins | `https://yomi-plugins.web.app/index.json` |
| LNReader plugins | Light novel sources, many languages | `https://raw.githubusercontent.com/LNReader/lnreader-plugins/plugins/v3.0.0/.dist/plugins.min.json` |
| Keiyoushi | Mihon-format manga extensions (they run on the phone) | `https://github.com/keiyoushi/extensions/raw/repo/index.pb` |

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

All rights reserved — see [LICENSE](LICENSE). The code is public to be read, not reused.
