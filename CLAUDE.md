# Yomi — Claude Code Project Context

## What this app is
iOS manga, manhwa, manhua, and light novel reader. Plugin-based architecture:
JS plugins run in JavaScriptCore. Two plugin formats: Format A (manga) and Format B (LNReader/novels).
Firebase CDN hosts all 15 production plugins. App binary ships zero plugin files (App Store compliance).

## Tech stack
- **Swift + SwiftUI — iOS 26.2 deployment target. No iOS 18 fallbacks. Ever.**
- GRDB for SQLite (NOT SwiftData)
- JavaScriptCore for plugin execution
- Firebase Hosting: https://yomi-plugins.web.app

## Project path
`/Users/martingamberg/Desktop/Projects/Yomi/iOS`

## Key docs (read these at session start)
- `Yomi/ROADMAP.md` — current state, planned work, tech debt
- `Yomi/ARQUITECTURA.md` — full architecture, data flows, DB schema
- `Yomi/METODOLOGIA.md` — workflow rules, tech learnings per session
- `Yomi/RESEARCH.md` — master research doc (competitive, UX, App Store, iOS 26, plugins, architecture)
- `Yomi/design/DESIGN_HANDOFF.md` — **design track handoff + roadmap to launch (start here for design/publish work)**
- `Yomi/design/DESIGN_SYSTEM.md` — the justified design system (concept, color/theming, type, components, screens)
- `Yomi/design/DESIGN_RESEARCH.md` — design/UX/competitive research behind the system
- `Yomi/design/design_handoff_yomi/YOMI Screens.dc.html` — **full 16-screen design spec** (primary implementation reference; HTML + inline CSS; all canvas/reader theme colors, screentone patterns, Liquid Glass overlays)

## Design track (S82-S95 — all 12 blocks complete)

All 16 screens designed and confirmed. Concept: **"reading instrument / living archive"** — warm editorial canvas, covers + user accent are the only color, monospace catalog notation, ink/screentone signature. Confirmed: default accent **Vermilion `#E5473A`**, default canvas **Ink (`#14110F`)**, Space Grotesk (UI) + Space Mono (notation), Newsreader serif (novel body). Design tokens live in `DesignTokens.swift`; canvas colors are wired app-wide via `\.yomiCanvas` environment (`CanvasEnvironment.swift`, set from `AppSettings.canvasColors`); notation helpers in `Notation.swift`; Appearance Studio in `AppearanceStudioView.swift`. **Full design spec**: `Yomi/design/design_handoff_yomi/YOMI Screens.dc.html` — 16 screens as HTML with inline CSS. App icon assets: `AppIcon-Ink.png` + `AppIcon-Paper.png` in `Yomi/design/design_handoff_yomi/assets/`. **All 12 blocks complete as of S95 (2026-08-05).** Blocks 1-5 screenshot-verified S85; Block 6 (Browse) S86; Block 7 (History) S91; Block 8 (Updates) S92; Block 9 (Downloads) S93; Block 10 (Insights) S94; Blocks 11-12 (More/Settings/Onboarding/empty states) S95. **S96 (2026-08-06): the full functional audit Martin asked for, done.** App Store screenshot work is unblocked. **S97-S98: Tachimanga feature-parity pass, complete — see below.**

## Current state (post S102 — 2026-08-06 · CloudKit sync architecture scoped, not implemented)

**S102: designed the full multi-device CloudKit sync architecture** — the last big item on
`TACHIMANGA_PARITY.md`'s backlog, scoped (not built) the same way S90 scoped the Suwayomi-server
design before writing code. Full design doc: `Yomi/CLOUDKIT_SYNC_DESIGN.md`. Headline decisions
(confirmed with Martin): sync on app foreground/background rather than real-time push (no push
entitlement needed), and metadata + reading-state only — no downloaded files or custom cover images
sync. Key finding: `Manga.id`/`Chapter.id` are already content-derived (traced through
`JSBridge.swift`), not local UUIDs, which means (1) chapter lists never need to sync, only the small
per-chapter state a user actually touches, and (2) first-sync bootstrap on an existing library needs
no special merge logic — same content, same id, on any device. `CKSyncEngine` chosen over
`NSPersistentCloudKitContainer` (Core Data-only, ruled out — Yomi is GRDB) and raw `CKDatabase` calls.
See `Yomi/ROADMAP.md`'s S102 entry for the full narrative and `Yomi/CLOUDKIT_SYNC_DESIGN.md` for data
model, write/read paths, bootstrap flow, entitlements, and testing plan. **Next session that picks
this up starts by implementing against that doc**, not re-scoping.

**Prior state (post S101 — 2026-08-06 · rows 31-33 shipped + theme/contrast audit)**

**S101: shipped the 3 features S100 deferred, plus a canvas×accent contrast audit that found 3 real
bugs (live-testing, not just math).** Background auto-refresh (real `BGTaskScheduler` wiring —
`com.yomi.refresh` registered in `AppDelegate`, scheduled on `scenePhase == .background`, handler
reuses `UpdatesViewModel.refresh()` verbatim), background download (gated on auto-refresh, hooks into
`UpdatesViewModel.checkUpdates(for:)`'s new-chapter discovery to auto-enqueue via `DownloadManager`,
manga only), and an in-reader source-URL globe icon (new `JSBridge.resolveSourceURL(path:)` —
best-effort, no plugin changes: reads a plugin's own top-level `BASE_URL`/`BASE` JS global back out
of the JSContext when `path` isn't already absolute; works for ~7 of 15 plugins + Mangayomi-format
sources, hides the icon rather than guessing for the rest). Toggles in `SettingsView`'s Data section,
both default off.

