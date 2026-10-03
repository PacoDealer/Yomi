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
- GRDB (SQLite, not SwiftData) · JavaScriptCore (JS plugins) · Kingfisher (images) · WKWebView (novel reader)
- Keiyoushi: OpenJDK Mobile Zero + patched M-Extension-Server (`Yomi/Features/Keiyoushi/`, `scripts/keiyoushi/`)
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` project-wide — check build settings before claiming an isolation bug

## Docs (read the relevant one, not all of them)
- `Yomi/ROADMAP.md` — session log (newest first), plans, App Store submission checklist (authoritative)
- `Yomi/KNOWN_ISSUES.md` — numbered bug table (#1–#164), open rows listed at its top
- `Yomi/RESEARCH.md` — research; **§22 = direction (S122), §23 = perf audit, §25 = UX evidence + ranked list §25.10, §26 = S138 "calm" design direction**
- `Yomi/ARQUITECTURA.md` — architecture, data flows, DB schema · `Yomi/METODOLOGIA.md` — workflow + per-session lessons
- `Yomi/KEIYOUSHI_POC.md` — on-device Keiyoushi results + gaps · `Yomi/HISTORY.md` — archived sessions + old CLAUDE.md states
- `Yomi/design/` — S79–S95 design system (Space Grotesk/Mono "catalog" look) — **superseded by S138 "calm", RESEARCH §26**

## Current state (S139 — 2026-10-03)
- S128–S136 perf batch done: runs 1–5 hang-free on Martin's iPhone 17 (RESEARCH §23.6).
- Novel reader: one persistent WKWebView + JS controller (`Features/Reader/NovelReaderWeb.swift`), infinite
  scroll, swipe, typography pass (`ReaderFonts.swift`), Pages mode, Text · Look · Reading panel tabs.
- **Design = "calm", Apple Music-inspired (RESEARCH §26):** SF Pro everywhere (`YomiTokens.Font` helpers return
  system fonts), system neutrals, colour from covers, one accent, nothing on covers, plain `Notation`
  (`chapterTitle`, `plainText` for source strings). Built: Library, NovelDetailView, **MangaDetailView (S139)** —
  both details share the album header, `detailPillLabel()` pills, ⋯ menu, glass select bar. Martin approved the
  calm look on device (S138 build). Still old style: Browse/Extensions, History/Updates/More.
- **Agreed order:** Extensions redesign (repos into Settings, one list, no format tags, App Store-style rows) →
  KNOWN_ISSUES #165 (Continue shelf = last novel + last manga only) → #166 (History, get specifics) → remaining
  screens → TTS (§25.10 #8) → first-run + imports (#3, #6) → legal last.
- Open gaps: Keiyoushi first page 4–6 s; manga Download needs a JSBridge (Keiyoushi/Suwayomi titles can't
  download); Updates/Downloads not routed for Keiyoushi titles; no Mihon/Tachimanga backup import; no Dynamic
  Type outside the reader; stale "More → Plugins" copy (`OnboardingView.swift:48`, `BrowseView.swift:676`);
  GPLv3 NewPipe still in the extension-server jar; Pages-mode UI tests flaky on the sim (#164).
- Phone has the S138 build, not S139. Personal build expires every 7 days (free team) —
  `scripts/build-personal.sh` prints the real expiry; read it.
- Next GRDB migration prefix: **`v23_`**.

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
Yomi/Database/DatabaseManager.swift       # migrations (next v23_)
Yomi/Database/Queries/*.swift             # all DB access
Yomi/Features/Extensions/JSBridge.swift   # JavaScriptCore runtime, cheerio bundle (Resources/yomi-js-libs.js)
Yomi/Features/Extensions/ExtensionManager.swift, PluginCatalogService.swift
Yomi/Features/Keiyoushi/                  # JVM host, repository (index.pb), bridge, browse
Yomi/Features/More/PluginsView.swift      # Browse → Extensions tab (repos, installed, available)
Yomi/Features/Browse/BrowseView.swift     # Sources · Extensions · Migrate
Yomi/Features/Reader/NovelReaderWeb.swift, ReaderFonts.swift, ChapterReaderView.swift
Yomi/Features/Browse/NovelDetailView.swift, Yomi/Features/Library/MangaDetailView.swift
scripts/build-js-libs.mjs, build-reader-fonts.sh, keiyoushi/, perf/
```

## Plugins on Firebase
Plugin sources live only in `~/Desktop/Projects/Yomi/Firebase/public/` (not git).
Deploy: `cd ~/Desktop/Projects/Yomi/Firebase && firebase deploy --only hosting`.

## Session close
1. Update ROADMAP.md (session entry) + METODOLOGIA.md (lessons) + ARQUITECTURA.md (if structure changed);
   update "Current state" above **by replacing it**, never by appending a new "Prior state" block.
2. `git add -A && git commit && git push` — every session, no exceptions.
3. Changed JS plugins → copy to Firebase `public/` and deploy.
