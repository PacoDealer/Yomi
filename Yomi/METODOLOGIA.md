# Working methodology — Yomi

## Workflow (updated S22 — Claude Code-first)

### Roles
- **Claude Code (terminal)** → everything: reads files, plans, implements, builds, fixes errors, commits/pushes
- **Claude.ai (Desktop app)** → session strategy only: review priorities, flag risks, architectural concerns. Does NOT generate implementation prompts anymore.
- **Xcode** → compile verification, simulator, UI inspection
- **GitHub Desktop** → visual diff review, manual push when required
- **User** → product owner + QA: decides what to build, tests on simulator, reports what feels wrong

### Why the relay was eliminated
The old workflow (Claude.ai generates prompts → user copy-pastes → Claude Code executes) existed because
Claude.ai couldn't see the real file state and compensated by generating extremely explicit prompts.
Claude Code can read actual files before acting, making the relay unnecessary and harmful.
Evidence: S21 regressions (OnboardingView, markRead()) happened because Claude.ai replaced entire files
without seeing what they omitted. Claude Code reading first prevents this class of bug.

### Workflow rules
- Claude Code reads the target file before every edit. Always. No exceptions.
- One file at a time, compile after each new file.
- Never create multiple files simultaneously (docs are the valid exception).
- Commits after each logical unit — not at session close. Clean rollback points matter.
- Code changes and doc updates go in the same session. Never leave docs stale overnight.
- When chaining independent fixes: run all without compiling, compile once at the end.
- Diagnose before prescribing: (1) read the actual file, (2) find exact failure point, (3) write one targeted fix.
- All code, commits, docs, and communication in English (from S15 onward).

### Session start
`cd /Users/martingamberg/Desktop/Projects/Yomi/iOS` → open Claude Code.
CLAUDE.md loads automatically with full context. No pasting required.
If starting a session after a long gap: read ROADMAP.md to confirm current state.

### Session close
1. Claude Code updates all three docs (ROADMAP + METODOLOGIA + ARQUITECTURA) in one step.
   Valid exception to "one file per prompt": they are docs, not Swift code.
2. **Commit and push to GitHub.** Every session must end with a commit + `git push`.
   No exceptions — leaving uncommitted work overnight causes context loss and rollback risk.

## AI tooling setup (established S22)

### Philosophy
Claude Code is capable of reading files, planning, implementing, building, and iterating without a human relay. The workflow that uses Claude.ai to generate prompts for Claude Code to execute treats Claude Code as a dumb executor — this is suboptimal. Claude Code-first is better: Claude Code reads actual file state, generates its own implementation plan, writes code, builds, fixes errors, and commits. Claude.ai is reserved for session-level strategy.

### CLAUDE.md
Located at `/Users/martingamberg/Desktop/Projects/Yomi/iOS/CLAUDE.md`. Loaded automatically every session. Contains: tech stack, iOS 26 rules, GRDB/concurrency rules, key file paths, current session state, build command, App Store checklist. Update after every session close. This file replaces the session-start paste ritual.

### Memory system
Located at `~/.claude/projects/-Users-martingamberg/memory/`. Contains `MEMORY.md` (index) and `project_yomi.md` (project state). Persists project path, tech stack, and session state across conversations.

### MCP servers
Model Context Protocol servers extend Claude Code with external capabilities. Installed at user scope (available across all projects).

| Server | Status | Install command | What it does |
|--------|--------|----------------|--------------|
| XcodeBuildMCP | ✅ Connected | `claude mcp add --scope user XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp` | Build, simulator, LLDB, read errors |
| context7 | ✅ Connected | `claude mcp add --transport http --scope user context7 https://mcp.context7.com/mcp` | Live docs for GRDB, SwiftUI, JS libraries. Append `use context7` to prompts. |
| github | ✅ Connected | `claude mcp add --transport http --scope user github https://api.githubcopilot.com/mcp -H "Authorization: Bearer TOKEN"` | PR/issue management |
| mobile-mcp | ✅ Connected | `claude mcp add --scope user mobile-mcp -- npx -y @mobilenext/mobile-mcp@latest` | iOS Simulator UI automation |
| apple-docs | ✅ Connected | `claude mcp add --scope user apple-docs -- npx -y @kimsungwhee/apple-docs-mcp@latest` | SwiftUI + iOS 26 API from developer.apple.com |

Verify: `claude mcp list` (terminal) or `/mcp` (inside Claude Code session).

### Plugins
Claude Code has a `/plugin` marketplace system. Install inside a Claude Code session.

| Plugin | Command | What it does |
|--------|---------|--------------|
| swift-lsp | `/plugin install swift-lsp@claude-plugins-official` | Real-time Swift diagnostics (note: produces false positives for cross-file types — see S22 learnings) |

### What was evaluated and discarded
- **Phase 3 plugins from Claude.ai research** (`/plugin install frontend-design@claude-plugins-official`, etc.): some did not exist and were hallucinated. Always verify slash commands with `/help` before spending time on them.
- **Custom Yomi MCP**: evaluated, deferred. XcodeBuildMCP already covers build/simulator needs. A custom MCP for GRDB inspection or JSContext isolation testing may be worth building in a future session.
- **Claude.ai connectors** (GitHub, Figma, etc.): these affect the Claude.ai web app, not Claude Code terminal sessions. Useful for Claude.ai planning context but irrelevant to implementation.

## Tech stack
- Swift + SwiftUI (iOS 26)
- GRDB for local SQLite database
- JavaScriptCore for executing JS plugins (Yomi format and LNReader format)
- Architecture inspired by LNReader (Android, TypeScript plugins) and Mihon (Android)

## JS plugin structure
Yomi supports two plugin formats:

**Format A — Yomi/Manga** (global functions):
  getMangaList(page) → [{id, path, title, coverURL, summary, author, artist, status, genres}]
  getChapterList(mangaPath) → [{id, path, name, chapterNumber}]
  getPageList(chapterPath) → [urlString]
  searchManga(query, page) → [{id, path, title, coverURL, summary, author, artist, status, genres}]

**Format B — LNReader/Novel** (class exported on global `plugin`):
  plugin.popularNovels(pageNo, options) → [{name, path, cover}]
  plugin.parseNovel(novelPath) → {path, name, cover, author, summary, status, chapters}
  plugin.parseChapter(chapterPath) → String (HTML)
  plugin.searchNovels(searchTerm, pageNo) → [{name, path, cover}]

JSBridge auto-detects the format: if `plugin.popularNovels` exists → Format B, otherwise → Format A.

## Shims injected by JSBridge
- SOURCE.fetch(url, options) → synchronous HTTP GET or POST via DispatchSemaphore
    options: { method, body, headers } — defaults to GET, POST if method="POST"
- cheerio.load(html) → recursive HTML parser + CSS selector engine in pure JS (functional since S6)
- localStorage / sessionStorage → in-memory JS objects
- console.log/warn/error → Swift print()
- require(name) → module cache shim: routes cheerio/he/node-fetch/axios to native equivalents; injects module, exports, process globals (since S18)

## File path rules
- Before generating any edit prompt, Claude.ai must cite the confirmed exact file path
- If path is uncertain, the prompt includes a `find Yomi -name "*.swift"` step before editing
- Frequently referenced paths:
  - JSBridge: Yomi/Features/Extensions/JSBridge.swift
  - ExtensionManager: Yomi/Features/Extensions/ExtensionManager.swift
  - PluginCatalogService: Yomi/Features/Extensions/PluginCatalogService.swift
  - UpdatesView+ViewModel: Yomi/Features/More/UpdatesView.swift (ViewModel embedded in same file)
  - AppSettings: Yomi/AppSettings.swift (project root, not in Core/)
  - ContentView: Yomi/ContentView.swift (project root)

## Sessions

Full session-by-session log moved to `Yomi/HISTORY.md` (and current sessions to `ROADMAP.md`)
during the 2026-08-04 doc restructure — this file now stays workflow-rules-only. See those
two files for what happened when; see the Technical learnings sections below for durable
patterns and lessons.

## Technical learnings — S96 (part 2, same session — Martin's live visual review)

**`.glassEffect()` called with no arguments does not reliably clip to the shape it's placed on —
it needs the shape passed explicitly via `.glassEffect(_:in:)`, applied directly to the content, not
as a `.background { Shape().glassEffect() }`.** Every reader/action-bar glass panel in the app
(`ChapterReaderView`'s and `TextReaderView`'s bottom bars, `LibraryView`'s selection action bar,
`GlassChip.swift`'s shared circle chip) used the `.background { RoundedRectangle(cornerRadius:
_).glassEffect() }` pattern. This is a documented iOS 26 gotcha: the parameterless `glassEffect()`
has its own shape-inference behavior and is known to render as a Capsule instead of the declared
shape. Circular chips (`GlassChip`) looked fine by coincidence (a Capsule on a square bounding box
*is* a circle), which is why this went unnoticed through 6 sessions of design-track work — it only
became visually obvious on wide/short panels, where the fallback rendered as an oval/blob instead of
a softly-rounded rectangle. Confirmed by Martin screenshotting the novel reader's settings panel and
asking why it looked like a gray oval overlapping the text. Fixed all 6 call sites to
`.glassEffect(.regular, in: <Shape>)` applied directly to the content (no `.background {}` wrapper).

**A native SwiftUI `Slider` doesn't fit into an otherwise fully custom design system, even when
`.tint()`'d correctly** — its default iOS 26 thumb is a large white pill/capsule shape that visually
clashes with everything else in Yomi (thin accent-color capsule progress bars everywhere else: cover
cells' read-progress bar, the reader's own chapter-progress footer, the Continue card). Martin
flagged this live ("why is there both a rectangle and a circle") on the manga reader's page scrubber.
Built `Core/YomiScrubber.swift` — a small custom `GeometryReader` + `DragGesture` scrubber matching
the app's thin-track/small-accent-thumb language — and swapped it in for both native `Slider` uses
(manga reader page scrubber, novel reader font-size control).

## Technical learnings — S96

**iOS Simulator's `cfprefsd` daemon caches app preferences at a device-level path, independent of
the app's per-install Data Container — `simctl uninstall` does not reliably clear it.** This
resolves the S95 mystery (#16, "stale `#00FF00` accentColor survived `simctl uninstall`") for real:
it was never a Yomi bug or leftover manual-testing state. The actual cache lives at
`~/Library/Developer/CoreSimulator/Devices/<udid>/data/Library/Preferences/<bundleid>.plist` — a
device-global path, not inside `Containers/Data/Application/<container-uuid>/`. `simctl uninstall`
removes the app bundle and its Data Container (which *does* get a fresh UUID each reinstall) but
apparently doesn't always invalidate this separate `cfprefsd`-level cache, so `UserDefaults.standard`
reads on the "fresh" install can silently return values from a previous install. Hit this again S96
on `hasSeenOnboarding` (read back `true` on a supposedly-fresh install, so Onboarding never
appeared). **Correct procedure for genuine fresh-install QA on this simulator**, superseding plain
`simctl uninstall`:
```
xcrun simctl terminate <udid> <bundleid>
xcrun simctl uninstall <udid> <bundleid>
rm -f ~/Library/Developer/CoreSimulator/Devices/<udid>/data/Library/Preferences/<bundleid>.plist
xcrun simctl spawn <udid> launchctl stop com.apple.cfprefsd.xpc.daemon
```
Then reinstall. This is now the standing procedure (see memory `feedback_yomi_qa_state`) — do not
spend time again treating a "value survived uninstall" symptom as a Yomi code bug without first
clearing this cache and retesting.

**`.contextMenu` and a separate `.onLongPressGesture` attached to the same view do not compose —
`.contextMenu`'s own long-press interaction consistently wins, silently starving the custom
gesture.** `MangaCoverCell`/`NovelLibraryCoverCell` each had both, meaning Library's entire
multi-select mode (checkboxes + bottom action bar, a real S82 feature) was unreachable by long-press
— confirmed live, deterministically, across repeated tries with varying press durations. There is no
reliable way to run a custom long-press *and* a native context menu off the same gesture recognition
in SwiftUI; the fix is to fold the custom action into the context menu itself (add a "Select" `Button`
as the first item) rather than trying to win the gesture race. General rule: **never attach
`.onLongPressGesture` to a view that also has `.contextMenu` — the long-press gesture will not fire.**

**`.onChange(of:)` does not fire for a value that is already at its "changed" state when the view
first mounts — only for transitions observed while the view is live.** `MoreView`'s
`.onChange(of: appRouter.openMorePlugins) { … }` was meant to auto-push `PluginsView` whenever
another screen set the flag to request a deep link. This worked once More had already been visited
once this session (so `MoreView` was alive to observe the `false → true` transition), but silently
no-op'd on a *genuinely first* visit to More — the flag was already `true` by the time `MoreView`'s
body first evaluated, so there was no transition to observe. `OnboardingView` had already
independently hit this and papered over it with a `DispatchQueue.main.asyncAfter(deadline: .now() +
0.4)` delay (a timing hack, not a real fix). The correct fix is `.onChange(of:initial: true) { … }`
(iOS 17+), which also invokes the closure once for the view's initial value. Any `.onChange`-driven
deep-link/flag-consumption pattern in this app should default to `initial: true` unless there's a
specific reason not to fire on first appearance.

**When a config value has an explicit "system/auto" state (empty string, `nil`, etc.), every
downstream consumer of that value must agree on what "auto" resolves to — a partial implementation
is worse than no feature at all.** `AppSettings.canvas == ""` meant "follow device" — `colorScheme`
correctly resolved this to `nil` (defer to system dark/light), but the separate `canvasColors`
computed property, used to paint every custom background in the app, unconditionally hard-coded Ink
regardless of system appearance. The result wasn't a crash or an obviously-broken screen — it was a
systemic, silent mismatch (light system chrome over dark custom content) that only shows up on a
specific device appearance setting, and precisely matches "the whole app doesn't look like the
mocks," the exact complaint that opened S95's session. Since "follow device" wasn't even a reachable
picker option (only a silent legacy-migration fallback), the simplest correct fix was to stop
producing that half-implemented state at all — default fresh installs straight to the fully-specified
`"Ink"`. Lesson: grep every read site of a shared "auto" value before shipping it, not just the one
you're actively changing.

**A helper function that mutates a child record should also update the parent's derived "touch"
timestamp if a sibling helper for the same conceptual action already does — an inconsistency here is
invisible until a downstream screen filters on that timestamp.** `ChapterQueries.markRead(id:
mangaId:)` and `ChapterQueries.markAllRead(mangaId:)` both call `MangaQueries.touchLastRead(mangaId:)`
after writing to the `chapter` table; `ChapterQueries.setRead(chapterId:isRead:)` — used by Updates'
mark-read actions and Detail's manual per-chapter toggle — did not, despite doing the same
conceptual "mark as read" write. Chapters correctly showed `isRead = true`, but the owning
manga/novel's `lastReadAt` never moved, so History (which filters on `lastReadAt != nil`), Library's
"last read" sort, and the Continue-reading card all silently excluded or stale-dated anything marked
read this way — while still looking completely correct on the screen where the action was taken.
This class of bug (two near-identical functions, one incomplete) won't surface in code review of
either function alone; only grepping *all* functions that touch the same underlying "read" concept
and diffing their side effects catches it.

## Technical learnings — S95