**Theme audit (Martin's ask: "revise how the different app themes look with every possible accent
combination"), computed first, then live-verified — found the audit's own math was too optimistic
until live-tested.** WCAG contrast across all 4 canvases × 11 accents flagged: (1) most accents are
barely visible as icons/progress-bars on Paper/Sepia (as low as 1.24:1) — a real, unresolved tension
between "accent is always exactly the user's chosen color" and legibility, flagged for Martin rather
than silently recolored; (2) every accent's hardcoded white button-label text was failing WCAG AA
except Indigo — confirmed live (Ink + Yellow: "Resume" text genuinely unreadable). Fixed with
`YomiTokens.Accent.foreground(for:on:)`, applied at ~12 real sites app-wide. **First version of that
fix was itself wrong, caught by Martin from a live screenshot**: a blanket "pick whichever of
white/black wins" formula flipped even passing defaults (Vermilion on Ink) to black, breaking the
card's all-one-ink-color convention — corrected to keep the canvas's own ink color whenever it clears
a 3:1 threshold, only flipping for accents that genuinely fail. Martin's screenshot also caught 2 more
real bugs missed by the math-only pass: `CoverImage.swift`'s no-cover placeholder used `Color.secondary`
(system light/dark only) instead of canvas tokens, and — root-caused while fixing — Kingfisher's
`KFImage.placeholder` doesn't live-repaint on an environment-only change (`.id(canvas.name)` forces a
remount on canvas switch); and a novel-indicator badge rendered two different ways on two screens
(Library grid's "NOVEL" pill vs. the Continue shelf's chunky "N" square), unified to the pill. **Lesson
for future theme/design passes: WCAG math alone missed real bugs a live screenshot caught in seconds —
always live-verify at least the worst-case combos the math flags, don't stop at the calculator.**

Full narrative in `Yomi/ROADMAP.md`'s S101 entry. All fixes live-verified via `build_run_sim` +
mobile-mcp/XcodeBuildMCP screenshots across multiple canvas×accent combos, zero build warnings.

**Prior state (post S100 — 2026-08-06 · S99 audit backlog cleared)**

