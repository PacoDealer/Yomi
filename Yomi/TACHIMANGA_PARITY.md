# Tachimanga Parity Audit (S97, 2026-08-06)

Source: live walkthrough of Tachimanga on Martin's physical iPhone via macOS iPhone Mirroring
(32 screenshots — Browse/Sources, Migrate, History, full More/Settings tree, Library, Downloads,
reader + all reader settings sheets). Every claim below about Yomi's current state was verified
against the actual source in this repo on 2026-08-06, not against session memory — several things
assumed missing in an earlier pass (App Lock, Tachiyomi backup import, category rename/delete,
concurrent-download limit) turned out to already exist. Treat this file, not memory, as the source
of truth for what's actually missing.

Status legend: ❌ Missing · 🟡 Partial · ✅ Parity (Yomi already has it) · 🔷 Yomi ahead (Yomi does
more than Tachimanga here already)

Note throughout: several Tachimanga features are premium-gated there (👑 in their UI) — Yomi has no
premium tier, so matching them means shipping them free. Flagged inline as [premium in Tachimanga].

---

## 1. Reader — reading modes & page layout

| Feature | Tachimanga | Yomi | Status |
|---|---|---|---|
| Reading modes | 7: Paged LTR/RTL/vertical, Continuous LTR/RTL/vertical, Webtoon | ✅ Fixed S97 — `ReaderMode` now has 6 cases (Paged RTL/LTR, Paged Vertical, Continuous RTL/LTR, Webtoon = continuous vertical). Paged-vertical uses the standard rotate-90°/counter-rotate-content TabView technique; Continuous horizontal is a new `ContinuousHorizontalReaderView` mirroring `WebtoonReaderView`'s structure. Both wired into the in-reader mode picker and Settings' default-mode picker. Live-verified: renders without crashing in the simulator; swipe-to-page interaction not independently confirmed due to the pre-existing documented mobile-mcp swipe-simulation unreliability in this environment (see `ROADMAP.md` S87) — the technique itself is SwiftUI-standard and low-risk. | ✅ Parity (6 of 7 — "Continuous vertical" intentionally treated as identical to existing Webtoon mode, not duplicated) |
| Page Layout (double-page spreads) | Single / Double / Automatic, "Separate first page", "Invert double pages" [premium] | ✅ Fixed S98 — `pageLayout` = "single"/"double"/"automatic" (spreads in landscape, via a live `GeometryReader` width/height comparison). `MangaReaderView`'s `TabView` selection goes through a proxy `Binding` snapping any page index to its spread's start, so `currentPage` keeps its normal meaning everywhere else (progress/resume/scrubber). Tap zones move by whole spreads. "Separate first page"/"Invert double pages" not implemented (smaller Tachimanga-premium niceties, out of scope). Live-verified: single mode unregressed, double mode renders 2 pages side by side and advances 1→3→5. | ✅ Parity (core Single/Double/Automatic) |
| Tap zones | 5 presets: L-Shaped, Right-And-Left, Edge, Kindle-ish, Disabled | ✅ Fixed S98 — `tapZoneLayout` now has 6 presets: `default` (thirds, unchanged), `sides` (Edge, unchanged), plus new `lShaped`/`kindle`/`rightLeft`/`disabled`. New layouts are Yomi's own reasonable interpretation of the named behaviors (not pixel-verified against Tachimanga's exact zone geometry) — all share a fixed top-center menu strip for reachability. Still a plain Picker, no visual zone-diagram. | ✅ Parity (6 presets, superset of Tachimanga's 5) |
| Auto Webtoon detection | Not observed in Tachimanga's Reader settings | `autoWebtoonFromTags` — auto-switches by genre tags — `AppSettings.swift:203` | 🔷 Yomi ahead |
| Autoscroll | Toggle in in-reader settings sheet | `autoScrollSpeed` (1-10s) exists in `AppSettings.swift:242`, used in `ChapterReaderView.swift` | ✅ Parity |
| Keep screen on while reading | Listed toggle | `keepScreenOn` → `UIApplication.shared.isIdleTimerDisabled` — `ChapterReaderView.swift:136,143` | ✅ Parity |
| Double tap to zoom | Toggle | ✅ Fixed S98 — `MangaPageView`'s double-tap previously always reset to 1x (not a real zoom toggle); now toggles between 1x and 2x. | ✅ Parity |
| Press and hold to scroll | Toggle (Webtoon/Continuous only) | Not found | ❌ Missing |
| Long press action menu | Toggle | Not found | ❌ Missing |
| Show status bar when reading | Toggle | Not found (reader likely always hides status bar) | ❌ Missing (probably fine as-is, low priority) |
| Classic start reading button | Toggle | N/A — Yomi has no per-chapter splash screen at all (see §7) | N/A |
| Mouse wheel speed | Slider (Mac Catalyst/iPad trackpad support) | Not found | ❌ Missing — only matters if Yomi ever targets Catalyst/iPad; low priority |
| Strict scale | Toggle (restrict zoom to fixed range) | Not found | ❌ Missing, low priority |
| Reader scroll indicator | Toggle (Webtoon/Continuous) | Not found | ❌ Missing, low priority |
| Swipe right to go back | Always / Disable / Disable-in-horizontal | Not found as a setting (need to check default reader nav gestures) | ❌ Missing as a *setting* (may already work as default behavior — verify) |
| Skip duplicate chapters (scanlator dedup) | Toggle: "show only highest-priority scanlator per chapter" [premium] | No dedup logic found anywhere in chapter list loading | ❌ Missing |
| Image saved and shared with watermark | Toggle [premium] | Not applicable / not found | ❌ Missing, low priority (arguably skip — watermarking shared piracy-source images is a Tachimanga-specific choice, not obviously desirable for Yomi) |
| Side padding | Slider | `webtoonHorizontalPadding` (Webtoon only) `AppSettings.swift:247`; no equivalent for paged mode | 🟡 Partial |
| Crop borders | Toggle (in-reader settings) | Not found | ❌ Missing |
| Rotation | "Follow Device" setting | Not found (check if reader currently locks orientation) | ❌ Missing as explicit setting |

## 2. Browse / Sources

| Feature | Tachimanga | Yomi | Status |
|---|---|---|---|
| Source list (Last used / Pinned / by language) | Yes | Have Browse with installed sources — pinning/grouping not confirmed, needs check | 🟡 Needs live check |
| **Migrate tab** — move a library title from one source to another, preserving progress, with per-source match-count badges | Full dedicated tab under Browse | ✅ Fixed S98 — `MigrateView.swift`/`MigrationService.swift`, reachable from Browse's segmented control (Sources / Global search / **Migrate**). Picks a library manga, searches every other installed manga source in parallel with match-count badges, transfers reading status/notes/categories/per-chapter read-state (matched by chapterNumber) on migrate, with a replace-vs-keep-old-entry choice. Manga only (novels not covered). Live-verified end-to-end with real installed sources + direct DB inspection. | ✅ Parity |
| Cloudflare bypass | Automatic, global toggle, configurable timeout, request-dump debug log, applies to all source types uniformly | ✅ Fixed S97 — `NovelDetailView.swift` now has the same `cfBlockedURL`/`CFBypassView` wiring as `MangaDetailView.swift`. Also fixed a deeper bug found while verifying: the CF-detection heuristic in `JSBridge.swift` only matched 403 + "Just a moment"/"cf-mitigated", missing real-world variants like Cloudflare's 1015 rate-limit page — broadened to any error status + a wider marker list. Live-verified against FreeWebNovel's real Cloudflare block. Tachimanga's configurable-timeout + request-dump-log affordances are still not matched — tracked in §9. | ✅ Parity (core bypass), 🟡 partial on debug tooling |
| Extension repositories UI | Repo shown with URL, Copy/Discord buttons, "Add repository" (by URL or by name) | `SettingsView.swift:302-338` — text field for URL + link out to GitHub docs. No "by name" directory lookup, no per-repo Copy/Discord affordance shown for *installed* repos (only for adding new ones) | 🟡 Partial — functionally fine, less polished |
| Show NSFW extensions/sources toggle + disclaimer copy | Yes, with disclaimer that toggle doesn't fully prevent NSFW surfacing | `showNSFW` exists (`AppSettings.swift:80`), check if SettingsView copy includes the same disclaimer | 🟡 Needs copy check |

## 3. Library

| Feature | Tachimanga | Yomi | Status |
|---|---|---|---|
| Categories: create/rename/delete/reorder | Full CRUD | **Already fully implemented** — `Yomi/Features/Library/CategoryView.swift` (rename:116, delete:132, reorder:144), reachable via More → Categories | ✅ Parity (earlier draft of this audit wrongly called this missing — corrected) |
| Default category (Always ask / specific) | Yes | ✅ Fixed S98 — `defaultCategoryId` setting auto-assigns new library adds (manga + novel) to a chosen category. "Always ask" (an interactive picker sheet on every add) not implemented — judgment call to keep scope contained; "specific category" mode covers the common case. | 🟡 Partial (specific-category mode only, no "Always ask") |
| Show number of items (on category tabs) | Toggle | ✅ Fixed S98 — the backing query (`CategoryQueries.fetchItemCounts()`) already existed for More → Categories but was never wired into `LibraryView`'s tab bar; now toggleable via `showCategoryItemCounts`. | ✅ Parity |
| Display Mode (grid/list) | Yes | `libraryDisplayMode` — ✅ | ✅ Parity |
| Grid columns / items per row | Yes (stepper) | `libraryColumns` stepper in `AppearanceStudioView.swift:355` | ✅ Parity |
| Skip updating titles (completed / not-started / excluded categories) | Yes | `skipUpdateWithUnread/NotStarted/Completed`, `excludedCategoryIds` — full parity, `SettingsView.swift:221` → `UpdatesSettingsView` | ✅ Parity |
| Updates continue in background / Automatic refresh | Toggles | ✅ Fixed S101 — real `BGTaskScheduler` wiring (`com.yomi.refresh`), not just a UI toggle. See `CLAUDE.md` Known Issue #31. | ✅ Parity |
| **Global Update** (force-refresh all sources) | Yes, top-level Library long-press action | ✅ Already existed — `UpdatesViewModel.refresh()` (`UpdatesView.swift:117`) checks every manga+novel in the library in parallel via `TaskGroup`, triggered by the refresh icon in Updates' toolbar or pull-to-refresh. Different entry point (Updates tab vs. Library context menu) but functionally equivalent. Corrected from an earlier draft of this audit that wrongly called it missing. | ✅ Parity |
| **Updates Summary** (info sheet on last global update) | Yes | ✅ Fixed S97 — `refresh()` now returns the count of newly-discovered chapters (diffing chapter-id sets before/after); `UpdatesView` shows a "N new chapters found" / "No new chapters" toast for 2s after any manual or pull-to-refresh. Live-verified rendering (temporarily extended the dismiss timer to confirm the toast text/style, then restored it). | ✅ Parity |
| **Open random entry** | Yes | ✅ Already existed — the Shuffle toolbar icon in `LibraryView.swift:310-320` jumps to a random manga. Scoped to manga only (not novels) and unconditional (not filtered to unread) — minor gap vs. Tachimanga's version, not worth a separate fix. Corrected from an earlier draft of this audit that wrongly called it missing. | ✅ Parity (manga only) |
| Multi-select / bulk actions | Long-press → Select | ✅ Fixed S96, works via context menu | ✅ Parity |
| List-mode multi-select | — | Known gap noted in Known Issue #19 — list mode has no selection entry point yet | ❌ Still open (pre-existing Yomi gap, not Tachimanga-specific) |
| Per-card reading-status quick-set | Not observed in Tachimanga screenshots | `LibraryView.swift:764` context menu → Reading Status submenu | 🔷 Yomi ahead (unconfirmed Tachimanga doesn't have this — verify before crowing) |

## 4. History / Updates / Downloads

| Feature | Tachimanga | Yomi | Status |
|---|---|---|---|
| History row shape (cover, chapter, time-spent, relative date, delete) | Yes | Near-identical, `HistoryView.swift` (S91) | ✅ Parity |
| Downloads: per-manga row, byte size, delete-all | Yes | ✅ (S93) | ✅ Parity |
| Downloads: active queue with speed + progress + Pause | "Pause" button shown live | Yomi's `DownloadManager.swift` only has `cancel(chapterId:)` — **no true pause/resume**, deliberate judgment call from S93 (rendered as ✕ instead of implying a capability that doesn't exist) | 🟡 Partial — real pause/resume would need actual implementation, not just a relabeled button |
| Concurrent downloads setting | Yes [premium] | `concurrentDownloads` (1-5), exposed via `stepperPill` in `SettingsView.swift:216` | ✅ Parity (and free, where Tachimanga gates it) |
| Background Download toggle | Yes [premium] | ✅ Fixed S101 (and free, where Tachimanga gates it) — gated on the auto-refresh toggle above; auto-enqueues newly-discovered manga chapters. See `CLAUDE.md` Known Issue #32. | ✅ Parity (free) |
| Delete download after reading | Yes [premium] | `deleteDownloadAfterReading` — `SettingsView.swift:209` | ✅ Parity (free) |
| Reading Insights | Flat per-title bar-chart ranking, total hours, quote | GitHub-style contribution heatmap + streak + Most-Read list (S94) | 🔷 Yomi ahead — different approach, arguably more distinctive; not a gap |

## 5. Backup / Sync

| Feature | Tachimanga | Yomi | Status |
|---|---|---|---|
| Export/import own-format backup | Yes | ✅ `BackupView.swift` export/import sections | ✅ Parity |
| **Import** Tachiyomi/Mihon `.tachibk` | Yes | ✅ `TachiyomiBackupParser.swift`, wired in `BackupView.swift` | ✅ Parity |
| **Export/create** a Tachiyomi-compatible backup (for migrating *out* to Tachiyomi/Mihon/forks) | Yes [premium] | Not found — Yomi's export is Yomi-format only, one-way interop | ❌ Missing (low priority — mostly matters for user trust/no-lock-in messaging, not day-to-day use) |
| Automatic backup scheduling (frequency picker) | Yes, explicit frequency setting [premium], defaults Off | Yomi's iCloud auto-backup fires on every app background, no frequency picker | 🔷 Yomi ahead in default behavior, 🟡 missing the configurability |
| iCloud backup toggle + last-synced | Yes [premium] | ✅ `iCloudAutoBackup`, `BackupManager.swift` | ✅ Parity (free) |
| Dated backup list (multiple retained backups, sizes, per-entry menu) | Yes — shows 3+ dated entries with sizes | ✅ Fixed S108 — `BackupManager.swift` now writes timestamped files (`YomiBackup-<ISO8601>.json`) into the iCloud container instead of overwriting one fixed name, keeps the last 8, and `BackupView.swift`'s iCloud section is a real list (date + byte size, swipe-to-delete, tap-to-restore-that-entry) instead of a single date row. **Not live end-to-end verified** — the dev simulator's iCloud session had lapsed (needs password re-auth) this session; code review + zero-warning build only, matches the previously-working single-file pattern. | ✅ Parity (live round-trip unverified) |
| Full-app data sync across devices (library, history, bookmarks, repos, extensions) with in-app explainer copy | Yes, detailed explainer screen | ✅ Implemented S103 — `CloudSyncManager.swift`/`CloudSyncView.swift`, library+progress+categories sync via CKSyncEngine (repos/extensions intentionally excluded, each device installs its own plugins independently). Not yet verified against a real signed-in iCloud account — see `CLOUDKIT_SYNC_DESIGN.md`. | ✅ Parity (verification pending) |

## 6. Security / Privacy

| Feature | Tachimanga | Yomi | Status |
|---|---|---|---|
| App lock (biometric/passcode on foreground) | Yes [premium] | ✅ `AppLockView.swift` + `appLockEnabled`, wired in `YomiApp.swift` via `scenePhase` | ✅ Parity (free, where Tachimanga gates it) — but **cosmetic gap**: `AppLockView.swift` uses plain `Color(.systemBackground)`/system font, never restyled to the Ink/Space-Grotesk design system (predates S79 redesign) |
| Incognito mode (pause history) | Yes [premium] | ✅ `isIncognito` | ✅ Parity (free) |
| **Secure screen** (hide content in app switcher / on lock) | Yes [premium] | ✅ Fixed S97 — `AppSettings.secureScreenEnabled` + a `SecureScreenCover` overlay in `YomiApp.swift`, shown whenever `scenePhase != .active` (covers the App Switcher snapshot and any other non-active transition). Free, on-brand (Ink canvas + app icon), toggle in Settings next to App Lock. Live-verified: toggle persists, app backgrounds/resumes cleanly with no crash. | ✅ Parity (free, where Tachimanga gates it) |

## 7. Reader chapter-open experience

| Feature | Tachimanga | Yomi | Status |
|---|---|---|---|
| Stylized "Current: Chapter N" splash before the reader loads (art + scanlator credit/links) | Yes | Not found — Yomi opens straight into pages | ❌ Missing — cosmetic flair, arguably adds friction; low priority, judgment call |
| In-reader header shows source URL + external-link/globe icons | Yes | ✅ Fixed S101 — best-effort (no plugin changes): resolves for ~7 of 15 plugins + Mangayomi-format sources, hides the icon rather than guessing for pure-API sources. See `CLAUDE.md` Known Issue #33. | 🟡 Partial (works for most, not all, sources) |
| Continuous/webtoon-reader chapter-boundary transition — in-scroll "Finished: Chapter N / Current: Chapter N+1" banner + chapter title card, then flows straight into the next chapter's pages with no tap and without leaving the reader (S108: Martin sent 3 real screenshots of this from Tachimanga/AsuraScans) | Yes | ✅ Built S109 — `ChapterBoundaryCard` + background next-chapter preload in `ChapterReaderView.swift` (Webtoon + Continuous LTR/RTL only, matches Tachimanga's scope). Found+fixed a real CPU-hang bug in the preload's blocking fetch along the way (12s timeout added). CPU-behavior fix verified live; the card's on-screen appearance/crossing itself blocked from live pixel-verification by this environment's mobile-mcp swipe tooling (see `CLAUDE.md`/`ROADMAP.md` S109) — re-verify on a real device before trusting fully. | 🟡 Built, not yet visually confirmed |