**`.frame(height:)` doesn't clip — a fixed height copied from a sibling view can silently overflow
past a shared `.clipShape()`, and since `clipShape` also clips hit-testing, the overflow is neither
visible nor tappable.** `ContinueHeroCard`'s text `VStack` had `.frame(height: 104, alignment: .top)`
matching the adjacent 74×104pt cover thumb — correct for a 1-line title, but with a 2-line title the
VStack's actual content (title + subtitle + Spacer + Resume pill) needed more than 104pt. `.frame()`
alone doesn't crop children that exceed the proposed size; it just reports that size to the parent for
layout purposes, so the Resume pill kept rendering past the 104pt boundary — until the *outer*
`.clipShape(RoundedRectangle)` (applied to the whole card, `.background()`+`.clipShape()` per
DESIGN_SYSTEM's card convention) sliced it off. Since `clipShape` restricts hit-testing to its shape
too, the clipped portion of the button was a real dead zone — a user tapping where the button visibly
(barely) still showed could tap nothing at all. Lesson: never copy a sibling's fixed height onto a
text container with variable-length content; let it size naturally and use `alignment: .top` on the
containing stack instead.

**A bare `Color.clear.frame(width:)` with no height is greedy in the unconstrained dimension, and
`.overlay(alignment:)` proposes the *base view's full size* to its overlay content.** Used as a
symmetric spacer opposite a back-chip (to center a nav-bar title), `Color.clear.frame(width: 44)`
expanded to fill the entire height the `ScrollView` overlay proposed — the whole visible viewport —
stretching the containing `HStack` (and anything backgrounded on it) to full-screen size, and pushing
the "true" top-aligned content down to wherever it happened to land relative to the alignment guides.
Every other glass-nav-bar in the app that needed this same trick (`MangaDetailView`, etc.) already
used real buttons with their own fixed `.glassChip()` 44×44 size instead of a bare spacer — this was
the first place a *purely decorative* symmetric spacer was needed, and the missing explicit
`height: 44` is what broke it. Always give both dimensions when using `Color`/`Rectangle` purely as
an invisible layout spacer; never rely on "it's just 44 wide, height doesn't matter."

**`fullScreenCover` (and `sheet`) present a *separate* view hierarchy that does not inherit
`.tint()` from the presenting view.** `YomiApp.swift` sets `.tint(Color(hex: settings.accentColor))`
on `ContentView()`, then chains `.fullScreenCover` off the same view — but the cover's *content*
closure builds a new, disconnected view tree for presentation purposes, so `Color.accentColor`
inside `OnboardingView` resolved to the system default (blue) instead of the app's real accent. Any
full-screen/sheet content that relies on `Color.accentColor` (or other environment-derived styling
normally set higher up) needs that modifier applied again, explicitly, inside the presented view
itself — don't assume presentation modifiers carry environment values down for free.

**Chaining two separate `.fullScreenCover` modifiers on the same view is unreliable — only one
presentation slot survives.** `YomiApp.swift` had `.fullScreenCover(isPresented: $showOnboarding) {
OnboardingView() }` immediately followed by `.fullScreenCover(isPresented: $isLocked) { AppLockView
{...} }`, both applied to `ContentView()`. Since `appLockEnabled` defaults to off, `isLocked` starts
`false`, and `showOnboarding` should present on any first launch — but it silently never did,
regardless of `hasSeenOnboarding`. Root-caused only by merging both into a *single*
`.fullScreenCover` with a computed `Binding` (`isPresented: isLocked || showOnboarding`) and an
if/else inside the content closure to pick which view to show. General rule for this project: never
chain multiple `.sheet`/`.fullScreenCover` modifiers on the same view — always merge into one with
either an enum-driven `item:` binding or an if/else content switch.

**`UIImage(named:)` does not reliably load an `.appiconset` entry, even by the appiconset's own
name.** `UIImage(named: "AppIcon")` returned `nil` for `Yomi/Assets.xcassets/AppIcon.appiconset`
(silently falling back to a `book.fill` SF Symbol placeholder, no crash, no warning — easy to miss
without an explicit live look). Appiconsets are compiled differently from regular imagesets and
aren't guaranteed to be `UIImage(named:)`-addressable. Fix: added a plain
`OnboardingIcon.imageset` containing a duplicate copy of `AppIcon-Ink-1024.png` specifically for
in-app display — the small duplication is worth the reliability. If any other screen ever needs to
show the app's own icon in-app (not just as the Home Screen icon), reuse this asset rather than
trying `UIImage(named: "AppIcon")` again.

**Simulator UserDefaults can persist stale/wrong values indefinitely across rebuilds, reinstalls,
and even `simctl uninstall` on a long-lived dev simulator — always suspect this before a code bug.**
Two separate instances this session: (1) `AppSettings.accentColor` showed a leftover blue from
old manual Appearance Studio testing, fixed by the user tapping the correct swatch live; (2) a
mysterious pure-debug `#00FF00` accentColor value survived a full `simctl uninstall`+reinstall cycle
(root cause not found — not in any `.swift` source, Xcode scheme, or MCP session config). Both were
data artifacts on this specific simulator, not application bugs. See [[project_yomi]] Known Issues
#15/#16 and the standing memory `feedback_yomi_qa_state` for the general rule this confirms twice
over: verify live state before concluding the design system itself is broken.

## Technical learnings — S94

**The `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` / pure-computed-property bug (S91's `Notation`
finding) isn't limited to enums — it hits computed properties on plain structs too.**
`Manga.resolvedCustomCoverPath` and `Novel.resolvedCustomCoverPath` are simple stateless path-string
computations (no stored state, no MainActor dependency of any kind) but were still MainActor-isolated
under the project's actor-isolation default, because the isolation attaches to the *type*, not to
whether the member actually touches shared mutable state. Neither property had ever been called from
a `Task.detached` context until `InsightsView`'s "Most Read" cover lookup needed one this session —
the bug was invisible until then. Fixed the same way as `Notation`: mark the specific
member `nonisolated` (not the whole struct, since `Manga`/`Novel` do have other MainActor-relevant
context via GRDB's `PersistableRecord` conformance elsewhere in the project). General rule, extending
S91's: before adding *any* struct/enum member to a call site inside `Task.detached`, check whether it
reads only its own stored properties (safe to mark `nonisolated`) — don't wait for the compiler error
to discover it one type at a time.

## Technical learnings — S91

**`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes plain enums/structs MainActor-isolated by
default too, not just classes/views.** `Notation` (a pure, stateless string-formatting `enum`, no
stored state) had never been called from inside a `Task.detached` block before — the first time
`HistoryView.loadHistory()` did it (formatting a chapter subtitle inside the detached DB-fetch
closure), the build produced two real Swift 6 errors: "main actor-isolated static method ... cannot
be called from outside of the actor." Fixed by marking the whole enum `nonisolated enum Notation`
rather than restructuring the call site — correct here because Notation has zero MainActor
dependencies, and it means any future background-context caller gets this for free too. General
rule for this project: any pure/stateless utility type meant to be callable from `Task.detached`
(formatters, pure calculators, parsers) should be declared `nonisolated` at the type level up front,
not discovered one build error at a time.

**`ScrollView` + `LazyVStack` (the pattern Library/Browse already use over native `List`) has no
`.swipeActions` equivalent** — that modifier only exists on `List` rows. When a design block needs
full custom row styling (as History's N.11 spec did: fixed-size cover, catalog-notation subtitle,
adaptive timestamp, kind pill — none of which fit cleanly in a `List` row without fighting
`.insetGrouped` chrome), the per-row delete affordance has to move to `.contextMenu` (long-press)
instead, matching the convention `LibraryView` already established for its own list-mode rows.

## Technical learnings — S89

**`INFOPLIST_ADDITIONAL_FILE` does not reliably merge into a `GENERATE_INFOPLIST_FILE = YES`
target — verify with `plutil -p` on the compiled bundle, never assume it worked.** This project
used it since S80 to inject `UIAppFonts` (and, briefly this session, `NSAppTransportSecurity`) —
confirmed via a clean build + `plutil -p` on the actual compiled `Info.plist` that **neither key
ever appeared**, even after a full clean rebuild. The reliable fix for a Swift-Xcode-16-generation
project (`PBXFileSystemSynchronizedRootGroup`) is to switch the target to an explicit
`INFOPLIST_FILE` (write the few `INFOPLIST_KEY_*`-equivalent keys — scene manifest, launch screen,
orientations, etc. — directly into it; build-environment keys like `MinimumOSVersion`/`DTXcode`/
`CFBundleIcons` are still injected automatically by Xcode's build steps regardless of which mode is
used), same pattern `YomiWidget` already used successfully. **One extra trap**: if the new
`Info.plist` lives inside a folder that's a `PBXFileSystemSynchronizedRootGroup` member (any file
physically present under `Yomi/` in this project), Xcode will *also* try to copy it as a bundle
resource, producing a "Multiple commands produce Info.plist" build error — must add `Info.plist` to
that folder's `PBXFileSystemSynchronizedBuildFileExceptionSet.membershipExceptions` array (exactly
how `YomiWidget`'s own exception set already excluded its `Info.plist`).

**zsh trap: never use `for path in ...`** — `path` is a special zsh variable tied to `$PATH`;
overwriting it with a `for` loop breaks all command resolution (`command not found: curl`) for the
rest of that shell invocation. Use any other loop-variable name.

**Backgrounding a real long-running process (e.g. a local test server) from an agent session is
unreliable with `nohup ... & disown` — it can get silently reaped** even though the process starts
and logs correctly. The Bash tool's own `run_in_background: true` parameter is the reliable
mechanism; even then, one observed case (running two `run_in_background` Bash calls back-to-back in
the same turn) appeared to kill the first process early. Prefer one `run_in_background` server
launch per turn, then poll/verify with a plain foreground `curl`/`ps` check rather than chaining
another background call immediately after.

## Technical learnings — S88

**The custom `cheerio` shim doesn't support `cheerio.load(html).text()` — chain off a selection,
not the load result directly.** Writing `cheerio.load(html || "").text()` to strip HTML tags to
plain text threw `TypeError: cheerio.load(...).text is not a function` at runtime (only caught via
the app's live JS-error log, not at write time — this shim has no compile-time type checking).
Every other plugin in the codebase that needs this (`asurascans.js`'s `stripHtml`) uses a plain
regex instead: `(html || "").replace(/<[^>]*>/g, "").trim()`. Reach for that pattern for any
"strip HTML to plain text" need — don't assume real-cheerio API surface is available (see S87's
note: it's a hand-rolled ~350-line parser, not the actual cheerio library).

**A cold, cookie-free request is the only real test of whether a site is Cloudflare-blocking
`SOURCE.fetch`.** Verified freewebnovel.com's chapter API worked via the Chrome MCP tab's
`fetch(url, {credentials: 'omit'})` — but that still ran over the same browser/IP that had already
built up Cloudflare trust from earlier navigation in the same session, so the "no cookies" test
was not actually cold. A follow-up plain `curl` from the shell (fresh process, no session, no
cookies) revealed the *same* endpoint returns a Cloudflare "Just a moment…" challenge page —
completely different result. Since `JSBridge`'s `SOURCE.fetch` is exactly this kind of cold,
cookie-less, non-browser request, `curl` from a fresh shell is the correct proxy for what the app
will actually experience — a same-tab `fetch()` with `credentials: 'omit'` is not, because
IP/TLS-fingerprint-based Cloudflare trust persists across requests on the same connection/session
regardless of the `credentials` option.

**Extension ID migrations need an explicit "retire the old row" step, not just "insert the new
one."** `PluginCatalogService.availableUpdate(for:)` already falls back to matching installed
extensions to catalog entries **by name** when the id doesn't match — a reasonable compatibility
shim for exactly this situation — but `ExtensionManager.install()` had no matching cleanup: it
always wrote the new id's row without checking whether an older-id row for the same plugin already
existed. The two mechanisms need to agree: if update-detection tolerates an id mismatch via name,
install must also *resolve* that mismatch, or every id-scheme migration silently doubles affected
rows forever. General lesson for any "id" that's meant to be a stable identity for the same real
underlying thing: a name/identity-based fallback lookup is only safe if the write path also
converges those rows back onto the canonical id, not just the read path.

**When verifying a live device/simulator bug via direct DB inspection, confirm you're looking at
the *current* app container.** `find`-ing for `yomi.db` under a device's `Containers/Data/
Application/` returned a stale container from an earlier build (a leftover `Extensions/*.js` file
set that no longer matched what the running app actually had) before the real, currently-mounted
container was found by sorting on file mtime. A wrong container silently produces a
plausible-looking but wrong answer (in this case, briefly concluding a fix hadn't taken effect when
it actually had) — always cross-check container mtime, not just presence of the expected file.

## Technical learnings — S87

**`URLCache` silently defeats "force refresh" unless you say so explicitly.** Both
`PluginCatalogService.fetchCatalog(force: true)` and `ExtensionManager.install()` called
`URLSession.shared.data(from:)` with the default cache policy. Firebase Hosting sends
`Cache-Control: max-age=3600`, so redeploying a `.js` plugin or `index.json` had **zero effect**
on already-running app sessions for up to an hour — "Update" buttons and even full
uninstall+reinstall cycles kept silently re-serving old cached content, no error, no signal
anything was wrong. Lesson: any fetch whose entire *purpose* is "get the current version" (an
explicit refresh, an install/reinstall) must use `.reloadIgnoringLocalCacheData`, not just rely on
a `force` flag name to imply it bypasses caching — the flag only bypassed the app's own in-memory
TTL guard, not `URLCache`. This cost most of a debugging session before being traced to caching
rather than the actual JS logic (which was correct from the first rewrite).

**A misleading generic error message can send you down the wrong root cause for hours.**
AquaManga's "No titles found — the site may be down or Cloudflare-protected" message was accurate
in *neither* direction: the site was up, not Cloudflare-blocking the actual requests, and the real
problem (stale CSS selectors after a site redesign) wasn't in the message's hypothesis space at
all. When a generic/hedged error message is the only lead, verify each hypothesis it names
independently and explicitly (here: temporary `print()` debug logging directly in the exact
`URLSession.dataTask` completion handler proved the fetch itself succeeded with real content,
which ruled out Cloudflare in about two minutes) rather than assuming the message's own framing is
correct and building the investigation around it.

**Custom parser code needs testing outside the app to debug efficiently.** `JSBridge.swift`'s
`cheerio` is a hand-rolled ~350-line HTML parser + CSS selector engine (not the real cheerio
library), evaluated inside `JSContext`. When results came back empty, the fastest way to prove the
selector logic itself was correct (vs. suspecting the parser) was extracting the exact shim source
into a standalone file and running it under Node.js against a real HTML fragment captured live via
a Chrome MCP session — far faster than iterating by rebuilding the iOS app and reading through
`print()` output each time. Keep this in mind for any future `cheerio`/selector debugging: reach
for Node standalone repro before assuming a live-app rebuild cycle is required.

**`mobile-mcp`'s `mobile_swipe_on_screen` `distance` parameter is unreliable for fine scrolling.**
Observed identical large scroll jumps for `distance: 1` and `distance: 800` — the gesture appears
to always fling with similar velocity regardless of the requested distance, in this session's
simulator. This made reaching a specific short section between two known screens (e.g. one row in
a long Settings list) impractical via repeated small swipes. Workaround used: navigate more
directly instead (search fields, fewer intermediate screens) rather than fighting the gesture.

## Technical learnings — S85

**Design tokens existing ≠ design tokens applied.** `YomiTokens.Canvas` (Ink/Midnight/Paper/Sepia)
was fully built in S80-S81 with correct bg/surface/text colors, but nothing outside
`AppearanceStudioView`'s own preview card ever read it — `ContentView`/`YomiApp` only drove
`.preferredColorScheme` (system light/dark) + accent tint. The app looked like "plain system dark
mode" for 4 sessions (S82-S85) because the token *system* existed but was never wired to the actual
chrome. Lesson: when a design-fidelity gap looks like "wrong colors everywhere," check whether the
token is defined vs. whether it's actually consumed at the root — grep for the enum/struct name
across the whole app, not just the screen you're looking at.

**SwiftUI environment values are the right tool for cross-cutting theme state.** Fixed the above by
adding one `\.yomiCanvas` `EnvironmentKey` (`Core/CanvasEnvironment.swift`), set once in
`ContentView` from `AppSettings.canvasColors`, read via `@Environment(\.yomiCanvas)` in any child —
no need to thread a parameter through every view's init or re-read `AppSettings.shared` everywhere.

**`mobile-mcp` element coordinates are the bounding box's top-left corner, not its center.**
`mobile_list_elements_on_screen` returns `{x, y, width, height}` with `(x, y)` at the top-left.
Tapping that raw `(x, y)` works fine for large text buttons but misses small circular hit targets
(e.g. 44×44 glass chips) since the corner falls outside a circle inscribed in that square. Always
tap `(x + width/2, y + height/2)`.

**A screenshot that looks unchanged after a tap doesn't always mean the tap failed.** Native SwiftUI
`Menu` popovers animate in over ~0.2s; a screenshot taken immediately after the tap can race the
animation and look like nothing happened. Re-fetch elements or screenshot again before concluding a
control is broken.

## Research methodology — lessons learned (post S42)

### The Suwayomi blind spot: "impossible" is never the final answer

For 40 sessions, every question about Keiyoushi/Tachiyomi/Mihon extensions received the same answer: **"impossible — Kotlin APKs, Android-only runtime, no iOS path."** This was technically correct for *direct integration* but missed the actual solution entirely.

**What was missed:** Suwayomi/Tachidesk is a self-hosted Java server that runs all 1000+ Keiyoushi Kotlin extensions server-side and exposes them as a REST+GraphQL API. The iOS app needs zero Kotlin — just URLSession. This was available from S1. It shipped in S41.

**Root cause of the miss:** Research stopped at the first-order question ("can Kotlin run on iOS?") and never asked the second-order question: **"what server-side bridges or proxies exist in this ecosystem?"**

### Rule for all future research

> When a direct implementation path is blocked, ALWAYS ask: **"Does a proxy, bridge, or server exist that exposes this through an API Yomi can consume?"**

Checklist to run before concluding "impossible":
1. Is there a self-hosted server that wraps this ecosystem? (Suwayomi for Keiyoushi, Komga for CBZ libraries)
2. Is there a REST/GraphQL API maintained by a third party?
3. Is there a web interface that could be scraped or automated?
4. Does any competing iOS app already support this — and if so, how?

**Point 4 is the most reliable signal.** If Paperback, Aidoku, or any other iOS reader already supports a feature or ecosystem, there is a path. Find out how they did it before concluding it's impossible.

### Implication for web search

Never rely on training-data knowledge alone for ecosystem research. Training data has a cutoff and may not reflect current tools, servers, or bridges. Use `WebSearch` for:
- "X iOS reader how does it support Y extensions"
- "Y extension format iOS bridge"
- "self-hosted server for Y manga/novel sources"

### What this means for the current app

Suwayomi is already integrated (S41). The same second-order thinking applies to every future "impossible" claim:
- "Kindle books can't be read" → is there a Calibre REST API?
- "Cloudflare blocks everything" → is there a FlareSolverr proxy?
- "Mangayomi uses Flutter+Dart plugins" → is there a server bridge or REST API?

Always ask the second question.

## Technical learnings — S47

- **`FormData` is a global, not a `require()` module**: LNReader's Madara/WordPress multisrc plugins (52+ sources) use `new FormData()` directly — it is a Web API global, like `URL` or `URLSearchParams`, not something loaded via `require()`. JavaScriptCore has none of these Web APIs. Missing `FormData` throws `ReferenceError: Can't find variable: FormData` at the very first line of `popularNovels()`, silently returning `[]`. Fix: inject a `FormData` constructor into `injectWebAPIs()` alongside `URL` and `URLSearchParams`. It only needs `_entries` array + `append`/`get`/`has`/`set`/`toString` — no file upload support required.

- **FormData body requires `Content-Type: application/x-www-form-urlencoded`**: the Madara plugins POST to WordPress's `wp-admin/admin-ajax.php` with a FormData body. The server reads parameters via PHP's `$_POST` superglobal, which only populates when `Content-Type` is `application/x-www-form-urlencoded` (for URL-encoded) or `multipart/form-data`. Since our shim serializes FormData as URL-encoded, the header must be set automatically — plugins don't set it themselves. Detect FormData body via `rawBody._entries` (the private marker array), serialize, and inject the header. Both `@libs/fetch`'s `fetchApi` and the global `fetchApi` in `injectSourceFetch` need the same treatment.

- **Full plugin audit pattern**: to find JSBridge gaps in an ecosystem, scan all plugin files for `require(` calls + global constructors. For LNReader: `grep -rh "require(" plugins/ | grep -oP "'[^']+'" | sort | uniq -c | sort -rn` gives the complete require frequency table. Then `grep -rl "FormData\|fetch\b" plugins/` finds global usage. This takes 60 seconds and surfaces all gaps at once.

- **`@libs/isAbsoluteUrl` is simple**: returns a boolean — `true` if the string has a scheme prefix. A simple `indexOf('://') > 0 && indexOf('://') < 20` check is sufficient without regex backslash escaping concerns in Swift string literals.

- **S46 cheerio shim correction — `each`/`map` pass wrapped objects, not raw nodes**: the S46 summary incorrectly described the final fix as "pass raw DOM nodes." The actual committed fix passes **wrapped cheerio objects** (`wrap([nodes[i]])`). This is compatible with both plugin styles: (1) Yomi-style `el.find(...)` — works because the wrapped object has `.find()`; (2) LNReader AO3-style `$(t).find(...)` — works because `$()` detects `typeof selector.find === 'function'` and returns the wrapper as-is. The METODOLOGIA S16 entry was updated in S46 to note this, but the description was still wrong. The wrapped-object approach is correct and final.

## Technical learnings — S45

- **Cloudflare auto-bypass with hidden WKWebView**: attach a 1×1pt `WKWebView` (frame `CGRect(x: -2, y: -2, width: 1, height: 1)`) to the app's `keyWindow`. It loads the URL silently in the background — the real WebKit engine solves the CF JS challenge without any user interaction. Poll `webView.configuration.websiteDataStore.httpCookieStore.getAllCookies` every 0.5s. `httpCookieStore` callbacks arrive on an arbitrary queue — always dispatch back to main before calling completion. Keep a 10s `Task` timeout as safety.

- **WKWebView navigationDelegate is held weakly**: `WKWebView` holds its `navigationDelegate` as a `weak` reference. If the coordinator is only a local variable, it will be deallocated before the delegate method fires. Solution: store the delegate in a `class` instance held by the caller (e.g. `AutoBypassHelper` owns itself as long as `withCheckedContinuation` is alive, since the continuation is captured in the class property).

- **`withCheckedContinuation` keeps the caller alive**: when `withCheckedContinuation` is used inside an `async` method on a `class` instance, the class instance is retained for the duration of the continuation's lifetime. This means `AutoBypassHelper.run(url:)` is safe — `self` remains alive even after `run()` returns (it's awaiting continuation resolution).

- **Top-level `let` in Swift 6 is `@MainActor` by default**: module-level stored `let` constants (not `lazy`) are inferred as `@MainActor` by Swift 6's concurrency model. Accessing them from `nonisolated` contexts produces a warning. Fix: add `nonisolated(unsafe)` if the type is non-`Sendable`; for `Sendable` types (like `NSLock`), the compiler will also warn that `nonisolated(unsafe)` is "unnecessary". Both warnings build successfully — pick whichever produces fewer total warnings (usually `nonisolated(unsafe)` on the var).

- **LNReader v3 plugins export via `module.exports`, not `globalThis.plugin`**: LNReader v3.0.0 TypeScript plugins compiled with CommonJS output set `module.exports = pluginInstance`. The `injectLNReaderAdapter` that runs AFTER `evaluateScript` must check `module.exports` / `exports.default` as fallback before the `var p = global.plugin; if (!p) return` guard. If not done, the plugin is treated as Format A (manga), `getMangaList` finds no function, and returns empty results.

- **Mangayomi catalog is Dart-only**: `sourceCodeUrl` for every Mangayomi entry ends with `.dart`, not `.js`. Installing them downloads a Dart file saved as `.js`. JSC evaluates Dart source as JavaScript → exception thrown → no globals set → `getMangaList` returns `[]`. Fix at catalog level (filter before install, not after).

- **LNReader v3 `@libs/fetch` returns an object, not a function**: `require("@libs/fetch")` must return `{ fetchApi: fn }` — not a raw function. Plugins call `(0, n.fetchApi)(url, opts)` — indirect call pattern to strip `this` binding. Returning `{}` silently sets `n.fetchApi` to `undefined`, which throws `TypeError` at call site. Same pattern applies to any `@libs/*` module that destructures its export.

- **`@State` with a parameter requires an `init`**: you cannot write `@State private var x = someParam` — the `@State` wrapper's initial value must be a literal or a constant expression. To initialize `@State` from a constructor argument, write `init(param: T) { _x = State(initialValue: param) }`. Attempting `@State private var x: String` then assigning in `init` via `self.x = …` compiles but ignores the value — `@State` ignores direct property assignment outside the `_x = State(…)` form.

- **`CFBypassView` `initialURL` pre-fills and auto-navigates**: `makeUIView` in `CFWebViewRepresentable` calls `navigate(wv)` immediately on creation. So if `urlText` is pre-filled with a valid URL (from `bridge?.cfBlockedURL`), the WKWebView navigates there automatically when the sheet opens — no user action required.

- **`JSContext.evaluateScript` drains microtasks before returning to Swift**: JSC internally calls `drainMicrotasks()` after executing a script, before returning control to the Swift caller. This means a full `async`/`await` Promise chain (compiled from TypeScript's `__awaiter`/`__generator`) resolves within a single `evaluateScript` call, provided all underlying operations are synchronous (i.e., `SOURCE._fetchSync` blocks and returns). **Consequence:** you can capture the resolved Promise value in a JS global (`__lnr_result`) and read it from Swift immediately after `evaluateScript` returns — it will always be populated. This is the correct pattern for calling LNReader v3 async plugin methods from Swift.

- **`JSValue.call(withArguments:)` does NOT drain microtasks**: calling a JS function from Swift via `.call(withArguments:)` returns the raw return value of the function — which is a `Promise` object for any `async` method. Microtasks are NOT drained before `.call` returns. The old `_resolve` trick tried to read a result set by a `.then()` callback, but `.then()` is a microtask scheduled for AFTER the call returns — so Swift always read `undefined`. Only `evaluateScript` triggers the microtask drain. **Rule: never call async JS plugin methods via `.call(withArguments:)` — always use `evaluateScript` with a global result variable.**

- **LNReader v3 TypeScript compiles `async/await` to `__awaiter`/`__generator`**: every `async` method in a LNReader v3 plugin returns a `Promise`, not a synchronous value. The compiled output looks like: `return __awaiter(this, void 0, void 0, function* () { yield SOURCE._fetchSync(...); return parsedItems; })`. Without the `evaluateScript` drain trick, every plugin method appears to return `undefined` to Swift. The correct `callPluginMethod` helper injects: `var __r = plugin['methodName'](...); if (__r && typeof __r.then === 'function') { __r.then(function(v) { __lnr_result = v; }); } else { __lnr_result = __r; }` — then reads `__lnr_result` after `evaluateScript` completes.

- **`JSContextDrainMicrotasks` is not exported in the iOS JavaScriptCore SDK**: the C function `JSContextDrainMicrotasks(JSContextRef)` exists on macOS (confirmed in TBD files) but is absent from the iOS simulator and device TBD files. Attempting `@_silgen_name("JSContextDrainMicrotasks")` in Swift 6 fails at link time with "undefined symbol". Do NOT attempt to call it on iOS — use `evaluateScript` instead, which drains internally.

## Technical learnings — S44 JavaScript lexical scope in JSC

### `const`/`let` at top-level are NOT on globalThis

In JavaScript, `var` at the top level of a script creates a property on the global object (`globalThis.x` works). But `const` and `let` at the top level create bindings in the **global lexical environment** — NOT properties on `globalThis`.

**Consequence:** Mangayomi plugins use `const source = {...}`. Inside a `injectMangayomiAdapter` JS closure, `global.source` (where `global = this`) is **undefined** because `source` is lexical, not a global object property.

**Correct detection:**
```javascript
// WRONG — doesn't find const/let bindings
var src = global.source;

// CORRECT — identifier lookup walks lexical scope
var src = null;
try {
    if (typeof source !== 'undefined' && source !== null) src = source;
} catch(e) {}
```

`typeof source` performs an identifier lookup that checks the lexical environment, finding `const source`. `global.source` only checks the global object property bag.

**Note:** `context.objectForKeyedSubscript("source")` in Swift/JSC DOES find lexical bindings (it checks both), so Swift-side detection works. The bug only affects JS-side detection within a second `evaluateScript` call.

## Technical learnings — S40 plugin build system

### esbuild IIFE format + JSC global scope
When esbuild compiles TypeScript to `format: 'iife'`, the output is wrapped as `(function() { ... })()`. Inside that IIFE, `var plugin = {...}` would be **function-scoped** (not global) and thus inaccessible via `context.objectForKeyedSubscript("plugin")` in JSC.

**Correct pattern:** end every TypeScript plugin with `(globalThis as any).plugin = plugin;`. This works because `globalThis` refers to the actual global object in JSC (available iOS 14+), so the property is set globally and JSBridge's `context.objectForKeyedSubscript("plugin")` finds it.

**Wrong pattern:** `var plugin = {...}` at top level in TypeScript → esbuild wraps it in IIFE → variable is local → JSC detection fails.

### build-plugins.mjs merge strategy
The script now loads existing Firebase index.json before writing. New TS-compiled entries override existing entries with the same `fileURL`; all other existing entries are preserved. This lets us mix hand-written `.js` files (existing 9 plugins) with TypeScript-compiled ones (new 6) in the same catalog.

### Multi-repo catalog merge in PluginCatalogService
`withThrowingTaskGroup` fetches all URLs concurrently (not sequentially). The `for try await result in group` loop is safe — it serializes result consumption even though tasks run in parallel. Post-merge dedup uses `Set<String>` of seen IDs and processes batches in fetch order (first catalog = highest priority on conflict).

## Competitive research — S38 (Tachimanga)

### Sources
- Full changelog scraped: tachimanga.app/docs/changelogs.html (v1.1–v4.15, Apr 2026)
- Full localization file: Weblate export ZIP — `tachimanga-intl-en.csv` (809 strings, Apr 19 2026 build)
- The ARB file in the same ZIP is for Sorayomi (Flutter desktop client), not the iOS app

### Key findings
- Tachimanga is **Flutter-based** (not SwiftUI). Many features Yomi has natively (SwiftUI animations, iOS 26 Tab API) are harder for them.
- **Premium paywall** on notes, sync, unlimited downloads. Yomi is fully free — strong competitive differentiator to highlight in App Store description.
- **Features Yomi already has** at parity: OLED mode, incognito, backup/restore, reading insights, categories, multi-select, downloads, progress resume, page slider, unread badge, alternate icons, NSFW filter, MAL tracking, reading status, continue reading.
- **Biggest gaps (S38):** auto webtoon from tags, hold-to-scroll, skip update conditions, concurrent downloads, delete-after-read, chapter sort options, random entry, text selection on descriptions.
- **Medium gaps (S39):** scanlator filter/priority, reader tap zones, separate padding settings, auto-scroll, saved searches, custom covers.
- **Long-term gaps (S40+):** app lock, Tachiyomi backup import, bulk migration, multiple extension repos.
- **Yomi exclusives to build (S41):** WidgetKit, TTS for novels, manga notes (free), global search, tab reordering.

### Tachimanga localization string keys worth knowing
- `auto_webtoon_mode` / `auto_webtoon_mode_desc` — tags: 'webtoon', 'long strip', 'manhwa'
- `hold_to_scroll` — only in webtoon + continuous modes
- `remove_after_read` — delete download automatically when chapter marked read
- `concurrent_download_title` / `concurrent_download_tips` — warn about IP bans from same-source concurrent
- `skip_updating_titles_with_unread_chapters` / `that_havent_been_read` / `with_completed_status`
- `exclude_categories` — categories excluded from global update
- `action_open_random_manga` — random entry from library
- `readerNavigationLayout*` — 6 tap zone layout modes (Default, Edge, Kindle-ish, L-Shape, Right&Left, Disabled + Invert toggle)
- `readerPaddingWebtoon` / `readerPaddingPaged` — separate per mode
- `scanlator_filter_label` / `scanlator_priority_label` — filter + priority per manga
- `saved_searches` / `save_query_title` — persist named search queries
- `repair_database` — dangerous DB repair tool
- `liquid_glass_appearance_title` — iOS 26 Liquid Glass toggle

### Addendum — S89: how Tachimanga does Keiyoushi
Confirmed via web research: Tachimanga does **not** embed or bundle Keiyoushi/Suwayomi — it's a
thin REST client against a separately self-hosted Suwayomi-Server (Docker/JVM/standalone jar),
same architecture Yomi already shipped in S41 via `SuwayomiService.swift`. No Flutter-specific
trick, no App Store precedent for bundling the JVM (matches the S53 feasibility study's DEFER
verdict). The reason it "just works" for Tachimanga users and didn't for Yomi users wasn't
architecture — it was two real bugs in `SuwayomiService.swift`/`Info.plist` (missing ATS
exception + a 404ing chapter-list REST path), both fixed and live-verified S89. See
`ROADMAP.md`'s S89 entry.

## Technical learnings — S39 visual audit

### Tachimanga is a Flutter+JVM app, not a native iOS JS app
The "credits" screen of Tachimanga reveals its architecture: it is built on Tachidesk-Server (Kotlin/JVM, fork of Suwayomi-Server) + Tachidesk-Sorayomi (Flutter UI). The app bundles an embedded JVM that runs as a local HTTP server, executing real Mihon/Tachiyomi Kotlin extensions. The Flutter UI communicates with the server via REST.

**Why this matters:**
- Tachimanga's 100+ sources come from Kotlin APK extensions — not JS plugins. We cannot run them.
- Their architecture requires ~100MB+ JVM bundle; Yomi is fully native Swift with no server.
- The architectural gap is not closeable by writing more plugins. Our response must be quality over quantity.
- Tachimanga is Flutter-based, so it cannot use SwiftUI, iOS 26 APIs, or native animations. This is a UI quality moat for Yomi.

### Cloudflare bypass pattern (from Tachimanga Advanced settings)
Tachimanga's "Bypassing Cloudflare automatically" toggle works by:
1. Opening a hidden `WKWebView` to the blocked domain
2. Waiting for WKWebView to complete the JS challenge (authentic browser fingerprint)
3. Extracting `cf_clearance` cookie + User-Agent via `WKWebView.configuration.websiteDataStore.httpCookieStore`
4. Injecting both into subsequent `URLSession` requests for that domain

This is implementable in Yomi. The 403 from SOURCE.fetch triggers the bypass flow; subsequent retries with the extracted cookies succeed. Comick and ~5 other sources would be unblocked.

### Keiyoushi extensions are Kotlin APKs — not usable in Yomi
The keiyoushi extension repo (`raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json`) lists 1000+ extensions but they are Kotlin `.apk` files compiled for Android/JVM. Tachimanga runs them via its embedded JVM. Yomi cannot load them. Do not attempt Kotlin extension compatibility — it requires bundling a JVM runtime which is impractical for App Store distribution.

### Tachimanga premium paywall — our opportunity
Many features Tachimanga charges for, Yomi provides free: OLED mode, app lock (planned S41), notes (planned S41), tracking (MAL already free), tab reordering (planned S41). The paywall is a genuine user pain point (visible in App Store reviews). Yomi's "fully free" positioning is a real competitive differentiator worth highlighting in App Store description.

## Technical learnings — S76 simulator and mobile-mcp

### Two simulator instances with same model + OS cause divergent app data
Xcode and XcodeBuildMCP can each track a different UDID when multiple instances of the same simulator model exist (e.g., "iPhone 17 Pro iOS 26.3" created twice via Xcode → Devices). Each UDID has its own isolated sandbox, UserDefaults, SQLite database, and Keychain — app data is completely separate. Symptoms: different accent color, different library content, different settings between what Xcode shows and what automation tests.

**Fix:** `xcrun simctl list devices available` lists all UDIDs. Call `mcp__XcodeBuildMCP__session_set_defaults` with `simulatorId: "UDID"` and `persist: true` — this writes to `.xcodebuildmcp/config.yaml` in the project root and survives session restarts. Confirm Xcode's active device in the scheme selector matches the same UDID.

### mobile-mcp cannot tap SwiftUI List `.onTapGesture` rows
SwiftUI `List` rows that use `.onTapGesture` for navigation render as `StaticText` accessibility elements with `custom_actions` (e.g. "Download", "Read", "Mark previous"). `mobile_click_on_screen_at_coordinates` fires a direct tap, which iOS routes to the `StaticText` default action — none. The tap is silently ignored.

`Button`-wrapped rows (e.g. novel chapter rows) DO respond correctly to coordinate taps since they render as `Button` accessibility elements with a default action.

**Workaround:** use `mobile_list_elements_on_screen` to identify element type. If `StaticText` with `custom_actions`, the row cannot be tapped via automation — verify via code review or physical device instead.

### XcodeBuildMCP `session_set_defaults` with `persist: true` survives restarts
Writing session defaults with `persist: true` saves to `.xcodebuildmcp/config.yaml` (project root). This file is loaded automatically on every Claude Code session start — no need to call `session_show_defaults` + `session_set_defaults` at session open if the config exists and is correct.

## Technical learnings — S37

### CancellationError must always be caught before the general catch
When a SwiftUI `.task {}` modifier is cancelled (e.g., user switches away from the tab before the task completes), Swift throws `CancellationError`. Any `do { } catch { }` block that doesn't explicitly handle `CancellationError` will treat it as a real failure and set error state. Pattern: always add `catch is CancellationError { isLoading = false }` BEFORE the general catch block in any async fetch function used by `.task {}`.

### Stable IDs for Browse-created model objects
When constructing model objects in Browse (not from DB), never use `UUID().uuidString` for IDs. A new UUID is generated every time `loadContent()` is called, so the same novel/manga gets different IDs on each Browse visit. Use deterministic IDs derived from the path: `"\(sourceId)_\(path)"`. This allows DB lookups to succeed on re-entry and chapter read state to persist.

### guard let ext else { return } without state cleanup is a hidden failure
`guard let ext else { return }` that fires mid-function (after the spinner was started, or before it was started) leaves UI in an inconsistent state — spinner stuck, empty content, no error message. Always include `isLoadingChapters = false` (or equivalent) in the guard's else branch before returning.

### GRDB reads from MainActor must use Task.detached
CLAUDE.md rule reconfirmed: `appDatabase.read { }` from `@MainActor` context blocks the main thread. Any `try?` synchronous call to `*Queries` methods inside `.task {}` or `.onAppear {}` should be wrapped in `Task.detached(priority: .userInitiated)`. Library loads (MangaQueries.fetchLibrary etc.) called synchronously in LibraryViewModel.loadLibrary() work in practice but are technically incorrect — deferred fix.

## Technical learnings — S35

### Source removal protocol: research before removing
When a source returns 403 or empty results, **do not remove it from the catalog immediately.** A 403 can have multiple causes:
- **Permanent Cloudflare block** (comick, lightnovelpub): URLSession always blocked as non-browser. Source never works.
- **Temporary security incident** (novelfire, S35): Site under attack, returns 403 during the incident window. Source will recover.
- **Site downtime / DNS issue**: Transient, resolves on its own.

**Protocol before removing any source:**
1. Check the source's home page via WebFetch — look for a status banner or notice.
2. Search the source's social media / Reddit / Discord for recent announcements.
3. If confirmed temporary, mark the source in `index.json` with a note and wait. Only remove if it's confirmed permanent (site dead or permanently Cloudflare-blocked as policy).

**Applied lesson (S35):** NovelFire was removed from index.json after observing Cloudflare 403. The correct action was to first check their site — they had posted a public security notice about an active attack. The source should be restored once the incident resolves.

### JSContext vs WKWebView for plugin execution
JSContext runs in the same process as the host app. iOS sandbox **disables JIT compilation** for same-process JS. WKWebView runs in a separate process with JIT enabled (12–15x faster for JS execution). However, WKWebView **suspends when not on screen** — any hidden off-screen WKWebView used for plugin execution will be suspended during background update checks, breaking UpdatesViewModel. JSContext's DispatchSemaphore synchronous model is also incompatible with WKWebView's async-only bridge. **JSContext is the correct choice for Yomi's current architecture.**

### Targeted WKWebView fallback for JS-rendered content
Some novel source pages (e.g., NovelFire synopsis) are rendered by client-side JavaScript after initial HTML load. `URLSession` + HTML parsing cannot capture dynamically injected content. Solution: add `requiresWebView: true` metadata flag to specific Format B plugins. JSBridge detects this flag and uses a hidden `WKWebView` to load the detail page, inject JS to extract rendered content, then return the result. This is a narrow escape hatch — does NOT change the general plugin execution model, which stays in JSContext.

### Aidoku source format (.aix / Rust WASM)
Aidoku community sources are written in **Rust**, compiled to WASM via `cargo build --target wasm32-unknown-unknown`. The `aidoku-rs` crate provides the `Source` trait and `register_source!` macro. Sources are distributed as `.aix` packages containing the compiled `.wasm` binary. Aidoku embeds a WASM runtime to execute them. This architecture provides true memory sandboxing and AOT performance, but requires plugin authors to know Rust and the `aidoku-cli` toolchain. Not viable for Yomi at current scale.

### Paperback plugin shim — what S24 built vs. what's missing
S24 implemented `require('paperback-extensions-common')` in the JSBridge cache, injecting a `Source` base class and `App` constructors. `injectPaperbackAdapter()` detects if a `Source` subclass was registered in `exports` post-eval, and wires `getMangaList/searchManga/getChapterList/getPageList` adapters. **What S37 must complete:** Paperback's HTTP layer uses `requestManager.schedule(request, 1)` which creates a `Request` object before executing. The shim must intercept `request.url`, `request.headers`, and `request.method` and route to `SOURCE._fetchSync`. Many real Paperback sources use this pattern — without it, they throw at runtime.

### iOS 26 app icon: 3-layer Liquid Glass format
Starting iOS 26, app icons require three transparent PNG layers (Background, Midground, Foreground) plus 6 visual modes (Default, Dark, Clear Light, Clear Dark, Tinted Light, Tinted Dark). The system composites them in real-time. **Icon Composer** (bundled with Xcode 26) handles layer import and preview. The `UIApplication.setAlternateIconName()` API is unchanged — alternate icon sets follow the same 3-layer structure. Backward compatible: older OS falls back to single-image assets.

## Technical learnings — S29

### Auto-mark read: race condition between onDisappear write and onAppear read
`ChapterReaderView.onDisappear` writes to DB (markChapterRead). Parent `MangaDetailView.onAppear`
fires simultaneously and reads DB (refreshChapterStates). The parent wins the race before the write
settles → UI shows chapter still unread.

Fix: don't rely on `onAppear` for post-read refresh. Instead, use `.onChange(of: chapterForNav)`:
```swift
.onChange(of: chapterForNav) { old, new in
    guard new == nil, old != nil else { return }
    Task {
        try? await Task.sleep(for: .milliseconds(500))
        await refreshChapterStates()
    }
}
```
500ms delay lets the onDisappear Task.detached write settle before the parent reads.
The `guard new == nil, old != nil` condition fires exactly once: when the user returns from the reader.

### SwiftUI overlay animation: opacity vs if-gating
`if showOverlay { topBar }` removes the view from the hierarchy when overlay hides. SwiftUI cannot
animate the disappearance of a removed view — the fade-out never plays.

Fix: keep views in the hierarchy and animate opacity:
```swift
VStack { topBar; Spacer(); bottomBar }
    .opacity(showOverlay ? 1 : 0)
    .allowsHitTesting(showOverlay)
    .animation(.easeInOut(duration: 0.2), value: showOverlay)
```
`.allowsHitTesting(false)` when hidden prevents invisible buttons from intercepting taps.

### JSBridge optional plugin functions
Pattern for calling plugin functions that may not exist:
```swift
nonisolated var supportsLatest: Bool {
    guard let fn = context.objectForKeyedSubscript("getLatestManga") else { return false }
    return !fn.isUndefined && !fn.isNull && fn.isObject
}
```
Call site: `guard supportsLatest else { return [] }`. This makes features optional per-plugin
without crashing. Sources without `getLatestManga` get `supportsLatest = false` and no picker is shown.

### Bridge reuse across tab switches
Creating a new `JSBridge` parses and evaluates the full JS file — expensive (10–50ms depending on
plugin size). When switching between Popular/Latest tabs in `SourceBrowseView`, reuse the existing
bridge instead of creating a new one:
```swift
let b: JSBridge
if let existing = bridge { b = existing } else { b = try makeBridge(); bridge = b }
```

### Incognito mode: skip persistence at DB write site
Read the flag at the earliest possible point before any DB write, not in the view layer:
```swift
let incognito = AppSettings.shared.isIncognito
// ...
guard !incognito else { return }
markChapterRead()
updateProgress()
```
Single guard covers all persistence. No changes needed in the query layer.

### navigationDestination(item:) requires Hashable
`navigationDestination(item: $chapterForNav)` where `chapterForNav: Chapter?` requires `Chapter`
to conform to `Hashable`. The fix is one line:
```swift
struct Chapter: Identifiable, Codable, Hashable { ... }
```
SwiftUI synthesizes `Hashable` automatically from all stored properties (which are all Hashable types).

## Technical learnings — S28 (audit)

### INSERT OR IGNORE is mandatory for chapter list persistence
`MangaDetailView.loadChapters()` fetches chapters from JSBridge but never calls any INSERT.
Every subsequent SQL UPDATE (`markRead`, `markDownloaded`, `updateProgress`) silently affects 0 rows
because the chapter row doesn't exist. This is the root cause of both the "downloads not showing"
and "read state not persisting" bugs reported in S26 and S27.

Fix pattern:
```swift
nonisolated static func insertAllIgnoringConflicts(_ chapters: [Chapter]) throws {
    _ = try appDatabase.write { db in
        for ch in chapters { try ch.insert(db, onConflict: .ignore) }
    }
}
```
Call in `loadChapters()` AFTER fetching from JSBridge, BEFORE the DB merge step.
**Never use `chapter.save(db)` or `chapter.insert(db)` alone for chapter list persistence.**
`save()` is INSERT OR REPLACE — it overwrites existing isRead/isDownloaded/progress state.
`insert()` throws on conflict. Only `.insert(db, onConflict: .ignore)` is safe: inserts new rows,
skips existing ones without touching their state.

### @Observable DownloadManager.completedDownloadCount pattern
To propagate download completion to views that aren't the active download target, add an observable
Int counter to DownloadManager that increments after each successful download. Views observe via
`.onChange(of: downloadManager.completedDownloadCount)` and call their refresh function. This avoids
NotificationCenter and keeps the reactive chain entirely in SwiftUI observation.

### refreshChapterStates() — lightweight DB merge without JSBridge
When a view needs to reflect DB state changes (download complete, read state change) without
re-fetching the full chapter list from the network, use a merge function that:
1. Fetches all chapters for the manga from DB (one SQL query)
2. Builds a Dictionary<String, Chapter> keyed by id
3. Maps in-memory chapters: if savedMap[ch.id] exists, copy isRead/isDownloaded/progress/lastPageRead/readAt

This pattern is safe to call on .onAppear without causing a network fetch.

## Technical learnings — S27

### Chapter progress resume: lastPageRead vs progress ratio
Two strategies for reading resume:
- `progress: Double` — fractional position 0.0–1.0. Used for MAL tracking and webtoon scroll.
- `lastPageRead: Int` — exact page index. Used for manga chapter resume.

Using a page ratio to derive an index introduces floating-point drift (a 47-page chapter at
progress 0.6 gives page index 27.6 → 27 or 28 depending on rounding). Use `lastPageRead`
for exact resume when the chapter has been partially read and the page count is known.
Fallback: if `lastPageRead == 0` and `progress > 0`, use ratio calculation as legacy fallback.

### Source filter re-trigger pattern in search views
When a search view has both a text query and a source picker, the source change must immediately
re-trigger the search. Extract the search logic into a shared function `runSearch(query:debounce:)`
that both `.onChange(of: searchQuery)` and `.onChange(of: selectedSource)` call. Source changes
should use `debounce: false` to avoid unnecessary delay — the user already made a deliberate choice.

## Technical learnings — S23

### @Observable + external storage
`@Observable` macro expansion only generates `access(keyPath:)` / `withMutation(keyPath:)`
calls for **stored properties**. Computed properties backed by UserDefaults are invisible to
the observation graph — mutations write to UserDefaults but no notification fires. The fix:
store the value in a `var` with `didSet` that persists to UserDefaults. The singleton's
`private init()` reads the current UserDefaults value into each stored property.
`@ObservationIgnored` must be applied to the `defaults` ivar to prevent the macro from
trying to observe it. `colorScheme` can remain computed because it derives from `theme`
(a tracked stored property) — the observation chain propagates correctly.

### navigationDestination(isPresented:) for dynamic navigation
When the destination view requires reference-type state (like JSBridge) that doesn't conform
to Hashable, use `navigationDestination(isPresented: $flag)` with separate `@State` vars for
the data, rather than `navigationDestination(item:)` which requires Hashable. Set the data
vars first, then set the Bool flag to trigger navigation.

### Slider binding for Int page state
SwiftUI Slider works with Double. To bind it to an `@Binding<Int>`:
```swift
Slider(
    value: Binding(get: { Double(currentPage) }, set: { currentPage = Int($0.rounded()) }),
    in: 0...Double(totalPages - 1),
    step: 1
)
```
The `.rounded()` prevents off-by-one drift from floating point.

### ScrollView fixes overflow in List sections
A plain `HStack` inside a `List` cell does not clip or scroll — items overflow off-screen
silently. Wrap in `ScrollView(.horizontal, showsIndicators: false)` when the content count
is variable or guaranteed to exceed screen width (e.g., color swatch rows).

## Technical learnings — S24

### Paperback shim: Promise resolution in JavaScriptCore
Paperback plugins use async/await (compiled to generator + Promise chains by TypeScript).
These work in JSContext because: (1) SOURCE.fetch is synchronous (DispatchSemaphore), so
`await fetch()` resolves immediately; (2) JavaScriptCore drains the microtask queue before
returning from `evaluateScript` / `JSValue.call(withArguments:)`. The `_resolve(promise)`
helper in the adapter captures the synchronously-resolved value via `.then(v => result = v)`.

### Paperback chapter path encoding
Paperback's `getChapterDetails(mangaId, chapterId)` needs both IDs. Yomi's `getPageList(path)`
only receives one string. Solution: encode as `mangaId + "|" + chapterId` in `getChapterList`,
split on first `|` in `getPageList`. Safe because `|` doesn't appear in typical manga IDs.

### WKScriptMessageHandler for JS→Swift callbacks
To detect scroll-to-end in WKWebView: inject a `WKUserScript` at `.atDocumentEnd` containing
a scroll event listener that calls `window.webkit.messageHandlers.name.postMessage(...)`.
The Coordinator must conform to `WKScriptMessageHandler` and be added via
`config.userContentController.add(coordinator, name: "readComplete")` BEFORE the WKWebView is created.
The `once: true` event listener option ensures the message fires only once per chapter.

### Keychain migration pattern
When migrating from UserDefaults to Keychain: in `loadToken()`, check if the legacy UserDefaults
key exists → save to Keychain → delete from UserDefaults. This runs once on first launch after
update. Users are seamlessly migrated without needing to re-login.

### scrollPosition(id:anchor:) for scroll restoration
iOS 17+: `.scrollPosition(id: $binding, anchor: .top)` tracks the ID of the topmost visible item.
Use `onChange(of: visibleId)` to update currentPage. On appear, call `proxy.scrollTo(id, anchor: .top)`
inside a `ScrollViewReader` to restore position. The binding is `Binding<(Int)?>`  —
unwrap in onChange before assigning to `Int`.

## Competitive & UX research

See `Yomi/RESEARCH.md` §2 (Community Sentiment & User Needs) and §4 (UX & Reading Science) —
the canonical version of this research. The S23-era summary previously duplicated here was
removed during the 2026-08-04 doc restructure.

## S22 — Technical learnings

- **PBXFileSystemSynchronizedRootGroup eliminates manual Xcode target membership**: Yomi uses this Xcode feature, which means any file dropped into the `Yomi/` directory is automatically included in the target. No "Add Files to Yomi" step needed. Confirmed by checking `project.pbxproj` for the `isa = PBXFileSystemSynchronizedRootGroup` entry. Applies to `PrivacyInfo.xcprivacy` and any new `.swift` or resource file. Never perform the manual Xcode add step without first verifying this setting.

- **SourceKit false positives are always noise — xcodebuild is the signal**: swift-lsp (the LSP plugin) analyzes each file in isolation without the full Xcode module context. It will always report "Cannot find type 'Manga' in scope", "Cannot find 'AppSettings' in scope", etc. These are structurally unavoidable and carry zero diagnostic value for this project. The only reliable error source is `xcodebuild`. Rule: ignore SourceKit errors entirely; act only on xcodebuild errors.

- **Chapter.progress is Double, not Double? — check model types before writing conditionals**: the `Chapter` model has `progress: Double` (non-optional). Writing `if let progress = saved.progress` fails to compile. Before writing any conditional binding in a fix, read the model definition to confirm optionality. The correct pattern here: `if saved.progress > 0 { let progress = saved.progress }`.

- **Simulator device names change across Xcode versions**: "iPhone 16 Pro" does not exist in Xcode 26.3.1. Available iPhone simulators: iPhone 16e, iPhone 17, iPhone 17 Pro, iPhone 17 Pro Max, iPhone Air. Always check with `xcrun simctl list devices available | grep iPhone` before hardcoding a destination. Update CLAUDE.md and ARQUITECTURA.md when simulator names change.

- **PrivacyInfo.xcprivacy reason code for UserDefaults: CA92.1**: Apple requires a specific reason code when accessing UserDefaults. The correct reason for a settings/preferences use case is `CA92.1` ("Access from the app itself"). Do not use `C617.1` (which is for user-triggered actions) or leave the reasons array empty — App Store validation checks the reason code, not just the presence of the file.

- **MCP --scope user flag placement**: `claude mcp add --scope user NAME -- COMMAND` is correct. `claude mcp add NAME -- COMMAND --scope user` is wrong — the flag after `--` is passed to the subprocess, not to `claude mcp add`. This caused XcodeBuildMCP and mobile-mcp to register incorrectly on first install.

- **Never share credentials in conversation**: a GitHub PAT was accidentally pasted into the conversation during MCP setup. Revoke and regenerate immediately when this happens. Use `YOUR_TOKEN_HERE` as a placeholder in all command examples in docs.

- **Claude Code-first workflow is strictly better than the relay for this project**: the relay (Claude.ai generates prompts → user copy-pastes → Claude Code executes) was necessary when Claude.ai was the only context-holder. With CLAUDE.md + memory + XcodeBuildMCP, Claude Code has everything it needs to plan and implement independently. The relay added latency, introduced stale-context bugs (S9, S14, S21 regressions), and degraded the user experience. The correct model: Claude.ai for strategic session review, Claude Code for everything inside a session.

- **Reading progress restore: Task.detached for DB read, MainActor.run for state**: after `loadPages()` sets `pages`, reading `chapter.progress` from DB must happen in `Task.detached` (ChapterQueries is nonisolated but DB access should not block MainActor). The page index is `Int(progress * Double(pageCount - 1))`. Setting `currentPage` requires `await MainActor.run { ... }`. Always verify both write path (updateProgress on disappear) and read path (fetchOne on load) when implementing progress features.

- **Pan-when-zoomed requires GeometryReader for clamping dimensions**: `.scaleEffect` scales around the view center but doesn't move the image. Adding pan requires knowing the view's actual rendered size, which means wrapping in `GeometryReader`. Clamping formula: `maxOffset = (scale - 1) * dimension / 2` for both axes. The DragGesture must guard `scale > 1.0` to avoid intercepting the TabView's page swipe gesture at scale == 1.0.

- **Browse pagination: empty page = no more content**: there is no `total` field to compare against in Format A or Format B. The correct signal for "no more pages" is an empty result from the next page fetch. When the source returns 0 items, set `hasMoreContent = false` and hide the button. This works for all 7 current plugins.

## S31 — Technical learnings

- **INSERT OR IGNORE pattern is mandatory for chapter persistence**: using `chapter.save(db)` (INSERT OR REPLACE) would overwrite `isRead`, `readAt`, and `readingSeconds` on every fetch from the source — silently resetting reading progress. Always use `chapter.insert(db, onConflict: .ignore)` in batch persist flows. After the INSERT OR IGNORE, re-fetch the full set from DB to merge the existing state back into the in-memory array.

- **`Column` is a GRDB type — import GRDB in any file that uses it**: TextReaderView originally tried to write `Column("id")` directly in the view. This doesn't compile — `Column` lives in GRDB which the view doesn't import. The fix is to push all DB write logic into the matching `*Queries.swift` file (`NovelQueries.addReadingTime`) and call the typed method from the view. Never import GRDB in views.

- **NovelChapter must be Hashable for `navigationDestination(item:)` to work**: SwiftUI's `navigationDestination(item:)` overload requires the item type to be `Hashable`. Adding `Hashable` conformance to `NovelChapter` (and `NovelReaderDest` structs with UUID-based hashing) unlocks type-safe navigation without isPresented bool gymnastics.

- **JSBridge destinations in navigation structs need custom Hashable**: `JSBridge` is a `final class` that is not `Hashable`. When embedding it in a navigation destination struct, implement `Hashable` via UUID: `let id = UUID()` + `static func ==` + `func hash(into:)` that only hash the UUID. This gives each navigation event a unique identity without requiring JSBridge itself to be hashable.

- **Novel updates need path-based deduplication, not ID-based**: manga chapter IDs are assigned by the source (stable). Novel chapter IDs are synthesized locally as `"\(novelId)-ch-\(index)"`. When checking for new chapters, compare by `path` (source-assigned, stable) not by local ID. The new-chapter detection in `checkNovelUpdates` correctly uses `Set(localChapters.map { $0.path })` and filters `source.chapters` by path.

- **SourceKit diagnostics are always noise in a multi-file Swift project**: every session, SourceKit emits "Cannot find type X in scope" for types defined in other files. These are false positives from single-file LSP analysis. The rule is absolute: ignore all SourceKit errors, trust only `xcodebuild` output. Confirmed this session — BUILD SUCCEEDED with dozens of SourceKit errors still active.

## S21 — Technical learnings

- **WindowGroup / Scene has no `.tint()` modifier**: `.tint()` is a `View` modifier. Applying it to `WindowGroup` fails to compile: "value of type 'WindowGroup<some View>' has no member 'tint'". Both `.preferredColorScheme()` and `.tint()` must be applied to `ContentView()` inside `WindowGroup`, not to the `WindowGroup` or `Scene` itself.

- **`updateUIView` fires on every SwiftUI re-render — guard if expensive**: `UIViewRepresentable.updateUIView` is called whenever the parent view re-evaluates, not only when binding values change. The old `Coordinator.lastHTML` guard that prevented redundant `loadHTMLString` calls was removed in S21. The replacement `evaluateJavaScript` is cheap enough that always-firing is acceptable, but for expensive operations (full page reload, heavy computation) always implement a diffing guard.

- **`#if DEBUG` is the correct gate for dev-only code in `@main App`**: placing `#if DEBUG ExtensionManager.shared.seedBundledPlugins() #endif` in `YomiApp.init()` ensures the release archive is clean. Swift strips `#if DEBUG` blocks in Release configuration by default — no additional build setting needed. This is the correct pattern for any code that must exist in simulator/debug but must never ship.

- **`Color.hexString` via UIColor: sRGB only, P3 values are quantized**: `UIColor.getRed(_:green:blue:alpha:)` returns sRGB components. If the user picks a wide-color P3 color from the system ColorPicker, `hexString` will quantize it to the nearest sRGB value. In practice this is invisible at `#RRGGBB` precision, but the stored hex will differ slightly from the original P3 color.

- **Partial file rewrites silently drop existing logic**: two regressions in S21 (OnboardingView gate, `NovelQueries.markRead()`) happened because the prompt provided a complete replacement file that did not include those pieces. Rule: when replacing an entire file, always read the current file first and explicitly check for logic the new file does not include. Any omission from a replacement file is a silent deletion.

## S20 — Technical learnings

- **@Observable singletons on App structs require @State to drive WindowGroup re-evaluation**: a plain `AppSettings.shared.colorScheme` call in `WindowGroup.body` does NOT register SwiftUI observation — tracking only fires on `@State`-held references. Fix: `@State private var settings = AppSettings.shared` in `YomiApp`. Then `settings.colorScheme` and `settings.accentColor` in the body trigger re-evaluation on every change. Without this, `.preferredColorScheme` and `.tint` are set once at launch and never update.

- **.task {} vs .onAppear {} for tab-triggered fetches**: `.task {}` fires once, when a view first enters the hierarchy. `.onAppear {}` fires on every appearance, including programmatic tab navigation (`appRouter.selectedTab = tabMore`). For PluginsView, `.task` silently failed after onboarding navigated to More (view already mounted). Rule: use `.onAppear { Task { ... } }` for any fetch that must re-fire when the user navigates back to a tab.

- **Three-file prompts are justified for interconnected state**: the accentColor feature required coordinated changes in AppSettings (new property), SettingsView (picker UI), and YomiApp (wiring .tint). Running these as separate prompts would leave the app in a broken intermediate state. When a feature's backing storage, UI, and root wiring all live in different files and must be consistent, a single prompt touching all three is correct — not a violation of the one-file rule.

- **.tint() across .fullScreenCover boundaries needs runtime verification**: `.tint(Color(hex: settings.accentColor))` applied to `ContentView()` inside `WindowGroup` may not propagate into `OnboardingView` (presented via `.fullScreenCover`, which creates a new presentation context). If broken at runtime: add `.tint(Color(hex: AppSettings.shared.accentColor))` directly inside `OnboardingView`.

## S19 — Technical learnings

- **preferredColorScheme(nil) does not force system appearance in simulator**: passing `nil` tells SwiftUI to follow the system preference, but this may not apply in the simulator as expected. Before writing any fix, read `YomiApp.swift` to confirm the modifier placement. To diagnose, pass explicit `.dark` or `.light` first — only switch to nil once explicit values are confirmed working.

- **AppSettings reader values and local @State must not coexist as dual sources of truth**: `TextReaderView` has a local `@State private var fontSize: Double` that drives the slider but is disconnected from `AppSettings.novelFontSize`. Font changes don't persist and settings from `SettingsView` have no effect. Fix: remove local `@State fontSize`, use `AppSettings.shared.novelFontSize` as the single source. Re-inject CSS via `webView.evaluateJavaScript` on `.onChange(of: AppSettings.shared.novelFontSize)`.

- **OnboardingView pattern — fullScreenCover + hasSeenOnboarding**: gate with `@State private var showOnboarding = !AppSettings.shared.hasSeenOnboarding` in `YomiApp`. Use `.fullScreenCover(isPresented: $showOnboarding)`. Last page: `AppSettings.shared.hasSeenOnboarding = true` then `dismiss()`. Persists across launches via UserDefaults.

- **seedBundledPlugins call removed from YomiApp**: removed from `YomiApp.init()` for App Store compliance. Method kept in `ExtensionManager` for dev use. `.js` files removed from Xcode target membership (not from disk) — they no longer ship in the binary.

- **Never write a fix for a UIViewRepresentable without reading the current file first**: `ReaderWebView` has a `Coordinator.lastHTML` guard in `updateUIView`. Any re-inject change must account for it — writing blind risks duplicating the guard or breaking the reload path entirely.

- **PluginsView .task{} catalog fetch may not fire when tab is activated programmatically**: when `appRouter.selectedTab = tabMore` is called during onboarding, `PluginsView` may already be in the hierarchy and its `.task {}` won't re-fire. Add explicit `errorMessage` state + retry button before assuming network is the cause of an empty Browse tab.

- **Immersive tap layer in ZStack**: add `Color.clear.contentShape(Rectangle()).onTapGesture { ... }` after the background color, before reader content. Tap target for full screen without blocking scroll/pinch above. Placing it on top intercepts scroll events.

## Pre-S19 Audit — Research findings

### App Store compliance (confirmed)
- Paperback and Aidoku are on the App Store using the identical extension model
- The legal line: app binary must ship with ZERO piracy-adjacent plugin files
- Users install plugins themselves = user action, not developer action
- Bundled .js files in Yomi/Resources/ must be removed before App Store submission
- seedBundledPlugins in YomiApp.swift must be removed with them
- Onboarding replaces bundled plugins: first-launch screen → Browse catalog → install

### Dark mode — correct SwiftUI pattern
- `.preferredColorScheme()` must be applied in YomiApp.swift on ContentView inside WindowGroup, NOT on a child NavigationStack or individual views
- AppSettings.theme stores "system"/"light"/"dark" as String
- Computed var `colorScheme: ColorScheme?` — nil for system, .light or .dark otherwise
- Pattern: `ContentView().preferredColorScheme(appSettings.colorScheme)`

### Immersive reader — correct pattern
- `@State var showChrome = true` toggled by TapGesture on scroll content
- All chrome (nav, tab bar, controls) uses: `.opacity(showChrome ? 1 : 0).animation(.easeInOut(duration: 0.2), value: showChrome)`
- System status bar: `.statusBarHidden(!showChrome)` on the root reader view
- Tab bar: `.toolbar(showChrome ? .visible : .hidden, for: .tabBar)`
- Never use `.hidden` directly — always opacity+animation for smooth transition

### TextReaderView font size fix
- WKWebView renders HTML once — changing AppSettings.novelFontSize after load has no effect
- Fix: call `webView.evaluateJavaScript("document.body.style.fontSize = '\(size)px'")` on every font size change
- Better fix: observe AppSettings changes via `.onChange(of:)` and re-inject the full CSS string
- Line height should be 1.6× (not 1.5×) per research — more comfortable for long-form reading

### Novel reader optimal settings (research-confirmed)
- Font size default: 18pt, range 14–28pt
- Line height: 1.6× font size
- Dark text color: #E8E8E8 (not white — reduces glare)
- Dark background: #1C1C1E (not pure black — easier on eyes)
- Sepia text: #2C1810 on #FFF8F0 background
- Light mode: #1C1C1E on white
- Contrast ratios meet WCAG 4.5:1 in all three modes
- Font: SF Pro (system) for default; Georgia acceptable for sepia mode

## S18 — Technical learnings

- **require() shim in JSBridge**: inject before plugin eval via `injectRequireShim(into:)`. Cache modules in `__moduleCache`. Route `cheerio` to global, `he` inline (named + numeric + hex entity decode/encode), `node-fetch`/`node-fetch/src/index.js` to `SOURCE._fetchSync`, `axios` get/post to `SOURCE._fetchSync`. Unknown modules return empty `{}` — never crash. Always inject `module`, `exports`, `process` globals. This enables LNReader v2.x plugins to run in JavaScriptCore without an esbuild compilation step.

- **PluginCatalogService pattern**: `@Observable` singleton that owns remote catalog state (`entries`, `isLoading`, `errorMessage`). `fetchCatalog()` is a plain `async func` — call from `.task {}` in the View. Never call from `init()`. `isInstalled()` cross-references `ExtensionManager.shared.installed` by name.

- **Firebase Hosting as plugin CDN**: project yomi-plugins, live at https://yomi-plugins.web.app. `index.json` + `.js` files in `~/Projects/Yomi/Firebase/public/`. Deploy: `cd ~/Projects/Yomi/Firebase && firebase deploy --only hosting`. Firebase folder lives outside the Xcode repo (`~/Projects/Yomi/Firebase`) — not committed to git.

- **esbuild IIFE for JSContext**: `format: 'iife'`, `bundle: true`, `platform: 'browser'`, `target: 'es6'`. Output is a self-contained JS file with no `import`/`require` statements — directly evaluatable by `JSContext.evaluateScript()`.

## S17 — Technical learnings

- **api.asurascans.com requires Origin + Referer headers**: Cloudflare blocks requests without these headers. Every `SOURCE.fetch` call in asurascans.js must include `{ headers: { "Origin": "https://asurascans.com", "Referer": "https://asurascans.com/" } }`. Without them, the API returns 403 or an empty response.

- **asurascans chapterPath format**: `"{seriesSlug}/{chapterSlug}"` — split on first `/` to get both components. `getChapterList` builds it as `mangaPath + "/" + ch.slug`. `getPageList` splits it to call `/api/series/{seriesSlug}/chapters/{chapterSlug}`. Pages are in `json.data.chapter.pages[].url`.

- **asurascans getMangaList endpoint**: `GET /api/search?page={page}&order=popular` (not `/api/series`). Chapter list pagination via `GET /api/series/{slug}/chapters?limit=100&page={page}`, loop while `json.meta.has_more === true`.

- **DateComponents is Hashable in Foundation**: `Set<DateComponents>` works without any custom conformance. Used in InsightsView streak logic to collect distinct calendar days where reading occurred. No need for a custom wrapper type.

- **Streak logic — check yesterday if today is empty**: streak should not reset if the user hasn't read yet today but read yesterday. Pattern: count consecutive days starting from today; if streak == 0, restart count from yesterday. This preserves the streak through the morning before the user opens the app.

## S16 — Technical learnings

- **seedBundledPlugins skip logic is a deployment trap**: the `fileExists` check that skips copying bundled JS files means simulator never picks up JS fixes after the first install. Rule: bundled plugins must always be overwritten on launch (`removeItem` then `copyItem`). Safe because bundled plugins are read-only source-of-truth — only network-installed plugins should be preserved.

- **cheerio shim each() contract (updated S46)**: the Yomi cheerio shim now matches real cheerio — `each`/`map` pass `(index, rawDOMNode)` to callbacks. Plugin code can do `$(node)` inside the callback to wrap it. The `$()` selector function detects raw nodes via `selector.type` property and wraps them. **Old behaviour (pre-S46)**: the shim passed `(index, wrappedCheerioObject)` — this broke any plugin that did `$(t).find(...)` inside `.each()`. The root cause: real cheerio's `.each()` passes the raw DOM element as `this` and second arg; calling `$(rawNode)` is the standard pattern. Always match real cheerio's contract.

- **Debug prints are the fastest path to root cause**: when a plugin returns empty and the cause is unknown, add `print("🔍 ...")` to JSBridge before `parseMangaArray`/`parseNovelItems` to see the raw JS return value. This immediately distinguishes between: network failure (empty string), selector mismatch (JS array length 0), or type mismatch (JSValue not convertible to array).

- **GitHub repo ≠ simulator disk**: Claude Code writes to disk but changes only reach the simulator after a build. The simulator runs files from the app bundle (built from disk), not from the git repo. Always push after a fix session — GitHub is the source of truth, not the simulator cache.

- **Verify fixes in repo before diagnosing simulator**: after CC commits, confirm the actual file content via `curl https://raw.githubusercontent.com/PacoDealer/Yomi/main/...` before assuming the simulator is running the fixed code. Divergence between repo and disk is a common source of confusion.

- **Claude.ai can read the GitHub repo directly**: use `curl https://raw.githubusercontent.com/PacoDealer/Yomi/main/{path}` to read any file without asking CC. This eliminates a full round-trip prompt for diagnostic reads and speeds up root cause analysis significantly.

- **Workflow improvement — diagnose before prescribing**: when plugins return empty, the correct flow is: (1) read the actual file from GitHub, (2) read the shim implementation from GitHub, (3) identify the exact failure point, (4) write one targeted fix prompt. Do not write fix prompts based on assumptions — the each() bug was correctly identified only after reading the actual shim code.

## Technical learnings
- **PrivacyInfo.xcprivacy is required for all iOS 17+ App Store submissions**: Apple rejects builds that access privacy-sensitive APIs without a `PrivacyInfo.xcprivacy` file. Yomi uses `UserDefaults` (NSPrivacyAccessedAPICategoryUserDefaults) for AppSettings and MAL token — both must be declared. Create the file at `Yomi/PrivacyInfo.xcprivacy` (XML plist format). Without it, App Store Connect will reject the upload automatically. This cannot be patched post-submission.

- **Reading progress saved but never restored — always verify the full round-trip**: `ChapterQueries.updateProgress(id:progress:readingSeconds:)` is called on disappear and stores progress as a 0.0–1.0 Double. But `ChapterReaderView` initializes `currentPage = 0` and `loadPages()` never reads the stored progress back. The data exists in the DB unused. When implementing progress features, always verify both the write path AND the read path before closing the session.

- **SourceBrowseView only shows page 1 — pagination must be explicit**: `getMangaList(page:)` is designed for pagination but `SourceBrowseView.loadContent()` calls it with `page: 1` and never calls it again. There is no "load more" trigger. This is a silent limitation — the app appears to work but users see ~20 titles on MangaDex instead of thousands. Never assume pagination works without testing with a source that has more than one page of results.

- **MangaPageView zoom without pan is broken UX**: `.scaleEffect` scales around the view center but doesn't move the image. At 4x zoom, all four corners of the image are inaccessible. The fix requires `@State var offset: CGSize` + `DragGesture` with clamping. The clamping logic: `max offset.x = (scale - 1) * viewWidth / 2`, same for y. Reset offset to `.zero` when scale returns to 1.0.

- **Novel chapter read semantics — mark on finish, not on open**: `TextReaderView.loadContent()` calls `NovelQueries.markRead()` immediately after the HTML string is received. A chapter is "read" the instant it opens. The correct trigger is scroll-to-bottom, detectable via WKWebView's `scrollView.contentOffset.y + scrollView.frame.height >= scrollView.contentSize.height`. Use a WKNavigationDelegate or JS injection to detect this.

- **@Bindable for @Observable singletons in views**: to create a SwiftUI binding to a property on an `@Observable` singleton (e.g. `AppSettings.shared`), you cannot use `$AppSettings.shared.someProperty` directly. You must first declare `@Bindable var settings = AppSettings.shared` inside the view (or receive it as a parameter), then bind via `$settings.someProperty`. Without `@Bindable`, the `$` prefix won't compile on a non-`@State` reference.
- **JSBridge is per-extension, not a singleton**: never share a JSBridge instance between extensions or between concurrent tasks. Each JSBridge owns a JSContext that evaluates one script. The correct pattern is `JSBridge(scriptURL: localURL)` fresh for each plugin call site. Sharing instances causes state bleed between plugins.
- **SwiftUI view identity: mutate @State instead of replacing the view for in-reader navigation**: ChapterReaderView uses `currentChapterIndex: @State Int` + computed `activeChapter` to navigate between chapters without SwiftUI creating a new view instance. If the view were replaced (e.g. via NavigationLink push/pop), all `@State` (pages, isLoading, timer) would reset. Mutating existing @State preserves the view lifecycle and avoids redundant loads.
- **Context window auto-summary can describe planned work as completed**: when Claude Code's context compresses mid-session, the summary may present outcomes that were planned (or partially executed) as fully done. At the start of any resumed session, always read the actual file state — do not trust the summary's description of completed work.
- **xcode-select pointing to CommandLineTools**: if `xcodebuild` fails with "xcode-select: error: tool 'xcodebuild' requires Xcode" or similar, prefix all build commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Check with `xcode-select -p`. Fix permanently via `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- **Simulator device name changes across Xcode versions**: "iPhone 16 Pro" may not exist in a newer Xcode's simulator list. Always check available names with `xcrun simctl list devices available | grep iPhone` before hardcoding a destination in build commands. Use the newest available Pro model.
- **iOS 26 TabView**: new API `Tab("title", systemImage:) {}` — old `.tabItem {}` renders nothing
- **Xcode PBXFileSystemSynchronizedRootGroup**: all files in the folder are included automatically — never use `.gitkeep` or `.gitignore` inside the target
- **Swift 6 + GRDB**: `init(row:)` and `encode(to:)` from FetchableRecord/PersistableRecord require `nonisolated` with `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`
- **DerivedData stale**: clean with `rm -rf ~/Library/Developer/Xcode/DerivedData/Yomi-*` and ⇧⌘K in Xcode
- **JSBridge async**: JSContext is synchronous; SOURCE.fetch blocks with DispatchSemaphore; always call from Task.detached, never from MainActor
- **Keiyoushi plugins**: they are Android .apk, do not run on iOS; replaced in S18 by a real Yomi-native catalog on Firebase Hosting
- **LNReader plugins**: TypeScript compiled to JS — compatible with JavaScriptCore if correct shims are implemented (fetch, cheerio, storage, require)
- **Cheerio shim**: full recursive HTML parser + CSS selector engine implemented in pure JS; functional since S6. Not a stub.
- **db.write unused result**: GRDB db.write returns the closure value — use `_ = try appDatabase.write { ... }` to silence the "Result of call to 'write' is unused" warning
- **GRDB bulk column update**: use `Model.filter(Column("id") == id).updateAll(db, [Column("field").set(to: value)])` instead of fetch-mutate-save for partial updates
- **SHA256 stable IDs**: `CryptoKit.SHA256.hash(data: Data(url.utf8)).compactMap { String(format: "%02x", $0) }.joined().prefix(32).lowercased()` — generates reproducible 32-char IDs from a URL
- **MangaDex pagination**: use limit=100 with offset loop; cap at 2000 to avoid infinite loops on series with many chapters
- **@Observable + UserDefaults**: use `@ObservationIgnored` on the `defaults` ivar; computed properties with get/set to UserDefaults work correctly as bindings
- **UIApplication.isIdleTimerDisabled**: always reset to `false` in `.onDisappear` — otherwise the screen stays on globally even after the user leaves the reader. Must be `true` in `.onAppear`
- **GRDB + Swift 6 strict concurrency**: expose DatabaseQueue as a `nonisolated(unsafe) var appDatabase: DatabaseQueue!` at module level. Official GRDB pattern for `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`. All `*Queries` methods access `appDatabase` directly — no actor hop
- **\*Queries enums**: all static methods must be `nonisolated` or the compiler infers MainActor isolation and blocks calls from `Task.detached`
- **Two v4_ migrations coexist**: GRDB tracks migrations by string name, not numeric prefix. `v4_reading_insights` and `v4_reading_time` are independent and coexist without conflict. Next migration must use prefix `v6_`
- **appDatabase.read async overload**: from a `@MainActor` context (like `exportBackup()` in `BackupManager`), `appDatabase.read` resolves to the async overload. Requires `try await appDatabase.read { ... }`
- **MAL OAuth PKCE plain**: MAL does not support S256, only the `plain` method (code_challenge == code_verifier). The verifier is a random string of 43-128 chars
- **Timer in SwiftUI**: `@State private var readingTimer: Timer?` started in `.onAppear` and always invalidated in `.onDisappear` + in every navigation function before creating the next timer
- **ChapterReaderView activeChapter pattern**: use `currentChapterIndex: Int` as `@State` + `var activeChapter: Chapter { chapters[currentChapterIndex] }` as computed property, instead of storing the chapter directly — enables prev/next navigation without re-init of the view
- **Extension must be Hashable for Picker + .tag()**: iOS 26 `Picker` requires the selection type to conform to `Hashable`. `Extension` only had `Identifiable + Codable` — adding `Hashable` to the conformance list is sufficient; the compiler synthesizes it automatically because all stored properties (`String`, `URL?`, `Bool`, `[String]`) already conform
- **Text + Text deprecated in iOS 26**: the `+` operator on `Text` was removed. Old: `Text(date, style: .relative) + Text(" ago")`. New: `Text("\(Text(date, style: .relative)) ago")`. SwiftUI `Text` supports interpolating other `Text` values (including those with special formatters like `.relative`) — the live-updating behavior of `.relative` is preserved
- **simultaneousGesture for multi-tap**: double-tap + single-tap on the same view requires `.simultaneousGesture` on the double-tap gesture; without it SwiftUI routes all taps to the single-tap handler
- **Shimmer with GeometryReader + animated LinearGradient**: animate a `@State private var phase: CGFloat` from -1 to 1 with `.linear(duration:).repeatForever(autoreverses: false)`, use it as offset in `Gradient.Stop` locations — creates a horizontal sweep effect with no external dependencies
- **debounceTask pattern**: `@State private var debounceTask: Task<Void, Never>?` — cancel on each keystroke before creating a new `Task.sleep(500ms)`. Cleaner than Combine for simple debounce in SwiftUI
- **didSet in @Observable**: properties with `didSet` in `@Observable` classes work correctly for side effects (e.g.: `selectedCategoryId { didSet { updateFilteredIds() } }`)
- **INSERT OR IGNORE**: for join tables where the composite PK guarantees uniqueness, use `INSERT OR IGNORE` instead of `save()` — avoids errors if the pair already exists
- **CategoryView + MoreView in one prompt**: violated the "one file per prompt" rule because CategoryView required an entry point in MoreView. Compiled without errors, but the correct pattern is to split into two prompts. Acceptable exception only when the second change is a single-line NavigationLink
- **Category assignment pattern**: assignment sheet in DetailView loads `allCategories` + `assignedIds` in a separate `.task` via `Task.detached`; toggle calls `assign`/`unassign` individually and updates local `Set<String>` for immediate feedback without reloading the entire list from DB. Category button in toolbar: `disabled` + `opacity(0.4)` when `!manga.inLibrary` — only makes sense to assign if in library
- **Chapter pagination pattern**: `@State displayedChapterCount: Int = 50`; full array in memory; only the `.prefix(count)` slice is rendered in List. The index passed to ChapterReaderView must be the real index in the full array: `chapters.firstIndex(where: { $0.id == chapter.id })` — not the index in the visible slice, or prev/next navigation breaks
- **Updates tab / background refresh pattern**: `withTaskGroup` to refresh multiple manga in parallel from background; each task creates its own `JSBridge` (don't share instances). Compare remote IDs vs local IDs with `Set` to detect new chapters without saving all of them — only update `lastUpdatedAt` if `hasNew`. `ProgressView` in toolbar replaces button during `isRefreshing`; `guard !isRefreshing` at start of method to avoid concurrent executions
- **Dedup by URL → ID (confirmed since S8)**: `SHA256(url).prefix(32)` as plugin id guarantees the same URL never produces two different entries — dedup by id is sufficient, no need to compare `sourceListURL` separately

## S14 — Technical learnings
- **@Observable final class is automatically Sendable**: when a class conforms to `@Observable`, Swift makes it `Sendable` implicitly. Therefore `nonisolated(unsafe)` on `static let shared` of an `@Observable` singleton is unnecessary — Xcode rejects it with a "consider removing it" warning. Do not add `nonisolated(unsafe)` to `@Observable` singletons.

- **ExtensionManager.shared from Task.detached — correct pattern**: `ExtensionManager.shared` is MainActor-isolated and not accessible from `Task.detached`. The solution is to capture a local closure BEFORE entering the Task, in the MainActor context where `shared` is accessible:
```swift
  let bridgeFn: (Extension) -> JSBridge? = { ext in
      let docs = FileManager.default.urls(
          for: .documentDirectory, in: .userDomainMask)[0]
      return JSBridge(scriptURL: docs
          .appendingPathComponent("Extensions", isDirectory: true)
          .appendingPathComponent("\(ext.id).js"))
  }
  // Inside Task.detached use bridgeFn(ext) instead of
  // ExtensionManager.shared.bridge(for: ext)
```
  If the calling context is already `@MainActor` (e.g.: `loadContent()` in `SourceBrowseView`), the closure can be used directly without `Task.detached`.

- **bridge(for:) nonisolated**: the `bridge(for:)` method in `ExtensionManager` must be `nonisolated` and reconstruct the URL directly with `FileManager.default.urls(for:in:)` — it cannot access MainActor-isolated properties like `self.extensionsDirectory`.

- **Xcode breakpoint as false crash**: an active breakpoint in a frequently called function (e.g.: `MangaQueries.fetchAll`) pauses execution simulating a crash or deadlock. Before diagnosing concurrency or GRDB issues, check Xcode → Breakpoints for unexpected active breakpoints. The `Breakpoints_v2.xcbkptlist` file in xcuserdata is the source of truth — `shouldBeEnabled = "Yes"` activates the breakpoint.

- **sourceListURL stale — definitive rule**: NEVER build `JSBridge(scriptURL: ext.sourceListURL)` directly anywhere in the app. The URL stored in DB becomes stale after sandbox reinstallation. The only valid pattern is to reconstruct the path from `FileManager` + `ext.id` at runtime. This applies in BrowseView, UpdatesView, MangaDetailView, and any future point that needs to access a plugin.

- **Claude.ai generates prompt against wrong file**: without seeing the real code, Claude.ai may indicate a fix goes in `BrowseView.swift` when it's actually in `UpdatesView.swift`. Claude Code detects this when reading the file, but it costs an extra prompt. Improved protocol: at session start, paste the content of files that will be touched, not just `find` + ROADMAP.

- **JS plugins — selectors unverified in session**: plugins written during a session (royalroad, scribblehub, novelfire, comick) use CSS selectors/API endpoints inferred at the time of writing. HTML selectors change without notice. When debugging a broken plugin, first verify the root list selector (`.fiction-list-item`, `.search_main_box`, `.novel-item`, API endpoint). Each plugin has a `// Selectors verified: {date}` comment in its header.

- **ScribbleHub requires POST in SOURCE.fetch**: ScribbleHub loads the TOC via POST to `wp-admin/admin-ajax.php` with `action=wi_gettocchp`. If `JSBridge.swift` only supports GET, the TOC will be empty and `parseNovel` will return zero chapters. Before testing `scribblehub.js`, verify that `SOURCE.fetch` supports `method: "POST"` and `options.body`.

- **Firebase Hosting as plugin repo**: Firebase Hosting (free tier) hosts the Yomi plugin repository (`index.json` + `.js` files). Live at `https://yomi-plugins.web.app/index.json`. `PluginCatalogService` fetches from this URL; `PluginsView` Browse tab lists entries with real Install buttons. Implemented in S18.

- **User retention findings from S14 research**: highest ROI retention features, ordered by impact: (1) key action in first 3 minutes = 2x retention — the "Browse sources" button in LibraryView empty state goes in this direction; (2) push notifications for new chapters — request permission AFTER user saves their first manga (iOS opt-in rate 43.9%); (3) "Continue reading" row at LibraryView top — maximum friction reduction; (4) light gamification without pressure (streaks, milestones without points/badges/leaderboards); (5) optimal typography in TextReaderView: 18pt minimum, line-height 1.5x, color `#E8E8E8` in dark mode (not pure white).

## S13 — Technical learnings
- **iOS sandbox path invalidation**: absolute paths stored in GRDB become stale after reinstallation or sandbox update. Rule: never persist an absolute path and use it directly — always reconstruct the path at runtime from a reference directory (e.g.: `extensionsDirectory`) + stable ID. Applies to any `URL` in DB pointing to `Documents/`.
- **seedBundledPlugins skip logic**: base the skip on `FileManager.fileExists(atPath:)`, not on whether the ID is already in DB. The DB may have the record but the file may be missing (reinstallation). Always DB upsert even if the file already exists — guarantees metadata is in sync.
- **SOURCE.fetch User-Agent**: many scrapers block requests without User-Agent (Cloudflare, CDN). Inject realistic UA (iPhone Safari) + Accept + Accept-Language as defaults in the URLRequest of SOURCE.fetch. Plugins can override with their own headers if needed.
- **SHA256(filename) for bundled plugins**: use the JS file name (without extension) as the SHA256 id seed, not the URL. Bundled plugins have no network URL — the ID must be derivable from the name at compile time to perform idempotent upserts on every launch.
- **Bundled plugins vs network plugins**: bundled plugins are copied from `Bundle.main` to `Documents/Extensions/` on every launch (skip if already on disk). Network plugins are downloaded from URL. Both use the same `extension` table format and the same `bridge(for:)` flow.

## S12 — Technical learnings
- **cheerio `.each` callback (updated S46 — matches real cheerio)**: the Yomi shim now passes `(index, rawDOMNode)` to `.each()` callbacks, matching real cheerio. `$(node)` wraps it. The pre-S46 shim passed wrapped objects — this broke plugins that called `$(t).find(...)` inside `.each()`. See S46 entry for the fix.
- **`attr()` helper in plugins**: must receive a cheerio object `$el`, not raw HTML. Define it as: `function attr($el, name) { return $el.attr("data-src") || $el.attr(name) || "" }`.
- **`DownloadManager.queue` does not contain the active chapter**: when `processQueue()` starts a download, it removes the item from `queue` immediately. The UI cannot depend on `queue` to show the in-progress chapter — use `activeChapter: Chapter?` exposed as a separate property.
- **In UI prompts about singletons**: specify the state of each property and its invariants before describing the UI. E.g.: "activeChapter was already removed from queue when it starts downloading — show it separately with `dm.activeChapter`".
- **async/sync signatures in prompts**: always explicitly specify whether a singleton method is `async` or not. The compiler may infer differently and generate hard-to-trace errors.
- **`ForEach` over reactive state**: before describing a `ForEach`, confirm what the collection contains in each possible state. Don't assume the active element is still in the list.
- **For new ViewModels**: explicitly list the Queries it uses in the prompt. E.g.: "`load()` uses `DownloadQueries.fetchAllDownloaded()` + `MangaQueries.fetchOne(id:)`". Prevents Claude Code from inferring incorrect names.

## S9 — Lessons learned

**Problem:** S9 prompts were generated against the S7 codebase state, not the real state. This caused ~60% of the session to rewrite work that already existed since S8.

**Root cause:** Claude.ai didn't have access to the real repo files. It planned against the system prompt (which described S7) instead of the current codebase.

**Solution — Session start protocol:**
Before asking Claude.ai for prompts, always run in Claude Code:
```
find Yomi -name "*.swift" | sort
find Yomi -name "*.js" | sort
cat Yomi/ROADMAP.md
```
Paste the complete output into Claude.ai and ask for analysis BEFORE generating prompts. Don't generate prompts until confirming the scope.
Additionally: paste the content of files that will be modified in that session. Prevents Claude.ai from generating prompts against the wrong file.

**Rule:** Claude.ai analyzes → proposes → user confirms → only then generates prompts. Never the other way around.

**Corollary:** ARQUITECTURA.md and METODOLOGIA.md in Claude.ai project knowledge are static until manually updated. If a session closes without updating them, they diverge from reality. The session start `find + ROADMAP` paste will catch new files, but architecture decisions, singleton descriptions, and learnings will be wrong. When in doubt, paste the relevant section of ARQUITECTURA.md alongside the file contents.

## Platform compatibility

**Current deployment target: iOS 26.2**

The project uses iOS 26-exclusive APIs that don't exist in earlier versions:

| API | File(s) | iOS 18 alternative |
|-----|---------|-------------------|
| `Tab("…", systemImage:) {}` | ContentView.swift | `.tabItem { Label(…) }` |
| `ContentUnavailableView` | HistoryView, BrowseView, PluginsView | Custom empty view |
| `.refreshable` | HistoryView | Manual pull-to-refresh |
| `.searchable` | BrowseView, SourceBrowseView | Custom search bar |
| `.ascNullsLast` (GRDB) | ChapterQueries | Raw SQL ORDER BY |
| `Text("\(Text(…)) …")` interpolation | HistoryView | DateFormatter or .formatted |

**Decision: do not lower the deployment target.**
Reasons:
- The app was intentionally designed for iOS 26 from session 1
- Backporting would require maintaining two code paths (`#available`) in at least 6 files
- The development iPhone can be updated to iOS 26 when available
- iOS 26 is the current shipping OS (2026)

**Rule:** if iOS 18 support is needed in the future, create a separate branch
`compat/ios18` and never mix it with main development.

## S32 — Technical learnings (2026-04-14)

- **ContinueReadingRow mixed-type pattern**: use a private `enum ContinueItem { case manga(Manga); case novel(Novel) }` with `var lastReadAt: Date?` computed property to merge and sort heterogeneous types in a single `[ContinueItem]` array. Fetch both in parallel `Task.detached`, merge, sort, take prefix(10).
- **LibraryViewModel status filter**: add `var statusFilter: ReadingStatus? = nil` and apply after category filter in `displayedManga`: `let base = statusFilter == nil ? categoryFiltered : categoryFiltered.filter { $0.readingStatus == statusFilter }`. Tapping the active chip again toggles it off (nil).
- **Novel category join table mirrors manga_category exactly**: same `category` table shared between manga and novels. Methods: `assignNovel/unassignNovel/categoriesForNovel/novelIds(inCategory:)` in CategoryQueries. No separate category table needed.
- **PluginCatalogService TTL pattern**: `private var lastFetchedAt: Date?` + `fetchCatalog(force: Bool = false)`. Guard: `if !force, !entries.isEmpty, let last = lastFetchedAt, Date().timeIntervalSince(last) < ttl { return }`. Pull-to-refresh callers pass `force: true`. All `.onAppear`/`.task` callers get TTL for free.
- **BackupManager v2 format**: `"version": 2` with `novels`, `novelChapters`, `novelCategories` arrays added. Import is backwards-compatible: v1 backups (missing novel keys) fall back to empty arrays via `?? []`. Novel chapters use `insertAllIgnoringConflicts` (INSERT OR IGNORE) on restore — safe, preserves existing read state.
- **NovelDetailView toolbar refactor (S32)**: replaced single heart `Button` with `Menu { ... }` (ellipsis.circle) containing library toggle + category sheet trigger. Matches MangaDetailView overflow menu pattern. Category sheet disabled when `!isInLibrary`.
- **App Store age rating 2026**: old 17+ system replaced by 4+/9+/13+/16+/18+. Yomi targets **18+**. Must update questionnaire in App Store Connect before submission.
- **Deep research saved to memory**: `research_competitive.md` + `research_ux_appstore.md` in Claude memory. Do not re-research Mihon/Tachimanga/LNReader/Paperback/App Store/UX unless explicitly asked.

## S33 — Technical learnings (2026-04-14)

- **ReadingStatus for novels — reuse existing enum, no new types needed**: `ReadingStatus` enum (defined in `Manga.swift`) is shared between manga and novels. Add `readingStatus: ReadingStatus` to `Novel.swift`, update the GRDB extension in `DatabaseManager.swift`, add `updateReadingStatus(novelId:status:)` to `NovelQueries.swift`. All six construction sites for `Novel(...)` must add `readingStatus: .none`. Pattern: migrate the column as `NOT NULL DEFAULT 'none'` (not nullable) — consistent with how manga handles it.
- **Private struct visibility across files**: `private struct ReadingStatusMenu` in `MangaDetailView.swift` is invisible to `NovelDetailView.swift` even in the same module. Remove `private` to make it `internal` (module-level accessible). The struct only uses types from the same module so there are no dependency issues. Any reusable component expected to be used by ≥2 views should not be `private`.
- **Library chip row guard for mixed-type libraries**: the status chip row was gated on `!viewModel.mangas.isEmpty`. With novels also needing the filter, change guard to `!viewModel.mangas.isEmpty || !viewModel.novels.isEmpty`. The same `statusFilter: ReadingStatus?` drives both `displayedManga` and `displayedNovels` — a single toggle filters whichever section the user has.
- **Firebase deploy flow after auth expiry**: `firebase deploy` fails silently (or with auth error) when the session has expired. Run `firebase login --reauth` first, then `firebase deploy --only hosting`. Both commands must be run from the `~/Desktop/Yomi\ 2.0/yomi-firebase` directory.

## S32 — LNReader plugin compatibility gaps (researched 2026-04-14)

The LNReader adapter in `JSBridge.swift` (`injectLNReaderAdapter`) is production-ready. Known gaps documented below — no code change needed unless a specific new plugin fails.

**Gap 1 — `latestUpdates` not called by UpdatesView**
The adapter wraps `plugin.latestUpdates` into a synchronous form, but `UpdatesView` does not call it. It checks for new chapters by calling `bridge.parseNovel(path:)` and comparing the returned chapter list against the DB. `latestUpdates` would be more efficient (returns a lightweight list), but `parseNovel` is more reliable since it also refreshes all chapter metadata. Future optimization: use `latestUpdates` as a fast pre-check before deciding whether to call `parseNovel`.

**Gap 2 — `plugin.options` not surfaced in UI**
`popularNovels(pageNo, options)` receives `options` from Swift as `undefined`. Some LNReader plugins use `options` to filter by genre, language, or sort order (e.g., `options.genres`, `options.sortedBy`). These filter capabilities are silently ignored — the user always gets the default list. Future work: expose a genre/sort picker in `BrowseView` for novel sources that declare options, and pass the selected values through the bridge.

**Gap 3 — Cloudflare blocks WuxiaWorld and WebNovel**
`SOURCE.fetch` uses a realistic iPhone Safari `User-Agent` and standard headers, but does not execute JavaScript or solve Cloudflare challenges. Sites with Cloudflare bot protection (WuxiaWorld, WebNovel) will return 403 or a JS challenge page instead of HTML. These sources are not viable with the current HTTP-only fetch model. Viable novel sources: Royal Road, ScribbleHub, NovelFire, LightNovelPub, NovelBin, FreeWebNovel.

## S34 — Technical learnings (2026-04-15)

- **FreeWebNovel chapter links use `class="con"`, not a list**: the detail page doesn't have a `<ul#chapter-list>` element. Chapter links are bare `<a href="/novel/title/chapter-N" class="con">` anchors. Correct selector: `a.con`. Filter to `/novel/` href to avoid matching unrelated links.
- **NovelBin `data-novel-id` is a text slug, not a numeric ID**: the regex `/data-novel-id=['"](\d+)['"]/` only captures digits. NovelBin embeds the novel slug (e.g., `martial-peak`) as the ID. Fix: use `/data-novel-id=['"]([^'"]+)['"]/` to capture any non-quote character sequence.
- **Custom cheerio shim `parseSimple` only captures one `.class` per selector segment**: e.g., `div.chapter-list.active` would only capture `chapter-list`, ignoring `active`. However, `matchesSimple` correctly checks multi-class nodes by splitting the node's class attribute by whitespace — so `div.chapter-list` matches `<div class="chapter-list active">`. The limitation is in writing selectors, not in matching.
- **Double SOURCE.fetch() inside parseNovel is safe**: two sequential `SOURCE.fetch()` calls within the same JS function work correctly. Each creates its own `DispatchSemaphore`, waits on the URLSession background thread callback, then proceeds. Since JSBridge runs inside `Task.detached(priority: .userInitiated)`, the semaphore wait does not block the main thread.
- **NovelFire synopsis may not match expected selectors**: `h1.novel-title` parses correctly but `div.summary` and `strong.ongoing` have been reported as empty. Root cause unconfirmed — could be dynamic content (JS-rendered on the real site but not returned by `SOURCE.fetch`), or an HTML structure difference. Fix: add multiple fallback selectors (`div.novel-synopsis`, `section.summary`, `div.description`) and a text-based fallback for status.
- **UpdatesView inserts ALL remote chapters, not just new ones**: after filtering `newChapters = remoteChapters.filter { !localIds.contains($0.id) }`, the code must insert `newChapters`, not `remoteChapters`. Inserting all chapters with INSERT OR IGNORE is non-destructive (won't overwrite read state) but wasteful for large chapter lists (e.g., 1000+ chapters).
- **Task.detached priority should always be explicit**: `Task.detached { }` without a priority inherits unspecified priority. Use `.background` for DB writes that don't need to be fast (marking read on navigation), `.userInitiated` for anything blocking UI load.
- **NovelFire chapters URL needs `?page=1`**: the chapters endpoint is paginated (`/book/{slug}/chapters?page=N`). Without `?page=1`, the default response format may differ. Always pass page number explicitly.
- **Removing dead/blocked plugins from catalog**: comick (Cloudflare, api.comick.dev returns 403), lightnovelworld (site permanently dead), lightnovelpub (Cloudflare). These were removed from `index.json` to keep the catalog clean. The JS files remain in Firebase for users who have them cached, but new installs won't see them.
- **NovelCoverCell AsyncImage should use phase-based initializer**: the two-closure `AsyncImage(url:content:placeholder:)` uses the same placeholder for both loading and error states. Use the phase-based `AsyncImage(url:content:)` with a `switch phase` to distinguish `.success` from other states. More importantly, use consistent aspect ratio in both success and placeholder branches to prevent grid row height instability (cells shifting when images load).
- **LazyVGrid bottom padding**: grids in `SourceBrowseView` had `.padding(.top, 8)` but no `.padding(.bottom)`. Add `.padding(.bottom, 8)` to prevent the last row from appearing flush against the bottom edge.
- **MainActor @State accessed inside Task.detached**: capturing `self.selectedFeed` (a `@State` property, therefore MainActor-isolated) inside `Task.detached` generates a Swift concurrency warning. Fix: capture the value in a local `let` before entering the task: `let currentFeed = selectedFeed`.
- **Sorting inside Task.detached can warn on struct properties**: sorting an array of enum cases (e.g. `HistoryItem`) by a struct property (e.g. `manga.lastReadAt`) inside `Task.detached` generates "Main actor-isolated property can not be referenced from a nonisolated context" in Xcode 26, even though the struct is not explicitly @MainActor. Fix: do the sort inside `await MainActor.run { }` after the Task.detached returns — sorting by Date is lightweight, there's no performance cost.
- **`try? funcReturningNonVoid()` produces unused-expression warning**: `try? CategoryQueries.insert(name:)` where `insert` returns `Category` evaluates to `Category?` which is then silently discarded. Xcode shows "Expression of type 'Category?' is unused". Fix: prefix with `_ = try? ...` to explicitly discard the result.
- **Chapters empty from Browse but work from Library**: when a novel source's `parseNovel()` returns empty chapters, the Library still shows chapters because they were previously persisted to DB and `NovelQueries.fetchChapters` returns the DB rows. From Browse, a transient Novel object (UUID id) is created and chapters depend entirely on `parseNovel()` returning data. Fix: repair the plugin's `parseNovel` selectors, then deploy to Firebase and reinstall.
- **Installed plugins are not auto-updated**: plugins installed by the user live in `Documents/Extensions/`. Removing a plugin from `index.json` (catalog) does not auto-uninstall it. User must manually uninstall via the Extensions tab. Stale/dead plugins (like LightNovelWorld) remain installed until the user removes them.

## S61 — Technical learnings (2026-05-05)

- **`@ViewBuilder` computed property for banner overlays**: extracting `chapterFinishedBanner` into a `@ViewBuilder` computed property keeps `body` readable and avoids Swift type-checker timeout from deeply nested conditionals. Use `if showBanner { bannerView }` in body and let the computed property hold all the layout/styling details.
- **Spring animation for bottom-edge banners**: `.move(edge: .bottom).combined(with: .opacity)` with `withAnimation(.spring)` gives a natural "slides up" entry. `.easeInOut` reads as mechanical; spring conveys liveness without specifying stiffness. Match the dismiss animation to `.easeOut(duration: 0.25)` — snappier exit vs entrance.
- **`onAppear` Task for auto-dismiss — not Timer**: `.onAppear { Task { try? await Task.sleep(for: .seconds(5)); withAnimation { show = false } } }` is idiomatic SwiftUI. `Timer.scheduledTimer` requires explicit invalidation and is harder to cancel on navigation; the `Task` inherits the view's lifetime and cancels when the view disappears if the view goes away before the sleep completes.
- **Banner always shows even in incognito**: `showFinishedBanner = true` is unconditional. Only the DB write (`NovelQueries.markRead`) is incognito-guarded. The banner is ephemeral in-memory UI state — showing it records nothing. Conflating "no persistent write" with "no UI feedback" would degrade UX for incognito readers.
- **`navigateToChapter` must reset all ephemeral display state**: `showFinishedBanner = false`, `lastKnownScrollPercent = nil`, and any other view-local flags must be cleared in `navigateToChapter`. If any flag survives chapter navigation it will appear on the new chapter with stale context — a class of bug that only surfaces after reading two chapters consecutively.

## S60 — Technical learnings (2026-05-05)

- **`scrollY / (scrollHeight - innerHeight)` not `scrollY / scrollHeight`**: `scrollHeight` is the total document height; `innerHeight` is the viewport height. The maximum `scrollY` is `scrollHeight - innerHeight`, not `scrollHeight`. Using `scrollHeight` as the denominator gives a max ratio of ~0.85 on a typical chapter (the last viewport-worth of content is unreachable by scrolling), making the progress bar never reach 100% and scroll restoration undershoot. Always use `var maxScroll = scrollHeight - innerHeight; pct = maxScroll > 0 ? scrollY / maxScroll : 0`.
- **`WKNavigationDelegate.didFinish` fires before layout is complete for long HTML**: JS `window.scrollTo(0, pct * maxScroll)` called in `didFinish` may execute before the document body has reached its full rendered height — `scrollHeight` is still 0 or equal to `innerHeight`. Guard: only restore if `maxScroll > 0`. For very long chapters, a short delay (~100ms) after `didFinish` before calling `scrollTo` improves accuracy; for average chapters it's fine without.
- **`ScrollViewReader` wrapping a `List` works for programmatic scrollTo**: `proxy.scrollTo("ch_<id>", anchor: .center)` correctly scrolls a `List` to a `ForEach` item tagged with `.id("ch_<id>")`. The `ScrollViewReader` must be the ancestor of the `List` (not inside it). A 300ms delay after the data loads (via `Task.sleep`) is necessary to allow the `List` to finish rendering rows before the scroll fires — without it, the scroll no-ops because the target row doesn't exist yet in the view hierarchy.
- **Progress bar in `List` rows via `GeometryReader`**: `GeometryReader { geo in Capsule().frame(width: geo.size.width * pct, height: 2) }.frame(height: 2)` is the correct pattern. The outer `.frame(height: 2)` constrains the `GeometryReader`'s infinite-height default. The capsule aligns to leading by default inside `GeometryReader`. Cap `pct` with `min(pct, 1)` to handle any floating-point values slightly above 1.0.
- **`hasRestored` flag prevents double-scroll on CSS re-inject**: `updateUIView` re-injects the `<style>` block when font/theme changes, which can trigger another `didFinish`. The `hasRestored: Bool` flag on the coordinator ensures the restore scroll only fires once per chapter load (coordinator is fresh per chapter since `ReaderWebView` is destroyed on `isLoading` toggle).
- **Chapter state refresh pattern**: after the reader closes, DB writes (markRead, updateScrollPercent) take ~100–300ms to flush from their `Task.detached` contexts. Re-fetching chapters immediately after the reader dismisses returns stale data. A 500ms `Task.sleep` before `refreshChaptersFromDB()` in `onChange(of: chapterForNav)` gives DB writes time to settle. `MangaDetailView` uses the same pattern — always mirror it when adding a `refreshChapterStates` equivalent to any detail view.
- **`.refreshable` on `List` inside `ScrollViewReader`**: works correctly — SwiftUI passes the pull gesture through `ScrollViewReader` to the `List`. No special handling needed. Any `List` that has a corresponding `loadX()` async function should have `.refreshable { await loadX() }` — this is the expected iOS pattern for force-refresh.

## S59 — Technical learnings (2026-05-04)

- **`.task` + `onAppear` paths are secondary incognito leak surfaces**: S57 audited primary paths (onDisappear, chapter-finish handlers). Secondary path `NovelDetailView.touchLastReadAt()` — called from `.task` on view appear — was not guarded and wrote `lastReadAt` to DB even in incognito. Any code path that writes reading state, even lightweight "I opened this item" writes, must check `AppSettings.shared.isIncognito`. Secondary paths are easiest to miss because they're not labelled as "read tracking" in the code.
- **`CodingKeys` exclusion as a format-tagging mechanism**: `PluginCatalogEntry.isNovel` is not present in any catalog JSON format (Yomi native, LNReader, Mangayomi). Excluding it from `CodingKeys` means it always decodes as its default value (`false`), then the specific parser path (`LNReaderEntry.toEntry()`) sets it to `true` after construction. This is a clean way to attach out-of-band metadata that cannot be derived from the JSON schema alone — no need for a separate type or a post-decode transform pass.

## S58 — Technical learnings (2026-05-04)

- **GRDB `init(row:)` + `encode(to:)` must be audited after every migration**: `v15_novel_notes` added a `notes` column to the `novel` table, but `Novel.init(row:)` and `encode(to:)` were never updated. `NovelQueries.updateNotes` used targeted `updateAll(Column("notes").set(to:))` SQL and worked for writes, but every `fetchLibrary()`/`fetchAll()` returned novels with `notes = nil`, silently discarding user data. The next session's decode would overwrite whatever was in the DB. Rule: whenever a migration adds a column, immediately update both `init(row:)` (decode) and `encode(to:)` (encode) in the same commit.
- **Custom cover propagation checklist**: Adding a `customCoverPath` field requires updating every view that renders a cover image, not just the detail view. Full list for Yomi: `MangaDetailView`, `NovelDetailView`, `MangaCoverCell` (grid), `MangaListRow` (list), `NovelLibraryCoverCell` (grid), `NovelLibraryListRow` (list), `HistoryRow`, `ContinueReadingRow` (manga card), `ContinueReadingRow` (novel card), `MangaUpdateHeader`, `NovelUpdateHeader`. Widget (`WidgetDataWriter`) correctly omits custom covers — widget process can't access the app's Documents directory without explicit App Group copying.
- **Swift type-checker timeout**: adding conditional branches + computed values inside a large `var body` can exceed Swift's type inference timeout ("unable to type-check in reasonable time"). Fix: extract large sections into `@ViewBuilder` computed properties (`headerSection`, `chaptersSection`, etc.) or standalone `@ViewBuilder func`s. Also, never put `let` computed bindings inside `ToolbarItem` content — move them to view-level computed properties.
- **Lightweight plugin format detection**: determining whether a JS plugin is LNReader (novel) or manga does not require JSBridge/JSC evaluation. The string `"popularNovels"` appears only in LNReader plugins. `(try? String(contentsOf: url)).contains("popularNovels")` in a `.task(id:)` is sufficient and fast (~1 ms per file). Used for Novel/Manga format badges in `ExtensionRow` and `InstalledExtensionRow`.
- **`onLongPressGesture` + `swipeActions` coexist fine**: `List` rows can have both `.swipeActions` and `.onLongPressGesture`. Long-press triggers the gesture recognizer before any swipe motion. In selection mode, swipe actions are suppressed via an `if !isSelectingChapters` guard inside the `swipeActions` block.

## S57 — Technical learnings (2026-05-04)

- **Incognito leaks hide in secondary code paths**: The primary read/write paths (ChapterReaderView.onDisappear, TextReaderView.flushReadingTime) had correct isIncognito guards. The leaks were in secondary paths: `touchLastRead()` (called on `.task` at MangaDetailView appear), `onReadComplete` (JS callback on 90% scroll), and both readers' `navigateToChapter` (which marks the *departing* chapter read/saves progress before loading the next). Always audit every code path that writes reading state, not just the primary completion handler.
- **`withTaskGroup` + JSBridge = thread starvation risk**: `group.addTask { bridge.searchManga() }` runs on Swift cooperative thread pool threads. JSBridge uses `DispatchSemaphore.wait()` which blocks the thread. With N sources, N cooperative threads are blocked simultaneously. Fix: `group.addTask { await Task.detached(priority: .userInitiated) { bridge.searchManga() }.value }` — makes the blocking nature explicit and uses a dedicated thread rather than a cooperative pool thread.
- **`[String: Int?]` double-optional cache is valid Swift**: `AniListService` uses `var cache: [String: Int?]`. Dictionary subscript returns `Value?` = `Int??`. `if let cached = cache[title]` distinguishes three states: (a) key absent → outer nil → if-let fails → re-fetch; (b) key present, value nil → outer some, inner nil → if-let succeeds, cached = nil → return nil (failure cached, no re-fetch); (c) key present, value some → if-let succeeds, cached = score → return score. This is correct and idiomatic.
- **AppLock pattern**: `scenePhase == .background → isLocked = true` in YomiApp.onChange. `AppLockView.onAppear` triggers LAContext.evaluatePolicy immediately — no extra user tap needed. `canEvaluatePolicy(.deviceOwnerAuthentication)` covers both biometric and passcode, so the lock screen works even without Face ID enrolled.
- **mobile-mcp WebDriverAgent failure doesn't block code audit**: When WDA times out, fall back to: `mcp__XcodeBuildMCP__screenshot` for visual verification, `xcrun simctl launch <udid> <bundleid>` to relaunch, AppleScript `click at {x,y}` on the Simulator window for UI interaction (window at System Events → process "Simulator"). Code review catches more bugs per hour than UI automation when the codebase is the primary concern.

## S56 — Technical learnings (2026-05-03)

- **Guard early-return must always restore DB state**: `loadChapters()` had two exit paths. The first (API returns empty) was fixed with `if loadedChapters.isEmpty { chapters = saved }`. The second (extension not installed — `guard let ext`) returned immediately with `chapters = []` — DB never queried. Any `guard ... else { return }` that exits before a DB fetch must fetch from DB first. Pattern: `guard let ext else { let saved = await Task.detached { ChapterQueries.fetchAll(...) }.value; chapters = saved; return }`.
- **WKWebView "Restore scroll position" prompt**: iOS WebKit shows a system-level "Restore scroll position" affordance (green arrow, accessible via VoiceOver as StaticText) whenever scroll state was previously saved. Suppress it by injecting `if ('scrollRestoration' in history) { history.scrollRestoration = 'manual'; }` as a `WKUserScript` at `.atDocumentStart` or `.atDocumentEnd`. One line, no side effects.
- **Back button hit area vs WKWebView tap gesture**: the novel reader back button (20×22 pt) competes with the WKWebView `UITapGestureRecognizer`. `shouldRecognizeSimultaneouslyWith → true` means both fire. The back button succeeds if tapped at its center (26, 133) — exact left-edge taps miss. To fix properly: increase button tap area with `.contentShape(Rectangle().inset(by: -12))` or use a larger padding container.
- **Two plugins with the same display name is valid**: `com.yomi.novelbin` (Yomi Firebase, Format A) and `64a5417437b8f41aaed9eca60d4a52ce` (LNReader catalog, Format B) both show as "NovelBin" in Sources. They are genuinely different plugins targeting the same site. Not a bug — just a UX confusion. DB query `SELECT id, name FROM extension WHERE name = 'NovelBin'` confirmed both rows with distinct IDs.
- **Simulator text field input via mobile-mcp is unreliable for Form sheets**: `mobile_type_keys` does not reliably inject text into a `Form`-hosted `TextField` presented in a `.sheet`. Workaround: use `xcrun simctl pbcopy <device> <text>` to load the clipboard, then long-press the field to get the Paste menu. Or restore values directly by editing the binary plist (`~/Library/Developer/CoreSimulator/.../Library/Preferences/bundleId.plist`) with `plistlib` + `json.dumps().encode()` and relaunch.

## S55 — Technical learnings (2026-05-03)

- **API-empty ≠ source-has-no-chapters**: `MangaDetailView.loadChapters()` pattern was `chapters = loadedChapters.map { mergeWithDB($0) }` — if `loadedChapters = []` (network failure), the map produces `[]` and overwrites all DB chapters. Fix: `if loadedChapters.isEmpty { chapters = saved } else { ... merge ... }`. Always check if the API returned nothing before discarding DB state. `NovelDetailView` already handled this correctly (always re-fetches from DB after API call).
- **Haptic guard for programmatic page changes**: `onChange(of: currentPage)` fires for ALL `currentPage` mutations, including programmatic resets (`navigateToChapter` sets `pages = []` then `currentPage = 0`). Since `pages` is cleared before `currentPage`, guarding with `if pages.count > 0` correctly suppresses haptics during navigation resets. `.onAppear`/`.task` page restores still fire one extra haptic (acceptable, single occurrence).
- **Swipe-to-delete UX for installed extensions**: `PluginsView` uses `.onDelete { indexSet in extensionManager.remove(...) }` on a `ForEach` inside a `List`. In simulator, mobile-mcp swipe coordinates must target the row precisely — the accessibility tree x-coord shifts left when the row is swiped, confirming the gesture registered. Delete button at trailing edge: found via `list_elements_on_screen` after swipe, not by guessing coordinates.
- **Extension install/remove cycle is atomic**: Install taps button → JS file downloads → `ExtensionQueries.upsert` → `loadInstalled()` — list updates immediately. Remove swipes row → `extensionManager.remove(ext)` calls `ExtensionQueries.delete` + deletes JS file → `loadInstalled()` — catalog entry immediately reverts from checkmark back to Install button. No stale state observed.
- **SourceKit LSP errors are always noise**: Every file edit triggered "Cannot find type 'Manga'" etc. in SourceKit. These are cross-file dependency resolution failures in isolation mode — never signal a real build error. Only `mcp__XcodeBuildMCP__build_sim` output is authoritative.

## S54 — Technical learnings (2026-05-03)

- **Underline tab bar in SwiftUI**: replace capsule chips with a `VStack(spacing:0) { Text(...).padding() + Rectangle().fill(selected ? accentColor : .clear).frame(height:2) }`. Wrap in `ScrollViewReader` + give each tab an `.id("tab_\(cat.id)")`. Use `.onChange(of: selectedCategoryId)` to call `proxy.scrollTo(id, anchor: .center)` so the active tab always scrolls into view. Mark the "All" tab id as `"tab_all"` since `selectedCategoryId == nil` for it.
- **Horizontal swipe to change category on a vertical ScrollView**: use `.simultaneousGesture(DragGesture(minimumDistance:40).onEnded { ... })`. Guard `abs(translation.width) > abs(translation.height) * 1.5` to avoid triggering on diagonal scroll. Map `selectedCategoryId` to an index in `[nil] + categories.map { Optional($0.id) }` — `[String?]` equality works fine with Swift optional semantics.
- **Merging two filter rows into one Menu**: remove the second horizontal chip row for status filter and add it as a second `Section` inside the sort `Menu`. Use `Divider()` between sections. The menu icon should fill (`.fill` variant) when either sort is non-default OR status filter is active — combine into one `let active = sortOrder != .lastRead || statusFilter != nil` binding.
- **Bulk operations in multi-select**: capture `installed` from `ExtensionManager.shared.installed` on the caller's context (MainActor) BEFORE entering `Task.detached`. Inside the detached task, use the captured `[Extension]` array (a value copy, safe to read). Call `DownloadManager.shared.enqueue` after the await returns (back on MainActor). `ChapterQueries.markAllRead(mangaId:)` is `nonisolated` — safe to call in a detached task loop.
- **`UIImpactFeedbackGenerator` for page turn haptics**: create the generator inline at call site — `UIImpactFeedbackGenerator(style: .light).impactOccurred()` — no need to store it. Add to `onChange(of: currentPage)` before the existing logic.

## S53 — Technical learnings (2026-05-02)

- **Embedded JVM on iOS requires NSExtension process isolation, not just framework embedding**: Code App (thebaselab) does NOT simply embed the JDK as a framework in the main target. It runs the JVM in a separate sandboxed process via NSExtension, using XPC/IPC. This is a fundamentally different architecture that requires building an app extension, cross-process lifecycle management, and separate entitlements. Any plan to "embed OpenJDK frameworks" without accounting for this is missing the critical piece.

- **OpenJDK 8 is the only proven iOS App Store JVM — and Suwayomi has moved past it**: thebaselab/codeapp-java ships OpenJDK 8 (JDK 8 only, not 11 or 21). Suwayomi dropped Java 8 support in v1.1 (June 2024); v2.x requires Java 21. There is no confirmed-working combination of (iOS-approved JDK) + (Suwayomi) as of 2026-05-02. Do not greenlight this feature without first confirming a working JAR+JDK pairing.

- **`SuwayomiService.baseURL` is already an indirect property — localhost is a drop-in**: the entire `SuwayomiService.swift` reads its base URL from `AppSettings.shared.suwayomiURL`. No service code changes are needed to point at an embedded server. The only integration work is: (1) start the JVM/server on app launch, (2) set `AppSettings.shared.suwayomiURL = "http://localhost:4567"` automatically when the embedded server is running. All browse, search, chapter, and page URL logic already works.

- **App Store listing attributes (iOS version, native/JS) do not confirm the absence of embedded runtime**: Tachimanga lists iOS 15.0+ and does not mention Java. Code App lists iOS 14.0+ and does not say "runs Java". App Store product pages are marketing materials, not architecture docs. Absence of "JVM" in the listing is not evidence that the app is pure Swift.

- **When in doubt about a competitor's architecture, look for open-source server forks, not the App Store listing**: Tachimanga's public repos (`tachimanga/Tachidesk-Server`) are more diagnostic than their iOS binary. The App Store listing vs. the server fork remain in conflict — the architecture is genuinely unconfirmed.

## S50 — Technical learnings (2026-04-28)

- **Language filter chip bar pattern**: collect unique `Extension.language` strings from installed array via `compactMap` + `Set.insert().inserted` dedup + `sorted()`. Render `RepoFilterChip` chips above the List in a `VStack(spacing: 0)` — same component used for repo filter in extensions tab. Filter computed property returns all when `selectedLanguage == nil`, filtered when set. Tapping a chip that's already selected clears the filter.
- **`showLatestNovels: true` for LNReader Latest feed**: LNReader's `popularNovels(page, options)` accepts `{showLatestNovels: true}` in the options object to return latest-updated novels instead of popular. All LNReader v3 plugins support this option (it's a standard LNReader API). Add `latestNovels(page:)` to JSBridge that injects `showLatestNovels: true` into `__lnr_opts` and calls `callPluginMethod`. Set `supportsLatest = true` for all LNReader sources.
- **Popular/Latest picker should not be gated on `!isNovelSource`**: the original guard `!isNovelSource && supportsLatest` hid the picker for all novel sources. After adding LNReader Latest support, the guard becomes just `supportsLatest` — works for manga, novels, and Mangayomi uniformly.
- **VStack wrapping List in ViewBuilder context**: adding a chip bar above a `List` requires wrapping in `VStack(spacing: 0)`. In SwiftUI's ViewBuilder, `List` is a single expression so it can coexist with the chip `ScrollView` inside the `VStack`. Brace count: `VStack { if chips { ... } List { ... }.task { ... } }` needs its own closing `}` even if `List` is the last child — don't count `List`'s close as VStack's close.

## S49 — Technical learnings (2026-04-26)

- **Mangayomi JS plugin format (current)**: plugins define `class DefaultExtension extends MProvider { ... }` and `const mangayomiSources = [{...}]`. They do NOT define a `source` variable. Pre-eval shims must include `MProvider` (ES5 constructor function — ES6 `class extends` works with it) and `SharedPreferences`. Post-eval adapter must detect `DefaultExtension` + `mangayomiSources`, instantiate with `new DefaultExtension()`, then set `instance.source = mangayomiSources[0]` (normalizing `langs[]` → `lang`).
- **`getSrc`/`getHref` must be getter properties, not methods**: Mangayomi plugins write `el.getSrc` (property access) not `el.getSrc()`. Defining them as functions returns the function object (truthy but wrong). Fix: use `Object.defineProperties` with `get:` descriptors for both, and use `get getSrc() { return ''; }` shorthand in the `_nullEl` object literal.
- **Native `async/await` in JSC does not resolve via `_resolve()`**: `_resolve(promise).then(cb)` fires `cb` synchronously only when `SyncPromise` is used. Native `async function` in JSC wraps its return in the native internal Promise system, not `global.Promise`, so microtask continuations are scheduled and don't run until `evaluateScript` or the run loop. Fix: use `context.evaluateScript(...)` for all Mangayomi method calls (same as `callPluginMethod` for LNReader) — JSC drains microtasks after each `evaluateScript` call.
- **Mangayomi method name differences**: `getLatestUpdates` (not `getLatest` — current plugins), `episodes` (not `chapters` — field in `getDetail` return for manga chapters). Always check both names via `?? fallback`.
- **Mangayomi item field names**: list items use `{link, name, imageUrl}` — not `{url, title, image}`. Map `item.link || item.url` for id/path, `item.name || item.title` for title, `item.imageUrl || item.image` for cover URL.

## S48 — Technical learnings (2026-04-26)

- **`PBXFileSystemSynchronizedRootGroup` + `INFOPLIST_FILE` conflict**: adding a widget extension with a manual `Info.plist` file and `INFOPLIST_FILE = ...` causes "Multiple commands produce Info.plist" because the synchronized group also processes the plist as a resource. Fix: add the file to the target's `PBXFileSystemSynchronizedBuildFileExceptionSet.membershipExceptions` array so the synchronized group skips it. The `INFOPLIST_FILE` build phase then handles it exclusively.
- **`INFOPLIST_FILE` does NOT auto-inject bundle keys — must be a complete plist**: when using `INFOPLIST_FILE` (as opposed to `GENERATE_INFOPLIST_FILE = YES`), Xcode uses the file as-is and only performs `$(VAR)` variable expansion. It does NOT add `CFBundleIdentifier`, `CFBundleName`, `CFBundleExecutable`, etc. Missing `CFBundleIdentifier` triggers "Embedded binary's bundle identifier is not prefixed with parent app's bundle identifier" during `ValidateEmbeddedBinary`. Always write a complete Info.plist with all standard keys using `$(PRODUCT_BUNDLE_IDENTIFIER)`, `$(EXECUTABLE_NAME)`, `$(MARKETING_VERSION)`, `$(CURRENT_PROJECT_VERSION)`. `CFBundlePackageType` for app extensions is `XPC!` (not `APPL`).
- **Widget bundle ID must be a dotted prefix of the parent app's bundle ID**: `pacodealer.YomiWidget` is NOT a valid extension of `pacodealer.Yomi` (it reads as a sibling). Correct form: `pacodealer.Yomi.widget`. The iOS validator checks `childBundleID.hasPrefix(parentBundleID + ".")`.
- **OPDS Atom XML — navigation vs acquisition detection**: navigation entries have `<link type="application/atom+xml...">` pointing to another feed. Acquisition entries have `<link rel="http://opds-spec.org/acquisition" ...>` pointing to a downloadable file. Cover images use `rel="http://opds-spec.org/image"` or `rel="http://opds-spec.org/image/thumbnail"`. Feed-level `<link rel="next">` handles pagination. XMLParser in Foundation is SAX-style and strips namespace prefixes — use local element names directly (`feed`, `entry`, `title`, `link`, etc.).
- **`TimelineProvider` with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` in widget extension**: works as-is. The provider's callback-based methods (`getTimeline(in:completion:)`) are implicitly `@MainActor`, and calling the completion handler from the same context is valid. No nonisolated annotation needed. Widget extensions don't have the same JSBridge DispatchSemaphore constraint as the main app.
- **App Groups and widget data sharing**: shared data goes in `UserDefaults(suiteName: "group.pacodealer.Yomi")`, not `UserDefaults.standard`. Both the main app and widget extension must declare `com.apple.security.application-groups` in their `.entitlements` files. Both entitlements files must be wired to their respective targets via `CODE_SIGN_ENTITLEMENTS` in build settings. Call `WidgetCenter.shared.reloadAllTimelines()` after writing to trigger a widget refresh.

## S97 — Technical learnings (2026-08-06)

- **iPhone Mirroring (macOS) cannot be automated** — `iPhone Mirroring.app` renders the real device
  live (screenshots via `screencapture -R` work perfectly), but synthetic clicks (`cliclick`,
  AppleScript `System Events click at`) never register as touches on the phone — confirmed via both
  instant clicks and explicit down/hold/up sequences, on multiple known-good targets. Almost certainly
  a deliberate Apple anti-automation measure on that specific feature. For any future "watch Martin's
  real device" task, the only path is Martin driving it manually while Claude screenshots/observes —
  don't burn time re-attempting programmatic clicks.
- **A "verified against source" audit still needs a second pass before triggering new work.**
  `TACHIMANGA_PARITY.md`'s first draft, though grep/read-verified per file, still called two already-
  implemented features "missing" (Global Update, Open random entry) because the search terms used
  didn't match their actual names in the codebase (`refresh()`, "shuffle"). Re-reading the actual
  call site before implementing — not just trusting a clean grep miss — caught both before wasted work.
- **mobile-mcp round-trips in this environment can take much longer in wall-clock time than the
  simulator's own clock suggests is happening within the app** — a 2-second SwiftUI auto-dismiss timer
  (Updates' refresh toast) reliably closed before any screenshot could land, across several attempts,
  even back-to-back. Diagnosed by watching the simulator's own status-bar clock jump by many real
  minutes between one tool call and the next. Workaround for verifying short-lived transient UI:
  temporarily inflate the dismiss duration, confirm the visual, then restore the real value — don't
  conclude a short-lived toast/banner is broken just because a screenshot missed it.
- **CF-detection heuristics need to match real-world block pages, not just the textbook one.**
  `JSBridge.swift`'s Cloudflare check only looked for `"Just a moment"` / `"cf-mitigated"` — real
  Cloudflare error pages vary a lot (1015 rate-limit, 1020 access-denied, etc.) and don't all contain
  either string. Found by actually triggering a live block (FreeWebNovel) and reading the raw response
  body via `mobile_list_elements_on_screen`'s full accessibility dump, not by reasoning about it in
  the abstract.

## S98 — Technical learnings (2026-08-06)

- **`GeometryReader` used directly as `List` row content destabilizes every row below it** — not just
  a layout quirk, a real hit-testing bug. `StorageView`'s summary bar used a `GeometryReader` to
  measure its own width for a proportional stacked-bar chart, placed as the first `Section`'s row
  content; every row in every `Section` after it became untappable, and the List's actual scroll
  position visibly desynced from what `mobile_list_elements_on_screen`'s accessibility tree reported
  (rows reported at y-offsets that didn't match the screenshot). Fixed by moving the chart entirely
  outside the `List` (a plain header view above it) — the safe pattern for any chart/graph that needs
  its own geometry, inside a `List`, in this codebase from now on: don't nest `GeometryReader` in a row.
- **A `confirmationDialog`/`.alert` with a computed `isPresented` `Binding` (derived from some other
  observable, e.g. `optionalTarget != nil`) races its own dismiss-triggered `Binding` setter against an
  `async` button closure that reads the same observable again.** SwiftUI's auto-dismiss-on-tap calls
  the `isPresented` setter (which cleared `migrationTarget` in `MigrateView`) as part of the same
  transaction as the button tap; a `Button { Task { await doThing() } }` whose `doThing()` re-reads
  `migrationTarget` after a suspension point sees `nil` — the guard silently bails, no crash, no error.
  From the outside this is indistinguishable from a dead button (dialog dismisses, nothing happens) —
  looked exactly like the `mobile-mcp` tap-flakiness this session already knew about (see
  `CLAUDE.md`'s mobile-mcp section), which cost real time before the actual cause was found. **Fix
  pattern: capture the target by value in each button's closure at dialog-build time, never re-read the
  optional/observable property inside the button's own action after any `await`.**
- **`mobile-mcp` plain-`Button` tap flakiness (documented in `CLAUDE.md`) is real and distinct from the
  race above** — confirmed by reproducing the identical symptom on `AdvancedSettingsView`'s untouched,
  pre-existing "Export diagnostic log" button. `NavigationLink`s were reliably tappable throughout this
  session even at the same navigation depth; only plain `Button` actions (sheet/dialog presentation,
  in-place state mutation) were affected. When a button-triggered UI change won't register, try 2-3x
  and a fresh relaunch before concluding it's a real bug — but check for a state race first if the
  surrounding code has one, since the two failure modes are visually identical.
- **`xcrun simctl spawn <device> defaults write <bundle-id> <key> -string <value>` is a reliable way to
  seed a `UserDefaults`-backed `AppSettings` property for testing** without fighting flaky UI —
  `AppSettings` reads all its defaults once in `init()`, so a relaunch (`build_run_sim` again) after
  the `defaults write` picks it up. Used to force `pageLayout` to verify double-page spreads without
  needing the in-reader settings sheet's gear icon (itself affected by the tap flakiness above).
- **Direct `sqlite3` against the simulator's `yomi.db`** (path via `xcrun simctl get_app_container
  <device> <bundle-id> data`, then `Documents/yomi.db`) is the fastest way to both seed test data (e.g.
  marking a chapter read to verify Migrate's progress-transfer) and to verify a feature's actual
  database effect when the UI's own confirmation is unreliable or absent. Read-only inspection is
  always safe; writes for test-seeding purposes only (never as a substitute for the app's own logic).

## Architecture decisions

See `Yomi/ARQUITECTURA.md` §Design decisions — the full, current table. The short/stale copy
previously here was removed during the 2026-08-04 doc restructure.
