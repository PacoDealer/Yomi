# Yomi — Claude Code Project Context

## What this app is
iOS manga, manhwa, manhua, and light novel reader. Plugin-based architecture:
JS plugins run in JavaScriptCore. Two plugin formats: Format A (manga) and Format B (LNReader/novels).
Firebase CDN hosts all 8 production plugins. App binary ships zero plugin files (App Store compliance).

## Tech stack
- **Swift + SwiftUI — iOS 26.2 deployment target. No iOS 18 fallbacks. Ever.**
- GRDB for SQLite (NOT SwiftData)
- JavaScriptCore for plugin execution
- Firebase Hosting: https://yomi-plugins.web.app

## Project path
`/Users/martingamberg/Projects/Yomi/iOS`

## Key docs (read these at session start)
- `Yomi/ROADMAP.md` — current state, planned work, tech debt
- `Yomi/ARQUITECTURA.md` — full architecture, data flows, DB schema
- `Yomi/METODOLOGIA.md` — workflow rules, tech learnings per session
- `Yomi/RESEARCH.md` — master research doc (competitive, UX, App Store, iOS 26, plugins, architecture)

## Current state (post S38 — 2026-04-19)

S38 = 9 UX features shipped (Tachimanga parity blitz). All 9 items implemented, built, and pushed.

**S38 shipped:**
1. Auto-detect webtoon from tags — ChapterReaderView.init checks genres for manhwa/manhua/long strip → `.verticalScroll`
2. Hold-to-scroll in WebtoonReaderView — long-press toggles `.task(id:)` async auto-scroll loop
3. Delete download after reading — `AppSettings.deleteDownloadAfterReading` (default true), captured before Task.detached
4. Concurrent downloads — `AppSettings.concurrentDownloads` (1–5, default 3), used in DownloadManager
5. Smart update skip conditions — 3 AppSettings booleans, early returns in `checkUpdates(for:)`
6. Excluded categories from updates — `AppSettings.excludedCategoryIds`, `ExcludedCategoriesView` in SettingsView.swift
7. Chapter sort by name — `ChapterSortOption` enum, sort Menu in chapter section header
8. Random entry — shuffle toolbar button in LibraryView, `navigationDestination(isPresented:)` (Manga is not Hashable)
9. Text selection — `.textSelection(.enabled)` on synopsis in MangaDetailView + NovelDetailView

**App Store status:** Deferred. User not enrolled in Apple Developer Program yet.

## Known issues / carry-forward

| # | Issue | Notes |
|---|-------|-------|
| 1 | Firebase deploy pending | novelfull.js + updated index.json not yet live. Run: `firebase login --reauth && firebase deploy --only hosting` in `~/Projects/Yomi/Firebase` |
| 2 | Chapters from Browse (partial) | Defensive fixes in S37. Root cause unconfirmed — needs live device test. |
| 3 | App icon missing | User designing — 3-layer PNG for iOS 26 Icon Composer. |
| 4 | Alternate icons need Xcode step | Drop PNGs into appiconsets + add `CFBundleAlternateIcons` in Xcode Target → Info. |
| 5 | App Store deferred | Age rating 18+, description, screenshots pending. |

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

## ABSOLUTE RULES — never violate

### Swift 6 + concurrency
- All `*Queries` methods must be `nonisolated`
- All JSBridge calls must be `Task.detached(priority: .userInitiated)` — never call from MainActor (SOURCE.fetch blocks with DispatchSemaphore)
- Deliver results via `await MainActor.run { state = result }`
- `appDatabase` is `nonisolated(unsafe) var` at module level — never wrap in an actor
- `ExtensionManager.shared` is MainActor-isolated — capture a local closure before entering Task.detached

### File editing
- **Always read the target file before editing it.** Never write against assumptions.
- **When replacing an entire file: explicitly check what the new file omits vs the current file.** Silent deletion of existing logic is the #1 source of regressions (OnboardingView, markRead() both dropped this way in S21).
- One file at a time. Compile after each new file.
- Never create a file that isn't strictly required.

### GRDB
- Next migration prefix must be `v12_` (v11_ used for novel_reading_status in S33)
- `nonisolated` on all `*Queries` static methods
- Use `_ = try appDatabase.write { ... }` to silence unused result warning
- `appDatabase.read` from `@MainActor` context requires `try await`
- **INSERT OR IGNORE pattern**: `try ch.insert(db, onConflict: .ignore)` — never use `ch.save(db)` for chapter list persistence (save = INSERT OR REPLACE which overwrites existing read/download state)