## 8. Appearance

| Feature | Tachimanga | Yomi | Status |
|---|---|---|---|
| Theme presets (Default/Green Apple/Lavender/…) | Fixed preset list [some premium] | Canvas (Ink/Midnight/Paper/Sepia) × free-form accent `ColorPicker` — `AppearanceStudioView.swift` | 🔷 Yomi ahead — more flexible (any accent color vs fixed preset palettes) |
| Liquid glass toggle | Optional toggle | Yomi's Liquid Glass is baked into the design system everywhere, not optional | 🔷 Different by design, not a gap — flag if Martin wants an "off" switch for accessibility/performance |
| Pure black (OLED) dark mode | Yes [premium] | ✅ `pureBlack` — `SettingsView.swift:231` | ✅ Parity (free) |
| Color blend level (slider blending accent into surfaces) | Yes | ✅ Fixed S108 — new `AppSettings.colorBlendLevel` + `Color.mix(with:amount:)`, blends `bg`/`surface1`/`surface2` toward the accent (text/hairline untouched). Wired app-wide via `\.yomiCanvas` (`ContentView.swift`'s `blendedCanvasColors`, not the raw preset) and into Appearance Studio's live preview. Live-verified at 60% on Paper: visibly tints the whole app, and the existing AA contrast badge correctly drops to "Fail" — the slider surfaces the tradeoff instead of hiding it, consistent with S101's precedent. | ✅ Parity |
| App icon picker | Yes [premium] | ✅ `alternateIconName`, Ink/Paper icons | ✅ Parity (free) |
| Items per row | Stepper | ✅ `libraryColumns` | ✅ Parity |
| Rotation ("Follow Device") | Setting | Not found | ❌ Missing |
| Date format picker | Setting | ✅ Fixed S108 — new `AppSettings.use24HourClock`/`dateOrderDayFirst`, threaded as parameters into `Notation.historyTimestamp(_:use24Hour:dayFirst:)` (kept as parameters, not a direct `AppSettings.shared` read, since `Notation` is `nonisolated` per S91). Settings → General, two toggles. Live-verified both axes via seeded `lastReadAt` rows in History (today + >7-days-old): "20:30"↔"8:30 PM" and "JUL 20"↔"20 JUL". | ✅ Parity |

## 9. General / Advanced / Storage

| Feature | Tachimanga | Yomi | Status |
|---|---|---|---|
| Customize Tabs (reorder/hide bottom tabs) | Yes [premium] | ✅ Built S109 — new `CustomizeTabsView.swift` (drag-to-reorder + toggle-to-hide, "More" locked visible), `AppSettings.tabOrder`/`hiddenTabIDs`, `ContentView.swift` rebuilt to construct `Tab`s dynamically via `ForEach` (S108 had root-caused *why* Apple's own sidebar-editing UI never renders on iPhone — see S108 entry below). Reachable from Settings → Library → "Customize tabs". App launch with the default 5-tab order confirmed live; the reorder/toggle UI itself wasn't pixel-verified this session (mobile-mcp swipe tooling couldn't scroll far enough down Settings to reach it — see `CLAUDE.md` S109). | 🟡 Built, not yet visually confirmed |
| Default tab (which tab opens on launch) | Yes | ✅ Fixed S98 — `defaultTab` setting, wired into `AppRouter.init()`. | ✅ Parity |
| **Storage composition view** (visual bar: cache/sources/downloads/backups/other, each with size + Manage/Clear) | Yes, detailed | ✅ Fixed S98 — `StorageManager.swift`/`StorageView.swift`, reachable from Advanced → Storage. Real byte-accurate breakdown (Downloads/Image cache/Plugins/Custom covers/Web cache/Database/Other) with Manage/Clear actions per category. | ✅ Parity |
| Network settings: user agent, timeout | Shown, editable, plus CF-bypass toggle + request-dump | ✅ Partially fixed S98 — request timeout (10-60s) now editable in Advanced → Network. User Agent deliberately stays fixed: it's bound to the Cloudflare-bypass WebView's solved-challenge cookie (`CFBypassConstants.userAgent`, shared with `JSBridge`'s fetch) — making it editable would risk silently breaking CF bypass for a control most users would never touch. Request-dump debug log not implemented. | 🟡 Partial (timeout editable, UA intentionally fixed, no request-dump) |
| Repair Database | Yes | Not found (Yomi has DB migrations but no user-facing repair action) | ❌ Missing, low priority unless corruption reports come in |
| Enable log / Export log / HTTP request dump | Yes, toggleable | Yomi has one-shot "Export diagnostic log" only — no persistent logging toggle, no HTTP dump | 🟡 Partial |

---

## Summary: real, actionable gaps (excluding low-priority/cosmetic items)

**Status as of S98 (2026-08-06): every item explicitly called out below as high-value is shipped.**
Items 1-6 (original ordering) are all done — Cloudflare bypass (S97), reading modes + double-page
spreads (S97 + S98), Secure screen (S97), Storage composition view (S98), Migrate tab (S98), Global
Update/Updates Summary/Open random entry (S97, turned out already-implemented). Remaining open items,
roughly in order of expected value:

1. **Full multi-device sync** (vs today's iCloud backup-on-background) — the biggest lift by far.
   ✅ Scoped S102, implemented S103 — see `Yomi/CLOUDKIT_SYNC_DESIGN.md` and `Yomi/ROADMAP.md`'s S103
   entry. `CKSyncEngine`, sync on foreground/background, metadata + reading-state only (no files).
   **Not yet verified against a real signed-in iCloud account** (dev simulator has none) — next
   session touching this feature should do that verification pass first.
2. ~~**Dated backup list**~~ ✅ Fixed S108, live round-trip unverified (iCloud session lapsed on dev sim).
3. **Tachiyomi-compatible *export*** (for migrating out to Tachiyomi/Mihon/forks) — low priority,
   mostly a trust/no-lock-in signal rather than day-to-day utility.
4. ~~**Color blend slider**~~ ✅ Fixed S108, live-verified. ~~**Date format picker**~~ ✅ Fixed S108,
   live-verified. ~~**Customize Tabs**~~ ✅ Built S109 (see §9 above) — not yet visually confirmed,
   mobile-mcp swipe tooling couldn't reach the row this session; re-verify on a real device.
5. ~~**Continuous-reader chapter-boundary transition**~~ ✅ Built S109 (see §7 above) — CPU-hang bug
   found+fixed in the preload, that fix verified; the card's on-screen appearance not yet visually
   confirmed, same mobile-mcp swipe-tooling block; re-verify on a real device.
6. Cosmetic/low-priority items scattered through the tables above (AppLockView's pre-S79 styling,
   reader chapter-open splash screen, crop borders, press-and-hold-to-scroll, scanlator dedup, etc.) —
   pick up opportunistically, not worth a dedicated pass.

**Not recommended to copy:** Tachimanga's premium/paywall model itself (not relevant — Yomi has no
monetization here), and the "watermark on shared images" feature (not clearly desirable).

**S99 addendum**: a full project audit (code/docs/live-testing/App-Store-readiness, see `CLAUDE.md`
Known Issues rows 24-36 and `ROADMAP.md`'s S99 entry) resolved 3 of this doc's "needs check" rows to
confirmed-missing (background auto-refresh toggle, background download toggle, in-reader source-URL
icon — all small, none re-prioritized above item 4). The audit also surfaced items outside this doc's
scope entirely (stale age-rating declaration, an OPDS credential-storage inconsistency, silent DB-write
failures, an unresolved AquaManga reader-page render bug) — those live only in `CLAUDE.md`'s Known
Issues table, not here, since they aren't Tachimanga-parity items.

**S100 addendum**: worked through the S99 audit's Known Issues backlog (rows 24-30, 25, 26, 34, 35 —
age rating, doc cleanup, OPDS→Keychain, silent-failure toasts, the AquaManga reader-page bug, and
list-mode multi-select — all fixed, see `CLAUDE.md`). Martin made an explicit scope call on the 3 items
this doc flagged confirmed-missing above (background auto-refresh toggle, background download toggle,
in-reader source-URL icon): these are genuine new features, not bugs, and were deliberately **not**
built this session — left here as the backlog for a future dedicated feature pass, same treatment as
item 1 (multi-device sync).

**S101 addendum**: all 3 items S100 deferred are now shipped (rows updated above to ✅/🟡; see
`CLAUDE.md` Known Issues #31-33 and `ROADMAP.md`'s S101 entry for full detail). Item 1 (multi-device
sync) remains the only big item left in this doc, still needing its own architecture-scoping session.
