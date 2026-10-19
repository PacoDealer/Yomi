# Yomi — iOS Manga & Novel Reader

A clean, fast manga, manhwa, manhua and light novel reader for iOS. It reads your own files (CBZ, CBR, CB7, ZIP, EPUB) and can be extended with repositories you add by link.

---

## Getting Started

Yomi is a reader. It comes with **no sources and no content**. You can read your own files, or add **repositories**
(lists of extensions published by other projects) by pasting their link.

### Read your own files
**Browse → On This iPhone → Local Files** — import CBZ, CBR, CB7, ZIP or EPUB files, or link a folder from the Files app.

### Add a repository
1. Copy a repository link from the project that publishes it
2. In Yomi: **Browse → Extensions → Add Repository** (or **⋯ → Add Repository**) — paste the link → **Add**
3. Every extension in that repository appears under **Available** — tap **Add** on the ones you want
4. Open **Browse → Sources** and pick a source
5. Updates show up under **Updates**; swipe left on an extension to delete it
6. Manage repositories in **⋯ → Repositories** or **More → Settings → Repositories** (swipe left to remove one)

### Repository formats Yomi reads

- **Yomi** JSON catalogs (`index.json` listing JavaScript plugins)
- **LNReader** plugin lists (light novels)
- **Mihon / Tachiyomi** extension repositories (`index.min.json` / `index.pb`) — the extensions run on the phone

Repositories are run by their own projects and are not part of Yomi. You are responsible for the repositories you add
and for using sources you are allowed to use.

---

## Migrate from Mihon, Tachiyomi or Tachimanga

1. In Mihon / Tachiyomi: **More → Backup → Create backup** (a `.tachibk` file). In Tachimanga: export a `.tmb` backup.
2. In Yomi: **More → Backup → Import Backup** and pick the file
3. Library, categories, read history and repositories are merged in — nothing already in Yomi is replaced

---

## Contributing

- Bug reports: [open an issue](https://github.com/PacoDealer/Yomi/issues)
- Feature requests: issues welcome
- Source bugs: check the source website directly first

---

## License

Yomi is open source under the [Mozilla Public License 2.0](LICENSE): you can use, study and build on it, including
in your own projects; changes to Yomi's own files stay open under the same licence. Some parts keep their own
licences — see [NOTICE](NOTICE).
