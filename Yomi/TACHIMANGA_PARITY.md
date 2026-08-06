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
| Page Layout (double-page spreads) | Single / Double / Automatic, "Separate first page", "Invert double pages" [premium] | No concept of double-page spreads anywhere in `ChapterReaderView.swift` | ❌ Missing entirely |
| Tap zones | 5 presets: L-Shaped, Right-And-Left, Edge, Kindle-ish, Disabled | 3: `tapZoneLayout` = "default" (thirds) / "sides" (20%/60%/20%) / "disabled" — `ChapterReaderView.swift:392-430` | 🟡 Partial — fewer presets, no visual zone-diagram picker (Tachimanga's dialog shows named layouts, Yomi's `SettingsView.swift:414` is a plain Picker) |
| Auto Webtoon detection | Not observed in Tachimanga's Reader settings | `autoWebtoonFromTags` — auto-switches by genre tags — `AppSettings.swift:203` | 🔷 Yomi ahead |
| Autoscroll | Toggle in in-reader settings sheet | `autoScrollSpeed` (1-10s) exists in `AppSettings.swift:242`, used in `ChapterReaderView.swift` | ✅ Parity |
| Keep screen on while reading | Listed toggle | `keepScreenOn` → `UIApplication.shared.isIdleTimerDisabled` — `ChapterReaderView.swift:136,143` | ✅ Parity |
| Double tap to zoom | Toggle | Not found — check pinch/zoom gesture support in reader | ❌ Likely missing (needs live check) |
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
| **Migrate tab** — move a library title from one source to another, preserving progress, with per-source match-count badges | Full dedicated tab under Browse | No migration feature anywhere in codebase | ❌ Missing entirely — real gap, meaningful for source churn (sources die/get CF-blocked often, per Yomi's own Known Issues) |
| Cloudflare bypass | Automatic, global toggle, configurable timeout, request-dump debug log, applies to all source types uniformly | ✅ Fixed S97 — `NovelDetailView.swift` now has the same `cfBlockedURL`/`CFBypassView` wiring as `MangaDetailView.swift`. Also fixed a deeper bug found while verifying: the CF-detection heuristic in `JSBridge.swift` only matched 403 + "Just a moment"/"cf-mitigated", missing real-world variants like Cloudflare's 1015 rate-limit page — broadened to any error status + a wider marker list. Live-verified against FreeWebNovel's real Cloudflare block. Tachimanga's configurable-timeout + request-dump-log affordances are still not matched — tracked in §9. | ✅ Parity (core bypass), 🟡 partial on debug tooling |
| Extension repositories UI | Repo shown with URL, Copy/Discord buttons, "Add repository" (by URL or by name) | `SettingsView.swift:302-338` — text field for URL + link out to GitHub docs. No "by name" directory lookup, no per-repo Copy/Discord affordance shown for *installed* repos (only for adding new ones) | 🟡 Partial — functionally fine, less polished |
| Show NSFW extensions/sources toggle + disclaimer copy | Yes, with disclaimer that toggle doesn't fully prevent NSFW surfacing | `showNSFW` exists (`AppSettings.swift:80`), check if SettingsView copy includes the same disclaimer | 🟡 Needs copy check |

## 3. Library

| Feature | Tachimanga | Yomi | Status |
|---|---|---|---|
| Categories: create/rename/delete/reorder | Full CRUD | **Already fully implemented** — `Yomi/Features/Library/CategoryView.swift` (rename:116, delete:132, reorder:144), reachable via More → Categories | ✅ Parity (earlier draft of this audit wrongly called this missing — corrected) |
| Default category (Always ask / specific) | Yes | Not found | ❌ Missing |
| Show number of items (on category tabs) | Toggle | Not found — Yomi's category tabs (`LibraryView.swift:491+`) don't show counts | ❌ Missing |
| Display Mode (grid/list) | Yes | `libraryDisplayMode` — ✅ | ✅ Parity |
| Grid columns / items per row | Yes (stepper) | `libraryColumns` stepper in `AppearanceStudioView.swift:355` | ✅ Parity |
| Skip updating titles (completed / not-started / excluded categories) | Yes | `skipUpdateWithUnread/NotStarted/Completed`, `excludedCategoryIds` — full parity, `SettingsView.swift:221` → `UpdatesSettingsView` | ✅ Parity |
| Updates continue in background / Automatic refresh | Toggles | Present per Tachimanga screenshot; Yomi equivalent not fully confirmed — needs check | 🟡 Needs check |
| **Global Update** (force-refresh all sources from a context menu) | Yes, top-level long-press action | Not found | ❌ Missing |
| **Updates Summary** (info sheet on last global update) | Yes | Not found | ❌ Missing |
| **Open random entry** | Yes | Not found | ❌ Missing (small, delightful, cheap to add) |
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
| Background Download toggle | Yes [premium] | Not found as an explicit toggle — check whether downloads already continue in background by OS default | 🟡 Needs check |
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
| Dated backup list (multiple retained backups, sizes, per-entry menu) | Yes — shows 3+ dated entries with sizes | Yomi shows only a single "last backup date," no retained history list | ❌ Missing |
| Full-app data sync across devices (library, history, bookmarks, repos, extensions) with in-app explainer copy | Yes, detailed explainer screen | Not found — Yomi has iCloud *backup*, not live multi-device *sync* | ❌ Missing — bigger feature, real architecture decision (CloudKit sync engine), not a quick add |

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
| In-reader header shows source URL + external-link/globe icons | Yes | Needs check | 🟡 Needs check |

## 8. Appearance

| Feature | Tachimanga | Yomi | Status |
|---|---|---|---|
| Theme presets (Default/Green Apple/Lavender/…) | Fixed preset list [some premium] | Canvas (Ink/Midnight/Paper/Sepia) × free-form accent `ColorPicker` — `AppearanceStudioView.swift` | 🔷 Yomi ahead — more flexible (any accent color vs fixed preset palettes) |
| Liquid glass toggle | Optional toggle | Yomi's Liquid Glass is baked into the design system everywhere, not optional | 🔷 Different by design, not a gap — flag if Martin wants an "off" switch for accessibility/performance |
| Pure black (OLED) dark mode | Yes [premium] | ✅ `pureBlack` — `SettingsView.swift:231` | ✅ Parity (free) |
| Color blend level (slider blending accent into surfaces) | Yes | Not found | ❌ Missing, low priority |
| App icon picker | Yes [premium] | ✅ `alternateIconName`, Ink/Paper icons | ✅ Parity (free) |
| Items per row | Stepper | ✅ `libraryColumns` | ✅ Parity |
| Rotation ("Follow Device") | Setting | Not found | ❌ Missing |
| Date format picker | Setting | Not found — `Notation.swift` formats are presumably hardcoded | ❌ Missing, low priority |

## 9. General / Advanced / Storage

| Feature | Tachimanga | Yomi | Status |
|---|---|---|---|
| Customize Tabs (reorder/hide bottom tabs) | Yes [premium] | Not found — fixed 6-tab `TabView` | ❌ Missing |
| Default tab (which tab opens on launch) | Yes | Not found | ❌ Missing, easy add |
| **Storage composition view** (visual bar: cache/sources/downloads/backups/other, each with size + Manage/Clear) | Yes, detailed | `AdvancedSettingsView.swift` only has undifferentiated "Clear image cache / Clear plugin catalog cache / Clear WebView cookies" buttons — no sizes shown at all, no visual breakdown. `DownloadManager.directorySize(mangaId:)` exists but is only used per-manga in Downloads, never aggregated | ❌ Real gap — Tachimanga's storage screen is genuinely more transparent |
| Network settings: user agent, timeout | Shown, editable, plus CF-bypass toggle + request-dump | `AdvancedSettingsView.swift` shows User Agent / timeout as **hardcoded read-only text** ("fixed in this version") | 🟡 Partial — Yomi under-exposes control here vs Tachimanga |
| Repair Database | Yes | Not found (Yomi has DB migrations but no user-facing repair action) | ❌ Missing, low priority unless corruption reports come in |
| Enable log / Export log / HTTP request dump | Yes, toggleable | Yomi has one-shot "Export diagnostic log" only — no persistent logging toggle, no HTTP dump | 🟡 Partial |

---

## Summary: real, actionable gaps (excluding low-priority/cosmetic items)

Roughly in order of expected value to Yomi, not yet a commitment to sequence — for discussion:

1. **Cloudflare bypass missing from the novel path** (`NovelDetailView.swift`) — this isn't just
   parity, it's an existing open bug (Known Issue #11) that Tachimanga's architecture happens to
   avoid by applying bypass uniformly. Fixing this unblocks real broken sources today.
2. **More reading modes** (continuous LTR/RTL/vertical, paged-vertical) + **double-page spread
   support** — meaningful reader-completeness gap, likely to matter to manga readers specifically.
3. **Secure screen** (app-switcher content blur) — cheap, real privacy win given the app's content.
4. **Storage composition view** — cheap-ish (the byte-counting primitive already exists via
   `DownloadManager.directorySize`), meaningfully more transparent than today's undifferentiated
   clear-cache buttons.
5. **Migrate tab** (source-to-source library migration) — bigger feature, valuable given how often
   Yomi's own sources go down/get Cloudflare-blocked (see Known Issues table).
6. **Global Update / Updates Summary / Open random entry** — small, cheap, rounds out Library.
7. **Full multi-device sync** (vs today's iCloud backup-on-background) — the biggest lift by far,
   real architecture decision (CloudKit or similar), should be scoped separately if wanted at all.
8. Everything else in the tables above (tap-zone presets, category default/count-toggle, Tachiyomi
   *export*, dated backup list, customize tabs, default tab, network settings exposure, reader gesture
   settings) — smaller, mostly additive, can slot in around the above.

**Not recommended to copy:** Tachimanga's premium/paywall model itself (not relevant — Yomi has no
monetization here), and the "watermark on shared images" feature (not clearly desirable).

Next step: confirm priority/order above, then work through them as normal Yomi sessions (one or a
few related items per session, live-verified via `build_run_sim` + mobile-mcp per this project's
established methodology) — not a single mega-session.
