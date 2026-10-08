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
- `Yomi/KNOWN_ISSUES.md` — numbered bug table (#1–#190), open rows listed at its top
- `Yomi/RESEARCH.md` — research; **§22 = direction (S122), §23 = perf audit, §25 = UX evidence + ranked list §25.10, §26 = S138 "calm" design direction**
- `Yomi/ARQUITECTURA.md` — architecture, data flows, DB schema · `Yomi/METODOLOGIA.md` — workflow + per-session lessons
- `Yomi/KEIYOUSHI_POC.md` — on-device Keiyoushi results + gaps · `Yomi/HISTORY.md` — archived sessions + old CLAUDE.md states
- `Yomi/design/` — S79–S95 design system (Space Grotesk/Mono "catalog" look) — **superseded by S138 "calm", RESEARCH §26**

## Current state (S147 — 2026-10-08)
- S128–S136 perf batch done: runs 1–5 hang-free on Martin's iPhone 17 (RESEARCH §23.6).
- Novel reader: one persistent WKWebView + JS controller (`Features/Reader/NovelReaderWeb.swift`), infinite
  scroll, swipe, typography pass (`ReaderFonts.swift`), Pages mode, Text · Look · Reading panel tabs.
- **Design = "calm", Apple Music-inspired (RESEARCH §26):** SF Pro everywhere, system neutrals, colour from
  covers, one accent, nothing on covers, plain `Notation`, **no list separators** (Martin S141). Every main
  screen is calm now, incl. every More sub-screen (S146). Settings-style lists use `CalmList` +
  `Section(calm:)` (Core/CanvasEnvironment.swift). Delete everywhere = swipe → red trash.
- **Theme:** `canvas` "Automatic" (follows iPhone light/dark, default for fresh installs) / Ink / Midnight /
  Paper / Sepia; palette resolved in ContentView via `canvasColors(for: colorScheme)`. Time/Date follow the
  iPhone unless chosen.
- **Extensions:** no repositories on a fresh install, none suggested; one tap "Add"; delete = swipe. **Any
  number of Mihon repositories** (`mihonRepoURLs`, `KeiyoushiRepository.repos`), `index.pb` or
  `index.min.json`, folder links accepted (S142). Catalog ↔ installed matching: `PluginCatalogEntry.installIds`.
- **Downloads:** Keiyoushi/Suwayomi manga download too (`DownloadManager.canDownload`; Keiyoushi needs Yomi open).
- **Updates:** refresh checks JS + Keiyoushi titles (Keiyoushi pool 3), progress row, Updates Summary
  (Failed/Completed, Retry). Background refresh skips Keiyoushi. One row per chapter found (`fetchedAt`, v23).
- **Reading state:** only reading counts toward History/Continue. ONE Continue rule for every screen:
  `ResumeReading.chapter(in:)` (ContinueReadingRow.swift) = after the end of the RUN of read chapters (S144).
- **Chapter numbers:** sources without one (Keiyoushi -1, e.g. Asura) are parsed from the name —
  `Core/ChapterRecognition.swift` (Mihon port); v24 filled old rows. Yomi assumes ascending order everywhere.
- **Keiyoushi pages:** bridge returns on a NEW port after background; `KeiyoushiBridge.pointAtLivePort` rewrites
  page requests, `resumeIfPaused` on foreground, reader pages retry (`PageRetry`). Pages > 4096 px tall
  (Asura = 900×16000) are drawn as strips or they render BLACK (S145, #190). DEBUG probe:
  `-keiyoushiPageProbe [-keiyoushiPageProbeTitle x] [-keiyoushiPageProbePause]` (device; args after `--`).
- **Read-aloud (S143):** app-wide `ListenPlayer` (`Features/Reader/ListenPlayer.swift`, views in
  `ListenPlayerViews.swift`) — Swift owns the sentences, the reader only highlights/follows; keeps playing outside
  the reader (tab bar accessory). Lock screen/background untested on device. Settings → Novels → Listening (S144).
- **Martin's rule (S144): no new features until everything works perfectly** (daily use: RTOC + Asura manhwa).
  S144–S145 fixed his field report (KNOWN_ISSUES 181–190, all device-checked); device perf S145: 0 hangs (novel detail, Browse).
  S147 (sim only): `.tachibk` import → working Keiyoushi titles (same ids/paths as the bridge, memo, categories,
  history, repos), import sheet, "Source missing" + Migrate (now searches Keiyoushi), calm first-run screen.
  Next: device-check S147 with Martin's real Tachimanga export → local CBZ/EPUB (#6 rest) → legal last (incl. #170).
  New backlog: per-extension Settings screen (Mihon source preferences; e.g. Asura "Hide premium chapters").
  Backlog: pinch-zoom in vertical (webtoon) mode (S145).
  Backlog: genre chips on NOVELS (LNReader `genres` dropped by `SourceNovel`; manga have them — S145).
  Backlog added S142: Dynamic Type, auto backups, lockable SFW mode, reader auto-dark at night, separate tap
  zones per manga mode, Spanish (ROADMAP S142). Aidoku/Paperback: answered S143 (possible, not now).
- Open gaps: Keiyoushi first page 4–6 s; no Tachimanga `.tmb` import (Tachimanga exports .tachibk, which works);
  no local CBZ/EPUB; GPLv3 NewPipe still in the extension-server jar; notification prompt on a fresh install not yet observed on device.
- Phone has the S145 Release build (Asura strips fix), profile expires **2026-10-14 20:46 UTC**. Free team = 7 days —
  `scripts/build-personal.sh` prints the real expiry; read it.
- Device-data repro: copy the phone's `Documents` (devicectl) + prefs into the sim container — METODOLOGIA S141.
- Simulator in the desktop app stays dark at system level (simctl appearance doesn't take) — check light on device.
- Build into `~/Library/Developer/Xcode/DerivedData/…` — `iOS/build/` on the Desktop fails CodeSign (xattrs).
- Next GRDB migration prefix: **`v25_`**. UI tests 13/13 (S144).

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
Yomi/Database/DatabaseManager.swift       # migrations (next v25_)
Yomi/Database/Queries/*.swift             # all DB access
Yomi/Features/Extensions/JSBridge.swift   # JavaScriptCore runtime, cheerio bundle (Resources/yomi-js-libs.js)
Yomi/Features/Extensions/ExtensionManager.swift, PluginCatalogService.swift
Yomi/Features/Keiyoushi/                  # JVM host, repository (index.pb), bridge, browse
Yomi/Features/More/PluginsView.swift      # Browse → Extensions tab + RepositoriesView, AddRepoSheet
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