### iOS 26 patterns
- TabView: `Tab("title", systemImage:) {}` — `.tabItem {}` renders nothing in iOS 26
- `Text + Text` is deprecated — use `Text("\(Text(…)) …")` interpolation
- `.tint()` and `.preferredColorScheme()` go on `ContentView()` inside WindowGroup, NOT on WindowGroup/Scene itself
- `@Observable` singletons in App structs require `@State` to drive re-evaluation (not just `AppSettings.shared.property`)

### Plugin system
- Never build `JSBridge(scriptURL: ext.sourceListURL)` — URL in DB goes stale. Always reconstruct from `FileManager` + `ext.id`
- `JSBridge` is per-extension, never shared between concurrent tasks
- `#if DEBUG seedBundledPlugins()` in `YomiApp.init()` — never in release

## Key file paths
```
Yomi/AppSettings.swift                         # @Observable singleton, UserDefaults, 16 props (incl. libraryColumns, keepScreenOn, isIncognito, showUnreadBadge)
Yomi/ContentView.swift                         # Root TabView with AppRouter binding
Yomi/YomiApp.swift                             # Entry point, DB setup, #if DEBUG seed, .tint + .preferredColorScheme on ContentView
Yomi/Core/AppRouter.swift                      # @Observable, module-level appRouter var
Yomi/Core/Color+Hex.swift                      # Color(hex:) init + Color.hexString
Yomi/Core/NotificationManager.swift
Yomi/Database/DatabaseManager.swift            # Migrations v1–v8_last_page; next must be v9_
Yomi/Database/Queries/MangaQueries.swift
Yomi/Database/Queries/ChapterQueries.swift     # insertAllIgnoringConflicts (INSERT OR IGNORE — safe bulk persist, called from loadChapters)
Yomi/Database/Queries/CategoryQueries.swift
Yomi/Database/Queries/NovelQueries.swift       # fetchLibrary() EXISTS but is never called by LibraryViewModel
Yomi/Database/Queries/ExtensionQueries.swift
Yomi/Features/Extensions/JSBridge.swift        # JavaScriptCore bridge, shims, require(), getLatestManga(), supportsLatest
Yomi/Features/Extensions/ExtensionManager.swift
Yomi/Features/Extensions/PluginCatalogService.swift
Yomi/Features/Library/LibraryView.swift        # Uses settings.libraryColumns for grid columns
Yomi/Features/Library/LibraryViewModel.swift   # novels field + NovelQueries.fetchLibrary() call still missing
Yomi/Features/Library/MangaDetailView.swift    # Chapter tap→reader via navigationDestination(item:). insertAllIgnoringConflicts in loadChapters.
Yomi/Features/Browse/BrowseView.swift          # SourceBrowseView: FeedTab enum, supportsLatest picker, bridge reuse
Yomi/Features/Reader/ChapterReaderView.swift   # Auto-mark read, incognito guard, lastPageRead save/resume
Yomi/Features/Reader/TextReaderView.swift      # Novel reader; overlay opacity animation; dynamic colorScheme (sepia/dark/light)
Yomi/Features/More/PluginsView.swift
Yomi/Features/More/SettingsView.swift          # Incognito toggle + unread badge toggle added
Yomi/Features/More/InsightsView.swift          # ScrollView + LazyVGrid StatCards redesign
Yomi/Features/Onboarding/OnboardingView.swift
Yomi/Resources/                                # JS plugins (test-source.js only; production on Firebase)
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

## App Store checklist (incomplete items)
- App icon — missing (user designing)
- Age rating 17+ declaration (App Store Connect only)
- App description, screenshots, support URL (App Store Connect only)
- PrivacyInfo.xcprivacy — DONE (S22)
- Privacy policy URL — DONE (yomi-plugins.web.app/privacy)
- MAL token → Keychain — DONE (S24)

## Session close
1. Update all three docs in one prompt: ROADMAP.md + METODOLOGIA.md + ARQUITECTURA.md
2. **Commit and push to GitHub** — every session ends with `git add -A && git commit && git push`. No exceptions.
