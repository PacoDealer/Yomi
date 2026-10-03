# Tooling notes (moved from CLAUDE.md, S137)

Verbatim copy of the old CLAUDE.md sections: MCP tools, mobile-mcp quirks (S98/S99/S111), research rule,
full key-file-path table, build command, dev tooling (SwiftLint/fastlane/jscpd/Pulse), App Store pointer.
Some details are older than S137 — verify before relying on them.

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

**New tooling note (S111):** a third, distinct issue — `mobile_set_orientation` can leave its
internal orientation state desynced from the simulator's actual rendered orientation after testing a
rotation-lock feature. `mobile_get_orientation` kept reporting `landscape` well after screenshots
clearly showed portrait, and every tap during that window landed on a plausible-but-wrong element
with no error. Re-issuing `mobile_set_orientation` (portrait, then landscape again) forced a fresh
read and fixed it. If taps start landing on wrong-but-plausible elements for no clear reason, check
`mobile_get_orientation` first — especially after any orientation-related testing earlier in session.

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
- Next migration prefix must be `v23_` (v22_novel_chapter_unread_index added in S120 — `idx_novel_chapter_unread` on `novel_chapter(novelId, isRead)`, see Known Issue #144)
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
Yomi/Database/DatabaseManager.swift            # Migrations v1–v21_cloud_sync_pending; next must be v22_
Yomi/Sync/CloudSyncManager.swift               # CKSyncEngine + delegate; CloudRecordType; module-level markCloudDirty()/markCloudDeleted() called from *Queries writes
Yomi/Features/More/CloudSyncView.swift         # Settings → More → Sync UI (toggle + status row), distinct from BackupView
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
Yomi/Features/Reader/TextReaderView.swift      # Novel reader; overlay opacity animation; dynamic colorScheme (sepia/dark/light); chapterContentCache preload
Yomi/Features/More/MangaTracker.swift          # Shared protocol every tracker conforms to (authURL/handleCallback/searchManga/updateProgress/logout/isLoggedIn)
Yomi/Features/More/TrackerManager.swift        # Tracker registry (loggedInTrackers) + OAuth-callback router by host, called from ContentView's one .onOpenURL
Yomi/Features/More/MALService.swift            # PKCE OAuth, no client_secret needed
Yomi/Features/More/AniListTrackerService.swift # Implicit Grant OAuth, no client_secret — distinct from the unrelated Extensions/AniListService.swift score actor
Yomi/Features/More/ShikimoriService.swift      # Authorization Code Grant, requires client_secret; shikimori.io (not .one, which redirects)
Yomi/Features/More/BangumiService.swift        # Authorization Code Grant, requires client_secret; OAuth on bgm.tv, REST on api.bgm.tv
Yomi/Features/More/TrackersView.swift          # More → Trackers: auto-update toggle + all 4 tracker connect rows
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

## Dev tooling (added 2026-08-14, commit `2e22ad4`)

- **SwiftLint** (`.swiftlint.yml` at repo root) — CLI-only, not wired into the Xcode build. Run
  `swiftlint lint` manually or via `/code-review`. Baseline as of 2026-08-14 was 909 findings,
  unremediated — check current count before assuming it's clean.
- **fastlane** (`Gemfile` + `fastlane/Fastfile`) — `fastlane build` wraps the documented
  `xcodebuild` command above and works today. `fastlane beta`/`fastlane release` are stubs that
  `UI.user_error!` until `fastlane/Appfile`'s `apple_id`/`team_id` are filled in — no credentials
  exist yet. No UI Test target, so no `screenshots` lane either (add one first).
- **jscpd** (`.jscpd.json`) — copy-paste detector, report-only (`threshold: 100`, never fails a
  build). Run via `npx jscpd .`. Baseline 2026-08-14: 5.6% duplication / 104 clones.
- **Pulse network logging** — `Pulse`/`PulseUI` SPM deps on the main app target (not YomiWidget),
  DEBUG-only. `Yomi/Core/NetworkLogging.swift` exports `yomiLogNetwork(_:response:data:error:)`,
  called manually after each real fetch (`JSBridge`'s plugin scraper, MAL/Suwayomi/OPDS/AniList
  services, extension install, plugin catalog fetch) instead of Pulse's `URLSessionProxy` —
  that type is `@MainActor`, which would force an actor hop into the `nonisolated`/`Task.detached`/
  custom-actor call sites this project actually has. View captured traffic live at
  **Settings → Advanced → Network Console**. Not covered: `DownloadManager`'s concurrent
  page-download loop (deliberately skipped, high volume/low value) and CloudKit sync traffic
  (`CKSyncEngine` isn't URLSession-based, needs separate instrumentation if ever wanted).
- **ccusage**, **git-safety.sh blocking upgrade**, **agnix** — global Claude Code tooling, not
  Yomi-specific; see `~/.claude` memory (`project_toolbox_audit`) if relevant here.

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
