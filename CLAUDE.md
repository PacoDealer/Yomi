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

## Design track (S82-S85 — Blocks 1-5 of 12 implemented, Phase 0 fidelity gaps closed S85)

All 16 screens designed and confirmed. Concept: **"reading instrument / living archive"** — warm editorial canvas, covers + user accent are the only color, monospace catalog notation, ink/screentone signature. Confirmed: default accent **Vermilion `#E5473A`**, default canvas **Ink (`#14110F`)**, Space Grotesk (UI) + Space Mono (notation), Newsreader serif (novel body). Design tokens live in `DesignTokens.swift`; canvas colors are wired app-wide via `\.yomiCanvas` environment (`CanvasEnvironment.swift`, set from `AppSettings.canvasColors`); notation helpers in `Notation.swift`; Appearance Studio in `AppearanceStudioView.swift`. **Full design spec**: `Yomi/design/design_handoff_yomi/YOMI Screens.dc.html` — 16 screens as HTML with inline CSS. App icon assets: `AppIcon-Ink.png` + `AppIcon-Paper.png` in `Yomi/design/design_handoff_yomi/assets/`. **Implementation order (12 blocks):** ~~Library~~ → ~~Library-selection~~ → ~~Detail~~ → ~~Manga Reader overlay~~ → ~~Novel Reader overlay~~ → Browse → History → Updates → Downloads → Insights → More+Settings → Onboarding+empty states. Compile + screenshot checkpoints after blocks 1, 3, 5, 12 — **all reached and screenshot-verified live against the mockup as of S85; Blocks 1-5 have no known fidelity debt.** Next session: Block 6 (Browse).

## Current state (post S85 — 2026-08-04 · Phase 0 — all 6 design-fidelity gaps closed)

S84 found 6 fidelity gaps in Blocks 1-5 (Library Continue hero missing, cover-cell catalog-index
badge missing, wrong fonts on source/tab labels, list-mode `MangaListRow` zero design-system
treatment, Detail header structurally wrong, reader top bar not icon-chip-only). **S85 fixed all
six**, plus a deeper root cause found first: `YomiTokens.Canvas` (Ink/Midnight/Paper/Sepia) was
only ever read inside `AppearanceStudioView`'s own preview — never applied as the real app
background, so every screen rendered as plain system dark mode regardless of canvas choice. Fixed
via `AppSettings.canvasColors` + a `\.yomiCanvas` environment key set once in `ContentView`. Built
the missing Continue hero (`ContinueHeroCard` in `ContinueReadingRow.swift`) with a genuine
ambient-tint-from-cover background (`UIImage.averageColor()`, new `Core/UIImage+AverageColor.swift`).
Rebuilt `MangaDetailView`/`NovelDetailView` headers to the §14 full-bleed blurred-backdrop +
overlapping-thumb + floating-glass-nav structure (new shared `Core/GlassChip.swift` modifier);
deleted the now-orphaned colored `StatusBadge`/`NovelStatusBadge` structs. Moved the manga reader's
oversized mode-switch Picker out of the top bar into a "Reader Settings" sheet behind a `gearshape`
chip, matching the spec's 44pt icon-chip pattern; left the novel reader top bar untouched (already
correct — its typography controls are intentionally always-visible in the bottom card, not gated).
All 6 fixes screenshot-verified live via `mobile-mcp` against the mockup, not just code-read.
**Full detail in `Yomi/ROADMAP.md`'s S85 entry.**

**Process note:** `mobile-mcp` element coordinates are the bounding box's top-left corner, not its
center — tap `(x + width/2, y + height/2)` for small circular targets like the 44×44 glass chips,
or taps silently miss.

Full session-by-session history (S1-S84) lives in `Yomi/ROADMAP.md` (recent) and `Yomi/HISTORY.md`
(archived) — not duplicated here. This file keeps only the single most-recent state above.
## Known issues / carry-forward

