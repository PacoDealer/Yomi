# Yomi — Claude Code Project Context

iOS manga/manhwa/manhua + light novel reader. Sources come from repositories the user adds by URL:
Yomi's own JS plugin catalog (Firebase, `https://yomi-plugins.web.app/index.json`), LNReader JS
plugins, and Keiyoushi (Mihon) extensions run **on the phone** in an embedded OpenJDK Zero JVM.
App binary ships zero plugin files (App Store compliance). Repo: `PacoDealer/Yomi`, path
`~/Desktop/Projects/Yomi/iOS`. Martin reads light novels in Yomi daily (WeTried plugin).

> **Keep this file under ~200 lines** (Anthropic guidance: longer files are followed less reliably).
> Session narratives go in `Yomi/ROADMAP.md`, bugs in `Yomi/KNOWN_ISSUES.md`, lessons in
> `Yomi/METODOLOGIA.md`. Rules that only apply to some files go in `.claude/rules/` (path-scoped).

## Tech stack
- Swift + SwiftUI, **iOS 26.2 deployment target — no older-iOS fallbacks, ever**
- GRDB (SQLite, not SwiftData) · JavaScriptCore (JS plugins) · Kingfisher (images) · WKWebView (novel reader) · Unrar.swift (CBR)
- Keiyoushi: OpenJDK Mobile Zero + patched M-Extension-Server (`Yomi/Features/Keiyoushi/`, `scripts/keiyoushi/`)
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` project-wide — check build settings before claiming an isolation bug

## Docs (read the relevant one, not all of them)
- `Yomi/ROADMAP.md` — session log (newest first), plans, App Store submission checklist (authoritative)
- `Yomi/KNOWN_ISSUES.md` — numbered bug table (#1–#211), open rows listed at its top
- `Yomi/RESEARCH.md` — research; **§22 = direction (S122), §23 = perf audit, §25 = UX evidence + ranked list §25.10, §26 = S138 "calm" design direction**
- `Yomi/ARQUITECTURA.md` — architecture, data flows, DB schema · `Yomi/METODOLOGIA.md` — workflow + per-session lessons
- `Yomi/KEIYOUSHI_POC.md` — on-device Keiyoushi results + gaps · `Yomi/HISTORY.md` — archived sessions + old CLAUDE.md states
- `Yomi/design/` — S79–S95 design system (Space Grotesk/Mono "catalog" look) — **superseded by S138 "calm", RESEARCH §26**

## Current state (S170 — 2026-10-15)
- **S170 (docs only):** catch-up audit — all of A–F is in code, tests pass; dropped promises → new group L. Decided:
  keep the MPL port + add licences rows (repo is public — keep it so, or host MPL files elsewhere first); CloudKit
  schema deploy right before the next upload; hide trackers with empty client ids. NEXT: K → H → G → L (ROADMAP S170).
- **S169 (sim):** F17 — crop borders (`cropBorders` paged, `cropBordersStrip` strip+continuous; `PageBorders.swift` =
  **MPL-2.0 port**, kept — ROADMAP S170), two-page spreads via `PageSpreads` (cover alone option,
  wide pages alone, shapes must match; `PageShapes` observable + `PageShapes.learn`), reader background
  `readerBackground` Black/Dark grey/White/Automatic (`ReaderPageLook.swift`; Automatic reads the SCREEN's light/dark,
  the reader forces dark). Tests `scripts/reader-page-tests/run.sh` 26/26. NEXT: G (ROADMAP S169).
- **S168 (sim):** F16 reader gestures (`ReaderPageActions.swift`): tap zones per mode, strip long press, page menu.
  **#211 fixed** (long-strip counter stuck since S164) — **Martin's phone (`98af933`) still has it.**
  `scrollPosition(id:)` ignores code-driven scrolling — see `StripScroller.isDriving`.
- **S167 (sim):** E15 hidden scanlation groups (`excluded_scanlator`, `MangaDetailView.readingList` + SQL
  `ChapterQueries.notExcluded`), duplicate warning on add, chapter bookmarks (`setBookmarked` only). v28. **New
  CloudKit fields need the Production schema before the next TestFlight build** (ROADMAP S167).
- **S166:** smart updates = Mihon v0.21 FetchInterval port (`Core/FetchInterval.swift`, tests 54/54); v27 schedule
  columns (`UpdateScheduleQueries`); "Titles not due yet" ON by default. Refresh = one stream per source. DEVICE-verified.
- **S165:** ChapterRecognition v2 = Mihon v0.21 port (volumes, parts → letters, shared numbers, neighbour fill),
  Mihon's tests ported: `scripts/chapter-recognition-tests/run.sh` (103/103). Keiyoushi lists parsed as a whole
  (`KeiyoushiMapping.chapters`); refresh rewrites changed numbers.
- **S164:** page-list cache (sim only): reopening a chapter that isn't downloaded skips `fetchPages`
  (`Features/Reader/PageListCache.swift`, Caches JSON, 7 days; reader calls `readerPages`). A cached page's first failure
  refetches the list once (`PageRetry.pageFailed`). Bridge-proxied `127.0.0.1/image/<id>` lists never cached. DEBUG
  `-yomiStalePageList`.
- **S162–S163** (sim only): robust downloads (retries, resume, Pause/Resume, low-storage pause, Failed + Retry All);
  tall pages split into HEIC parts (`TallPageSplitter.swift`), `lastPageRead` in SOURCE pages. S161 = ROADMAP "THE PLAN" A–K.
- **S160:** long-strip memory fixed (#209, sim-measured: 20 tall pages 908→1,964 MB before, flat ~775 MB after) —
  `StripPageImage` releases pages off screen and draws strips into owned bitmaps; Kingfisher memory cap 256 MB.
  #208 (Aqua/Madara) PARKED: Aqua's site is down, only Madara source in his library. Not on the phone yet.
- S159: Keiyoushi pages load natively (Asura chapter 22.9 → 1.5 s, device probe; `research_notes/…/S159_measurements.md`).
  S128–S136 perf batch: hang-free on Martin's iPhone 17 (RESEARCH §23.6).
- Novel reader: one persistent WKWebView + JS controller (`Features/Reader/NovelReaderWeb.swift`), infinite
  scroll, swipe, typography pass (`ReaderFonts.swift`), Pages mode, Text · Look · Reading panel tabs.
- **Design = "calm", Apple Music-inspired (RESEARCH §26):** SF Pro everywhere, system neutrals, colour from
  covers, one accent, nothing on covers, plain `Notation`, **no list separators** (Martin S141). Every main
  screen is calm now, incl. every More sub-screen (S146). Settings-style lists use `CalmList` +
  `Section(calm:)` (Core/CanvasEnvironment.swift). Delete everywhere = swipe → red trash.
- **Theme:** `canvas` "Automatic" (follows iPhone light/dark, default for fresh installs) / Ink / Midnight /
  Paper / Sepia; palette resolved in ContentView via `canvasColors(for: colorScheme)`. Time/Date follow the
  iPhone unless chosen.
- **Extensions:** no repositories on a fresh install, none suggested; one tap "Add"; delete = swipe. **Any
  number of Mihon repositories** (`mihonRepoURLs`, `KeiyoushiRepository.repos`), `index.pb` or
  `index.min.json`, folder links accepted (S142). Catalog ↔ installed matching: `PluginCatalogEntry.installIds`.
- **Downloads:** Keiyoushi/Suwayomi manga download too (`DownloadManager.canDownload`; Keiyoushi needs Yomi open).
- **Updates:** refresh checks JS + Keiyoushi titles (per-source streams: 5 plugin / 3 Keiyoushi at once), progress row, Updates Summary
  (Failed/Completed, Retry). Background refresh skips Keiyoushi. One row per chapter found (`fetchedAt`, v23).
- **Reading state:** only reading counts toward History/Continue. ONE Continue rule for every screen:
  `ResumeReading.chapter(in:)` (ContinueReadingRow.swift) = after the end of the RUN of read chapters (S144).
- **Chapter numbers:** sources without one (Keiyoushi -1, e.g. Asura) are parsed from the name —
  `Core/ChapterRecognition.swift` (Mihon v0.21 port, list-aware since S165); v24 filled old rows. Yomi assumes ascending order everywhere.
- **Keiyoushi pages:** bridge returns on a NEW port after background; `KeiyoushiBridge.pointAtLivePort` rewrites
  page requests, `resumeIfPaused` on foreground, reader pages retry (`PageRetry`). Pages > 4096 px tall
  (Asura = 900×16000) are drawn as strips or they render BLACK (S145, #190). DEBUG probe:
  `-keiyoushiPageProbe [-keiyoushiPageProbeTitle x] [-keiyoushiPageProbePause]` (device; args after `--`).
- **Read-aloud (S143):** app-wide `ListenPlayer` (`Features/Reader/ListenPlayer.swift`, views in
  `ListenPlayerViews.swift`) — Swift owns the sentences, the reader only highlights/follows; keeps playing outside
  the reader (tab bar accessory). Lock screen/background untested on device. Settings → Novels → Listening (S144).
- **Martin's rule (S144): no new features until everything works perfectly** (daily use: RTOC + Asura manhwa).
  S144–S145 fixed his field report (KNOWN_ISSUES 181–190, all device-checked); device perf S145: 0 hangs (novel detail, Browse).
  S147 (DEVICE-verified with Martin's 148-title Tachimanga export): `.tachibk` import → working Keiyoushi titles (same ids/paths as the bridge, memo, categories,
  history, repos), import sheet, "Source missing" + Migrate (now searches Keiyoushi), calm first-run screen.
  Keiyoushi indexes refresh when > 6 h old (#192). v25 removed dead pre-S147 import rows.
  S148: **Migrate by source** (Browse → Migrate = sources → titles → ordered targets → review → migrate; old entry
  only leaves the Library; Mihon read rule; real read dates kept — `MassMigration.swift`, `MigrationService`).
  **Local files** (`Features/Local/`): Browse → On This iPhone → Local Files; Import (→ `Documents/Local`) + a
  linked Files folder (bookmark — Documents is NOT exposed, it holds yomi.db); CBZ/ZIP/image folders = manga,
  EPUB = novel (`EpubBook`, `NovelContent.html` for all novel content); own ZIP reader `Core/ZipArchive.swift`;
  "Open in Yomi" for .cbz/.epub. CBR/RAR added S156. Part C sim-verified only.
  Migration device-verified (AllManga → MangaFire, DB compared). NEXT: Martin's manga reader report KNOWN_ISSUES #197–#200
  (paged chapter swipe, continuous starts at end, continuous over-zoom, pinch-zoom dead) → part C device check → publishing path (ROADMAP S148).
  New backlog: per-extension Settings screen (Mihon source preferences; e.g. Asura "Hide premium chapters").
  Backlog: pinch-zoom in vertical (webtoon) mode (S145).
  Backlog: genre chips on NOVELS (LNReader `genres` dropped by `SourceNovel`; manga have them — S145).
  Backlog added S142: Dynamic Type, auto backups, lockable SFW mode, reader auto-dark at night, separate tap
  zones per manga mode, Spanish (ROADMAP S142). Aidoku/Paperback: answered S143 (possible, not now).
- Open gaps: Keiyoushi page list ~4.5 s warm (JVM work, S159); no CBR/RAR; NewPipe-free extension-server jar staged + on phone since S150, Keiyoushi device check pending; notification prompt on a fresh install not yet observed on device.
- S149–S150: manga reader slide/swipe/zoom everywhere; Migrate = sources (with icons) → titles → carry-over options →
  **every installed manga source searched, most chapters suggested, no Skip** (row tap = manual search) → Copy / Migrate.
  Source icons: gradient+initials only as fallback (`SourceIconBadge`, `isMihonIcon`). No novel migration exists.
  Publishing: Developer Program ACTIVE 2026-10-11; repo = all rights reserved (`LICENSE`). S151: licence notices
  screen (`LicensesView.swift`, texts from `scripts/build-licenses.sh` — re-run after dependency changes; #202 closed);
  `scripts/build-testflight.sh` (Config/TestFlight.xcconfig, paid team `F9R33MN82P`) → **build 1.0 (493) uploaded
  2026-10-11**. Needs the LOCAL Apple Distribution cert in the keychain (cloud signing breaks on the í in "Martín").
  S152: build 493 on TestFlight (Internal group, Martin installed it); **CloudKit schema in Production**; #170 app
  changes (no link from the app to any repository list — in-app `RepositoryHelpView`; Report a Bug = mail to
  yomiappreader@gmail.com); **build 504 submitted to Beta App Review 2026-10-12** (external group "Friends", public
  link in ROADMAP S152). Each upload needs the encryption question answered by hand (standard algorithms, France No).
  S153: sync fixes #204 (refused changes stay visible + retried) and #205 (received records keep their change tag —
  504 lacks this; **build 508 uploaded** with both, add it to Friends once 504 is approved), both run against CloudKit in the simulator.
  S154: App Store listing DRAFTED in `Yomi/APP_STORE_LISTING.md` (waiting for Martin's approval; nothing entered in
  App Store Connect) + `Firebase/public/support.html` (not deployed). The 18+ switch now lives ONLY in
  `RepositoriesView` (off by default; Martin's decision — don't add it back to Extensions or Settings → Privacy).
  **App is iPhone-only** (`TARGETED_DEVICE_FAMILY = 1`); iPad comes as a later update. Open decisions in the listing
  doc §4.
  S155: **build 515 on TestFlight, in Friends; a friend imported his Tachimanga .tmb with it.** Tachimanga `.tmb`
  import (`TachiyomiBackupParser.parseTachimanga`; `ZipArchive` reads per-entry ZIP64). After 515, pushed but in NO
  build: Backup screen = ONE Import (json/.tachibk/.tmb, `importAnyBackup`) + ONE Export menu (Martin's design —
  don't split them again; never two `.fileImporter`s on a view); iCloud backup fix (`CloudDocuments` entitlement —
  unproven until on a phone). **Never upload to TestFlight without Martin's explicit go for that build.**
  S156 (simulator only, in NO build): Library reloads when the first-run screen closes; novel genres from the
  source (`JSBridge.novelGenres`; WeTried + NovelFire plugins deployed; CloudKit
  Production `Novel.genres` UNVERIFIED — settled at the pre-upload schema deploy, ROADMAP S170); daily on-device backup (`saveLocalBackupIfDue`,
  More → Backup → On This iPhone); `YomiTokens.Font` helpers follow Dynamic Type (cap 1.5×). **CBR/RAR**
  via `Core/ComicArchive.swift` + Swift package Unrar.swift (RARLAB UnRAR; licence text in `licence-unrar.txt` —
  keep the package updated, it parses untrusted files; a new picker file type needs an Info.plist UTType).
  S157 (in NO build): **source filters** for Keiyoushi sources (`KeiyoushiFilter.swift`, `KeiyoushiFilterSheet`,
  filter button in `KeiyoushiBrowseView`; Mac-server + sample-data verified, real screen unseen on a device); #207 =
  filters an extension fetches from its site (Asura genres) don't load (zstd JNI). Parity list: `TACHIMANGA_PARITY.md`.
  Open: #206 double back button from Library search, per-extension settings screen unseen on a device
  (built + Mac-verified; `KeiyoushiSourceSettingsView`), solid/huge CBR. NEXT in ROADMAP S156.
- Phone has the S166 Release build `98af933` (paid team): profile expires **2027-10-15**. `scripts/build-personal.sh` still uses the empty entitlements (no iCloud/widget data).
- Device-data repro: copy the phone's `Documents` (devicectl) + prefs into the sim container — METODOLOGIA S141.
- Simulator in the desktop app stays dark at system level (simctl appearance doesn't take) — check light on device.
- Build into `~/Library/Developer/Xcode/DerivedData/…` — `iOS/build/` on the Desktop fails CodeSign (xattrs).
- Next GRDB migration prefix: **`v29_`** (v28 = hidden groups + bookmarks, S167). UI tests 13/13 (S148; #193 and #196 are flaky — re-run alone).

## Fresh clone
`Yomi/Config/AppSecrets.swift` is gitignored — copy `AppSecrets.swift.template` next to it and fill in
values (MAL required to compile; AniList/Shikimori/Bangumi may stay empty).

## ABSOLUTE RULES
### Concurrency (Swift 6)
- All `*Queries` methods `nonisolated`. `appDatabase` is `nonisolated(unsafe) var` — never wrap in an actor.
- JSBridge calls only off MainActor (`SOURCE.fetch` blocks on a semaphore); main-actor callers use
  `await loadBridge(for:)`; deliver results with `await MainActor.run { … }`.
- Never read `AppSettings.shared` inside `Task.detached` — capture values first.
- `ExtensionManager.shared` is MainActor — capture what you need before detaching.

### Editing
- Read a file before editing it. When replacing a whole file, diff what the new one omits.
- Grep all call sites before removing/renaming a symbol; after changing a signature, grep stale call
  sites before suspecting the toolchain (S115).
- Read a doc section before updating it — never update docs from memory.
- Compile before touching a third unrelated file. Read the full compiler error before fixing.
- Don't create files that aren't strictly required.

### iOS 26 / SwiftUI
- `Tab("title", systemImage:) {}` (`.tabItem` renders nothing). `Text + Text` deprecated — interpolate.
- `.tint()`/`.preferredColorScheme()` on `ContentView()`, not the Scene. `@Observable` singletons in App need `@State`.
- `.glassEffect(.regular, in: Shape)` on content, not the parameterless form in a background.
- A `Group` whose branches can all be false drops its modifiers (`.task` never runs — #163).
- Images: `KFImage` (never `AsyncImage`); covers via `.coverSized()`, reader pages via `.readerPage()`.

### Verification
- "Done" means verified: build with zero warnings (rebuild **YomiWidget** too when `AppSettings.swift`
  or other shared files change), run UI tests (`YomiUITests`) when touching readers, check the screen.
- Say plainly what was verified on device vs simulator vs compile-only.
- Research: never say "impossible" before asking what bridge/server/competitor already solves it, and
  check live sources (WebSearch, apple-docs, context7) — not training data — for APIs and guidelines.
- Never test with MangaDex — use Asura Scans / MangaFire (manga) and WeTried / NovelFire (novels).

## Tools
- **XcodeBuildMCP**: call `session_show_defaults` before the first build. Enabled workflows: simulator,
  simulator-management, **ui-automation** (`snapshot_ui`, `tap`, `swipe`, `type_text` — prefer these over
  mobile-mcp, whose taps/swipes are flaky, see `.claude/skills/yomi-sim/`), device, debugging, coverage.
- **xcode** (Apple, `xcrun mcpbridge`, needs Xcode open with the project): `RenderPreview` for SwiftUI
  previews (fast design iteration without tapping), live diagnostics, `DocumentationSearch`.
- **apple-docs**, **context7** (GRDB, Kingfisher, any library) — always for API questions.
- Simulator: iPhone 17 Pro **iOS 26.3**, UDID `F31CC190-186D-4598-9ED8-225821907550` (the 26.0 one
  can't install). Device: "iPhone de Martin (2)" `270B9EDA-7298-5206-9E67-71C0E8F60CF6` (must be unlocked).
- Perf on device: `scripts/perf/record.sh` — see RESEARCH §23.6 / project memory for the tunnel recipe.

## Build
```bash
xcodebuild -scheme Yomi -destination 'platform=iOS Simulator,id=F31CC190-186D-4598-9ED8-225821907550' build
scripts/build-personal.sh --release   # Martin's iPhone (free team; read the printed profile expiry)
```

## Key paths
```
Yomi/AppSettings.swift                    # @Observable UserDefaults singleton (shared with YomiWidget)
Yomi/Core/DesignTokens.swift, CanvasEnvironment.swift   # tokens, \.yomiCanvas
Yomi/Database/DatabaseManager.swift       # migrations (next v29_)
Yomi/Database/Queries/*.swift             # all DB access
Yomi/Features/Extensions/JSBridge.swift   # JavaScriptCore runtime, cheerio bundle (Resources/yomi-js-libs.js)
Yomi/Features/Extensions/ExtensionManager.swift, PluginCatalogService.swift
Yomi/Features/Keiyoushi/                  # JVM host, repository (index.pb), bridge, browse
Yomi/Features/More/PluginsView.swift      # Browse → Extensions tab + RepositoriesView, AddRepoSheet
Yomi/Features/Browse/BrowseView.swift     # Sources · Extensions · Migrate
Yomi/Features/Reader/NovelReaderWeb.swift, ReaderFonts.swift, ChapterReaderView.swift
Yomi/Features/Browse/NovelDetailView.swift, Yomi/Features/Library/MangaDetailView.swift
scripts/build-js-libs.mjs, build-reader-fonts.sh, keiyoushi/, perf/
```

## Plugins on Firebase
Plugin sources live only in `~/Desktop/Projects/Yomi/Firebase/public/` (not git).
Deploy: `cd ~/Desktop/Projects/Yomi/Firebase && firebase deploy --only hosting:plugins` (S154: second target `site` = support/privacy pages in `site/`, host `yomi-reader`).

## Session close
1. Update ROADMAP.md (session entry) + METODOLOGIA.md (lessons) + ARQUITECTURA.md (if structure changed);
   update "Current state" above **by replacing it**, never by appending a new "Prior state" block.
2. `git add -A && git commit && git push` — every session, no exceptions.
3. Changed JS plugins → copy to Firebase `public/` and deploy.
