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

## Current state (post S24 — 2026-04-07, starting S25)

S23 + S24 both complete same day. All shipped and pushed.

**S24 shipped:** Library sort (SortOrder enum + toolbar Menu), Webtoon scroll persistence
(ScrollViewReader + .scrollPosition), novel read on scroll-to-end (WKScriptMessageHandler),
MAL → Keychain (KeychainHelper), downloads cleanup on library remove, Discuss button
(optional plugin export → WKWebView sheet), Paperback compatibility shim (Source base class +
App constructors + post-eval adapter wiring getMangaList/searchManga/getChapterList/getPageList).

**S25 priority order:**
1. App icon (design — coral/amber + 読 or kitsune, 1024×1024 PNG, App Store blocker)
2. Privacy policy URL (GitHub Pages or Firebase static page)
3. Library unread count sort option
4. Paperback plugin testing with real .js bundles — fix any adapter issues
5. PluginCatalogService cache guard (fetchCatalog guard !isLoading)
6. Multi-select long-press in library (bulk ops)
7. Reading status field (DB migration v7)

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
- Next migration prefix must be `v6_` (v4_ prefix used twice — GRDB tracks by string name)
- `nonisolated` on all `*Queries` static methods
- Use `_ = try appDatabase.write { ... }` to silence unused result warning
- `appDatabase.read` from `@MainActor` context requires `try await`

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
Yomi/AppSettings.swift                         # @Observable singleton, UserDefaults, 12 props
Yomi/ContentView.swift                         # Root TabView with AppRouter binding
Yomi/YomiApp.swift                             # Entry point, DB setup, #if DEBUG seed, .tint + .preferredColorScheme on ContentView
Yomi/Core/AppRouter.swift                      # @Observable, module-level appRouter var
Yomi/Core/Color+Hex.swift                      # Color(hex:) init + Color.hexString
Yomi/Core/NotificationManager.swift
Yomi/Database/DatabaseManager.swift
Yomi/Database/Queries/MangaQueries.swift
Yomi/Database/Queries/ChapterQueries.swift
Yomi/Database/Queries/CategoryQueries.swift
Yomi/Database/Queries/NovelQueries.swift
Yomi/Database/Queries/ExtensionQueries.swift
Yomi/Features/Extensions/JSBridge.swift        # JavaScriptCore bridge, shims, require()
Yomi/Features/Extensions/ExtensionManager.swift
Yomi/Features/Extensions/PluginCatalogService.swift
Yomi/Features/Library/LibraryView.swift
Yomi/Features/Library/LibraryViewModel.swift
Yomi/Features/Library/MangaDetailView.swift
Yomi/Features/Browse/BrowseView.swift
Yomi/Features/Reader/ChapterReaderView.swift
Yomi/Features/Reader/TextReaderView.swift
Yomi/Features/More/PluginsView.swift
Yomi/Features/More/SettingsView.swift
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
- PrivacyInfo.xcprivacy — missing, hard reject
- Privacy policy URL — missing
- App icon — missing
- MAL token → Keychain (currently UserDefaults)
- Age rating 17+ declaration
- App description, screenshots, support URL

## Session close
Update all three docs in one prompt: ROADMAP.md + METODOLOGIA.md + ARQUITECTURA.md
