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
- GRDB (SQLite, not SwiftData) · JavaScriptCore (JS plugins) · Kingfisher (images) · WKWebView (novel reader) · Unrar.swift (CBR) · PLzmaSDK (CB7/7z, VENDORED in `Vendor/PLzmaSDK` — read its VENDORED.md before updating)
- Keiyoushi: OpenJDK Mobile Zero + patched M-Extension-Server (`Yomi/Features/Keiyoushi/`, `scripts/keiyoushi/`)
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` project-wide — check build settings before claiming an isolation bug

## Docs (read the relevant one, not all of them)
- `Yomi/ROADMAP.md` — session log (newest first), plans, App Store submission checklist (authoritative)
- `Yomi/KNOWN_ISSUES.md` — numbered bug table (#1–#217), open rows listed at its top
- `Yomi/RESEARCH.md` — research; **§22 = direction (S122), §23 = perf audit, §25 = UX evidence + ranked list §25.10, §26 = S138 "calm" design direction**
- `Yomi/ARQUITECTURA.md` — architecture, data flows, DB schema · `Yomi/METODOLOGIA.md` — workflow + per-session lessons
- `Yomi/KEIYOUSHI_POC.md` — on-device Keiyoushi results + gaps · `Yomi/HISTORY.md` — archived sessions + old CLAUDE.md states
- `Yomi/design/` — S79–S95 design system (Space Grotesk/Mono "catalog" look) — **superseded by S138 "calm", RESEARCH §26**

## Current state (S187 — 2026-10-20)
Session-by-session detail: `Yomi/ROADMAP.md`. The S137–S183 version of this block is archived verbatim in `Yomi/HISTORY.md`.
- **S187:** the 18+ switch is age-gated (`Core/AgeGate.swift`, Declared Age Range, entitlement in both files; fallback =
  self-declaration when the service is unavailable). Sim-verified; real system sheet + signing with the new entitlement
  unchecked on the phone. DEBUG `-yomiAgeRange adult|under|declined|unavailable`.
- **S185 (Martin's audit decisions, ROADMAP S185):** Yomi is open source under **MPL-2.0** (`LICENSE` + `NOTICE`);
  scrapers/catalog/plugin build tools live ONLY in the Firebase git (`Firebase/tools/`) and were erased from this
  repo's history — **never commit site plugins here again**. GitHub ruleset blocks force-push/deletion of `main`.
  Migration failure → `DatabaseFailureView` (no more `fatalError`). Kingfisher 8.14 done S188. Next: S188 plan tasks 2–6, extension-writing guide
  (FUNDING.yml done S186).
- **S184 (overnight audit, report `Yomi/AUDIT_S184.md`):** privacy manifests fixed (App Group reason `1C8F.1`, widget +
  `OpenJDKRuntime.framework` manifests, DiskSpace `E174.1`); internal docs + unused Space fonts no longer copied into the
  app (target membership exceptions — **any new .md under `Yomi/` must be excluded too**); 13 Spanish leaks fixed (1028
  keys); DB copied to Application Support/`yomi-before-migration.db` before pending migrations; `scripts/test-all.sh` +
  GitHub Actions `Tests` workflow; issue forms; novel reader CSP (nonce — **new reader scripts need the nonce**,
  inline handlers never run); Library remove = write then reload. Firebase folder now has a LOCAL git repo (no remote).
- **Phone:** personal Release `94cee39` (S183 cache fix); `scripts/build-personal.sh --release` with the phone unlocked
  installs the latest. Real entitlements, CloudKit **Production**; profile expires 2027-10-15. **TestFlight:** build 602
  (`c26c96c`, uploaded S185 — needs encryption answer + Friends group) is the newest uploaded — **never upload without Martin's explicit go for that build**; each upload needs
  the encryption question by hand; needs the LOCAL Apple Distribution cert (cloud signing breaks on the í in "Martín").
- **Martin's rule (S144): no new features until everything works perfectly** (daily use: RTOC + Asura manhwa, WeTried novels).
- **Open (Martin):** S183 phone check-list (ROADMAP S183), trackers (AniList client id), two-device sync test, tip jar
  (Paid Apps Agreement), App Store listing/screenshots (`Yomi/APP_STORE_LISTING.md`), Sponsors + Ko-fi accounts.
- **Translate is OFF** (`NovelTranslation.isAvailable = false`, backlog ROADMAP S182).

### Rules that come from past sessions
- **Spanish (S180):** `Yomi/Localizable.xcstrings` is GENERATED — build, then `python3 scripts/localization/build-catalog.py`
  (reads `.stringsdata` + `es-*.json`, `plurals.json`, `dynamic.json`). Literals in `Text`/`Button`/`Label` or a
  `LocalizedStringKey` param are extracted; text built as `String` (incl. `var x: String` shown later, `case .a: "…"`)
  needs `String(localized:)`; plurals = English plural + a `plurals.json` row; shared components take
  `LocalizedStringKey`. Leaks: `scripts/localization/find-unlocalized.py`. Test with `-AppleLanguages (es)`.
- **Safe Mode (S179):** any new title list filters with `SafeMode.filter.allows` (capture the Sendable `SafeFilter` before detaching).
- **Motion (S178):** `withMotion`, `.motion`, `Motion.slide/pop` — never bare `withAnimation`.
- **Reader pages:** load through `PageNames.source(url)` (Keiyoushi pages keyed `chapterId#index`; bridge URLs change
  every launch), never `KFImage(url)`. Pages > 4096 px tall are drawn as strips or they render BLACK (#190). Keiyoushi
  bridge returns on a NEW port after background (`KeiyoushiBridge.pointAtLivePort`, `PageRetry`).
- **Reading state:** ONE Continue rule — `ResumeReading.chapter(in:)`. Chapter numbers parsed by `Core/ChapterRecognition.swift`
  (Mihon port); Yomi assumes ascending order everywhere. `scrollPosition(id:)` ignores code-driven scrolling (`StripScroller.isDriving`).
- **Design = "calm" (RESEARCH §26):** SF Pro, system neutrals, colour from covers, one accent, **no list separators**,
  `CalmList` + `Section(calm:)`, delete = swipe → red trash. Theme `canvas` Automatic/Ink/Midnight/Paper/Sepia.
- **Extensions:** fresh installs have NO repositories and Yomi suggests none (5.2.2); the 18+ switch lives ONLY in
  `RepositoriesView` (off by default, `AdultExtensionsToggle` — turning it on goes through `AgeGate`). Any number of Mihon repositories (`index.pb` / `index.min.json`).
- **Backup screen:** ONE Import (json/.tachibk/.tmb) + ONE Export menu — never two `.fileImporter`s on a view.
- **Licences:** `LicensesView` texts from `scripts/build-licenses.sh` (re-run after dependency changes). `PageBorders.swift`
  is MPL-2.0 — if the repo ever goes private, host it publicly first. Mihon ports are Apache-2.0 (ChapterRecognition,
  FetchInterval, PageAnalysis parts, TallPageSplitter rule). CB7 = PLzmaSDK **vendored** (`Vendor/PLzmaSDK/VENDORED.md`);
  CBR = Unrar.swift (parses untrusted files — keep it updated).
- **Trackers** without a client id are hidden (`MangaTracker.isConfigured`; only MAL is set).
- **App is iPhone-only** (`TARGETED_DEVICE_FAMILY = 1`).
- **Perf gates:** `scripts/perf-gates.sh` (`--device <id>` needs the phone unlocked; it REPLACES Martin's install →
  reinstall with `build-personal.sh --release`). UI tests: ReaderUITests 13/13 + PerfUITests 3/3 (#193/#196 were the App Store rating sheet — fixed S188).
- Device-data repro: copy the phone's `Documents` (devicectl) + prefs into the sim container — METODOLOGIA S141.
- Simulator in the desktop app stays dark at system level (simctl appearance doesn't take) — check light on device.
- Build into `~/Library/Developer/Xcode/DerivedData/…` — `iOS/build/` on the Desktop fails CodeSign (xattrs).
- Next GRDB migration prefix: **`v31_`** (v30 = `term_replacement`, S177).

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
scripts/build-personal.sh --release   # Martin's iPhone (paid team, real entitlements, CloudKit Production)
```

## Key paths
```
Yomi/AppSettings.swift                    # @Observable UserDefaults singleton (shared with YomiWidget)
Yomi/Core/DesignTokens.swift, CanvasEnvironment.swift   # tokens, \.yomiCanvas
Yomi/Database/DatabaseManager.swift       # migrations (next v31_)
Yomi/Database/Queries/*.swift             # all DB access
Yomi/Features/Extensions/JSBridge.swift   # JavaScriptCore runtime, cheerio bundle (Resources/yomi-js-libs.js)
Yomi/Features/Extensions/ExtensionManager.swift, PluginCatalogService.swift
Yomi/Features/Keiyoushi/                  # JVM host, repository (index.pb), bridge, browse
Yomi/Features/More/PluginsView.swift      # Browse → Extensions tab + RepositoriesView, AddRepoSheet
Yomi/Features/Browse/BrowseView.swift     # Sources · Extensions · Migrate
Yomi/Features/Reader/NovelReaderWeb.swift, ReaderFonts.swift, ChapterReaderView.swift (+ ReaderPagedViews/ReaderScrollViews/ReaderOverlayView)
Yomi/Features/Browse/NovelDetailView.swift, Yomi/Features/Library/MangaDetailView.swift
scripts/build-js-libs.mjs, build-reader-fonts.sh, keiyoushi/, perf/
```

## Plugins on Firebase
Built plugins live in `~/Desktop/Projects/Yomi/Firebase/public/`, TypeScript sources + `build-plugins.mjs` +
`catalog-hashes.py` in `Firebase/tools/` (S185) — a LOCAL git repo (no remote), never in the public iOS repo: commit
there after every plugin or site change.
Deploy: `cd ~/Desktop/Projects/Yomi/Firebase && firebase deploy --only hosting:plugins` (S154: second target `site` = support/privacy pages in `site/`, host `yomi-reader`).

## Session close
1. Update ROADMAP.md (session entry) + METODOLOGIA.md (lessons) + ARQUITECTURA.md (if structure changed);
   update "Current state" above **by replacing it**, never by appending a new "Prior state" block.
2. `git add -A && git commit && git push` — every session, no exceptions.
3. Changed JS plugins → copy to Firebase `public/` and deploy.