**S100: worked through S99's Known Issues backlog end to end** (rows 24-30, 25, 26, 34, 35 — age
rating, doc cleanup, OPDS→Keychain, silent-failure toasts, the AquaManga reader-page bug, list-mode
multi-select), per Martin's "let's go through all the known issues and fix them." Rows 31-33
(background auto-refresh/download toggles, in-reader source-URL icon) are real new features, not bugs —
explicitly deferred to a future dedicated session at Martin's call, backlog now lives in
`Yomi/TACHIMANGA_PARITY.md`'s S100 addendum. Headline fix: the AquaManga reader-page bug (#34) and the
long-unverified cover-loading fix (#9) turned out to share one deeper root cause — Kingfisher's
`ImageDownloader` defaults to an `.ephemeral` session with its own private cookie store, invisible to
the `HTTPCookieStorage.shared` that `CFBypassView` writes `cf_clearance` into, so the S89 UA
`requestModifier` alone was never sufficient. Fixed by pointing Kingfisher's session config at `.shared`
— verified live, both covers and reader pages render real art now. Full narrative in
`Yomi/ROADMAP.md`'s S100 entry, technical lessons in `Yomi/METODOLOGIA.md`'s S100 section. All fixes
live-verified via `build_run_sim` + `mobile-mcp` + direct `sqlite3`/`defaults read` inspection, zero
build warnings throughout.

**Prior state (post S99 — 2026-08-06 · full project audit, documentation-only)**

S99 ran a full audit of the whole project — code quality, docs consistency, live simulator
verification, and App Store/security readiness — as 4 parallel research passes plus a manual
live-simulator spot-check, deliberately making no fixes, only cataloguing findings as new Known Issues
rows 24-36 for S100 to work through (see above). Code/quality was otherwise genuinely clean after 98
sessions (zero TODO/FIXME, zero unsafe force-unwraps, zero Swift-6 isolation violations, clean build).

**Prior state (post S98 — 2026-08-06 · Tachimanga parity pass complete)**

S97-S98 worked through `Yomi/TACHIMANGA_PARITY.md` (a source-verified feature audit against Tachimanga,
produced S97) end to end — **every item the audit itself flagged as high-value is now shipped.**
S98 alone shipped 4 items, in order of increasing complexity:
1. **Storage composition view** (`StorageManager.swift`/`StorageView.swift`, Advanced → Storage) — real
   byte-accurate breakdown (Downloads/Image cache/Plugins/Custom covers/Web cache/Database/Other) with
   Manage/Clear actions. Found + fixed a real SwiftUI bug live: a `GeometryReader` used directly as
   List row content destabilized every row below it (untappable, accessibility-tree/scroll desync) —
   moved the summary bar entirely outside the `List`.
2. **Library/Settings round-out**: category item counts on Library's tab bar, Default Category
   (auto-assign on add), Default Tab (launch tab), editable request timeout in Advanced → Network
   (User Agent stays fixed — bound to the Cloudflare-bypass WebView's solved-challenge cookie), tap
   zones expanded 3→6 presets, and a real double-tap-to-zoom fix (previously just reset to 1x).
3. **Double-page spreads** for the manga reader (Single/Double/Automatic-in-landscape). `currentPage`
   keeps meaning "a real page index" everywhere (progress/resume/scrubber) — `MangaReaderView`'s
   `TabView` selection goes through a proxy `Binding` that snaps to the enclosing spread's start.
4. **Migrate tab** (Browse → Migrate) — move a library manga to a different installed source,
   transferring status/notes/categories/per-chapter read-state (matched by `chapterNumber`). **Real bug
   found live, looked exactly like a dead button from the outside**: the confirmation dialog's
   `isPresented` binding cleared `migrationTarget` as part of the same transaction as the button tap's
   auto-dismiss, so re-reading `migrationTarget` inside the button's `async` closure (after a
   suspension point) raced and saw `nil`. Fixed by capturing the target by value in the closure instead.

All 4 live-verified via `build_run_sim` + mobile-mcp (Migrate also cross-checked via direct sqlite
inspection of the simulator's `yomi.db`), zero build warnings throughout. See `Yomi/ROADMAP.md`'s S98
entry for full detail, and `Yomi/TACHIMANGA_PARITY.md` for the updated per-feature status table and
remaining (now genuinely long-tail) backlog — full multi-device CloudKit sync is the only big item left,
and needs its own architecture-scoping session like S90 gave the Suwayomi-server design.

**Tooling note**: this session hit real `mobile-mcp` tap-delivery flakiness on plain `Button`s several
navigation levels deep (confirmed via an untouched pre-existing button failing identically) —
`NavigationLink`s stayed reliable throughout. Don't assume a dead-looking button is this tooling issue
without first checking for a state race like the Migrate one above; they can look identical.


Full session-by-session history (S1-S90) lives in `Yomi/ROADMAP.md` (recent) and `Yomi/HISTORY.md`
(archived) — not duplicated here. This file keeps only the single most-recent state above.
## Known issues / carry-forward

| # | Issue | Notes |
|---|-------|-------|
| 1 | Chapters from Browse (partial) | ✅ NovelFire + NovelBin fixed and verified live S88 (see Yomi/ROADMAP.md S88 entry). NovelFire was hardcoded to chapter-list page 1 only (100/3,139 chapters); rewrote to loop all pages. NovelBin's domain (`novelbin.me`) was dead (DNS_PROBE_FINISHED_NXDOMAIN) — rebranded to `novelarrow.com`, rewrote the whole plugin against its clean JSON API. FreeWebNovel's scrape was also rewritten (old code picked up unrelated links, not chapters) but is now blocked by a new site-wide Cloudflare challenge with no bypass wired into the novel-detail path — see row 11. Asura Scans/MangaDex only code-reviewed (pagination logic already loops correctly), not live-retested. |
| 2 | ~~App icon missing~~ | ✅ Done S87 — wired into Xcode (see #3). |
| 3 | ~~Alternate icons need Xcode step~~ | ✅ Done S87 — `AppIcon.appiconset` now ships `AppIcon-Ink-1024.png`; new `AppIcon-Paper.appiconset` added; `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES` set in both configs (Xcode 26's automatic alternate-icon Info.plist generation — verified `CFBundleAlternateIcons.AppIcon-Paper` in the compiled Info.plist). Deleted the two stale empty `AppIconDark`/`AppIconMinimal` appiconsets and fixed `AppearanceStudioView.swift`'s icon picker to use the real `AppIcon-Paper` key instead of leftover placeholder names. |
| 4 | App Store content missing | Age rating 18+, description, screenshots pending in App Store Connect. |
| 5 | ~~Firebase deploy pending~~ | ✅ Deployed S53 — babelnovel.js + lightnovelpub.js live. |
| 6 | ReadComicOnline + Mangapill broken | Downloaded from dead GitHub repo. User should uninstall from Extensions tab. |
| 7 | ~~Inconsistent cover-cell sizes in grid~~ | ✅ Root-caused + fixed S87. `.aspectRatio(_, contentMode: .fill)` alone falls back to the content's own intrinsic size whenever the parent proposes unbounded height (grid cell with only column width fixed, or `.frame(width:)` with no height) — cell height ended up varying per image. Fixed with a new `coverAspectSized()` modifier (`Core/CoverImage.swift`): a `Color.clear.aspectRatio(2/3, contentMode: .fit)` sizer drives a deterministic width-based height, with the real image as an `.overlay` + `.clipped()`. Applied to the shared `CoverImage` component (fixes `NovelLibraryCoverCell`, `NovelCoverCell`, `OPDSBrowseView` for free) plus the inline duplicates in `MangaCoverCell.swift`, `LibraryView.swift`'s `NovelLibraryCoverCell` custom-cover branch, `ContinueReadingRow.swift` (both manga/novel cells), and `HistoryView.swift`. Verified live: MangaDex Popular grid cells are now uniform. |
| 8 | Manga sources never show Popular/Latest tabs | ✅ Root-caused S88 for Suwayomi specifically: `SuwayomiSource.supportsLatest` was already decoded from the server's own API (real Keiyoushi/Tachiyomi extensions do report it correctly) but `SuwayomiService` had no `fetchLatest()` and `SuwayomiBrowseView` never called anything but popular — a pure client-side gap. Added `fetchLatest()` + a `FeedTab` picker in `SuwayomiBrowseView`, matching `BrowseView.swift`'s existing pattern. S89: Popular tab now live-verified working end-to-end against a real Suwayomi server; Latest tab specifically not re-tested this session (same code path, lower risk). Prior verdict still stands for direct JS plugins: `JSBridge.supportsLatest` requires `getLatestManga`, which `mangadex.js`/`asurascans.js` never implemented. |
| 9 | ~~AquaManga "Cloudflare bypass fails"~~ | ✅ Root-caused S87 — **misdiagnosed originally, not a Cloudflare problem at all.** Confirmed live (Chrome + in-app debug logging): SOURCE.fetch's plain UA/headers get a clean `200` with full HTML every time, no CF challenge — the domain migrated `aquareader.net` → `aquareader.org` and was **rebuilt on a custom theme** (no longer Madara WordPress), so `aquamanga.js`'s old selectors (`div.page-item-detail`, `li.wp-manga-chapter`, etc.) matched nothing. Rewrote `getMangaList`/`getChapterList`/`searchManga` against the live DOM (`article.aqua-archive-card`, `a.aqua-ch-item`, fixed a `searchManga` container bug that only ever matched the first of N results). `getPageList` needed no change — the reader page kept the old markup. Deployed to Firebase (`v1.1.0`). **While chasing why the fix "didn't take" during testing, found and fixed two real caching bugs**, both `URLCache` serving stale CDN responses despite `Cache-Control: max-age=3600` no longer matching the redeployed content: `PluginCatalogService.fetchCatalog(force: true)` and `ExtensionManager.install()` now both set `.reloadIgnoringLocalCacheData` — without this, "Update" and even a fresh reinstall could silently keep running old plugin code indefinitely. **Two things found this session:** (a) ✅ AquaManga cover images — fixed for real S100 (see #34's entry): the S87 UA `requestModifier` alone wasn't enough because Kingfisher's `ImageDownloader` defaults to an `.ephemeral` session with its own private cookie store, invisible to the `HTTPCookieStorage.shared` that `CFBypassView` writes `cf_clearance` into; pointing Kingfisher's session config at `.shared` fixed both covers and reader pages, verified live. (b) **Runaway pagination** (still open): `SourceBrowseView.loadMore()` fetched **100+ pages in seconds** for AquaManga — `hasMoreContent` only goes false on an *empty* result, but AquaManga's archive apparently never returns empty past the real last page (~63 pages for 1,495 series), so it never terminates. Needs a page-level dedup or max-page safety cap in `BrowseView.swift`'s `loadMore()`. |
| 10 | ~~Keiyoushi repo — not missing, architectural~~ | ✅ Architecture verdict still correct (Kotlin/APK, cannot run in JSC, confirmed since S18) — but S89 found the bridge itself had **two real bugs** that meant it never actually worked even with a server configured: no ATS exception (all Suwayomi/OPDS traffic over plain HTTP was silently blocked) and `SuwayomiService.fetchChapters()` hit a 404ing REST path. Both fixed and live-verified S89 against a real Suwayomi-Server with the real Keiyoushi repo and a real installed extension (Asura Scans) — Popular/detail/chapters/page-image all confirmed working end-to-end. Tachimanga researched and confirmed to use the *exact same* self-hosted-server-bridge architecture, not an embedded/bundled Keiyoushi — Yomi's S41 design was already correct, it just had bugs. See `ROADMAP.md`'s S89 entry for full detail including how to stand up a persistent server. |
| 11 | ~~FreeWebNovel blocked by Cloudflare~~ | ✅ Fixed S97 — `NovelDetailView.swift` had zero `CFBypassView` wiring (unlike `MangaDetailView.swift`), so a CF-blocked novel source just showed a generic "No chapters found." Added the same `cfBlockedURL`/"Bypass Cloudflare" button/`CFBypassView` sheet pattern used by manga. **Also found and fixed a second, deeper bug while live-verifying against FreeWebNovel's real Cloudflare Error 1015 (rate-limit) page**: `JSBridge.swift`'s `_fetchSync` CF-detection only matched `"Just a moment"`/`"cf-mitigated"` on a 403 — real-world Cloudflare block pages vary (1015 rate-limit, 1020 access-denied, etc.) and don't all contain those exact strings, so `cfBlockedURL` silently never got set for this case even though the response was clearly a Cloudflare page ("Cloudflare Ray ID", "Please enable cookies"). Broadened to any error status (`>=400`) plus a wider marker list; purely additive, doesn't change the existing unconditional `hasCFRay` trigger. Verified live end-to-end: FreeWebNovel's "Shadow Slave" now shows the Bypass button and `CFBypassView` opens with the real page source. |
| 12 | Duplicate extension rows (new, found+fixed S88) | `ExtensionManager.install()` always inserted under the *catalog's* id without removing an existing install of the same plugin under a *different*, older id — Yomi went through a sha256-hash-id → stable-catalog-id migration at some point and nothing ever cleaned up the old rows. Result: Plugins/Browse showed some sources (NovelFire, FreeWebNovel, NovelBin) **twice**, one stale/unupdatable alongside one fresh, confirmed directly in `yomi.db`. Fixed: `install()` now deletes any other installed extension with the same name before writing the new row. **The user's real device likely has this same duplication for any plugin installed before the id-scheme migration** — worth a quick glance at the Plugins screen next session; if duplicates are there, tapping "Update" on the affected source once (with this fix shipped) will self-heal it. |
| 13 | ~~Custom fonts may never have rendered~~ | ✅ Resolved S95 — confirmed not actually broken. Verified live via a temporary debug print: `UIFont.familyNames`/`fontNames(forFamilyName:)` show both Space Grotesk and Space Mono registered correctly, and `UIFont(name: "Space Grotesk", size:)` resolves a real font instance. The S89 `Info.plist` fix was sufficient; no further action needed. |
| 14 | Onboarding was never actually presented to any user (found+fixed S95) | `YomiApp.swift` chained two separate `.fullScreenCover` modifiers on the same `ContentView()` (`showOnboarding` and `isLocked`) — SwiftUI only reliably tracks one presentation slot per view identity this way, so the first (`showOnboarding`) silently never fired, regardless of `hasSeenOnboarding`. Fixed by merging into a single `.fullScreenCover` with a computed `Binding` and if/else content (lock screen takes priority). Verified live via a full `simctl uninstall`+reinstall (forcing a genuine first launch) — all 3 pages now show correctly. |
| 15 | ~~`LibraryView` root background not wired to `\.yomiCanvas`~~ | ✅ Fixed S96 — added `.background(canvas.bg.ignoresSafeArea())` to its root, matching every view since S85. |
| 16 | ~~Stale debug accentColor survived `simctl uninstall`~~ | ✅ Root-caused S96 — **not a Yomi bug.** iOS Simulator's `cfprefsd` caches app preferences at a device-level path (`.../data/Library/Preferences/<bundleid>.plist`) independent of the app's per-install Data Container; `simctl uninstall` doesn't reliably clear it. Real fresh-install testing needs `rm` on that plist + `xcrun simctl spawn <device> launchctl stop com.apple.cfprefsd.xpc.daemon` after uninstall, before reinstalling. |
| 17 | ~~`AppSettings.canvasColors` didn't implement "follow device"~~ | ✅ Fixed S96 — canvas `""` (the true fresh-install default) resolved `colorScheme` to `nil` (follow system) but `canvasColors` unconditionally to Ink, breaking chrome/content consistency for any first-time user on a light-mode device. Fixed by defaulting fresh installs to `canvas = "Ink"` directly. See `ROADMAP.md` S96. |
| 18 | ~~"Get plugins" silently failed to deep-link on first visit to More~~ | ✅ Fixed S96 — `MoreView`'s `.onChange(of: appRouter.openMorePlugins)` doesn't fire for a flag already `true` when the view first mounts (i.e. More never visited yet this session). Fixed with `initial: true`. |
| 19 | ~~Library multi-select unreachable via long-press on grid cells~~ | ✅ Fixed S96 — `.contextMenu` was consistently winning over a separate `.onLongPressGesture` on the same view. Replaced the dead-code gesture with a "Select" context-menu item. List mode's equivalent gap fixed S100, see #35. |
| 20 | ~~Manual mark-read actions never touched `lastReadAt`~~ | ✅ Fixed S96 — `ChapterQueries.setRead`/`NovelQueries.markRead`/`markAllChapters` (used by Updates, Detail's per-chapter/bulk toggles, and even `TextReaderView`'s own reading flow) never updated the parent manga/novel's `lastReadAt`, unlike their sibling functions — broke History, Library's last-read sort, and the Continue card. Fixed at the query layer across every call site. |
| 21 | 3 of 4 novel sources tried S96 are site-side blocked (not a Yomi bug) | LightNovelPub and BabelNovel return raw HTTP 403 to a real browser UA via `curl`; BoxNovel returns HTTP 200 but a JS-only anti-bot redirect shell with no real HTML. All three are genuinely Cloudflare/bot-gated right now, not a client parsing bug — the app's "may be down or Cloudflare-protected" message is accurate. NovelBin (novelarrow.com backend) still works correctly. |
| 22 | ~~`.glassEffect()` rendering as an oval/blob instead of the declared shape~~ | ✅ Fixed S96 (Martin's live visual review) — the parameterless `.glassEffect()` used via `.background { Shape().glassEffect() }` across 6 call sites (both readers' bottom bars, Library's selection action bar, `GlassChip`) doesn't reliably clip to that shape, a documented iOS 26 gotcha. Fixed by applying `.glassEffect(.regular, in: <Shape>)` directly to content instead. |
| 23 | ~~Native `Slider` clashed with the app's design language~~ | ✅ Fixed S96 (Martin's live visual review) — the default iOS 26 `Slider` thumb (large white pill) didn't match the thin-capsule-progress-bar look used everywhere else. Built `Core/YomiScrubber.swift`, swapped in at both call sites (manga reader page scrubber, novel reader font size). |
| 24 | ~~Age rating declaration stale (17+ vs 18+)~~ | ✅ Fixed S100 — `CLAUDE.md`'s App Store checklist and `Yomi/design/DESIGN_HANDOFF.md` (3 mentions) all corrected to 18+. Grepped project-wide for stray "17+" afterward — no other stale mentions remain (remaining `17+` hits are unrelated iOS-version-availability notes in METODOLOGIA.md and correct historical "replaces 17+" explanations in RESEARCH.md/HISTORY.md). |
| 25 | ~~OPDS password stored in UserDefaults, not Keychain~~ | ✅ Fixed S100 — `opdsPassword`'s `didSet` now writes through to `KeychainHelper` instead of `UserDefaults`, matching the MAL-token pattern (`MALService.swift`). The `@Observable` stored property itself is unchanged (required for SwiftUI observation — see the class-level comment), only its persistence target moved. Init migrates any existing `UserDefaults` value to Keychain once, then removes it. Verified live: set a password, force-quit (not just background) and relaunch — value survived in the UI while confirmed absent from `defaults read` on `UserDefaults`, round-tripping through Keychain only. |
| 26 | ~~Silent DB-write failures on mark-read / toggle-library~~ | ✅ Fixed S100 — added a new reusable `Core/YomiToast.swift` (`.yomiToast(_:)` view modifier, self-dismissing top banner matching `UpdatesView`'s existing refresh-summary banner styling, plus `YomiHaptics.error()`). Wired into both `ChapterReaderView.markChapterRead`'s and `MangaDetailView.toggleLibrary`'s `catch` blocks alongside the existing `print()`. GRDB write failures are rare by nature (not reproduced live), so this was verified by code review + clean build rather than forcing a live failure. |
| 27 | ~~Blanket `NSAllowsArbitraryLoads` ATS exception~~ | Not a code fix by design — S99 recommendation stands: keep as-is (target hosts for self-hosted Suwayomi/OPDS aren't known in advance, so per-domain `NSExceptionDomains` scoping isn't feasible), add an App Store Connect review-note at submission explaining the self-hosted-server feature. S100: folded into the consolidated App Store checklist (`ROADMAP.md`, see #36) so it's tracked as a submission-time action item instead of floating here. |
| 28 | ~~`README.md` still references removed Extensions tab~~ | ✅ Fixed S100 — line 26 changed from "open Browse → Extensions and install" to "open Browse → Sources and install," matching line 54's already-correct wording. |
| 29 | ~~`EXTENSIONS.md` orphaned/stale~~ | ✅ Fixed S100 — deleted. Not referenced from any Swift source (the in-app "Plugin setup guide" link points to `README.md`), and its content (7/15 plugins, built around the removed Extensions tab) was fully superseded by `README.md`'s repository-based install flow. |
| 30 | ~~This doc's own file-index note is stale~~ | ✅ Fixed S100 — the "Key file paths" table's `NovelQueries.swift` note corrected to reflect its real call sites (`LibraryViewModel.swift:191`, `UpdatesView.swift:96,126`). |
| 31 | ~~No "background auto-refresh" toggle in UI~~ | ✅ Fixed S101 — real `BGTaskScheduler` wiring (`com.yomi.refresh`, registered in `AppDelegate`, scheduled on `scenePhase == .background`), not just a toggle. Handler reuses `UpdatesViewModel.refresh()` verbatim. Toggle in `SettingsView`'s Data section, default off. Actually triggering a real `BGAppRefreshTask` fire isn't practically testable in the simulator without lldb — registration/no-crash/toggle-persistence verified live, the task body itself was not. |
| 32 | ~~No "background download" toggle in UI~~ | ✅ Fixed S101 — `AppSettings.backgroundDownloadEnabled`, gated on #31 (disabled/dimmed in Settings while auto-refresh is off). Wired into `UpdatesViewModel.checkUpdates(for:)`'s new-chapter discovery to auto-enqueue via `DownloadManager`. Manga only — novels have no download feature at all, not just in the background. |
| 33 | ~~In-reader header has no source-URL/globe icon~~ | ✅ Fixed S101 — new `JSBridge.resolveSourceURL(path:)`, best-effort with no plugin changes required: reads a plugin's own top-level `BASE_URL`/`BASE` JS global back out of the JSContext when `path` isn't already absolute. Works for ~7 of 15 plugins (those declaring `const BASE_URL` outside an IIFE) plus Mangayomi-format sources; can't resolve one for esbuild-bundled IIFE plugins or pure-API sources (MangaDex/Comick) — hides the icon rather than guessing. Wired into both `ChapterReaderView.swift` and `TextReaderView.swift`, reusing the existing `DiscussWebSheet`. Icon visibility (meaning URL resolution) verified live against AquaManga; tap-to-open hit this session's mobile-mcp tap flakiness (a control tap on the pre-existing gearshape icon failed identically) and wasn't re-confirmed past that. |
| 34 | ~~AquaManga reader page failed to render live~~ | ✅ Root-caused + fixed S100 — deeper than #9's UA-only theory. Reader pages (`ChapterReaderView.swift`'s `MangaPageView`/`WebtoonReaderView`/`ContinuousHorizontalReaderView`) used raw `AsyncImage`, which can't carry any custom request modifier at all — switched to `KFImage` (matching `CoverImage.swift`'s pattern) so they inherit `KingfisherManager.shared`'s global config. But that alone still 403'd live: Kingfisher's `ImageDownloader` defaults to `URLSessionConfiguration.ephemeral`, which keeps its own private in-memory cookie store — invisible to `HTTPCookieStorage.shared`, exactly where `CFBypassView` copies the `cf_clearance` cookie. Fixed by pointing Kingfisher's downloader at an explicit session config with `httpCookieStorage = .shared` (`YomiApp.swift` init, alongside the existing UA `requestModifier`). This was the real root cause of **both** #34 and #9's previously-unverified cover fix — verified live: AquaManga's cover art and "Path of Vengeance" Ch. 2 pages 1–2 all render correctly now (previously gray placeholder / broken-image icon). |
| 35 | ~~List-mode multi-select still open (re: #19)~~ | ✅ Fixed S100 — confirmed genuinely broken (not just untested): list mode's `.contextMenu` had no "Select" entry and `MangaListRow`/`NovelLibraryListRow` had no selection UI at all, unlike grid mode's `MangaCoverCell`/`NovelLibraryCoverCell` (fixed S96). Added matching "Select" context-menu entries + checkbox rendering to both list rows, wired into the same `isSelecting`/`selectedIds`/`selectedNovelIds` state grid mode already uses (so the existing toolbar Select-All/Cancel and bottom bulk-action bar work for free). Hit the exact `NavigationLink` + `.contextMenu` "narrows tappable area to content only" bug documented in row 8's S86 finding — fixed the same way, an explicit `.contentShape(Rectangle())` on the row container. Verified live: long-press → Select → multi-row checkbox selection → bulk-action bar, both manga and novel list rows. |
| 36 | ~~App Store Connect readiness has zero local tracking artifact~~ | ✅ Fixed S100 — `Yomi/ROADMAP.md`'s "App Store submission checklist" table is now the single authoritative source (updated to current accurate status — app icon done, OPDS Keychain done, ATS review-note item added from #27). This file's own "App Store checklist" section now points to it instead of duplicating. RESEARCH.md/HISTORY.md sections are historical/research narrative, not live checklists — left as-is, not floating duplicates of the actionable list. |
| 37 | ~~Accent-fill buttons had hardcoded white text, unreadable on bright accents~~ | ✅ Fixed S101 — WCAG audit found every accent preset except Indigo failed AA (4.5:1) for white text on its own fill; confirmed live (Ink + Yellow: "Resume" text invisible, 1.52:1). New `YomiTokens.Accent.foreground(for:on:)` keeps the canvas's own ink color whenever it clears 3:1 against the accent, else flips to the opposite pole — applied at ~12 real sites (Resume buttons, badges, empty-state/onboarding CTAs, selection checkmarks). A first "always pick whichever of white/black wins" version was wrong (flipped passing defaults like Vermilion-on-Ink to black, breaking the card's one-ink-color convention) — caught live by Martin, corrected to the threshold version. Paper/Sepia's deeper issue — most accents are also low-contrast as icons/progress-bars directly against those light backgrounds — is a real, separate, *unresolved* color-science tension (accent-vs-bg, not fixable by a foreground-color trick) and was deliberately left for Martin to weigh in on rather than silently recoloring his chosen accents. |
| 38 | ~~No-cover placeholder ignored canvas selection~~ | ✅ Fixed S101 — `Core/CoverImage.swift`'s placeholder used `Color.secondary` (system light/dark mode only), not canvas tokens; any manga/novel without cover art rendered a plain gray box regardless of Ink/Midnight/Paper/Sepia. Fixed to `canvas.surface2`. Root-caused a second layer while fixing: Kingfisher's `KFImage.placeholder` snapshots once at mount and doesn't live-repaint on an environment-only change (correct from a fresh launch with the new canvas already active, stale after switching canvas mid-session without relaunching) — added `.id(canvas.name)` to force a clean remount on every canvas switch, verified live both ways. |
| 39 | ~~Novel indicator badge rendered two different ways~~ | ✅ Fixed S101 (Martin's live catch) — Library grid's `NovelLibraryCoverCell` used a small translucent "NOVEL" text pill (top-trailing); `ContinueReadingRow`'s "Up next" shelf used a chunky solid-accent-filled "N" square (top-leading) for the exact same meaning. Unified the shelf cell to the grid's pill style. |

## MCP tools — use these every session

### XcodeBuildMCP (build + simulator)
**Always call `session_show_defaults` before the first build of a session.** Then `build_run_sim` (or `build_sim`).
```
mcp__XcodeBuildMCP__session_show_defaults  — verify project/scheme/simulator configured
mcp__XcodeBuildMCP__session_set_defaults   — set if missing: project=Yomi.xcodeproj, scheme=Yomi, simulator="iPhone 17 Pro"
mcp__XcodeBuildMCP__build_sim              — compile only (fast check)
mcp__XcodeBuildMCP__build_run_sim          — compile + launch in simulator
mcp__XcodeBuildMCP__screenshot             — screenshot the running simulator
mcp__XcodeBuildMCP__launch_app_logs_sim    — stream live logs
```

### context7 (live library docs)
Use whenever touching GRDB, SwiftUI, or any third-party API. Append `use context7` to the query.
```
mcp__context7__resolve-library-id  — find the library ID (e.g. "grdb swift")
mcp__context7__query-docs          — fetch current API docs for that library
```
Never rely on training-data knowledge for GRDB migration syntax, SwiftUI modifiers, or iOS 26 APIs — always fetch via context7.

### mobile-mcp (simulator UI automation)
Use to inspect what's actually rendered on screen after a build+run.
```
mcp__mobile-mcp__mobile_take_screenshot         — visual snapshot
mcp__mobile-mcp__mobile_list_elements_on_screen — accessibility tree with coordinates
mcp__mobile-mcp__mobile_click_on_screen_at_coordinates — tap a UI element
```
**Known flakiness (S98):** plain `Button` taps intermittently fail to register several navigation
levels deep — confirmed via an untouched, pre-existing button failing identically, so it's a tooling
issue, not a code regression. `NavigationLink`s stayed reliable throughout. Retrying 2-3 times, or a
fresh `build_run_sim` relaunch, usually clears it. **But don't assume every dead-looking button is
this** — S98 also found a real state-race bug (`confirmationDialog`'s `isPresented` binding clearing
observable state before an `async` button closure re-read it) that looked externally identical to
this tooling flakiness. If a tap-triggered dialog/sheet dismisses but nothing happens, check for a
race before blaming the tool. For quick UserDefaults-backed setting changes, `xcrun simctl spawn
<device> defaults write <bundle-id> <key> <value>` + relaunch is a reliable bypass. For DB-state setup
(seeding test data), `sqlite3` directly against the simulator's `yomi.db` (via `xcrun simctl
get_app_container <device> <bundle-id> data`) also works well and was used to verify Migrate.

**New tooling note (S99):** a second, distinct issue — a systematic coordinate offset specifically on
the bottom tab bar. Tapping the reported x-coordinate for "More" landed on "Updates" instead; a
manually-compensated x-value worked correctly. Full-width list rows elsewhere were unaffected — this
looks like a coordinate-mapping quirk for this specific device/session rather than a real SwiftUI
hit-testing bug (the tab bar is a standard `TabView`, not custom-built). If tab-bar taps land on the
wrong tab, try a small x-offset before concluding it's a real bug.

### github
Use for PR/issue management. Repo: `PacoDealer/Yomi`.
```
mcp__github__list_issues    — see open issues
mcp__github__issue_read     — read a specific issue
mcp__github__create_pull_request
```

### swift-lsp plugin
Installed via `/plugin install swift-lsp@claude-plugins-official` inside a Claude Code session.
Provides real-time Swift diagnostics. **Remember: SourceKit errors from swift-lsp are always noise
(cross-file types not resolved in isolation). Only xcodebuild errors are signal.**

### apple-docs (SwiftUI + iOS 26 API)
Use for SwiftUI + iOS 26 API lookups from developer.apple.com.
```
mcp__apple-docs__search_apple_docs      — search for a symbol or topic
mcp__apple-docs__get_apple_doc_content  — fetch full doc page
mcp__apple-docs__search_wwdc_content    — search WWDC session transcripts
```

## Research rule — never say "impossible" without asking the second question

For 40 sessions, "Keiyoushi extensions are impossible on iOS" was the stock answer. Suwayomi — a self-hosted server that exposes all 1000+ extensions via REST — was always the solution. It shipped in S41.

**Before concluding any ecosystem integration is impossible:**
1. Does a self-hosted server/proxy expose it via REST? (Suwayomi for Keiyoushi, FlareSolverr for Cloudflare, Komga for local libraries)
2. Does any competing iOS app (Paperback, Aidoku, Tachimanga) already support it? If yes, find out how.
3. Use `WebSearch` — never rely on training-data knowledge alone for ecosystem research.

"X format is impossible to run on iOS" ≠ "there is no path." Always ask: **what bridge, proxy, or server exists?**

## ABSOLUTE RULES — never violate

### Swift 6 + concurrency
- All `*Queries` methods must be `nonisolated`
- All JSBridge calls must be `Task.detached(priority: .userInitiated)` — never call from MainActor (SOURCE.fetch blocks with DispatchSemaphore)
- Deliver results via `await MainActor.run { state = result }`
- `appDatabase` is `nonisolated(unsafe) var` at module level — never wrap in an actor
- `ExtensionManager.shared` is MainActor-isolated — capture a local closure before entering Task.detached
- **Never read `AppSettings.shared` properties inside `Task.detached`.** Capture any needed values as local constants on MainActor before entering the detached task — `AppSettings` is not thread-safe.

### File editing
- **Always read the target file before editing it.** Never write against assumptions.
- **When replacing an entire file: explicitly check what the new file omits vs the current file.** Silent deletion of existing logic is the #1 source of regressions (OnboardingView, markRead() both dropped this way in S21).
- **Before removing or renaming any public symbol (function, property, type): grep for all call sites first.** A symbol that looks unused in its own file may be the only path through a critical flow elsewhere.
- **Before editing doc sections (ROADMAP/METODOLOGIA/ARQUITECTURA/CLAUDE.md): read the current content of that section.** Never update docs from memory — diffs, not recollection.
- Compile before touching a third unrelated file. Chaining two tightly coupled edits then compiling is fine; letting errors compound across unrelated files is not.
- Never create a file that isn't strictly required.

### GRDB
- Next migration prefix must be `v20_` (v19_ used for source indexes in S77)
- `nonisolated` on all `*Queries` static methods
- Use `_ = try appDatabase.write { ... }` to silence unused result warning
- `appDatabase.read` from `@MainActor` context requires `try await`
- **INSERT OR IGNORE pattern**: `try ch.insert(db, onConflict: .ignore)` — never use `ch.save(db)` for chapter list persistence (save = INSERT OR REPLACE which overwrites existing read/download state)

### Diagnosing errors
- **Read the full build error before touching any code.** Never fix what you expect — fix what the compiler says.
- After a session gap of more than a few days: run a build before writing any new code. DerivedData and simulator state can drift.

### iOS 26 patterns
- TabView: `Tab("title", systemImage:) {}` — `.tabItem {}` renders nothing in iOS 26
- `Text + Text` is deprecated — use `Text("\(Text(…)) …")` interpolation
- `.tint()` and `.preferredColorScheme()` go on `ContentView()` inside WindowGroup, NOT on WindowGroup/Scene itself
- `@Observable` singletons in App structs require `@State` to drive re-evaluation (not just `AppSettings.shared.property`)

### Image loading
- **Never use `AsyncImage` for cover images or manga pages.** `AsyncImage` has no disk cache — every app launch re-fetches all images. Use `KFImage` from Kingfisher (SPM: `https://github.com/onevcat/Kingfisher`). Drop-in replacement: `KFImage(url)` instead of `AsyncImage(url:)`.
- Kingfisher provides automatic disk + memory cache. Cover images load instantly after the first fetch.
- For manga page images inside readers, `AsyncImage` is acceptable (pages are transient — not worth caching to disk).

### Database performance
- **Always add an index when a new table is queried by a non-primary-key column.** Current indexes: `idx_chapter_mangaid`, `idx_chapter_unread`, `idx_novel_chapter_novelid` — added in v18_ migration.
- Every new `WHERE column = ?` query pattern on a large table needs a corresponding index.

### Plugin system
- Never build `JSBridge(scriptURL: ext.sourceListURL)` — URL in DB goes stale. Always reconstruct from `FileManager` + `ext.id`
- `JSBridge` is per-extension, never shared between concurrent tasks
- `#if DEBUG seedBundledPlugins()` in `YomiApp.init()` — never in release

## Key file paths
```
Yomi/AppSettings.swift                         # @Observable singleton, UserDefaults, 40+ props (incl. canvas, accentColor, libraryColumns, keepScreenOn, isIncognito, showUnreadBadge, lineSpacing, libraryDisplayMode)
Yomi/ContentView.swift                         # Root TabView with AppRouter binding
Yomi/YomiApp.swift                             # Entry point, DB setup, #if DEBUG seed, .tint + .preferredColorScheme on ContentView, BGTaskScheduler registration + scheduleBackgroundRefresh()
Yomi/Core/AppRouter.swift                      # @Observable, module-level appRouter var
Yomi/Core/Color+Hex.swift                      # Color(hex:) init + Color.hexString
Yomi/Core/DesignTokens.swift                   # YomiTokens: Canvas (Ink/Midnight/Paper/Sepia), Accent (Vermilion default), Font (Space Grotesk + Mono), TypeScale, Reader themes, Radius, Spacing, Motion
Yomi/Core/CanvasEnvironment.swift               # \.yomiCanvas environment key — set once in ContentView from AppSettings.canvasColors, read via @Environment everywhere
Yomi/Core/GlassChip.swift                       # .glassChip() — shared 44×44 floating Liquid Glass circle modifier for chrome buttons
Yomi/Core/UIImage+AverageColor.swift            # UIImage.averageColor() via CIAreaAverage — backs Continue hero's ambient-tint-from-cover background
Yomi/Core/Notation.swift                       # Catalog-notation formatters (Space Mono output): chapter(), progress(), readingTime(), status(), novelIndex(), historyTimestamp(), etc. `nonisolated enum` (S91) — safe to call from Task.detached.
Yomi/Core/NotificationManager.swift
Yomi/Database/DatabaseManager.swift            # Migrations v1–v19_source_indexes; next must be v20_
Yomi/Database/Queries/MangaQueries.swift
Yomi/Database/Queries/ChapterQueries.swift     # insertAllIgnoringConflicts (INSERT OR IGNORE — safe bulk persist, called from loadChapters)
Yomi/Database/Queries/CategoryQueries.swift
Yomi/Database/Queries/NovelQueries.swift       # fetchLibrary() called from LibraryViewModel.swift:191, UpdatesView.swift:96,126
Yomi/Database/Queries/ExtensionQueries.swift
Yomi/Features/Extensions/JSBridge.swift        # JavaScriptCore bridge, shims, require(), getLatestManga(), supportsLatest
Yomi/Features/Extensions/ExtensionManager.swift
Yomi/Features/Extensions/PluginCatalogService.swift  # multi-URL parallel fetch, dedup by id, invalidateCache()
Yomi/Features/Extensions/SuwayomiService.swift       # Suwayomi REST client; SuwayomiSource/MangaPage/ChapterItem structs; isEnabled check
Yomi/Features/Extensions/SuwayomiBrowseView.swift    # Browse one Suwayomi source (infinite scroll, search, isPresented: nav)
Yomi/Features/Library/LibraryView.swift        # grid/list toggle (settings.libraryDisplayMode), grid columns, multi-select
Yomi/Features/Library/LibraryViewModel.swift   # manga + novels; SortOrder enum; fetchLibrary() runs in Task.detached
Yomi/Features/Library/MangaDetailView.swift    # Chapter tap→reader via navigationDestination(item:). insertAllIgnoringConflicts in loadChapters.
Yomi/Features/Library/MangaCoverCell.swift     # Cover cell + MangaListRow struct (for list mode)
Yomi/Features/Library/MigrateView.swift        # Migrate tab UI: library picker → per-source parallel search w/ match badges → confirm → migrate
Yomi/Features/Library/MigrationService.swift   # Migration logic: transfers status/notes/categories/chapter read-state (matched by chapterNumber)
Yomi/Features/Browse/BrowseView.swift          # SourceBrowseView: FeedTab enum, supportsLatest picker, bridge reuse; Suwayomi section; Migrate segment
Yomi/Features/Reader/ChapterReaderView.swift   # Auto-mark read, incognito guard, lastPageRead save/resume; MangaReaderView has double-page spread logic
Yomi/Features/Reader/TextReaderView.swift      # Novel reader; overlay opacity animation; dynamic colorScheme (sepia/dark/light)
Yomi/Features/More/PluginsView.swift
Yomi/Features/More/SettingsView.swift          # Plugin Repos section, Suwayomi section, Advanced → NavigationLink; Appearance → AppearanceStudioView
Yomi/Features/More/AppearanceStudioView.swift  # Canvas × Accent × Type studio; live preview card; WCAG contrast badge; app icon tiles; Reset defaults
Yomi/Features/More/AdvancedSettingsView.swift  # Cache → Storage NavigationLink, Network (editable timeout), Database (log export), Build info
Yomi/Features/More/StorageManager.swift        # Pure FileManager/Kingfisher size computation for the Storage view — safe from Task.detached
Yomi/Features/More/StorageView.swift           # Storage composition view: per-category size + Manage/Clear, reachable from Advanced
Yomi/Features/More/InsightsView.swift          # ScrollView + LazyVGrid StatCards redesign
Yomi/Features/Onboarding/OnboardingView.swift
Yomi/Resources/                                # JS plugins (test-source.js only; production on Firebase)
Yomi/design/design_handoff_yomi/YOMI Screens.dc.html  # PRIMARY DESIGN REFERENCE — 16 screens, HTML+CSS, all tokens/themes inline
Yomi/design/Fonts/                             # SpaceGrotesk-Variable.ttf, SpaceMono-Regular.ttf, SpaceMono-Bold.ttf, YomiFonts.plist
scripts/build-plugins.mjs                      # esbuild bundler for TS plugins
```

## Build command
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme Yomi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
# Available simulators (Xcode 26.3.1): iPhone 16e, iPhone 17, iPhone 17 Pro, iPhone 17 Pro Max, iPhone Air
```
Check available simulators: `xcrun simctl list devices available | grep iPhone`
Clean DerivedData if stale: `rm -rf ~/Library/Developer/Xcode/DerivedData/Yomi-*`

## Firebase plugin deploy
```bash
cd ~/Projects/Yomi/Firebase && firebase deploy --only hosting
```
Firebase folder lives outside the Xcode repo — not committed to git.

## App Store checklist
**Single authoritative checklist: `Yomi/ROADMAP.md`'s "App Store submission checklist" table** (S100 —
consolidated here from what used to be near-duplicate lists scattered across this file, ROADMAP.md,
RESEARCH.md, and HISTORY.md, per Known Issue #36). Update that table, not this section, when checklist
items change. Current headline: code-side work is done (icon, privacy manifest, privacy policy URL, MAL
+ OPDS credentials both in Keychain, screenshots unblocked since S96) — everything left is App Store
Connect data-entry only (age rating 18+, description, support URL, screenshots, ATS review notes for
`NSAllowsArbitraryLoads`).

## Session close
1. Update all three docs in one prompt: ROADMAP.md + METODOLOGIA.md + ARQUITECTURA.md
2. **Commit and push to GitHub** — every session ends with `git add -A && git commit && git push`. No exceptions.
3. **If JS plugins were modified** — copy changed `.js` files to `~/Projects/Yomi/Firebase/public/` and run: `cd ~/Projects/Yomi/Firebase && firebase deploy --only hosting` (requires `firebase login --reauth` if credentials expired).