| # | Issue | Notes |
|---|-------|-------|
| 1 | Chapters from Browse (partial) | Defensive fixes in S37. Root cause unconfirmed — needs live device test. |
| 2 | ~~App icon missing~~ | ✅ Designed S79/S82 — "Y." monogram (Space Grotesk Y + Vermilion dot), **Ink** default + **Paper** alternate. PNGs in `Yomi/design/design_handoff_yomi/assets/`; layers in `Yomi/design/icons/layers/`. TODO: drag into `AppIcon.appiconset` in Xcode + `CFBundleAlternateIcons` entry. |
| 3 | Alternate icons need Xcode step | Drop PNGs into appiconsets + add `CFBundleAlternateIcons` in Xcode Target → Info. |
| 4 | App Store content missing | Age rating 18+, description, screenshots pending in App Store Connect. |
| 5 | ~~Firebase deploy pending~~ | ✅ Deployed S53 — babelnovel.js + lightnovelpub.js live. |
| 6 | ReadComicOnline + Mangapill broken | Downloaded from dead GitHub repo. User should uninstall from Extensions tab. |

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
Yomi/YomiApp.swift                             # Entry point, DB setup, #if DEBUG seed, .tint + .preferredColorScheme on ContentView
Yomi/Core/AppRouter.swift                      # @Observable, module-level appRouter var
Yomi/Core/Color+Hex.swift                      # Color(hex:) init + Color.hexString
Yomi/Core/DesignTokens.swift                   # YomiTokens: Canvas (Ink/Midnight/Paper/Sepia), Accent (Vermilion default), Font (Space Grotesk + Mono), TypeScale, Reader themes, Radius, Spacing, Motion
Yomi/Core/CanvasEnvironment.swift               # \.yomiCanvas environment key — set once in ContentView from AppSettings.canvasColors, read via @Environment everywhere
Yomi/Core/GlassChip.swift                       # .glassChip() — shared 44×44 floating Liquid Glass circle modifier for chrome buttons
Yomi/Core/UIImage+AverageColor.swift            # UIImage.averageColor() via CIAreaAverage — backs Continue hero's ambient-tint-from-cover background
Yomi/Core/Notation.swift                       # Catalog-notation formatters (Space Mono output): chapter(), progress(), readingTime(), status(), novelIndex(), etc.
Yomi/Core/NotificationManager.swift
Yomi/Database/DatabaseManager.swift            # Migrations v1–v19_source_indexes; next must be v20_
Yomi/Database/Queries/MangaQueries.swift
Yomi/Database/Queries/ChapterQueries.swift     # insertAllIgnoringConflicts (INSERT OR IGNORE — safe bulk persist, called from loadChapters)
Yomi/Database/Queries/CategoryQueries.swift
Yomi/Database/Queries/NovelQueries.swift       # fetchLibrary() EXISTS but is never called by LibraryViewModel
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
Yomi/Features/Browse/BrowseView.swift          # SourceBrowseView: FeedTab enum, supportsLatest picker, bridge reuse; Suwayomi section
Yomi/Features/Reader/ChapterReaderView.swift   # Auto-mark read, incognito guard, lastPageRead save/resume
Yomi/Features/Reader/TextReaderView.swift      # Novel reader; overlay opacity animation; dynamic colorScheme (sepia/dark/light)
Yomi/Features/More/PluginsView.swift
Yomi/Features/More/SettingsView.swift          # Plugin Repos section, Suwayomi section, Advanced → NavigationLink; Appearance → AppearanceStudioView
Yomi/Features/More/AppearanceStudioView.swift  # Canvas × Accent × Type studio; live preview card; WCAG contrast badge; app icon tiles; Reset defaults
Yomi/Features/More/AdvancedSettingsView.swift  # Cache, Network (read-only), Database (log export), Build info
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

## App Store checklist (incomplete items)
- App icon — ✅ designed S79/S82 ("Y." monogram, Ink + Paper); PNGs in `Yomi/design/design_handoff_yomi/assets/`; layers in `Yomi/design/icons/layers/`. TODO: drag into `AppIcon.appiconset` in Xcode, add `CFBundleAlternateIcons` entry, upload to App Store Connect.
- Screenshots — blocked until design implementation complete (Blocks 6-12 remain: Browse, History, Updates, Downloads, Insights, More+Settings, Onboarding+empty states)
- Age rating 17+ declaration (App Store Connect only)
- App description, screenshots, support URL (App Store Connect only)
- PrivacyInfo.xcprivacy — DONE (S22)
- Privacy policy URL — DONE (yomi-plugins.web.app/privacy)
- MAL token → Keychain — DONE (S24)

## Session close
1. Update all three docs in one prompt: ROADMAP.md + METODOLOGIA.md + ARQUITECTURA.md
2. **Commit and push to GitHub** — every session ends with `git add -A && git commit && git push`. No exceptions.
3. **If JS plugins were modified** — copy changed `.js` files to `~/Projects/Yomi/Firebase/public/` and run: `cd ~/Projects/Yomi/Firebase && firebase deploy --only hosting` (requires `firebase login --reauth` if credentials expired).
