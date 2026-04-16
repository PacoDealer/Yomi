# Yomi — Claude Code Project Context

## What this app is
iOS manga, manhwa, manhua, and light novel reader. Plugin-based architecture:
JS plugins run in JavaScriptCore. Two plugin formats: Format A (manga) and Format B (LNReader/novels).
Firebase CDN hosts all 7 production plugins. App binary ships zero plugin files (App Store compliance).

## Tech stack
- **Swift + SwiftUI — iOS 26.2 deployment target. No iOS 18 fallbacks. Ever.**
- GRDB for SQLite (NOT SwiftData)
- JavaScriptCore for plugin execution
- Firebase Hosting: https://yomi-plugins.web.app

## Project path
`/Users/martingamberg/Documents/GitHub/Yomi`

## Key docs (read these at session start)
- `Yomi/ROADMAP.md` — current state, planned work, tech debt
- `Yomi/ARQUITECTURA.md` — full architecture, data flows, DB schema
- `Yomi/METODOLOGIA.md` — workflow rules, tech learnings per session

## Current state (post S34 — 2026-04-15)

S34 is a plugin debug + code review session.

**S34 shipped:**
- freewebnovel.js: chapter selector fixed (ul#chapter-list li a → a.con, with /novel/ href filter)
- novelbin.js: data-novel-id regex fixed (\d+ → [^'"]+) — NovelBin uses text slugs not numeric IDs
- novelfire.js: robust fallback selectors for summary/status; chapters URL gets ?page=1; multiple chapter selector fallbacks
- Catalog (index.json): removed comick (Cloudflare 403), lightnovelworld (site dead), lightnovelpub (Cloudflare) — 8 sources remain
- BrowseView: `let currentFeed = selectedFeed` before Task.detached (Swift 6 concurrency fix); NovelCoverCell phase-based AsyncImage; bottom padding on LazyVGrid
- UpdatesView: inserts `newChapters` not `remoteChapters` (performance — avoids re-inserting all chapters)
- TextReaderView: Task.detached(priority: .background) for markRead on navigation
- Full code review: all concurrency/GRDB rules confirmed correct, zero build warnings

**App Store blockers remaining:**
1. App icon (1024×1024 PNG) — user working on design separately
2. Age rating **18+** declaration (App Store Connect — 2026 system changed from 17+ to 18+)
3. App description, screenshots, support URL (App Store Connect — description text drafted in S33 session)

## Known issues / next session

| # | Issue | Notes |
|---|-------|-------|
| 1 | Chapters empty from Browse (novel sources) | `parseNovel()` returns empty chapters for novelfire + freewebnovel. Works from Library because chapters are already in DB. Root fix: the updated JS plugins need to reach the device via Firebase deploy + user reinstalls plugins. |
| 2 | LightNovelWorld shows in installed list | Removed from catalog index.json (site dead) but user already has it installed in Documents/Extensions/. Cannot auto-remove. User must manually uninstall via Extensions tab → swipe or long-press. |
| 3 | NovelFire synopsis/status empty | `div.summary` and `strong.ongoing` return empty despite being in HTML. Possibly JS-rendered on the real site. Multiple fallbacks added in S34. |
| 4 | App icon missing | User designing separately. App Store blocker. |
| 5 | Firebase deploy needed | S34 updated freewebnovel.js, novelbin.js, novelfire.js + index.json (comick/lightnovelworld/lightnovelpub removed). Run `firebase login --reauth && firebase deploy --only hosting` in `~/Desktop/Yomi\ 2.0/yomi-firebase`. After deploy, reinstall plugins in the app to get the fixed versions. |

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
cd ~/Desktop/yomi-firebase && firebase deploy --only hosting
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
