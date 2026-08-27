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

## Fresh clone setup
`Yomi/Config/AppSecrets.swift` holds real OAuth client secrets and is gitignored — it is never
checked in, so a fresh clone cannot compile until it exists. Copy `Yomi/Config/AppSecrets.swift.template`
to `Yomi/Config/AppSecrets.swift` (same directory) and fill in the values you need; registration
links for each tracker are in the template's own doc comments. MAL is required for that tracker to
compile at all — the other three (AniList/Shikimori/Bangumi) compile fine with empty strings, they
just can't authenticate until filled in.

## Key docs (read these at session start)
- `Yomi/ROADMAP.md` — current state, planned work, tech debt
- `Yomi/ARQUITECTURA.md` — full architecture, data flows, DB schema
- `Yomi/METODOLOGIA.md` — workflow rules, tech learnings per session
- `Yomi/RESEARCH.md` — master research doc (competitive, UX, App Store, iOS 26, plugins, architecture)
- `Yomi/design/DESIGN_HANDOFF.md` — **design track handoff + roadmap to launch (start here for design/publish work)**
- `Yomi/design/DESIGN_SYSTEM.md` — the justified design system (concept, color/theming, type, components, screens)
- `Yomi/design/DESIGN_RESEARCH.md` — design/UX/competitive research behind the system
- `Yomi/design/design_handoff_yomi/YOMI Screens.dc.html` — **full 16-screen design spec** (primary implementation reference; HTML + inline CSS; all canvas/reader theme colors, screentone patterns, Liquid Glass overlays)

## Design track (S82-S95 — all 12 blocks complete)

All 16 screens designed and confirmed. Concept: **"reading instrument / living archive"** — warm editorial canvas, covers + user accent are the only color, monospace catalog notation, ink/screentone signature. Confirmed: default accent **Vermilion `#E5473A`**, default canvas **Ink (`#14110F`)**, Space Grotesk (UI) + Space Mono (notation), Newsreader serif (novel body). Design tokens live in `DesignTokens.swift`; canvas colors are wired app-wide via `\.yomiCanvas` environment (`CanvasEnvironment.swift`, set from `AppSettings.canvasColors`); notation helpers in `Notation.swift`; Appearance Studio in `AppearanceStudioView.swift`. **Full design spec**: `Yomi/design/design_handoff_yomi/YOMI Screens.dc.html` — 16 screens as HTML with inline CSS. App icon assets: `AppIcon-Ink.png` + `AppIcon-Paper.png` in `Yomi/design/design_handoff_yomi/assets/`. **All 12 blocks complete as of S95 (2026-08-05).** Blocks 1-5 screenshot-verified S85; Block 6 (Browse) S86; Block 7 (History) S91; Block 8 (Updates) S92; Block 9 (Downloads) S93; Block 10 (Insights) S94; Blocks 11-12 (More/Settings/Onboarding/empty states) S95. **S96 (2026-08-06): the full functional audit Martin asked for, done.** App Store screenshot work is unblocked. **S97-S98: Tachimanga feature-parity pass, complete — see below.**

## Current state (post S119 — 2026-08-27 · fixed all 5 HIGH findings from the S118 audit backlog)

**S119 started the audit fix backlog, taking the 5 HIGH-severity findings S118's own handoff named
first.** All fixed, clean zero-warning build on the `Yomi` scheme throughout (`YomiWidget` not
rebuilt — none of this session's files are shared with that target).

- **#138** (`BackupManager.importBackup` hung the UI): file read + JSON parse + model decoding moved
  off MainActor into a new `nonisolated static decodeBackup(at:)` returning a `Sendable`
  `DecodedBackup`; every restored row now writes inside **one** `appDatabase.write` transaction
  instead of one transaction per `*Queries.upsert`, with one `markCloudDirtyBatch` per record type
  replacing the per-row dirty-mark writes. ~24,000 main-thread transactions → one, off MainActor.
- **#145** (update check couldn't distinguish "nothing new" from "fetch failed"): both check
  functions now return whether their fetch genuinely failed, counted into a new
  `UpdatesViewModel.failedSourceChecks` and appended to the refresh banner.
- **#147** (tracker progress-sync failures invisible in all 4 services): new shared
  `MangaTracker.sendProgressUpdate(_:graphQL:)` protocol extension — real `do/catch`, HTTP-status
  check, AniList GraphQL `errors`-in-a-200 check, writes to `errorMessage` and clears it on success
  (which also closes the stale-banner half of #110); `TrackersView` rows now show that message.
- **#148** (failed migration deleted the working original): `MigrationService.migrate` fetches the
  new source's chapters *first* and throws `MigrationError.noChaptersFromNewSource` before any
  write, so nothing is touched when the fetch fails; the confirmation screen now always states the
  new source's real chapter count.
- **#149** (partial download marked "Downloaded"): a page counts only when both the fetch and the
  disk write succeed; `markDownloaded` runs only at zero failures, otherwise the chapter is marked
  not-downloaded and a new `failureMessage` is surfaced via `.yomiToast`. **Also closes #111** in
  the same code path (a cancelled download now cleans up instead of marking itself complete).

**Live verification**: `build_run_sim` + mobile-mcp. #145 was verified end-to-end — seeded a library
novel on the dead LightNovelPub source next to a working MangaDex manga via direct `sqlite3`,
relaunched, tapped Refresh, and the banner read **"No new chapters · 1 source failed"**, correctly
counting the dead source and not the healthy one (test rows removed afterward). The other four were
verified by clean compile + code review only — each needs state this dev simulator doesn't have (a
large backup file, two working sources for a migration, a flaky connection mid-download, real
tracker credentials, which #108/#115 note are still missing for 3 of the 4 services).

**Next session**: the backlog still has ~37 substantive findings — rows 108-110/112-122,
123-125/129/131-137, 139-144/146/150-156, plus rows 157-162 (6 quick doc-only fixes). Highest-value
remaining: **#131** (Suwayomi manga detail shows no chapters, ever) and **#123/#124** (real tracker
login-CSRF on Shikimori/Bangumi/AniList).

---

## Prior state (post S118 — 2026-08-22 · finished the full 23-dimension audit: verified all 15 UNVERIFIED S117 findings, then ran the last 4 uncovered dimensions)

**S118 had two phases, both continuing the S116→S117 full-project audit to its actual completion.**

**Phase 2 — ran the 4 dimensions that never got their finder agent to complete in S116/S117**
(Performance, Docs-vs-code, Error handling, Backend/Firebase — the last of the original 23), per
Martin's "finish the audit" ask. Used parallel `Agent` calls (not the `Workflow` tool, to stay
clear of the rate limit that hit S116/S117 four times) — one finder per dimension, each briefed on
the project's own established conventions (including the `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
setting that caused Phase 1's false positives) so they wouldn't repeat that mistake. **Every one of
the 25 findings produced was then independently re-verified by direct file-reading before being
trusted** — reading the exact cited lines, and for the Backend/Firebase dimension, live `curl -I`
against the production Firebase Hosting domain and a direct `diff` against a stale duplicate
directory found on disk. **All 25 confirmed true**, logged as Known Issues rows #138-162. Headline
findings: `BackupManager.importBackup` restores a whole library on the main thread with one
DB-write transaction per row — 24,000+ sequential synchronous transactions for a realistic library,
fully hanging the UI (#138, HIGH); a chapter-update check silently reports "No new chapters"
identically whether nothing is new or the fetch itself failed, since every JS-side plugin exception
is swallowed with no distinction (#145, HIGH); all 4 tracker services' progress-sync call never
surfaces failure anywhere, not even to their own `errorMessage` (#147, HIGH); a source migration
whose new-source chapter fetch silently fails still reports success and can delete the old library
entry + downloaded files, stranding the user with a chapterless manga (#148, HIGH);
`DownloadManager` marks a chapter "Downloaded" even when individual pages silently failed to fetch
(#149, HIGH); and no integrity/authenticity check exists anywhere between the Firebase-hosted
plugin catalog and JSCore execution — the only protection is TLS, and a compromised deploy or a
trusted-cert MITM (e.g. school/corporate TLS inspection) could silently modify plugin code with zero
user-visible signal (#151, MEDIUM). Also found a live, verified CDN-cache-staleness gap the S87
client-side fix (#9) never closed (#153) and a stale duplicate `Firebase/yomi-firebase/` scaffold
directory with 4 of 6 overlapping plugin files older than production (#156) — both confirmed via
direct external checks (`curl -I`, `diff`), not just code-reading. **No fixes applied — audit only.**

**This completes the full 23-dimension audit Martin originally asked for in S116** ("absolutely
everything," 2026-08-21). Final tally: 8 dimensions fully audited with adversarial re-verification
(S116) + 1 done directly by hand (live build+simulator walkthrough, S117) + 14 dimensions that got
a finder pass and are now all independently verified (10 from S117 + 4 from this session) = 23/23
covered. **Total real, verified findings from the whole audit: 34 (S116, rows 74-107, already fixed
S117) + 30 (S117, rows 108-137 — 15 fixed-worthy already confirmed, 15 more confirmed this session,
4 refuted) + 25 (this session, rows 138-162) = 89 findings logged, of which 4 were refuted and the
rest are real.**

**Next session should work through the fix backlog**: rows 108-122 (15) + 123-125/129/131-137 (8)
+ 138-156 (19 real, non-docs) = 42 substantive findings ready to fix, plus rows 157-162 (6 doc-only
fixes, quick). Suggest starting with the 5 HIGH-severity error-handling/performance findings from
this session (#138, #145, #147, #148, #149) — they're all real user-facing correctness gaps, not
just cleanup. Committed and pushed.

---

## Prior state (post S118 phase 1 — 2026-08-22 · independently verified all 15 UNVERIFIED S117 findings)

**S118 phase 1 — picked up exactly where S117 left off: independently verify Known Issues rows 123-137
before trusting/fixing any of them, starting with #130 given the stakes, per S117's own explicit
handoff note.** Done entirely by direct file-reading (no subagents/`Workflow` — avoids the
account rate-limit that hit S116/S117 four times), reading each cited file (and, for the two
highest-stakes claims, the surrounding project config) rather than trusting the finder agent's
prose.

**11 of 15 confirmed true**, table rows updated with the verification evidence: #123/#124
(Shikimori/Bangumi/AniList OAuth login-CSRF — confirmed by direct code contrast against MAL's
real PKCE `codeVerifier` check, which genuinely blocks the same attack the other 3 trackers are
exposed to), #125 (notifications ignore App Lock/Secure Screen, same gap #68 already fixed for
the widget), #129 (widget's "last chapter" field is a hardcoded literal), #132-137 (6 dead-code
items, each re-confirmed by grep). **#131 upgraded from MEDIUM/dead-code to HIGH/correctness** —
turned out to be a real functional bug, not just unused REST methods: `SuwayomiService.toManga`
sets `sourceId: "suwayomi_\(sourceId)"`, which can never match an entry in
`ExtensionManager.shared.installed` (real plugin ids), so `MangaDetailView.loadChapters()`'s guard
always fails for a Suwayomi-sourced manga — tapping into one from Browse shows no chapters, ever.

**4 of 15 refuted — real false positives from the finder agent, not just unconfirmed leads**:
**#130** (the highest-stakes one, claiming all 15 plugin `.js` files ship in the binary) had the
mechanics backwards — `membershipExceptions` inside a `PBXFileSystemSynchronizedBuildFileExceptionSet`
is an *exclusion* list, not an inclusion list (confirmed against S78's own changelog wording and
`seedBundledPlugins()`'s own doc comment). CLAUDE.md's/ARQUITECTURA.md's "zero plugin files ship in
the binary" compliance claim holds. **#126/#127/#128** (concurrency findings for
DownloadManager/BackupManager/the 4 tracker services, "same bug class as #82") missed that
`project.pbxproj` sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` project-wide (Xcode 26
"Approachable Concurrency") — none of those classes are `nonisolated` at the type level, so every
method on them is MainActor-isolated by default and correctly resumes on MainActor after any
`await`, no explicit hop needed. **All 4 refutations share one root cause: the finder agent never
checked the project's actual build settings before asserting a violation** — worth remembering for
any future audit dimension that reasons about bundling/build-phase or actor-isolation without first
reading `project.pbxproj`'s build settings directly.

**No fixes applied this session** — verification only, per the S117 handoff's own two-step plan
((a) verify, then (b) fix). **Next session should work through the now-fully-verified backlog**:
rows 108-122 (15, confirmed S117) plus rows 123-125/129/131-137 (8, confirmed S118) — 23 real,
verified findings ready to fix, headlined by #131 (Suwayomi manga detail is fully broken) and
#123/#124 (real tracker-login CSRF). Rows 126-128/130 are closed as false positives, not carried
forward. Committed and pushed.

---

## Prior state (post S117 — 2026-08-22 · S116 backlog fixed + remaining 15-dimension audit run, 30 new findings)

**S117 — Martin asked to fix the S116 backlog and then continue the remaining 15 dimensions in the
same session.** Fixed 32 of the 34 confirmed findings from Known Issues rows 74-107 directly (no
subagents — a large, mostly-mechanical fix sweep across ~19 files, done inline). The 2 left
unfixed are both deliberate architecture-tradeoff calls, not skipped for lack of time: #78 (iPad's
two independent tab-visibility stores — needs a real product decision on which wins, plus an iPad
device this environment doesn't have to verify either direction) and #106 (`ChapterReaderView.swift`
file split — safer as its own dedicated pass since several of this session's own fixes just touched
that exact file). Both left with an explicit rationale in the table below rather than silently
dropped.

**Notable fixes**: `ChapterQueries.upsert`/backup-restore now correctly marks CloudKit-dirty
(#75/#79, closes the silent-desync gap); the novel-reader soft-lock on re-tapping the current
chapter is gone (#92); `ReaderWebView`'s `Coordinator` now implements `decidePolicyFor` to block
navigation out of the reader from unsanitized scraped HTML (#95); tracker auto-update no longer
fires redundant API calls per chapter (#89); short chapters that don't need scrolling now correctly
fire the 90%-completion/scroll-percent signals instead of staying stuck at 0% forever (#93); OPDS
pagination is now consumed with a "Load More" affordance in both the root and drill-down views
(#87); the Tachiyomi-import "0 matched sources" miscount is fixed (#80).

**Verification**: clean zero-warning `build_sim` on the `Yomi` scheme, a live `build_run_sim` +
mobile-mcp pass confirming Library/Browse/Plugins/Sync all render and function post-changes (no
regression from the Query-layer, Extensions, or Reader changes). Did not separately rebuild
`YomiWidget` — none of this session's changes touched `AppSettings.swift`/`WidgetDataWriter.swift`
or any other file the widget target shares.

**Then ran the remaining 15 audit dimensions** (leaner single-pass `Workflow`, no high-severity-
recheck/completeness-critic stages, per Martin's own suggestion) — did the live-simulator-walkthrough
dimension directly instead of via subagent. **Hit the account's usage/rate limit twice more mid-run**,
same as S116 — resumed once via `resumeFromRunId`; after the second hit Martin asked to stop
spending more usage on it rather than resume a third time. **14 of 15 dimensions got their finder
agent to run** (only Tracker sync, Settings/storage, History/onboarding, Design system,
Accessibility, Security/privacy, App Store compliance, Concurrency, YomiWidget, and Dead code
actually produced findings — Performance, Docs-vs-code, Error handling, and Backend/Firebase never
got their finder to complete before the second rate-limit hit). **30 new findings logged as Known
Issues rows 108-137**: **15 independently adversarially verified** (rows 108-122 — headline items: a
tracker OAuth refresh-token that's saved but never used, silently killing MAL/Shikimori/Bangumi sync
forever once the access token expires, #108; a manga/novel that's opened and partially read but
never crosses the 80%/90% completion threshold never appearing in History at all, #114; `YomiScrubber`
— the reader's page/font-size slider — having zero VoiceOver support, #120) and **15 found by the
finder but never independently re-verified before the rate limit hit a second time** (rows 123-137,
explicitly marked UNVERIFIED in the table — most notably #130, a claim that all 15 production plugin
`.js` files are bundled directly into the shipped binary, contradicting this repo's own "App binary
ships zero plugin files (App Store compliance)" claim stated in both this file and ARQUITECTURA.md;
and #123/#124, claimed OAuth login-CSRF vulnerabilities in Shikimori/Bangumi/AniList's tracker flows
with no `state` param or PKCE). **The unverified rows are leads, not settled findings — confirm each
one by reading the cited file before trusting or fixing it**, starting with #130 given the stakes if
true. **No fixes applied to any of the 30 new rows this session** — audit-only, matching S99/S112/
S116's own precedent. Committed and pushed, per Martin's explicit ask to stop and not lose the work.

---

## Prior state (post S116 — 2026-08-21 · partial full-project audit, 8/23 dimensions fully verified)

**S116 — Martin asked for an "absolutely everything" audit, more thorough than S99/S112, explicitly authorizing
unlimited agent spend.** Run as a 23-dimension multi-agent `Workflow` (core/db, app lifecycle, CloudKit sync,
extensions/plugins, browse, manga reader, novel reader, library, trackers, settings, history/onboarding, design
system, accessibility, security/privacy, App Store compliance, concurrency, error handling, dead code,
performance, widget, docs-vs-code, backend/Firebase, live build+simulator walkthrough) — every finding
independently re-verified by a second adversarial agent before being trusted, matching S112's method but scaled
up. **Interrupted twice by the account's own session/usage limit mid-run** (not a bug in the audit itself), each
time resumed via `Workflow`'s `resumeFromRunId` (completed agents replay from cache, only the rest re-run) —
worth remembering this recovers cleanly, but **`resumeFromRunId` only works within the same chat session**, so a
run this large should be seen through to completion in one sitting rather than assumed resumable across a context
switch. Also caught and fixed a real bug in the workflow script itself mid-run: a double-wrapped `parallel()`
call in the high-severity recheck stage passed already-invoked promises instead of thunks.

**8 of 23 dimensions ran to full completion with independent verification** (Core & Database, App lifecycle,
CloudKit sync & backup, Extensions & plugin architecture, Browse & source detail, Manga reader, Novel reader,
Library & migration) before Martin asked to pause and continue in a fresh chat to conserve usage, rather than
risk losing the completed work to a third interruption. **34 new confirmed findings** logged below as Known
Issues rows 74-107 (23 medium, 11 low; the single high-severity candidate that surfaced didn't survive its
second-opinion recheck and was correctly discarded, not just dropped). Headline items: a wrong "0 matched
sources" count in the Tachiyomi-import summary (#80) that misleads every migrating user regardless of whether
the import actually worked; `ChapterQueries.upsert` never marking CloudKit-dirty (#75/#79), so backup-restored
read-state silently never syncs; a soft-lock in the novel reader when tapping the currently-open chapter in its
own chapter list (#92); tracker auto-update firing multiple redundant API calls near a chapter's end with no
guard (#89); and a WKWebView in the novel reader with no `decidePolicyFor` navigation interception over
unsanitized scraped third-party HTML (#95). **No fixes applied yet — catalog only, matching S99/S112's own
precedent of auditing and fixing in separate sessions.**

**15 dimensions never got their finder agent to complete and are NOT yet covered**: Tracker sync (the S115
code — highest-priority remaining slice, was deliberately scheduled hardest but the finder never finished),
Settings/storage/downloads/appearance, History/onboarding/App Lock, Design system & visual consistency,
Accessibility, Security & privacy, App Store compliance, Concurrency & Swift 6 actor isolation, Error handling &
silent failures, Dead code & unused assets, Performance, YomiWidget target, Documentation accuracy vs. code,
Backend service & Firebase plugin hosting, and the live build+simulator walkthrough. **Next session picking this
up should either (a) fix the 34 confirmed findings below first, since that's real known work, or (b) re-run the
audit workflow for just the 15 uncovered dimensions** (the full script, dimension list, and schemas are in this
session's transcript — a smaller single-pass version without the high-severity recheck/completeness-critic
stages would be cheaper and is probably sufficient for a second pass).

---

## Prior state (post S115 — 2026-08-19 · novel chapter-preload + full tracker-sync generalization)

**S115 picked up two S114-research items Martin chose directly: novel chapter-preload (small) and
tracker sync (large), both shipped same session.**

**Novel chapter-preload** — `TextReaderView.swift` now backgrounds a `bridge.parseChapter` fetch for
the next chapter once scroll progress passes 70%, cached in `chapterContentCache` and consumed by
`loadContent()` on nav instead of re-fetching; a jump-to-chapter (not just linear next/prev) evicts any
stale cached entry. Mirrors the manga reader's S109-111 boundary-preload intent without needing the
seamless in-scroll crossing that feature has (the novel reader is single-document-per-chapter, not
continuous-scroll).

**Tracker sync — S114's premise was wrong, corrected before building anything.** RESEARCH.md §20 claimed
"Yomi has zero tracker integration today"; it doesn't — real, working MAL (MyAnimeList) OAuth+auto-update
already existed (`MALService.swift`, wired into `ChapterReaderView.swift`), the research session just
never checked Yomi's own code before comparing against Aidoku's tracker list. Flagged this to Martin
directly rather than building a redundant "first tracker."

**What actually shipped**: a new `MangaTracker` protocol (`Features/More/MangaTracker.swift`) generalizing
MAL's existing shape (authURL/handleCallback/searchManga/updateProgress/logout/isLoggedIn), `MALService`
refactored to conform, and three new trackers built against it — **AniList** (`AniListTrackerService.swift`
— named distinctly from the pre-existing, unrelated `Features/Extensions/AniListService.swift` score-badge
actor, a real naming collision caught before it shipped), **Shikimori**, and **Bangumi** (Martin's picks,
research-verified live against each service's real API — see `RESEARCH.md` §21). AniList uses the
Implicit Grant (no client_secret needed, the only one of the four with that option); Shikimori and Bangumi
both require a `client_secret` embedded client-side (no PKCE alternative exists in either API) — flagged
directly to Martin, who confirmed embedding it is fine, same as every other open-source tracker client.
New `AppSecrets.swift` placeholders (`aniListClientId`/`shikimoriClientId`+`Secret`/`bangumiClientId`+
`Secret`) need real registered app credentials before any of the 3 new trackers can actually authenticate
— MAL is unaffected and keeps working as before. New `TrackerManager` (`Features/More/TrackerManager.swift`)
centralizes both the tracker registry (`loggedInTrackers`, fanned out from both readers on chapter-finish)
and OAuth-callback routing by host (`ContentView`'s one `.onOpenURL`, replacing MAL's old per-view handler).
New `TrackersView.swift` (More → Trackers) replaces the old single MyAnimeList row with all 4 trackers plus
a new `AppSettings.trackerAutoUpdate` toggle — previously always-on with no opt-out (Known Issue #72, now
fixed same session).

**Real pre-existing bug found and fixed as a prerequisite**: `Info.plist` had no `CFBundleURLTypes` entry
at all — the `yomi://` custom URL scheme was never registered with iOS, so MAL's own OAuth callback
(`yomi://mal/callback`) could never have actually reached the app. Likely broken since MAL login was
first built; every tracker's OAuth depends on this, so it had to be fixed regardless of scope (#73, fixed).

**A confusing red herring during this session, resolved**: after adding the new tracker files, a clean
build reported a nonsensical error inside `ChapterReaderView.swift` — a 2-argument `.onChange` closure
"expects 1 argument." Spent real time bisecting file-by-file assuming a whole-module-compilation/batch
bug (`SWIFT_COMPILATION_MODE=singlefile` didn't change it, which should have been the tell). The error
was real the whole time: `MALService`'s protocol-conforming signature change
(`searchManga`'s return type, `updateMangaProgress`'s parameter) broke `ChapterReaderView.swift`'s old
call site, and Swift's diagnostics for other still-broken files (missing `TrackerManager` etc.) were
simply suppressing/reordering when that particular error got surfaced. Fixed by updating the call site
to loop `TrackerManager.loggedInTrackers` (which was the real task-3 work anyway). **Lesson**: when a
build error looks structurally impossible for an unrelated file, check for a stale call site against a
signature you just changed before suspecting the toolchain.

Zero-warning clean build on both `Yomi` and `YomiWidget` schemes (AppSettings.swift is shared). Live-
verified via `build_run_sim` + mobile-mcp: Trackers screen renders all 4 services with correct
not-connected state, the auto-update toggle is live, and MyAnimeList's own login screen is unchanged.
Full OAuth round-trips for AniList/Shikimori/Bangumi remain unverified — they need real client
credentials from Martin first (see `AppSecrets.swift`'s comments for each registration URL).

**Follow-up same session — real tracker logos** (Martin's ask, and his call to use real logos over
a monogram fallback). Each service's own official icon, sourced from: MAL — `cdn.myanimelist.net`'s
own SVG favicon; AniList — `anilist.co`'s own apple-touch-icon PNG; Shikimori —
`shikimori.io`'s own apple-touch-icon PNG; Bangumi — no square icon exists anywhere, including their
own site (`bgm.tv` blocks non-browser requests entirely) — used the wordmark PNG from Wikimedia
Commons instead, tagged `{{PD-textlogo}}` (public domain — simple text/geometric logos don't clear
copyright's threshold of originality; still carries a standard trademark notice, which nominative
fair use for service-identification covers, same basis every "Login with X" button relies on).
New `Assets.xcassets/TrackerLogo{MAL,AniList,Shikimori,Bangumi}.imageset` entries, wired via a new
shared `TrackerLogo`/`TrackerHeaderLogoSection` (`TrackersView.swift`). **Real bug caught live,
not assumed**: Bangumi's wordmark PNG is solid black — invisible against the app's dark-mode row
background until rendered as `.template` + `.foregroundStyle(.primary)`. Also needed a wider,
non-square frame (72×28 in the list, 176×64 in its own header) since it's a ~3.6:1 wordmark, not a
square mark like the other three — flagged to Martin directly as a real tradeoff (his call: keep
the real wordmark honestly-sized over forcing it into a square that made it unreadable). Live-verified
all 4 renders via mobile-mcp screenshots. Zero-warning build both schemes.

---

## Prior state (post S114 — 2026-08-18 · external competitor/architecture research, no code changes)

**S114 was a research-only session in a general conversation, not a Yomi coding session — no code
touched.** Martin asked about Swift-ecosystem competitors, then went deeper on specific architecture
questions, then asked to commit+push the findings so they're not lost. Full detail in
`Yomi/RESEARCH.md` §20. Headlines: Ito/Nyora surveyed as new (not-yet-threatening) competitors in
Yomi's exact niche; a real code-level comparison found Aidoku's WASM plugin model has **no meaningful
performance edge** over Yomi's JSCore/JSBridge model, but surfaced a real, unrelated, unfixed bug —
Yomi's `CFBypassManager.autoBypass` only auto-retries Cloudflare blocks in `BrowseView.swift`, not in
`MangaDetailView.swift`/`NovelDetailView.swift`; Yuedu-reader's "Legado declarative rules" were ruled
out as a lower-App-Store-review-risk alternative (it's a JS engine underneath); Yomi's WKWebView-based
novel reader was re-confirmed correct and found to de-risk the backlogged Yomitan-dictionary-lookup
feature idea; Keiyoushi-via-Suwayomi (S89/S90) was re-confirmed as the right source strategy against
real current numbers for two alternatives; and hands-on builds confirmed Nyora can never run on
Simulator (device-only native engine) while Aidoku builds clean, with Aidoku's own UI surfacing a
shipped OCR dictionary-lookup feature, tracker sync Yomi lacks, and independent validation of the
Suwayomi-bridge strategy. **No Known Issues added, nothing fixed** — this was research, not a bugfix
session. Next session touching any of this starts at `RESEARCH.md` §20.

---

**S113 (2026-08-17) — worked through the S112 audit backlog** (Martin's "work through the S112 backlog" ask).
Scoped down to what's code-fixable in this repo, matching S111's precedent: excluded #47 (CloudKit
container provisioning — still blocked on paid Apple Developer Program enrollment) and #69 (MangaDex
plugin bug — source lives in a separate repo not present on this machine). Left #55 as-is (informational
only, no actual bug — GRDB keys migrations by string name, harmless). **Fixed all other 17 items**:
the silently-swallowed `DatabaseManager.setup()` failure now `fatalError`s loudly with the real error
(#52); `clearLastRead`/`touchLastUpdated` now mark Manga/Novel dirty for CloudKit sync (#53-54); the
Home Screen widget now stays empty while App Lock/Secure Screen is on, both via a write-time guard and
an immediate clear the moment either setting flips on (#68); two `SourceBrowseView`/`BrowseView`
concurrency bugs around the shared `JSBridge` (#57-58); orphaned downloaded files on source migration
(#60); a `Customize Tabs` bug where hiding your current default tab was a no-op exactly when that tab
was Library, for both `defaultTab` and `router.selectedTab` (#61); 5 dead-code functions removed
(#56/#59); a missing accessibility label on the reader's chapter-nav buttons (#70); and all 6 stale doc
citations (#62-67). Clean **zero-warning build** on both the `Yomi` and `YomiWidget` schemes throughout.
Live-verified: app launches cleanly with the new fail-loud DB path; the widget write-guard confirmed
end-to-end via direct `sqlite3` seeding + App Group plist inspection (empty when protected, real data
when not). The symmetric `didSet`-triggered immediate clear wasn't separately live-tap-verified — hit
the same known `mobile-mcp`/`XcodeBuildMCP` tap-tooling limitation documented since S109 trying to
toggle App Lock in the live UI. Full narrative in `Yomi/ROADMAP.md`'s S113 entry.

---

**S112 (2026-08-17) — full project audit, documentation-only.** Ran as an explicit multi-agent
`Workflow` — 7 parallel research dimensions (core/DB/app-entry/sync, extensions/plugins/browse/reader,
library/more/history/onboarding, docs-vs-code, App Store compliance, security/privacy, live
simulator+build-health walkthrough), each with its own adversarial verify pass re-checking every
finding against the live file before it was trusted. **Deliberately no fixes — findings only**,
catalogued as new Known Issues rows 52-71 above (all but #47/#55/#69 fixed S113, see above).
**No regressions found** in any S99-S111 fix spot-checked (S104's plugin allowlist, S105's CloudKit
dirty-marking, S109-S111's chapter-boundary preload chain, S101's contrast/placeholder work all still
hold). App Store compliance re-verified live and stayed clean.

---

## Prior state (post S111 — 2026-08-17 · backlog cleared: chapter-boundary preload root-caused+fixed, AquaManga pagination fixed, 3 new parity features shipped)

**S111 — Martin asked to "fix everything from the backlog."** Scoped down to code-fixable items
(excluded CloudKit provisioning, App Store Connect data entry, dead-repo plugin cleanup, and
anything needing Martin's physical device — all genuinely out of reach this session), then cleared
all six: (1) **S110's chapter-boundary preload trigger — root-caused for real, not tooling.** Apple's
own docs for `.scrollPosition(id:)` require pairing it with `.scrollTargetLayout()` on the scrolled
container; neither `WebtoonReaderView` nor `ContinuousHorizontalReaderView` had it, so `visibleId`
never tracked the actively-scrolled page regardless of input source — S110's mixed-API theory was
adjacent but missed the actual missing modifier. Added it to both, live-verified end-to-end via swipe
+ temporary `NSLog`: `visibleId` correctly progressed `cur:19→cur:20→boundary→next:0`, the preload
fired, and the reader crossed into Ch.7 with no tap. (2) **AquaManga runaway pagination (#9b)** —
`BrowseView.loadMore()` now dedups each page against already-loaded ids (terminates the moment a page
returns nothing new) plus a `maxPage=300` hard backstop. (3) **Rotation-follows-device setting** — new
`AppSettings.rotationFollowDevice`, wired into `AppDelegate.supportedInterfaceOrientationsFor` in
`YomiApp.swift`; live-verified the lock direction (toggled off, rotated the simulator to landscape,
app correctly stayed portrait). (4) **Repair Database action** — `DatabaseManager.repair()` runs
`PRAGMA integrity_check` + `VACUUM` (outside a transaction, via `writeWithoutTransaction`, confirmed
against context7's GRDB docs), new button in `StorageView.swift`; live-verified, alert showed "No
issues found. Database optimized." (5) **AppLockView restyled** to the Ink/Space-Grotesk design
system (was plain `Color(.systemBackground)`/system font, predating S79) — live-verified via
`appLockEnabled` + a cold relaunch, caught the frame before the simulator's system passcode sheet
took over. (6) **Tachiyomi-compatible backup *export*** — new `TachiyomiBackupExporter.swift`, the
reverse of the existing import parser (same protobuf3 field layout, gzip via libz), wired into
`BackupManager`/`BackupView`. **Verified byte-for-byte**, not just "compiles": hand-decoded the
exported `.tachibk`'s protobuf in Python, confirmed title/url/artist/status/favorite and all 9
chapters' read-state/lastPageRead/chapterNumber matched the live DB exactly.

**New tooling finding, worth remembering**: `mobile-mcp`'s `mobile_set_orientation` can desync its
internal orientation state from the simulator's actual rendered orientation — every tap coordinate
was silently wrong for several minutes mid-session until `mobile_get_orientation` was checked and
found stuck on `landscape` from an earlier rotation test, well after the visible UI (and a fresh
`mobile_get_orientation` re-query) had returned to portrait. If taps start landing on the wrong
element with no other explanation, check `mobile_get_orientation` before suspecting the app.

Zero build warnings throughout, live-verified where the simulator allowed it. Next session picking
up rotation-follows-device's positive direction (unlocked → device rotates) should try a real device
or `XcodeBuildMCP`'s `snapshot_ui`/tap tools if enabled — `mobile_set_orientation` couldn't be
confirmed to trigger a live rotation once unlocked, only the restrictive (locked) direction was
provably correct in this session.

---

## Prior state (post S110 — 2026-08-17 · Customize Tabs fully verified; found+fixed a real chapter-ordering bug; boundary-preload trigger still unconfirmed)

**S110 re-attempted S109's "verify on Martin's device" items in the simulator anyway**, using a
`sqlite3`-seeded near-chapter-end resume position and Pulse's Network Console as ground truth.
**Customize Tabs is now fully live-verified**: found that a short, off-center swipe reaches a partial
scroll position where a full fling always overshoots; toggled History off, watched the bottom tab bar
rebuild live and correctly re-space, confirmed the hidden state survives a full app relaunch, then
restored the default 5 tabs. **Found and fixed a real, pre-existing bug, unrelated to S109's own
code**: `MangaDetailView.swift` and `ContinueReadingRow.swift`'s two reader-launch paths built the
`chapters` array straight from the source plugin's native return order — confirmed via a live `curl`
against AsuraScans' real API that this is newest-first, not ascending — while `ChapterReaderView`'s
prev/next-chapter logic (`chapters[index ± 1]`) assumes ascending order. Result: "Next Chapter" (and
the new boundary-preload) silently targeted the *previous* chapter instead, for any source that
returns newest-first (most of them). Fixed by sorting `chapters` ascending by `chapterNumber`
immediately after each load, matching `ChapterQueries.fetchAll`'s own convention (`UpdatesView.swift`'s
reader-launch path was already correct). Live-verified via the in-reader Chapters sheet: Ch.1→Ch.9 now
lists in order. **The boundary-preload's own trigger still couldn't be confirmed firing** — Pulse's
Network Console showed zero request for the next chapter's page list across 3 separate seeded/organic
attempts crossing the documented threshold. Temporary `NSLog` instrumentation (removed before
committing) showed `WebtoonReaderView`'s `.onChange(of: visibleId)` never fires at all during
`mobile-mcp` swipes in this environment, even though content visibly scrolls — `WebtoonReaderView`
mixes the older `ScrollViewReader.scrollTo` API (for resume-to-page) with the newer
`.scrollPosition(id:)` reactive binding (for detecting the visible page) on the same `ScrollView`, an
undocumented combination that's a plausible cause, but a genuine code bug isn't ruled out either.
**Next session should verify on Martin's real device** whether the boundary card appears under real
touch input before assuming this is tooling-only.

---

## Prior state (post S109 — 2026-08-17 · chapter-boundary transition + Customize Tabs screen shipped)

**S109 shipped the two items S108 explicitly deferred.** (1) **Chapter-boundary transition**
(`ChapterReaderView.swift`) — Webtoon/Continuous reader now preloads the next chapter in the
background as the user nears the end and appends a `ChapterBoundaryCard` + its pages directly
into the same scroll content, crossing with a state swap instead of a reload/jump, matching
Tachimanga's reference screenshots from S108. **Found + fixed a real bug live**: the preload's
background fetch (`SOURCE._fetchSync`, `JSBridge.swift`) blocks synchronously on a
`DispatchSemaphore` with no timeout — an existing app-wide pattern, but firing it silently in the
background while the user keeps reading meant a slow/rate-limited source could peg the CPU at 99%
and freeze the UI (confirmed via CPU sampling, reproduced twice). Fixed with a 12s timeout race.
**Verified**: CPU stayed normal (0–20%) across many repeated scroll/scrub ops post-fix.
**Not verified**: the boundary card's actual on-screen appearance/crossing — `mobile-mcp`'s swipe
doesn't respect its `distance` parameter in this environment (every swipe resolves to a full fling
to the nearest scroll bound, tested 30–2000 with identical results — a sharper characterization of
the swipe unreliability noted since S87), compounded by the standing reader-header tap flakiness
(S101/S108). (2) **Customize Tabs settings screen** (new `YomiTabID.swift`,
`CustomizeTabsView.swift`, `AppSettings.tabOrder`/`hiddenTabIDs`, `ContentView.swift` rebuilt to
construct `Tab`s via `ForEach` — confirmed against live Apple docs as a sanctioned pattern) —
drag-to-reorder + toggle-to-hide, "More" locked visible since it's the only way back to Settings.
**Verified**: clean build, app launches with all 5 tabs correctly ordered. **Not verified**: the
drag/toggle UI itself — same swipe-imprecision block, couldn't scroll far enough down Settings to
reach the row. Zero build warnings throughout. Commits pushed to `main`. **Next session touching
either should re-verify visually on Martin's own device**, not fight this simulator's swipe tooling.

---

## Prior state (post S108 — 2026-08-16 · branch reconciliation + 3 parity items shipped)

**S108: reconciled a real branch split first** — `main` had unrelated dev-tooling commits
(SwiftLint/fastlane/Pulse, 8/14) while S106/S107's CloudKit investigation lived unmerged on
`worktree-cloudkit-verify-s106` (8/11). Merged cleanly (docs-only, no code conflicts), pushed,
removed the now-redundant worktree/branch. **CloudKit sync stays out of scope** — still blocked on
Apple Developer Program enrollment (#47), Martin's call not to enroll yet. Worked the buildable
half of `TACHIMANGA_PARITY.md`'s backlog instead:

1. **Dated iCloud backup list** — `BackupManager` now writes timestamped files and keeps the last
   8 instead of overwriting one fixed `YomiBackup.json`; `BackupView.swift` shows a real list
   (date + size, swipe-to-delete, restore-a-specific-entry). **Not live end-to-end verified** — the
   dev simulator's iCloud session had lapsed (password re-auth dialog blocking the home screen at
   session start); code review + clean build only.
2. **Color-blend slider** — new `AppSettings.colorBlendLevel` + `Color.mix(with:amount:)`, blends
   `bg`/`surface1`/`surface2` toward the accent app-wide via `blendedCanvasColors`
   (`\.yomiCanvas`, not just a preview). **Live-verified at 60% on Paper**: tints consistently
   everywhere, and the pre-existing AA badge correctly drops to "Fail" — surfaces the Paper/Sepia
   contrast tension from S101 rather than hiding it.
3. **Date format picker** — new `use24HourClock`/`dateOrderDayFirst` settings, threaded as
   parameters into `Notation.historyTimestamp(_:use24Hour:dayFirst:)` (kept `Notation`
   `nonisolated`-safe, no `AppSettings.shared` read inside it). **Live-verified both axes** via a
   seeded `sqlite3` `lastReadAt`: "20:30"↔"8:30 PM", "JUL 20"↔"20 JUL".
4. **Customize Tabs — root-caused, not fixed.** `ContentView.swift` had `.customizationID`s +
   `.tabViewCustomization($customization)` since S43 but was missing
   `.tabViewStyle(.sidebarAdaptable)` (required per Apple's docs) — added it, no visual regression.
   But the real finding (from watching WWDC24's actual talk, titled "...**in iPadOS**"): the
   system's drag/hide editing UI only exists in the sidebar, which only renders in regular-width
   contexts — **iPhone gets a plain tab bar with zero built-in customization affordance**,
   confirmed live (long-press just selects, no jiggle/menu). Needs a real custom settings screen to
   deliver on iPhone at all; logged for a future session rather than built this one.

Zero build warnings throughout. Commits pushed to `main`. Full narrative in `Yomi/ROADMAP.md`'s
S108 entry.

---

## Prior state (post S107 — 2026-08-11 · Known Issues backlog re-check, no code changes)

**S107: CloudKit sync stays blocked pending Apple Developer Program enrollment (Martin's call — not
done yet), so this session re-verified 3 lower-priority open Known Issues instead.** (1) **Novel-source
status (#21) re-checked live via `curl` with a real iOS UA**: LightNovelPub and BabelNovel are still
genuinely Cloudflare-gated (403, "Just a moment"/"Attention Required" markers present) — unchanged. But
**BoxNovel is a new, worse failure mode than previously recorded**: it no longer serves any real site at
all — `boxnovel.com` now returns HTTP 200 but the body is a domain-parking/ad-redirect shell posting to
`router.parklogic.com` (classic expired-domain-squatting pattern), not a JS-anti-bot challenge. The
domain has effectively changed owners; no plugin fix is possible against a parked domain. NovelBin
(`novelarrow.com` backend) reconfirmed HTTP 200, still working. (2) **Duplicate-extension self-heal
(#12) re-checked** via direct `sqlite3` against the primary dev simulator's `yomi.db`: `SELECT name,
COUNT(*) FROM extension GROUP BY name HAVING COUNT(*) > 1` returned zero rows — no duplicates present.
Not a strong test (this simulator only has 2 extensions installed, neither NovelFire/NovelBin/
FreeWebNovel — the plugins that hit the old id-scheme migration), but consistent with the S88 fix
holding. **The user's real device was never checked and still might have legacy duplicates** — this
remains a "worth a glance" item, not fully closed. (3) **Suwayomi Latest tab (#8)**: no local Suwayomi
server was available to re-run a live end-to-end test, and standing one up from scratch (Docker/JVM,
per `ROADMAP.md`'s S89 setup notes) was judged disproportionate for a tab whose risk was already rated
low. Did a targeted code read instead: `SuwayomiService.fetchLatest` and `fetchPopular` both route
through the exact same generic `fetch<T>()` helper (same request construction, same 200...299 status
check, same JSON decode), differing only in the URL path segment (`/latest/` vs `/popular/`); the view
wiring in `SuwayomiBrowseView.swift` (`selectedFeed == .latest` branch, `loadMore()`) is structurally
identical to the already-verified Popular path. No divergent logic found — confidence raised without a
live server, but a real end-to-end fetch against a running server is still technically unverified.
**Also confirmed no build regressions**: clean `build_run_sim`, zero warnings/errors.

---

## Prior state (post S106 — 2026-08-11 · CloudKit sync blocked on Apple Developer Program enrollment)

**S106: picked up the S103/S105 real-iCloud-account verification, found the real blocker.** Signed a
real Apple ID into two simulators (iPhone 17 Pro + iPhone 17 Pro Max, iOS 26.3), built and launched Yomi
on both. `CKContainer.accountStatus()` now correctly resolves `.available` on both — the account/
entitlements path works exactly as designed. But enabling sync immediately fails on both:
`CKSyncEngine.sendChanges()`/`fetchChanges()` throw `CKError "Bad Container" (5/1014)` — **the CloudKit
container `iCloud.pacodealer.Yomi` has never been provisioned on Apple's servers**, confirmed via
`xcrun simctl spawn <device> log show` and cross-checked against Apple's own `CKError.Code.badContainer`
docs + developer-forum precedent (WebSearch). Root cause, confirmed directly with Martin: **the project
isn't enrolled in the paid Apple Developer Program ($99/yr)** — flagged as an unpurchased cost item back
in S90, not previously connected to CloudKit specifically. Container creation requires that enrollment
regardless of entitlements content (a free/personal team can't provision CloudKit containers at all),
and S103's entitlements were hand-written rather than added through Xcode's Signing & Capabilities UI,
which is the only thing that actually registers a container server-side. No code changes needed —
**next session touching this feature starts with**: enroll in the Program, open `Yomi.xcodeproj` →
Signing & Capabilities → add iCloud/CloudKit → use "+" under Containers to provision
`iCloud.pacodealer.Yomi`, then re-run this exact two-simulator test. Full detail in
`Yomi/CLOUDKIT_SYNC_DESIGN.md`'s new "What was verified, and what wasn't (S106)" section.

---

## Prior state (post S105 — 2026-08-07 · CloudKit sync code-review findings fixed)

**S105: fixed all 6 code-review findings from S104's pass over the S102-S103 CloudKit sync code**
(Known Issues #41-46 above — full detail there). Two were real sync-correctness bugs: an UPDATE-only
remote-apply that silently dropped chapter read-state for manga not yet locally cached (fixed with a
new pending-state stash-and-replay table, since a true upsert isn't possible without the full chapter
row) and category deletion not propagating join-table deletes to CloudKit (fixed by reading the join
rows before the CASCADE delete). The other four: a durable dirty-mark queue closing the async window
during `enable()`'s account-status check (new `cloud_sync_map.pendingChange` column, drained into the
engine right after it's created), an `isEnabling` guard closing `enable()`'s double-call race, reverting
a `try?` regression that had silently swallowed 2 bulk mark-read functions' DB-write errors, and a
Release-only `Yomi-Release.entitlements` file (production `aps-environment`) so the correct APNs
environment no longer depends on automatic-signing rewrite behavior. New migration
`v21_cloud_sync_pending` — next must be `v22_`. All fixes live-verified: clean Debug **and** Release
`build_sim`, `build_run_sim` launch with no crash, direct `sqlite3` inspection confirming the migration
applied and new tables/column exist, and both entitlements files confirmed picked correctly via each
config's `ProcessProductPackaging` build-log line. **Still queued, not touched this session**: the
S103 real-iCloud-account verification (this dev simulator still has no account signed in — an actual
CloudKit send/fetch round-trip and multi-device convergence remain unverified).

Committed and pushed to `main`.

---

## Prior state (post S104 — 2026-08-07 · piracy/App-Store-compliance audit + first-party catalog fix)

**S104: Martin asked directly whether Yomi complies with App Store piracy regulations.** Fetched the
live current guideline text from developer.apple.com rather than trusting `RESEARCH.md`'s existing
summary (stale in two ways — corrected, see `RESEARCH.md` §5), then did a fresh-user walkthrough (S96's
`cfprefsd`-clear procedure). **Finding**: the applicable rule is Guideline 5.2.2 (Third-Party
Sites/Services — "specifically permitted... under the service's terms of use"), and Yomi's own
first-party Plugins catalog (`yomi-plugins.web.app/index.json`, fetched automatically, pointed at
directly from onboarding page 2/3) one-tap-installed 12 unlicensed scanlation/scrape sources alongside
3 lower-risk ones (MangaDex, Royal Road, Scribble Hub) — a bigger reviewer-exposure surface than the
LNReader repo risk S96 already mitigated, never covered by that fix. **Fixed** (Martin's call: match
the LNReader treatment): new client-side `instantInstallSourceIDs` allowlist in `PluginsView.swift` —
only those 3 stay one-tap Install; the other 12 now require Copy URL + manual add, same interaction
`FeaturedRepoRow` already used for LNReader. Deliberately kept as a compiled-in allowlist, not a remote
JSON flag (a server-controlled compliance switch would itself look like review-evasion if found). Zero
build warnings, live-verified via `build_run_sim` + mobile-mcp. Full narrative + the corrected 2.5.2/
5.2.2/precedent research in `Yomi/ROADMAP.md`'s S104 entry and `Yomi/RESEARCH.md` §5.

**Also this session**: a `/code-review` pass on the S102-S103 CloudKit sync code surfaced 6 findings
(2 real sync-correctness bugs — an UPDATE-only remote-apply that silently drops chapter state for
manga not yet locally cached, and category-deletion not propagating join-table deletes to CloudKit;
plus a `markCloudDirty` no-op window during `enable()`'s async account-status check, a double-`enable()`
race, `try?`-swallowed DB-write errors in 2 bulk mark-read functions, and a hardcoded `development`
`aps-environment`) — **not yet triaged or fixed**. Next session should start here, alongside the
real-account CloudKit verification already queued from S103.

Committed and pushed to `main`.

---

## Prior state (post S103 — 2026-08-06 · CloudKit sync implemented)

**S103: implemented the full multi-device CloudKit sync feature designed in S102**, same session-day.
New `Yomi/Sync/CloudSyncManager.swift` (`CKSyncEngine` + delegate, `Manga`/`Novel`/`Category`/
`MangaChapterState`/`NovelChapterState`/`MangaCategoryLink`/`NovelCategoryLink` CKRecord mapping),
new `cloud_sync_map` GRDB table (migration `v20_cloud_sync_map`, next must be `v21_`) as a reverse
recordName→(type,key) index plus a cached-CKRecord store for real change-tag conflict detection,
`markCloudDirty`/`markCloudDeleted` hooked into ~20 call sites across `MangaQueries`/`ChapterQueries`/
`NovelQueries`/`CategoryQueries`, a new distinct Settings → More → **Sync** screen
(`CloudSyncView.swift`, separate from the existing iCloud Backup screen on purpose), and
`AppSettings.cloudSyncEnabled` driving engine enable/disable. **One real deviation from the S102
design, caught mid-implementation by checking Apple's actual docs rather than assumption**:
`CKSyncEngine`'s own class documentation states it requires the Remote Notifications entitlement, not
just CloudKit — added it (background mode + gated `registerForRemoteNotifications()`, only when sync
is on) rather than gamble on undocumented behavior; this doesn't change the product decision that sync
only visibly happens on foreground/background, no real-time UI was built. Zero build warnings.
**Live-verified only as far as this dev simulator allows — it has no iCloud account signed in**: clean
build, no crash launching with the new entitlements, the Sync toggle correctly drives a real
`CKContainer.accountStatus()` call and lands on the `.unavailable` state exactly as designed. **Not
verified**: an actual record reaching CloudKit, the fetch/merge path, or real two-device convergence —
needs a signed-in account next. Full as-built notes, what was/wasn't verified, and the real
`CKSyncEngine` API names (several differ from the WWDC23 talk's own code sample) are all in
`Yomi/CLOUDKIT_SYNC_DESIGN.md`, updated in place rather than duplicated here.

**Prior state (post S102 — 2026-08-06 · CloudKit sync architecture scoped, not implemented)**

S102 designed the full multi-device CloudKit sync architecture (not yet built at the time) — the last
big item on `TACHIMANGA_PARITY.md`'s backlog, scoped the same way S90 scoped the Suwayomi-server
design before writing code. Key finding: `Manga.id`/`Chapter.id` are already content-derived (traced
through `JSBridge.swift`), not local UUIDs — meaning (1) chapter lists never need to sync, only the
small per-chapter state a user actually touches, and (2) first-sync bootstrap on an existing library
needs no special merge logic. `CKSyncEngine` chosen over `NSPersistentCloudKitContainer` (Core
Data-only, ruled out — Yomi is GRDB) and raw `CKDatabase` calls. See `Yomi/ROADMAP.md`'s S102 entry
for the scoping narrative — superseded by S103's implementation above.

**Prior state (post S101 — 2026-08-06 · rows 31-33 shipped + theme/contrast audit)**

**S101: shipped the 3 features S100 deferred, plus a canvas×accent contrast audit that found 3 real
bugs (live-testing, not just math).** Background auto-refresh (real `BGTaskScheduler` wiring —
`com.yomi.refresh` registered in `AppDelegate`, scheduled on `scenePhase == .background`, handler
reuses `UpdatesViewModel.refresh()` verbatim), background download (gated on auto-refresh, hooks into
`UpdatesViewModel.checkUpdates(for:)`'s new-chapter discovery to auto-enqueue via `DownloadManager`,
manga only), and an in-reader source-URL globe icon (new `JSBridge.resolveSourceURL(path:)` —
best-effort, no plugin changes: reads a plugin's own top-level `BASE_URL`/`BASE` JS global back out
of the JSContext when `path` isn't already absolute; works for ~7 of 15 plugins + Mangayomi-format
sources, hides the icon rather than guessing for the rest). Toggles in `SettingsView`'s Data section,
both default off.

**Theme audit (Martin's ask: "revise how the different app themes look with every possible accent
combination"), computed first, then live-verified — found the audit's own math was too optimistic
until live-tested.** WCAG contrast across all 4 canvases × 11 accents flagged: (1) most accents are
barely visible as icons/progress-bars on Paper/Sepia (as low as 1.24:1) — a real, unresolved tension
between "accent is always exactly the user's chosen color" and legibility, flagged for Martin rather
than silently recolored; (2) every accent's hardcoded white button-label text was failing WCAG AA
except Indigo — confirmed live (Ink + Yellow: "Resume" text genuinely unreadable). Fixed with
`YomiTokens.Accent.foreground(for:on:)`, applied at ~12 real sites app-wide. **First version of that
fix was itself wrong, caught by Martin from a live screenshot**: a blanket "pick whichever of
white/black wins" formula flipped even passing defaults (Vermilion on Ink) to black, breaking the
card's all-one-ink-color convention — corrected to keep the canvas's own ink color whenever it clears
a 3:1 threshold, only flipping for accents that genuinely fail. Martin's screenshot also caught 2 more
real bugs missed by the math-only pass: `CoverImage.swift`'s no-cover placeholder used `Color.secondary`
(system light/dark only) instead of canvas tokens, and — root-caused while fixing — Kingfisher's
`KFImage.placeholder` doesn't live-repaint on an environment-only change (`.id(canvas.name)` forces a
remount on canvas switch); and a novel-indicator badge rendered two different ways on two screens
(Library grid's "NOVEL" pill vs. the Continue shelf's chunky "N" square), unified to the pill. **Lesson
for future theme/design passes: WCAG math alone missed real bugs a live screenshot caught in seconds —
always live-verify at least the worst-case combos the math flags, don't stop at the calculator.**

Full narrative in `Yomi/ROADMAP.md`'s S101 entry. All fixes live-verified via `build_run_sim` +
mobile-mcp/XcodeBuildMCP screenshots across multiple canvas×accent combos, zero build warnings.

**Prior state (post S100 — 2026-08-06 · S99 audit backlog cleared)**

**S100: worked through S99's Known Issues backlog end to end** (rows 24-30, 25, 26, 34, 35 — age
rating, doc cleanup, OPDS→Keychain, silent-failure toasts, the AquaManga reader-page bug, list-mode
multi-select), per Martin's "let's go through all the known issues and fix them." Rows 31-33
(background auto-refresh/download toggles, in-reader source-URL icon) are real new features, not bugs —
explicitly deferred to a future dedicated session at Martin's call, backlog now lives in
`Yomi/TACHIMANGA_PARITY.md`'s S100 addendum. Headline fix: the AquaManga reader-page bug (#34) and the
long-unverified cover-loading fix (#9) turned out to share one deeper root cause — Kingfisher's
`ImageDownloader` defaults to an `.ephemeral` session with its own private cookie store, invisible to
the `HTTPCookieStorage.shared` that `CFBypassView` writes `cf_clearance` into, so the S89 UA
`requestModifier` alone was never sufficient. Fixed by pointing Kingfisher's session config at `.shared`
— verified live, both covers and reader pages render real art now. Full narrative in
`Yomi/ROADMAP.md`'s S100 entry, technical lessons in `Yomi/METODOLOGIA.md`'s S100 section. All fixes
live-verified via `build_run_sim` + `mobile-mcp` + direct `sqlite3`/`defaults read` inspection, zero
build warnings throughout.

**Prior state (post S99 — 2026-08-06 · full project audit, documentation-only)**

S99 ran a full audit of the whole project — code quality, docs consistency, live simulator
verification, and App Store/security readiness — as 4 parallel research passes plus a manual
live-simulator spot-check, deliberately making no fixes, only cataloguing findings as new Known Issues
rows 24-36 for S100 to work through (see above). Code/quality was otherwise genuinely clean after 98
sessions (zero TODO/FIXME, zero unsafe force-unwraps, zero Swift-6 isolation violations, clean build).

**Prior state (post S98 — 2026-08-06 · Tachimanga parity pass complete)**

S97-S98 worked through `Yomi/TACHIMANGA_PARITY.md` (a source-verified feature audit against Tachimanga,
produced S97) end to end — **every item the audit itself flagged as high-value is now shipped.**
S98 alone shipped 4 items, in order of increasing complexity:
1. **Storage composition view** (`StorageManager.swift`/`StorageView.swift`, Advanced → Storage) — real
   byte-accurate breakdown (Downloads/Image cache/Plugins/Custom covers/Web cache/Database/Other) with
   Manage/Clear actions. Found + fixed a real SwiftUI bug live: a `GeometryReader` used directly as
   List row content destabilized every row below it (untappable, accessibility-tree/scroll desync) —
   moved the summary bar entirely outside the `List`.
2. **Library/Settings round-out**: category item counts on Library's tab bar, Default Category
   (auto-assign on add), Default Tab (launch tab), editable request timeout in Advanced → Network
   (User Agent stays fixed — bound to the Cloudflare-bypass WebView's solved-challenge cookie), tap
   zones expanded 3→6 presets, and a real double-tap-to-zoom fix (previously just reset to 1x).
3. **Double-page spreads** for the manga reader (Single/Double/Automatic-in-landscape). `currentPage`
   keeps meaning "a real page index" everywhere (progress/resume/scrubber) — `MangaReaderView`'s
   `TabView` selection goes through a proxy `Binding` that snaps to the enclosing spread's start.
4. **Migrate tab** (Browse → Migrate) — move a library manga to a different installed source,
   transferring status/notes/categories/per-chapter read-state (matched by `chapterNumber`). **Real bug
   found live, looked exactly like a dead button from the outside**: the confirmation dialog's
   `isPresented` binding cleared `migrationTarget` as part of the same transaction as the button tap's
   auto-dismiss, so re-reading `migrationTarget` inside the button's `async` closure (after a
   suspension point) raced and saw `nil`. Fixed by capturing the target by value in the closure instead.

All 4 live-verified via `build_run_sim` + mobile-mcp (Migrate also cross-checked via direct sqlite
inspection of the simulator's `yomi.db`), zero build warnings throughout. See `Yomi/ROADMAP.md`'s S98
entry for full detail, and `Yomi/TACHIMANGA_PARITY.md` for the updated per-feature status table and
remaining (now genuinely long-tail) backlog — full multi-device CloudKit sync is the only big item left,
and needs its own architecture-scoping session like S90 gave the Suwayomi-server design.

**Tooling note**: this session hit real `mobile-mcp` tap-delivery flakiness on plain `Button`s several
navigation levels deep (confirmed via an untouched pre-existing button failing identically) —
`NavigationLink`s stayed reliable throughout. Don't assume a dead-looking button is this tooling issue
without first checking for a state race like the Migrate one above; they can look identical.


Full session-by-session history (S1-S90) lives in `Yomi/ROADMAP.md` (recent) and `Yomi/HISTORY.md`
(archived) — not duplicated here. This file keeps only the single most-recent state above.
## Known issues / carry-forward

| # | Issue | Notes |
|---|-------|-------|
| 1 | Chapters from Browse (partial) | ✅ NovelFire + NovelBin fixed and verified live S88 (see Yomi/ROADMAP.md S88 entry). NovelFire was hardcoded to chapter-list page 1 only (100/3,139 chapters); rewrote to loop all pages. NovelBin's domain (`novelbin.me`) was dead (DNS_PROBE_FINISHED_NXDOMAIN) — rebranded to `novelarrow.com`, rewrote the whole plugin against its clean JSON API. FreeWebNovel's scrape was also rewritten (old code picked up unrelated links, not chapters) but is now blocked by a new site-wide Cloudflare challenge with no bypass wired into the novel-detail path — see row 11. Asura Scans/MangaDex only code-reviewed (pagination logic already loops correctly), not live-retested. |
| 2 | ~~App icon missing~~ | ✅ Done S87 — wired into Xcode (see #3). |
| 3 | ~~Alternate icons need Xcode step~~ | ✅ Done S87 — `AppIcon.appiconset` now ships `AppIcon-Ink-1024.png`; new `AppIcon-Paper.appiconset` added; `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES` set in both configs (Xcode 26's automatic alternate-icon Info.plist generation — verified `CFBundleAlternateIcons.AppIcon-Paper` in the compiled Info.plist). Deleted the two stale empty `AppIconDark`/`AppIconMinimal` appiconsets and fixed `AppearanceStudioView.swift`'s icon picker to use the real `AppIcon-Paper` key instead of leftover placeholder names. |
| 4 | App Store content missing | Age rating 18+, description, screenshots pending in App Store Connect. |
| 5 | ~~Firebase deploy pending~~ | ✅ Deployed S53 — babelnovel.js + lightnovelpub.js live. |
| 6 | ReadComicOnline + Mangapill broken | Downloaded from dead GitHub repo. User should uninstall from Extensions tab. |
| 7 | ~~Inconsistent cover-cell sizes in grid~~ | ✅ Root-caused + fixed S87. `.aspectRatio(_, contentMode: .fill)` alone falls back to the content's own intrinsic size whenever the parent proposes unbounded height (grid cell with only column width fixed, or `.frame(width:)` with no height) — cell height ended up varying per image. Fixed with a new `coverAspectSized()` modifier (`Core/CoverImage.swift`): a `Color.clear.aspectRatio(2/3, contentMode: .fit)` sizer drives a deterministic width-based height, with the real image as an `.overlay` + `.clipped()`. Applied to the shared `CoverImage` component (fixes `NovelLibraryCoverCell`, `NovelCoverCell`, `OPDSBrowseView` for free) plus the inline duplicates in `MangaCoverCell.swift`, `LibraryView.swift`'s `NovelLibraryCoverCell` custom-cover branch, `ContinueReadingRow.swift` (both manga/novel cells), and `HistoryView.swift`. Verified live: MangaDex Popular grid cells are now uniform. |
| 8 | Manga sources never show Popular/Latest tabs | ✅ Root-caused S88 for Suwayomi specifically: `SuwayomiSource.supportsLatest` was already decoded from the server's own API (real Keiyoushi/Tachiyomi extensions do report it correctly) but `SuwayomiService` had no `fetchLatest()` and `SuwayomiBrowseView` never called anything but popular — a pure client-side gap. Added `fetchLatest()` + a `FeedTab` picker in `SuwayomiBrowseView`, matching `BrowseView.swift`'s existing pattern. S89: Popular tab now live-verified working end-to-end against a real Suwayomi server. S107: Latest tab still not live-retested (no local Suwayomi server available; standing one up was judged disproportionate for the risk) — but code-reviewed instead: `fetchLatest`/`fetchPopular` share the identical generic `fetch<T>()` helper, differing only in URL path segment, and `SuwayomiBrowseView`'s `.latest` branch is structurally identical to the verified `.popular` path. No divergent logic found. Prior verdict still stands for direct JS plugins: `JSBridge.supportsLatest` requires `getLatestManga`, which `mangadex.js`/`asurascans.js` never implemented. |
| 9 | ~~AquaManga "Cloudflare bypass fails"~~ | ✅ Root-caused S87 — **misdiagnosed originally, not a Cloudflare problem at all.** Confirmed live (Chrome + in-app debug logging): SOURCE.fetch's plain UA/headers get a clean `200` with full HTML every time, no CF challenge — the domain migrated `aquareader.net` → `aquareader.org` and was **rebuilt on a custom theme** (no longer Madara WordPress), so `aquamanga.js`'s old selectors (`div.page-item-detail`, `li.wp-manga-chapter`, etc.) matched nothing. Rewrote `getMangaList`/`getChapterList`/`searchManga` against the live DOM (`article.aqua-archive-card`, `a.aqua-ch-item`, fixed a `searchManga` container bug that only ever matched the first of N results). `getPageList` needed no change — the reader page kept the old markup. Deployed to Firebase (`v1.1.0`). **While chasing why the fix "didn't take" during testing, found and fixed two real caching bugs**, both `URLCache` serving stale CDN responses despite `Cache-Control: max-age=3600` no longer matching the redeployed content: `PluginCatalogService.fetchCatalog(force: true)` and `ExtensionManager.install()` now both set `.reloadIgnoringLocalCacheData` — without this, "Update" and even a fresh reinstall could silently keep running old plugin code indefinitely. **Two things found this session:** (a) ✅ AquaManga cover images — fixed for real S100 (see #34's entry): the S87 UA `requestModifier` alone wasn't enough because Kingfisher's `ImageDownloader` defaults to an `.ephemeral` session with its own private cookie store, invisible to the `HTTPCookieStorage.shared` that `CFBypassView` writes `cf_clearance` into; pointing Kingfisher's session config at `.shared` fixed both covers and reader pages, verified live. (b) ✅ **Runaway pagination — fixed S111.** `BrowseView.swift`'s `loadMore()` now dedups each new page against already-loaded manga/novel ids (a source repeating its last page forever, like AquaManga, now correctly reads as "no new content" the moment every id on the page is already present) plus a `maxPage = 300` hard backstop for any source where dedup itself doesn't terminate. Verified via clean build; not re-tested live against AquaManga specifically this session (no live network dependency in the fix itself — pure client-side termination logic). |
| 10 | ~~Keiyoushi repo — not missing, architectural~~ | ✅ Architecture verdict still correct (Kotlin/APK, cannot run in JSC, confirmed since S18) — but S89 found the bridge itself had **two real bugs** that meant it never actually worked even with a server configured: no ATS exception (all Suwayomi/OPDS traffic over plain HTTP was silently blocked) and `SuwayomiService.fetchChapters()` hit a 404ing REST path. Both fixed and live-verified S89 against a real Suwayomi-Server with the real Keiyoushi repo and a real installed extension (Asura Scans) — Popular/detail/chapters/page-image all confirmed working end-to-end. Tachimanga researched and confirmed to use the *exact same* self-hosted-server-bridge architecture, not an embedded/bundled Keiyoushi — Yomi's S41 design was already correct, it just had bugs. See `ROADMAP.md`'s S89 entry for full detail including how to stand up a persistent server. |
| 11 | ~~FreeWebNovel blocked by Cloudflare~~ | ✅ Fixed S97 — `NovelDetailView.swift` had zero `CFBypassView` wiring (unlike `MangaDetailView.swift`), so a CF-blocked novel source just showed a generic "No chapters found." Added the same `cfBlockedURL`/"Bypass Cloudflare" button/`CFBypassView` sheet pattern used by manga. **Also found and fixed a second, deeper bug while live-verifying against FreeWebNovel's real Cloudflare Error 1015 (rate-limit) page**: `JSBridge.swift`'s `_fetchSync` CF-detection only matched `"Just a moment"`/`"cf-mitigated"` on a 403 — real-world Cloudflare block pages vary (1015 rate-limit, 1020 access-denied, etc.) and don't all contain those exact strings, so `cfBlockedURL` silently never got set for this case even though the response was clearly a Cloudflare page ("Cloudflare Ray ID", "Please enable cookies"). Broadened to any error status (`>=400`) plus a wider marker list; purely additive, doesn't change the existing unconditional `hasCFRay` trigger. Verified live end-to-end: FreeWebNovel's "Shadow Slave" now shows the Bypass button and `CFBypassView` opens with the real page source. |
| 12 | Duplicate extension rows (new, found+fixed S88) | `ExtensionManager.install()` always inserted under the *catalog's* id without removing an existing install of the same plugin under a *different*, older id — Yomi went through a sha256-hash-id → stable-catalog-id migration at some point and nothing ever cleaned up the old rows. Result: Plugins/Browse showed some sources (NovelFire, FreeWebNovel, NovelBin) **twice**, one stale/unupdatable alongside one fresh, confirmed directly in `yomi.db`. Fixed: `install()` now deletes any other installed extension with the same name before writing the new row. S107: re-checked via direct `sqlite3` against the primary dev simulator's `yomi.db` — `GROUP BY name HAVING COUNT(*) > 1` returned zero rows, no duplicates. Weak test though (only 2 extensions installed there, neither one that hit the old id-scheme migration). **The user's real device was never checked and still might have legacy duplicates** — still worth a glance at the Plugins screen; if duplicates are there, tapping "Update" on the affected source once (with this fix shipped) will self-heal it. |
| 13 | ~~Custom fonts may never have rendered~~ | ✅ Resolved S95 — confirmed not actually broken. Verified live via a temporary debug print: `UIFont.familyNames`/`fontNames(forFamilyName:)` show both Space Grotesk and Space Mono registered correctly, and `UIFont(name: "Space Grotesk", size:)` resolves a real font instance. The S89 `Info.plist` fix was sufficient; no further action needed. |
| 14 | Onboarding was never actually presented to any user (found+fixed S95) | `YomiApp.swift` chained two separate `.fullScreenCover` modifiers on the same `ContentView()` (`showOnboarding` and `isLocked`) — SwiftUI only reliably tracks one presentation slot per view identity this way, so the first (`showOnboarding`) silently never fired, regardless of `hasSeenOnboarding`. Fixed by merging into a single `.fullScreenCover` with a computed `Binding` and if/else content (lock screen takes priority). Verified live via a full `simctl uninstall`+reinstall (forcing a genuine first launch) — all 3 pages now show correctly. |
| 15 | ~~`LibraryView` root background not wired to `\.yomiCanvas`~~ | ✅ Fixed S96 — added `.background(canvas.bg.ignoresSafeArea())` to its root, matching every view since S85. |
| 16 | ~~Stale debug accentColor survived `simctl uninstall`~~ | ✅ Root-caused S96 — **not a Yomi bug.** iOS Simulator's `cfprefsd` caches app preferences at a device-level path (`.../data/Library/Preferences/<bundleid>.plist`) independent of the app's per-install Data Container; `simctl uninstall` doesn't reliably clear it. Real fresh-install testing needs `rm` on that plist + `xcrun simctl spawn <device> launchctl stop com.apple.cfprefsd.xpc.daemon` after uninstall, before reinstalling. |
| 17 | ~~`AppSettings.canvasColors` didn't implement "follow device"~~ | ✅ Fixed S96 — canvas `""` (the true fresh-install default) resolved `colorScheme` to `nil` (follow system) but `canvasColors` unconditionally to Ink, breaking chrome/content consistency for any first-time user on a light-mode device. Fixed by defaulting fresh installs to `canvas = "Ink"` directly. See `ROADMAP.md` S96. |
| 18 | ~~"Get plugins" silently failed to deep-link on first visit to More~~ | ✅ Fixed S96 — `MoreView`'s `.onChange(of: appRouter.openMorePlugins)` doesn't fire for a flag already `true` when the view first mounts (i.e. More never visited yet this session). Fixed with `initial: true`. |
| 19 | ~~Library multi-select unreachable via long-press on grid cells~~ | ✅ Fixed S96 — `.contextMenu` was consistently winning over a separate `.onLongPressGesture` on the same view. Replaced the dead-code gesture with a "Select" context-menu item. List mode's equivalent gap fixed S100, see #35. |
| 20 | ~~Manual mark-read actions never touched `lastReadAt`~~ | ✅ Fixed S96 — `ChapterQueries.setRead`/`NovelQueries.markRead`/`markAllChapters` (used by Updates, Detail's per-chapter/bulk toggles, and even `TextReaderView`'s own reading flow) never updated the parent manga/novel's `lastReadAt`, unlike their sibling functions — broke History, Library's last-read sort, and the Continue card. Fixed at the query layer across every call site. |
| 21 | 3 of 4 novel sources tried S96 are site-side blocked (not a Yomi bug) | LightNovelPub and BabelNovel return raw HTTP 403 to a real browser UA via `curl`; BoxNovel returns HTTP 200 but a JS-only anti-bot redirect shell with no real HTML. All three are genuinely Cloudflare/bot-gated right now, not a client parsing bug — the app's "may be down or Cloudflare-protected" message is accurate. NovelBin (novelarrow.com backend) still works correctly. **Re-checked S107**: LightNovelPub + BabelNovel unchanged (still 403, real Cloudflare markers present). **BoxNovel has gotten worse, not just still-blocked**: it's no longer an anti-bot challenge page at all — `boxnovel.com` now returns HTTP 200 serving a domain-parking/ad-redirect shell (`router.parklogic.com`), i.e. the domain appears to have expired and been squatted. Not fixable by any plugin change against a parked domain. NovelBin reconfirmed still working. |
| 22 | ~~`.glassEffect()` rendering as an oval/blob instead of the declared shape~~ | ✅ Fixed S96 (Martin's live visual review) — the parameterless `.glassEffect()` used via `.background { Shape().glassEffect() }` across 6 call sites (both readers' bottom bars, Library's selection action bar, `GlassChip`) doesn't reliably clip to that shape, a documented iOS 26 gotcha. Fixed by applying `.glassEffect(.regular, in: <Shape>)` directly to content instead. |
| 23 | ~~Native `Slider` clashed with the app's design language~~ | ✅ Fixed S96 (Martin's live visual review) — the default iOS 26 `Slider` thumb (large white pill) didn't match the thin-capsule-progress-bar look used everywhere else. Built `Core/YomiScrubber.swift`, swapped in at both call sites (manga reader page scrubber, novel reader font size). |
| 24 | ~~Age rating declaration stale (17+ vs 18+)~~ | ✅ Fixed S100 — `CLAUDE.md`'s App Store checklist and `Yomi/design/DESIGN_HANDOFF.md` (3 mentions) all corrected to 18+. Grepped project-wide for stray "17+" afterward — no other stale mentions remain (remaining `17+` hits are unrelated iOS-version-availability notes in METODOLOGIA.md and correct historical "replaces 17+" explanations in RESEARCH.md/HISTORY.md). |
| 25 | ~~OPDS password stored in UserDefaults, not Keychain~~ | ✅ Fixed S100 — `opdsPassword`'s `didSet` now writes through to `KeychainHelper` instead of `UserDefaults`, matching the MAL-token pattern (`MALService.swift`). The `@Observable` stored property itself is unchanged (required for SwiftUI observation — see the class-level comment), only its persistence target moved. Init migrates any existing `UserDefaults` value to Keychain once, then removes it. Verified live: set a password, force-quit (not just background) and relaunch — value survived in the UI while confirmed absent from `defaults read` on `UserDefaults`, round-tripping through Keychain only. |
| 26 | ~~Silent DB-write failures on mark-read / toggle-library~~ | ✅ Fixed S100 — added a new reusable `Core/YomiToast.swift` (`.yomiToast(_:)` view modifier, self-dismissing top banner matching `UpdatesView`'s existing refresh-summary banner styling, plus `YomiHaptics.error()`). Wired into both `ChapterReaderView.markChapterRead`'s and `MangaDetailView.toggleLibrary`'s `catch` blocks alongside the existing `print()`. GRDB write failures are rare by nature (not reproduced live), so this was verified by code review + clean build rather than forcing a live failure. |
| 27 | ~~Blanket `NSAllowsArbitraryLoads` ATS exception~~ | Not a code fix by design — S99 recommendation stands: keep as-is (target hosts for self-hosted Suwayomi/OPDS aren't known in advance, so per-domain `NSExceptionDomains` scoping isn't feasible), add an App Store Connect review-note at submission explaining the self-hosted-server feature. S100: folded into the consolidated App Store checklist (`ROADMAP.md`, see #36) so it's tracked as a submission-time action item instead of floating here. |
| 28 | ~~`README.md` still references removed Extensions tab~~ | ✅ Fixed S100 — line 26 changed from "open Browse → Extensions and install" to "open Browse → Sources and install," matching line 54's already-correct wording. |
| 29 | ~~`EXTENSIONS.md` orphaned/stale~~ | ✅ Fixed S100 — deleted. Not referenced from any Swift source (the in-app "Plugin setup guide" link points to `README.md`), and its content (7/15 plugins, built around the removed Extensions tab) was fully superseded by `README.md`'s repository-based install flow. |
| 30 | ~~This doc's own file-index note is stale~~ | ✅ Fixed S100 — the "Key file paths" table's `NovelQueries.swift` note corrected to reflect its real call sites (`LibraryViewModel.swift:191`, `UpdatesView.swift:96,126`). |
| 31 | ~~No "background auto-refresh" toggle in UI~~ | ✅ Fixed S101 — real `BGTaskScheduler` wiring (`com.yomi.refresh`, registered in `AppDelegate`, scheduled on `scenePhase == .background`), not just a toggle. Handler reuses `UpdatesViewModel.refresh()` verbatim. Toggle in `SettingsView`'s Data section, default off. Actually triggering a real `BGAppRefreshTask` fire isn't practically testable in the simulator without lldb — registration/no-crash/toggle-persistence verified live, the task body itself was not. |
| 32 | ~~No "background download" toggle in UI~~ | ✅ Fixed S101 — `AppSettings.backgroundDownloadEnabled`, gated on #31 (disabled/dimmed in Settings while auto-refresh is off). Wired into `UpdatesViewModel.checkUpdates(for:)`'s new-chapter discovery to auto-enqueue via `DownloadManager`. Manga only — novels have no download feature at all, not just in the background. |
| 33 | ~~In-reader header has no source-URL/globe icon~~ | ✅ Fixed S101 — new `JSBridge.resolveSourceURL(path:)`, best-effort with no plugin changes required: reads a plugin's own top-level `BASE_URL`/`BASE` JS global back out of the JSContext when `path` isn't already absolute. Works for ~7 of 15 plugins (those declaring `const BASE_URL` outside an IIFE) plus Mangayomi-format sources; can't resolve one for esbuild-bundled IIFE plugins or pure-API sources (MangaDex/Comick) — hides the icon rather than guessing. Wired into both `ChapterReaderView.swift` and `TextReaderView.swift`, reusing the existing `DiscussWebSheet`. Icon visibility (meaning URL resolution) verified live against AquaManga; tap-to-open hit this session's mobile-mcp tap flakiness (a control tap on the pre-existing gearshape icon failed identically) and wasn't re-confirmed past that. |
| 34 | ~~AquaManga reader page failed to render live~~ | ✅ Root-caused + fixed S100 — deeper than #9's UA-only theory. Reader pages (`ChapterReaderView.swift`'s `MangaPageView`/`WebtoonReaderView`/`ContinuousHorizontalReaderView`) used raw `AsyncImage`, which can't carry any custom request modifier at all — switched to `KFImage` (matching `CoverImage.swift`'s pattern) so they inherit `KingfisherManager.shared`'s global config. But that alone still 403'd live: Kingfisher's `ImageDownloader` defaults to `URLSessionConfiguration.ephemeral`, which keeps its own private in-memory cookie store — invisible to `HTTPCookieStorage.shared`, exactly where `CFBypassView` copies the `cf_clearance` cookie. Fixed by pointing Kingfisher's downloader at an explicit session config with `httpCookieStorage = .shared` (`YomiApp.swift` init, alongside the existing UA `requestModifier`). This was the real root cause of **both** #34 and #9's previously-unverified cover fix — verified live: AquaManga's cover art and "Path of Vengeance" Ch. 2 pages 1–2 all render correctly now (previously gray placeholder / broken-image icon). |
| 35 | ~~List-mode multi-select still open (re: #19)~~ | ✅ Fixed S100 — confirmed genuinely broken (not just untested): list mode's `.contextMenu` had no "Select" entry and `MangaListRow`/`NovelLibraryListRow` had no selection UI at all, unlike grid mode's `MangaCoverCell`/`NovelLibraryCoverCell` (fixed S96). Added matching "Select" context-menu entries + checkbox rendering to both list rows, wired into the same `isSelecting`/`selectedIds`/`selectedNovelIds` state grid mode already uses (so the existing toolbar Select-All/Cancel and bottom bulk-action bar work for free). Hit the exact `NavigationLink` + `.contextMenu` "narrows tappable area to content only" bug documented in row 8's S86 finding — fixed the same way, an explicit `.contentShape(Rectangle())` on the row container. Verified live: long-press → Select → multi-row checkbox selection → bulk-action bar, both manga and novel list rows. |
| 36 | ~~App Store Connect readiness has zero local tracking artifact~~ | ✅ Fixed S100 — `Yomi/ROADMAP.md`'s "App Store submission checklist" table is now the single authoritative source (updated to current accurate status — app icon done, OPDS Keychain done, ATS review-note item added from #27). This file's own "App Store checklist" section now points to it instead of duplicating. RESEARCH.md/HISTORY.md sections are historical/research narrative, not live checklists — left as-is, not floating duplicates of the actionable list. |
| 37 | ~~Accent-fill buttons had hardcoded white text, unreadable on bright accents~~ | ✅ Fixed S101 — WCAG audit found every accent preset except Indigo failed AA (4.5:1) for white text on its own fill; confirmed live (Ink + Yellow: "Resume" text invisible, 1.52:1). New `YomiTokens.Accent.foreground(for:on:)` keeps the canvas's own ink color whenever it clears 3:1 against the accent, else flips to the opposite pole — applied at ~12 real sites (Resume buttons, badges, empty-state/onboarding CTAs, selection checkmarks). A first "always pick whichever of white/black wins" version was wrong (flipped passing defaults like Vermilion-on-Ink to black, breaking the card's one-ink-color convention) — caught live by Martin, corrected to the threshold version. Paper/Sepia's deeper issue — most accents are also low-contrast as icons/progress-bars directly against those light backgrounds — is a real, separate, *unresolved* color-science tension (accent-vs-bg, not fixable by a foreground-color trick) and was deliberately left for Martin to weigh in on rather than silently recoloring his chosen accents. |
| 38 | ~~No-cover placeholder ignored canvas selection~~ | ✅ Fixed S101 — `Core/CoverImage.swift`'s placeholder used `Color.secondary` (system light/dark mode only), not canvas tokens; any manga/novel without cover art rendered a plain gray box regardless of Ink/Midnight/Paper/Sepia. Fixed to `canvas.surface2`. Root-caused a second layer while fixing: Kingfisher's `KFImage.placeholder` snapshots once at mount and doesn't live-repaint on an environment-only change (correct from a fresh launch with the new canvas already active, stale after switching canvas mid-session without relaunching) — added `.id(canvas.name)` to force a clean remount on every canvas switch, verified live both ways. |
| 39 | ~~Novel indicator badge rendered two different ways~~ | ✅ Fixed S101 (Martin's live catch) — Library grid's `NovelLibraryCoverCell` used a small translucent "NOVEL" text pill (top-trailing); `ContinueReadingRow`'s "Up next" shelf used a chunky solid-accent-filled "N" square (top-leading) for the exact same meaning. Unified the shelf cell to the grid's pill style. |
| 40 | ~~First-party plugin catalog one-tap-installed unlicensed sources~~ | ✅ Fixed S104 — see current-state entry above. `Catalog (15)` in `PluginsView.swift` let 12 unlicensed scanlation/scrape sources install with one tap, discoverable directly from onboarding — the same review-exposure pattern S96 fixed for the LNReader repo, just never applied here. New `instantInstallSourceIDs` allowlist (MangaDex/Royal Road/Scribble Hub only) gates the rest behind Copy URL + manual add. |
| 41 | ~~CloudSyncManager: remote apply drops chapter state for uncached manga~~ | ✅ Fixed S105. A real upsert isn't possible (the sync payload has no title/url/chapterNumber to construct a valid `chapter` row with — chapter lists are deliberately never synced, see `CLOUDKIT_SYNC_DESIGN.md`). Instead: if the UPDATE in `applyRemote(record:)` affects zero rows (`db.changesCount == 0`), the change is stashed in a new `pending_chapter_state`/`pending_novel_chapter_state` table (migration `v21_cloud_sync_pending`) and replayed the moment the chapter row actually gets inserted locally — hooked into `ChapterQueries.insertAllIgnoringConflicts`/`insertMangaAndChapters` and `NovelQueries.insertAllIgnoringConflicts` via new `CloudSyncManager.applyPendingChapterStates`/`applyPendingNovelChapterStates`, called inside the same write transaction. Verified live: clean migration on the existing dev-simulator DB, new tables present via direct `sqlite3` inspection. |
| 42 | ~~CategoryQueries.delete doesn't propagate join-row deletes to CloudKit~~ | ✅ Fixed S105. `CategoryQueries.delete(id:)` now reads the `manga_category`/`novel_category` rows for that category *before* the CASCADE delete, then calls `markCloudDeleted(.mangaCategoryLink/.novelCategoryLink, ...)` for each — same treatment the category's own `Category` CKRecord already got. |
| 43 | ~~CloudSyncManager: dirty-marking no-ops during enable()'s async window~~ | ✅ Fixed S105. `markCloudDirty`/`markCloudDeleted` now always persist the mapping and, when no engine exists yet, stash a durable mark in a new `cloud_sync_map.pendingChange` column (migration `v21_cloud_sync_pending`) instead of silently dropping it. `enable()` drains all pending marks into the freshly-created engine's state (`CloudSyncManager.drainPendingMarks`) right after `cloudSyncEngine` is assigned, before bootstrap/first sync — closing the window instead of just narrowing it. |
| 44 | ~~CloudSyncManager.enable() has a double-call race~~ | ✅ Fixed S105. New `private var isEnabling` flag, set synchronously before the first `await` and cleared via `defer` — `enable()`'s guard now checks `cloudSyncEngine == nil && !isEnabling`. Since both the flag-set and a concurrent caller's guard-check happen synchronously on MainActor (no suspension point between them), a second concurrent call reliably observes the flag and returns early instead of constructing a second `CKSyncEngine`. |
| 45 | ~~`try?` swallows DB-write errors in 2 bulk mark-read functions~~ | ✅ Fixed S105. `ChapterQueries.markAllRead` and `NovelQueries.markAllChapters` reverted to `try appDatabase.write { ... }` (both functions already declare `throws`) — a real GRDB write failure now propagates again instead of silently returning `nil`, restoring S100's Known Issue #26 toast-on-failure behavior for these two call sites. |
| 46 | ~~`Yomi.entitlements` hardcodes `aps-environment: development`~~ | ✅ Fixed S105 — doesn't rely on automatic-signing entitlement rewriting at all anymore. New `Yomi/Yomi-Release.entitlements` (identical except `aps-environment: production`); the Yomi target's Release build configuration's `CODE_SIGN_ENTITLEMENTS` now points at it directly, Debug still points at the original `Yomi.entitlements` (`development`). Verified via both configs' build logs: `ProcessProductPackaging` shows `Yomi.entitlements` for Debug and `Yomi-Release.entitlements` for Release — the correct file is picked at build time regardless of signing style or export path. |
| 47 | CloudKit container `iCloud.pacodealer.Yomi` never provisioned on Apple's servers | Found S106 — real Apple ID signed into 2 simulators, `accountStatus()` correctly resolves `.available`, but every `CKSyncEngine` send/fetch fails with `CKError "Bad Container" (5/1014)`. Root cause: this project isn't enrolled in the paid Apple Developer Program, which container creation requires regardless of entitlements content (S103's `.entitlements` were hand-written, never routed through Xcode's Signing & Capabilities → iCloud → CloudKit "+" flow that actually registers a container server-side). Not fixable in code. Next session: enroll in the Program, provision the container via Xcode, retest — see `Yomi/CLOUDKIT_SYNC_DESIGN.md`'s S106 section. |
| 48 | ~~Chapter-boundary preload could peg CPU/hang on a slow source~~ | ✅ Fixed S109. The new chapter-boundary-transition preload (`ChapterReaderView.preloadNextChapterIfNeeded`) calls `bridge.getPageList()` on a background task while the user keeps reading — `SOURCE._fetchSync` (`JSBridge.swift`) blocks synchronously on a `DispatchSemaphore` with no timeout, an existing app-wide pattern that's fine for a foreground load the user is already waiting on, but silently firing it in the background against a slow/rate-limited source pegged the CPU at 99% and froze the UI (confirmed via `ps aux` CPU sampling, reproduced twice live). Fixed with a 12s timeout race (`withTaskGroup`) — cancellation can't preempt the underlying blocking call, so a truly stuck fetch still burns one background thread until it resolves, but the preload state machine no longer waits on it. Verified: CPU stayed normal (0–20%) across many repeated scroll/scrub operations post-fix. |
| 49 | `mobile-mcp` swipe ignores its `distance` parameter in this environment | Found S109, partial workaround found S110 — every `mobile_swipe_on_screen` call, tested with `distance` from 30 to 2000 on two different `ScrollView`s (the Webtoon reader and a Settings screen), resolved to a full fling to the nearest scroll bound; no intermediate scroll position was reachable. A sharper, more specific characterization of the swipe-simulation unreliability already noted since S87 — previously assumed to be about *whether* a swipe registers, not that its magnitude is entirely ignored. Blocked live pixel-verification of both S109 features (chapter-boundary card, Customize Tabs screen). No fix available client-side; `XcodeBuildMCP`'s `tap`/`swipe`/`batch` UI-automation tools (referenced by `snapshot_ui`'s own `nextSteps` hints) aren't enabled in this session's tool config — enabling them (see xcodebuildmcp.com/docs/configuration) may sidestep this next time. **S110 found a partial workaround**: a short swipe started near the *bottom* of the visible content (not centered) with a small `distance` value reliably lands a genuine partial scroll, where the same swipe centered/full-height always overshoots to the bound — used this to reach and verify Customize Tabs. Still didn't help precisely inside the Webtoon reader's exceptionally tall per-page images (see #51). |
| 50 | ~~Chapter list built in source-native order, not ascending — broke Next/Prev chapter navigation~~ | ✅ Fixed S110. `MangaDetailView.loadChapters()` and both `ContinueReadingRow.swift` reader-launch paths (`ContinueHeroCard`/`ContinueReadingCell`) assigned `chapters` directly from the plugin's `getChapterList()` return order. Confirmed via a live `curl` against AsuraScans' real API that this is newest-first (`[9,8,...,1]`), not ascending — `ChapterReaderView`'s `hasNextChapter`/`navigateToChapter(index ± 1)` and the new S109 boundary-preload all assume ascending order, so "Next Chapter" silently went *backward* for any source returning newest-first (likely most of them). `UpdatesView.swift`'s reader-launch path already defensively sorted and was unaffected. Fixed by sorting `chapters` ascending by `chapterNumber` (nulls last) immediately after each load, matching `ChapterQueries.fetchAll`'s own convention. Live-verified via the in-reader Chapters sheet: Ch.1→Ch.9 now lists in order for the test manga (was silently reversed before). This bug predates S109 — likely present since chapter navigation was first built. |
| 51 | ~~Chapter-boundary preload's trigger couldn't be confirmed firing in the simulator~~ | ✅ Root-caused + fixed S111 — **a real code bug, not tooling.** Apple's own docs for `.scrollPosition(id:)` state it must be paired with `.scrollTargetLayout()` on the scrolled container to track the actively-visible view; neither `WebtoonReaderView`'s `LazyVStack` nor `ContinuousHorizontalReaderView`'s `LazyHStack` had it, so `visibleId` never updated during real scrolling regardless of input source — S110's suspicion (mixing `ScrollViewReader.scrollTo` with `.scrollPosition(id:)`) was on the right track but missed the actual missing piece. Added `.scrollTargetLayout()` to both. Live-verified end-to-end via temporary `NSLog` instrumentation (added then removed): swiped through Ch.6 in Webtoon mode, `visibleId` correctly progressed `cur:19 → cur:20 → boundary → next:0`, the preload fired and fetched real page data, and the reader crossed into Ch.7 with no tap — the full S109 feature now genuinely works, confirmed on this simulator. |
| 52 | ~~`DatabaseManager.shared.setup()` failure silently swallowed at app launch~~ | ✅ Fixed S113. `YomiApp.init()` now `do/catch`es `DatabaseManager.shared.setup()` and calls `fatalError` with the underlying error on failure instead of `try?` — fails loudly at the real point of failure instead of downstream at the first force-unwrap. Live-verified: clean launch unaffected (build+run, no crash). |
| 53 | ~~`clearLastRead` never marks Manga/Novel dirty for CloudKit sync~~ | ✅ Fixed S113. Both `MangaQueries.clearLastRead` and `NovelQueries.clearLastRead` now call `markCloudDirty` after the update, matching their sibling `touchLastRead` functions. |
| 54 | ~~`touchLastUpdated` never marks Manga/Novel dirty for CloudKit sync~~ | ✅ Fixed S113, same change as #53 — `MangaQueries.touchLastUpdated`/`NovelQueries.touchLastUpdated` now call `markCloudDirty`. |
| 55 | Migration numbering has a duplicate `v4` prefix | `DatabaseManager.swift` registers both `v4_reading_insights` (line 131) and `v4_reading_time` (line 140) — breaks the project's own "strictly ascending, unique per number" migration-naming convention. Functionally harmless — GRDB's `DatabaseMigrator` keys by the full string name, not the numeric prefix — but worth a beat before the next `v22_` migration to avoid repeating the slip. |
| 56 | ~~4 more query functions are dead code, unreachable from any UI~~ | ✅ Fixed S113 — removed all 4 (`MangaQueries.insert(_:)`, `NovelQueries.insert(_:)`, `ChapterQueries.insert(_:)` single-row variant, `NovelQueries.upsertChapter(_:)`) after re-confirming zero call sites project-wide. |
| 57 | ~~`SourceBrowseView` reuses one cached `JSBridge` across concurrent `Task.detached` calls with no mutual exclusion~~ | ✅ Fixed S113 — `loadMore()`'s guard now also checks `!isLoading`, so it bails while `loadContent()`'s own `Task.detached` is still in flight against the same cached bridge. |
| 58 | ~~Two `JSBridge.isLNReaderPlugin` reads happen on MainActor, not inside `Task.detached`~~ | ✅ Fixed S113 — both `PopularSourceCarousel.load()` and `SourceBrowseView.loadContent()` now read `isLNReaderPlugin` from inside their single `Task.detached` block (returning an enum result switched on back on MainActor), matching the two already-correct call sites. |
| 59 | ~~`JSBridge.isPaperbackPlugin` is dead code~~ | ✅ Fixed S113 — removed, zero call sites confirmed. |
| 60 | ~~Migrating away from a source with "remove old entry" leaves old downloaded chapter files orphaned on disk~~ | ✅ Fixed S113 — `MigrationService.migrate`'s `removeOld` branch now also removes the old manga's `Downloads/{id}` directory, matching `LibraryView`/`MangaDetailView`'s existing cleanup pattern. |
| 61 | ~~Hiding your current default tab via Customize Tabs can point cold-launch at a hidden tab~~ | ✅ Fixed S113 — `CustomizeTabsView`'s fallback now reassigns to the first still-visible tab (falling back to `.more`) instead of unconditionally `= AppRouter.tabLibrary`, which was a no-op exactly when the hidden tab was Library. Also caught and fixed the identical bug in the adjacent `router.selectedTab` fallback. |
| 62 | ~~`ARQUITECTURA.md` states the wrong default accent color~~ | ✅ Fixed S113 — corrected to `#E5473A` (Vermilion). |
| 63 | ~~`ARQUITECTURA.md`'s "Current tables" schema block predates v20/v21~~ | ✅ Fixed S113 — header now cites `v21_cloud_sync_pending`/S105; schema block adds `cloud_sync_map.pendingChange` and the two `pending_*_chapter_state` tables. |
| 64 | ~~`RESEARCH.md`'s "Last updated" banner predates its own S104 rewrite~~ | ✅ Fixed S113 — banner now reads 2026-08-07 (S104 §5 rewrite). |
| 65 | ~~`TACHIMANGA_PARITY.md` has two stale line-number citations that no longer point at the code they describe~~ | ✅ Fixed S113 — both citations updated to the current lines (`ChapterReaderView.swift:192,199`; `LibraryView.swift:127,245,861`). |
| 66 | ~~`ARQUITECTURA.md`'s file-index entry for `YomiApp.swift` predates the S95 lock/onboarding merge~~ | ✅ Fixed S113 — entry now describes the real merged-`fullScreenCover` pattern. |
| 67 | ~~`ARQUITECTURA.md` undercounts `AppSettings`'s property count~~ | ✅ Fixed S113 — corrected 43 → 55. |
| 68 | ~~Home Screen widget shows reading history even with App Lock / Secure Screen enabled~~ | ✅ Fixed S113 — `LibraryViewModel.writeWidgetData()` now guards on `AppSettings.shared.appLockEnabled`/`secureScreenEnabled` and writes an empty array when either is on; `AppSettings`'s `didSet` for both also immediately clears any already-written widget data the moment the setting flips on, rather than waiting for the next Library refresh. Live-verified the write-guard end-to-end via direct `sqlite3` seeding + App Group plist inspection (populated when unprotected, confirmed the guard compiles and gates correctly); the `didSet` immediate-clear path is a symmetric 2-line addition verified by clean compile, not separately live-tap-verified — `mobile-mcp` tap and `XcodeBuildMCP`'s `tap` (not enabled this session) both failed to register the App Lock toggle, same known limitation as S109. |
| 69 | MangaDex plugin lists licensed/external chapters as normal ones, which dead-end at "No pages found" | `com.yomi.mangadex.js` (live production plugin, hosted at `yomi-plugins.web.app`, source lives outside this repo)'s `getChapterList` (lines 81-133) pushes every chapter from MangaDex's `/feed` response with no check of `attrs.pages`/`attrs.externalUrl`. Reproduced live via `curl` against MangaDex's real API: 5 of 6 recent One Piece English chapters have `pages: 0` and an `externalUrl` pointing at MangaPlus, and hitting `at-home/server/{chapterId}` for one of those returns HTTP 404. `getPageList` (lines 135-156) returns `[]` on that failure, which `ChapterReaderView.swift:478-481` surfaces as the generic "No pages found for this chapter." MangaDex is one of only 3 sources on the `instantInstallSourceIDs` one-tap-install allowlist (`PluginsView.swift:38-42`), so this is a first-run-friction bug for a source the app actively steers new users toward. **Not fixed S113** — the plugin source lives in a separate repo not present on this machine. |
| 70 | ~~Reader's prev/next-chapter footer buttons have no `accessibilityLabel`~~ | ✅ Fixed S113 — added `"Previous chapter"`/`"Next chapter"` accessibility labels to both buttons. |
| 71 | Library's empty-state illustration doesn't match the design spec | The design spec (`YOMI Screens.dc.html`, "Empty state" section) shows a 132×132 box with a radial-gradient screentone-dot background, a crosshair (one horizontal + one vertical line), and a small accent dot near the top. The shipped shared component (`Core/YomiEmptyState.swift:20-38`, used by `LibraryView.swift:37,48-53`) instead renders a plain boxed SF Symbol (`"magnifyingglass"`) + a small accent circle — the component's own code comment acknowledges this is a deliberate simplification ("generalizes it to a boxed SF Symbol"), so it's a known, intentional simplification rather than an accidental bug, but the drift from spec is real. |
| 72 | ~~Tracker auto-update had no opt-out~~ | ✅ Fixed S115 — `ChapterReaderView.swift`'s MAL auto-update fired unconditionally whenever logged in, with no setting to disable it. New `AppSettings.trackerAutoUpdate` (default `true`, preserving prior behavior) gates both the manga and novel reader's tracker-update calls; toggle lives in the new Trackers screen (More → Trackers). |
| 73 | ~~`yomi://` custom URL scheme was never registered — MAL OAuth callback could never reach the app~~ | ✅ Fixed S115 — `Info.plist` had no `CFBundleURLTypes` entry at all. Found while adding new trackers' OAuth flows (all depend on the same scheme); likely broken since MAL login was first built, since nothing else exercises this path. Added the missing `CFBundleURLTypes` entry with scheme `yomi`. |
| 74 | ~~markCloudDirty/markCloudDeleted unconditionally perform 2 separate SQLite write transactions per call even ...~~ | ✅ Fixed S117 — added `markCloudDirtyBatch(_:keys:)` (one transaction for the whole id list) and switched `ChapterQueries.markAllRead`/`NovelQueries.markAllChapters` to use it instead of a per-chapter loop. **[MEDIUM/performance]** `Yomi/Sync/CloudSyncManager.swift:85` — markCloudDirty/markCloudDeleted unconditionally perform 2 separate SQLite write transactions per call even when CloudKit sync was never enabled, turning bulk mark-read operations into an N-transaction storm. markCloudDirty (CloudSyncManager.swift:85-92) and markCloudDeleted (99-106) always call CloudSyncManager.rememberMapping (353-360, its own `try? appDatabase.write { INSERT OR REPLACE INTO cloud_sync_map... }`), then when `cloudSyncEngine` is nil (guard at 88/102) also call CloudSyncManager.markPending (365-372), a second separate `try? appDatabase.write`. `cloudSyncEngine` (declared line 73) is only ever assigned inside CloudSyncManager.enable(), so for any user who hasn't turned on Settings > Sync it is nil for the app's entire lifetime -- meaning every ordinary DB write in the app already pays 2 extra small transactions for sync bookkeeping that has no working backend yet (Known Issue #47). This is acute in the bulk-write paths: ChapterQueries.markAllRead(mangaId:) (Database/Queries/ChapterQueries.swift:145-157) does one fast bulk UPDATE in a single transaction, then loops `for chapterId in chapterIds { markCloudDirty(...) }`; NovelQueries.markAllChapters(novelId:read:) (Database/Queries/NovelQueries.swift:234-248) does the same. For a title with a few hundred chapters, tapping 'Mark all as read' fires several hundred serial commit/fsync SQLite transactions synchronously on the calling thread purely for this bookkeeping. Batching the cloud_sync_map upserts for the whole id list into one transaction would remove nearly all of this cost. |
| 75 | ~~ChapterQueries.upsert(_:) never calls markCloudDirty, unlike every sibling chapter-state write path and unl...~~ | ✅ Fixed S117 — `upsert(_:)` now calls `markCloudDirty(.mangaChapterState, ...)` after saving, same as #79 (same root cause, fixed together). **[MEDIUM/correctness]** `Yomi/Database/Queries/ChapterQueries.swift:61` — ChapterQueries.upsert(_:) never calls markCloudDirty, unlike every sibling chapter-state write path and unlike MangaQueries.upsert/NovelQueries.upsert -- so its one real caller (Tachiyomi backup import) silently fails to propagate imported read-state to CloudKit sync. ChapterQueries.upsert (lines 61-65) does `try chapter.save(db)` with no markCloudDirty call afterward, unlike markRead(id:) (97-109), markRead(id:mangaId:) (112-121), setRead (124-142), markAllRead (145-157), updateProgress (160-172), and addReadingTime (175-187), all of which call `markCloudDirty(.mangaChapterState, key: "\(mangaId)\|\(id)")` after writing isRead/progress/readingSeconds -- and unlike MangaQueries.upsert (Database/Queries/MangaQueries.swift:88-93) and NovelQueries.upsert (Database/Queries/NovelQueries.swift:64-69), which both mark the row dirty. ChapterQueries.upsert is called from Features/More/BackupManager.swift:70 and :295 inside importTachiyomiBackup, which writes exactly the synced fields (isRead, progress via TachiyomiBackupParser) for every imported chapter. Once CloudKit sync is live, a user who imports a Tachiyomi/Mihon backup will have all that imported read/progress state stay stuck on the importing device -- it will never sync to their other devices, and if the same chapter row later gets a legitimate change synced down from another device, that remote change would be applied normally while the import's own state was never pushed up at all. |
| 76 | ~~The chapter-update-notification deep-link handlers (pendingOpenMangaId/pendingOpenNovelId) use .onChange wi...~~ | ✅ Fixed S117 — both `LibraryView.swift` onChange handlers now pass `initial: true`, same fix pattern as Known Issue #18. **[MEDIUM/correctness]** `iOS/Yomi/Features/Library/LibraryView.swift:431` — The chapter-update-notification deep-link handlers (pendingOpenMangaId/pendingOpenNovelId) use .onChange without initial: true, reproducing the exact bug class already found and fixed once (Known Issue #18, openMorePlugins). LibraryView.swift:431-451 has `.onChange(of: appRouter.pendingOpenMangaId) { _, id in ... }` and the equivalent for pendingOpenNovelId, both with no `initial: true`. AppDelegate's `userNotificationCenter(_:didReceive:withCompletionHandler:)` (YomiApp.swift:99-115) sets `appRouter.selectedTab = AppRouter.tabLibrary` and `appRouter.pendingOpenMangaId`/`pendingOpenNovelId` together inside `DispatchQueue.main.async`. SwiftUI's `.onChange` without `initial: true` only fires on a *transition* observed after the view is already mounted with its modifier attached — if LibraryView hasn't mounted yet at the moment the delegate callback runs (plausible on a genuinely cold launch, or whenever the user's `defaultTab` isn't Library and Library hasn't been visited yet this session), the property arrives already non-nil and the onChange handler never fires, so the notification tap silently fails to navigate anywhere. CLAUDE.md's own Known Issue #18 documents this exact pattern (`MoreView`'s `.onChange(of: appRouter.openMorePlugins)` not firing for an already-true flag on first mount) being found and fixed with `initial: true` in S96 — this notification-routing code (dated S102 in a nearby comment) reintroduces the identical bug shape in a different view. |
| 77 | ~~AppSecrets.swift is gitignored (correctly, for the OAuth client secrets it holds) but there is no template/...~~ | ✅ Fixed S117 — added `Yomi/Config/AppSecrets.swift.template` (non-`.swift` extension so the synchronized-group project doesn't also compile it) + a "Fresh clone setup" section in this file. **[MEDIUM/docs]** `iOS/Yomi/Config/AppSecrets.swift:1` — AppSecrets.swift is gitignored (correctly, for the OAuth client secrets it holds) but there is no template/example file or README instructions to recreate it — a fresh clone of the repo cannot compile at all. `.gitignore` (iOS/.gitignore:3) lists `Yomi/Config/AppSecrets.swift`; `git ls-files` confirms it has never been tracked. The Xcode project uses `PBXFileSystemSynchronizedRootGroup` (folder-auto-sync, confirmed in Yomi.xcodeproj/project.pbxproj), so any Swift file physically present under `Yomi/` is compiled automatically — meaning `MALService.swift`, `AniListTrackerService.swift`, `ShikimoriService.swift`, and `BangumiService.swift` (all of which reference `AppSecrets.malClientId`/`aniListClientId`/etc.) fail to compile with 'cannot find AppSecrets in scope' the moment this one file is missing. No `AppSecrets.example.swift` template exists anywhere in the repo, and neither README.md nor CLAUDE.md's onboarding/build instructions mention that this file must be manually created before the project will build. A fresh clone (new machine, disk loss, or any future collaborator) hits a full build failure with no in-repo guidance beyond recreating the exact property list from memory or old notes. |
| 78 | On iPad/regular-width, Apple's built-in sidebar tab-customization UI and Yomi's own CustomizeTabsView both ... | **[MEDIUM/architecture]** S117: deliberately not fixed — reconciling two independent tab-visibility stores is a real product decision (which one wins, or a migration/merge step) rather than a mechanical bug fix, and Yomi has no iPad testing device in this environment to verify either direction live. Flagging for Martin rather than deciding unilaterally, same as the S101/S102 precedent for open design tradeoffs. `iOS/Yomi/ContentView.swift:14` — On iPad/regular-width, Apple's built-in sidebar tab-customization UI and Yomi's own CustomizeTabsView both control tab visibility/order simultaneously, backed by two completely separate, unsynchronized state stores. ContentView.swift:14 stores `@AppStorage("tabViewCustomization") private var customization = TabViewCustomization()`, applied via `.tabViewCustomization($customization)` (line 31) with a `.customizationID(...)` on every tab (lines 52/58/64/73/79) — this is what drives Apple's native sidebar hide/reorder editing affordance in regular-width contexts (iPad/Mac), per the `.tabViewStyle(.sidebarAdaptable)` docs. Separately, `AppSettings.tabOrder`/`hiddenTabIDs` (read by ContentView's `visibleTabIDs`, line 19-22) drive `CustomizeTabsView.swift`, reachable from Settings on every device including iPad (`SettingsView.swift:223`, no size-class gating). Neither mechanism reads or writes the other's storage. On iPad this means a user can hide/reorder a tab through Apple's native sidebar editor without it ever being reflected in AppSettings.hiddenTabIDs/tabOrder or in CustomizeTabsView's own toggle state (which would keep showing that tab as visible), and vice versa — two independent sources of truth for the same concept, coexisting on the one device class where both are simultaneously reachable. `CustomizeTabsView.swift`'s own header comment frames itself purely as "the real substitute for iPhone" and doesn't address this iPad-side overlap. |
| 79 | ~~ChapterQueries.upsert never calls markCloudDirty(.mangaChapterState, ...), unlike every sibling chapter-sta...~~ | ✅ Fixed S117 — same fix as #75 (identical root cause, found independently by two dimensions). **[MEDIUM/correctness]** `iOS/Yomi/Database/Queries/ChapterQueries.swift:61` — ChapterQueries.upsert never calls markCloudDirty(.mangaChapterState, ...), unlike every sibling chapter-state write function and unlike its own counterpart NovelQueries.upsert — so restoring either backup format silently doesn't sync the restored read-state to CloudKit. `upsert(_ chapter: Chapter)` (lines 61-65) does `try chapter.save(db)` and returns — no `markCloudDirty` call. Every other chapter-state writer in the same file does call it: `markRead(id:)` line 107, `markRead(id:mangaId:)` line 119, `setRead` line 138, `markAllRead` line 154, `updateProgress` line 170, `addReadingTime` line 185. Its sibling `NovelQueries.upsert(_ novel: Novel)` (Database/Queries/NovelQueries.swift lines 64-69) DOES call `markCloudDirty(.novel, key: novel.id)` — a direct asymmetry with no comment explaining it. `ChapterQueries.upsert` has exactly two call sites, both in Features/More/BackupManager.swift: `importTachiyomiBackup` (line 70) and `importBackup` (line 295) — the two real backup-restore paths, which write real `isRead`/`progress`/`lastPageRead`/`readingSeconds` per-chapter state from the imported file. Concrete failure: a user restores a Yomi JSON backup or imports a Tachiyomi/Mihon `.tachibk` file with real reading progress on Device A; that progress is written to Device A's local DB but never queued for CloudKit, so it never reaches Device B even though CloudKit sync is otherwise enabled and working for every other read-state change in the app. |
| 80 | ~~The Tachiyomi-import "matched vs. unrecognized sources" count is computed wrong and always reports 0 matche...~~ | ✅ Fixed S117 — the mapped/unmapped check now reads the `"tachiyomi_"` prefix `parseManga` itself already sets on `manga.sourceId`, instead of re-deriving a bogus lookup key from it. **[MEDIUM/correctness]** `iOS/Yomi/Features/More/TachiyomiBackupParser.swift:99` — The Tachiyomi-import "matched vs. unrecognized sources" count is computed wrong and always reports 0 matched, even for sources (e.g. MangaDex) that were correctly resolved — misleading the user-facing import summary. Line 99: `if sourceMap[manga.sourceId.hasPrefix("tachiyomi_") ? 0 : UInt64(manga.sourceId.components(separatedBy: "_").last ?? "") ?? 0] != nil { result.mappedCount += 1 } else { result.unmappedCount += 1 }`. At this point `manga.sourceId` is already the resolved *Yomi* plugin id (set at line 162 to `yomiSourceId`, which is either a real plugin id like "mangadex" from `sourceMap[tachiyomiSourceId]`, or "tachiyomi_<bignum>" if unmapped). For a genuinely mapped manga, `manga.sourceId` = "mangadex": `hasPrefix("tachiyomi_")` is false, so it falls to the else branch, which tries `UInt64("mangadex".components(separatedBy: "_").last!)` = `UInt64("mangadex")` = nil → `?? 0` = 0, then looks up `sourceMap[0]`, which is never a key (`sourceMap` only has 2499283573021220255 and 1998944621) — so the condition is false and `unmappedCount` is incremented instead of `mappedCount`. For an actually-unmapped manga ("tachiyomi_12345"), the ternary evaluates to 0 too, and `sourceMap[0]` is still nil, so it also lands in `unmappedCount` — correct only by coincidence. Net effect: `mappedCount` can never be incremented for any real input, so `BackupManager.lastTachiyomiImportSummary` (BackupManager.swift line 73: "\(result.mangas.count) manga imported (\(result.mappedCount) matched, \(result.unmappedCount) unrecognized sources)") always shows "0 matched", shown verbatim to the user in BackupView's "Tachiyomi import complete" alert — telling every migrating user their sources went unrecognized even when e.g. MangaDex (the one source with a real plugin mapping) was resolved correctly and works fine. |
| 81 | ~~For a multi-language catalog group that isn't on the instant-install allowlist, the row's "Copy URL" button...~~ | ✅ Fixed S117 — added a second language-picker confirmationDialog for the Copy-URL path, so multi-lang groups now let the user pick which language's URL to copy instead of always the alphabetically-first. **[MEDIUM/ux]** `iOS/Yomi/Features/More/PluginsView.swift:613` — For a multi-language catalog group that isn't on the instant-install allowlist, the row's "Copy URL" button always copies the alphabetically-first language variant's URL — there is no way to copy any other language's URL for that source. CatalogGroupRow's trailing action (PluginsView.swift:605-624): the `isInstantInstall` branch (line 609-612) routes multi-lang groups through `onInstall`, which in PluginsView.body opens `langPickerGroup` so the user can choose a language (lines 260-266: `if group.isMultiLang { langPickerGroup = group } else { ... }`). But the non-instant-install "else" branch (lines 613-621) never calls `onInstall` at all — it directly does `UIPasteboard.general.string = group.primaryEntry.fileURL`, bypassing the language picker entirely. `group.primaryEntry` is `entries.sorted { $0.language < $1.language }[0]` (PluginCatalogService.swift:232), i.e. always the alphabetically-first language, regardless of which language the user actually wants. Since the app's own "featured" LNReader repo (`featuredRepos`, PluginsView.swift:18-24, described as "500+ light novel sources in 18 languages") is not in `instantInstallSourceIDs` (lines 38-42) and is therefore Copy-URL-only, every multi-language LNReader source group hits this exact path: a user wanting, say, the French or Spanish variant of a novel source can only ever copy the English (or whichever sorts first) URL through this screen, with zero UI affordance to pick a different language before copying. |
| 82 | ~~ExtensionManager.install()/remove() mutate the @Observable `installed`/`isLoading`/`errorMessage` state wit...~~ | ✅ Fixed S117 — `install()` now wraps every state mutation after an `await` in `await MainActor.run { ... }`, matching `PluginCatalogService`'s established pattern. **[MEDIUM/correctness]** `iOS/Yomi/Features/Extensions/ExtensionManager.swift:119` — ExtensionManager.install()/remove() mutate the @Observable `installed`/`isLoading`/`errorMessage` state with no MainActor hop after an `await`, unlike the sibling PluginCatalogService which explicitly wraps every equivalent mutation in `await MainActor.run { ... }`. install() (lines 118-161) sets `isLoading = true; errorMessage = nil` (119-120) directly, then does `let (data, response) = try await URLSession.shared.data(for: request)` (line 129) — a genuine cross-actor suspension point — and afterward mutates state again (`errorMessage = ...` at 159, plus `loadInstalled()` at 157 which reassigns `installed = valid` at line 54) with no actor hop; `remove()` (166-171) calls `loadInstalled()` synchronously too. Neither `ExtensionManager` nor any of these methods is marked `@MainActor`, so after the `await`, execution is not guaranteed to resume on the main actor. Contrast with `PluginCatalogService.fetchCatalog()` in the same feature area, which performs the identical kind of work (async network fetch, then mutate `entries`/`isLoading`/`errorMessage`) but explicitly wraps every one of those mutations in `await MainActor.run { ... }` (PluginCatalogService.swift:112-115, 121-124, 166-173) specifically because the fetch crosses an await boundary. `installed`/`isLoading`/`errorMessage` back live SwiftUI state (`@State private var extensionManager = ExtensionManager.shared`, PluginsView.swift:47) driving the Installed list and update badges directly, so off-main mutation risks UI updates that don't land reliably or in the expected order. |
| 83 | ~~install()'s dedup-by-name cleanup deletes ANY other installed extension whose display name case-insensitive...~~ | ✅ Fixed S117 — the dedup loop now also requires the stale entry's `sourceListURL` host to match the new install's host, so it only retires same-catalog legacy-id rows and never touches a differently-sourced plugin that happens to share a display name. **[MEDIUM/correctness]** `iOS/Yomi/Features/Extensions/ExtensionManager.swift:136` — install()'s dedup-by-name cleanup deletes ANY other installed extension whose display name case-insensitively matches the one being installed, with no check that it's actually the same plugin lineage and no user confirmation — a coincidental name collision silently destroys a different, unrelated installed plugin. ExtensionManager.swift:136-140: `for stale in installed where stale.name.lowercased() == ext.name.lowercased() && stale.id != ext.id { try? FileManager.default.removeItem(...); try? ExtensionQueries.delete(id: stale.id) }` matches purely on `name`, with no verification the two entries share any origin/id-prefix/catalog. This logic was added (per CLAUDE.md Known Issue #12) to clean up stale rows from an old sha256-id → stable-catalog-id migration, but as written it fires for *any* two installed extensions that happen to share a display name — e.g. a user who manually installs a custom/forked plugin via "Install from URL" (PluginsView.swift InstallFromURLSheet, id = sha256 of the custom URL) under a name that happens to match a catalog entry's name (or vice versa) will have the first one silently deleted, with zero warning, the moment the second is installed. This same mechanism compounds with `PluginCatalogService.availableUpdate(for:)`'s id-then-name fallback (PluginCatalogService.swift:205-209: `entries.first(where: { $0.id == ext.id }) ?? entries.first(where: { $0.name == ext.name })`) — if two different catalogs (e.g. Yomi's own hosted catalog and the featured LNReader repo) both happen to publish an entry with the same display name but different ids and different underlying source code, the app will offer the LNReader entry as an "available update" for the Yomi-catalog plugin (or vice versa) purely by name match, and tapping "Update" (PluginsView.swift:171-175) installs the *other catalog's plugin code* under a new id while this exact dedup logic deletes the original — presented to the user as an ordinary version bump, not a source swap. |
| 84 | ~~Switching the Popular/Latest feed tab (or submitting a search) while a previous loadMore() network call is ...~~ | ✅ Fixed S117 — added a `loadGeneration` counter bumped by `reset()`; a stale `loadMore()` result now checks its captured generation before applying, and `reset()` also clears `isLoading` so a new load is never blocked by a still-resolving stale one. **[MEDIUM/correctness]** `iOS/Yomi/Features/Extensions/SuwayomiBrowseView.swift:84` — Switching the Popular/Latest feed tab (or submitting a search) while a previous loadMore() network call is still in flight can leave the view showing stale content from the old feed under the new tab's UI, with no automatic retry. loadMore() (lines 102-128) guards re-entry only with `guard !isLoading, hasNextPage else { return }` (line 103) and sets `isLoading = true` before its `await service.fetch...` call. `.onChange(of: selectedFeed)` (lines 84-86) fires `Task { await reset(); await loadMore() }` — `reset()` (137-145) clears `mangas`/`currentPage`/`hasNextPage` but does NOT touch `isLoading`. If a prior loadMore() task (e.g. from initial `.task { await loadMore() }` at line 97, or a pagination trigger) is still awaiting its network response when the user switches tabs, the new task's `loadMore()` call immediately returns early because `isLoading` is still `true` from the old task — so the new feed is never loaded. When the old task's network call finally completes, it runs unconditionally: `mangas.append(contentsOf: newMangas)` (from the OLD feed) onto the just-reset (now supposedly-new-feed) array, sets `hasNextPage`/`currentPage` from the old feed's response, and sets `isLoading = false` (lines 116-121) — leaving the grid displaying old-feed page-1 results under the new tab's title/picker state, with nothing left to trigger a fresh load. The identical race applies to `runSearch()` (130-135) racing an in-flight initial `loadMore()`. This is the same class of bug Known Issue #57 fixed for `SourceBrowseView`'s JSBridge-backed loader, but that fix never touched this REST-backed Suwayomi browse view. |
| 85 | ~~Browse-only (not-in-library) novel chapters are never sorted ascending, so Next/Prev chapter navigation can...~~ | ✅ Fixed S117 — `NovelDetailView.loadChapters()`'s browse-only branch now sorts `fetched` ascending by `chapterNumber` (nulls last), same fix shape as #50 for manga. **[MEDIUM/correctness]** `iOS/Yomi/Features/Browse/NovelDetailView.swift:825` — Browse-only (not-in-library) novel chapters are never sorted ascending, so Next/Prev chapter navigation can silently go backward — the same bug class fixed for manga in Known Issue #50. `loadChapters()`'s `else` branch at line 825-827 (`chapters = fetched`) uses `fetched` (built at lines 800-812 directly from `source.chapters.enumerated().map`, i.e. whatever order the plugin's `parseNovel` returns) with zero sorting applied. Compare the `if novel.inLibrary` branch (lines 814-824), which re-fetches through `NovelQueries.fetchChapters` (`Database/Queries/NovelQueries.swift:133-139`), which does `.order(Column("chapterNumber").asc)` — so only library novels get a guaranteed ascending order. `TextReaderView.swift` (`hasNextChapter` line 83: `currentChapterIndex < chapters.count - 1`, `nextChapterForPreload` line 84: `chapters[currentChapterIndex + 1]`) navigates purely by array index, assuming ascending order — exactly the assumption that Known Issue #50 in CLAUDE.md documented as broken for MangaDetailView when a source (confirmed live via curl against AsuraScans) returns newest-first. `NovelDetailView`'s `.navigationDestination(item: $chapterForNav)` (line 123-127) lets a user tap any chapter and reach `TextReaderView` while `isInLibrary == false` (the 'Start reading'/`chapterRow` taps at lines 419-424 and 573-576 don't check `isInLibrary`), so any novel source that returns chapters newest-first will make 'Next Chapter' go backward for a user reading before adding to library — the exact scenario #50 fixed for manga was never mirrored here for novels. |
| 86 | ~~NovelDetailView's Cloudflare-block recovery is manual-only (no CFBypassManager.autoBypass), inconsistent wi...~~ | ✅ Fixed S117 — added `loadChaptersWithBypass()` mirroring `SourceBrowseView.loadWithBypass()`: auto-retries `CFBypassManager.autoBypass` in the background before showing the manual bypass button, with the same "Bypassing Cloudflare…" overlay and auto-bypass-failed banner. **[MEDIUM/ux]** `iOS/Yomi/Features/Browse/NovelDetailView.swift:479` — NovelDetailView's Cloudflare-block recovery is manual-only (no CFBypassManager.autoBypass), inconsistent with SourceBrowseView which auto-retries a background bypass before ever showing the user a blocked state. In `NovelDetailView.swift`, the only reaction to a Cloudflare block is the inline button at lines 479-491 (`showCFBypass = true`) inside `chaptersSection`, requiring a manual tap every time chapters load empty behind Cloudflare. `BrowseView.swift`'s `SourceBrowseView.loadWithBypass()` (lines 872-889) instead calls `CFBypassManager.autoBypass(url:)` (line 881) automatically the moment content comes back empty with a `cfBlockedURL` set, showing a 'Bypassing Cloudflare…' overlay and only falling back to a manual banner if that fails (`autoBypassFailed`, lines 833-852). `grep -rn "CFBypassManager" Yomi/Features` confirms `CFBypassManager.autoBypass` is called from exactly one place in the whole app (`BrowseView.swift:881`) — `NovelDetailView.swift` and `Features/Library/MangaDetailView.swift` (both checked) only wire the manual `CFBypassView` sheet, never `autoBypass`. This exact gap is already named in prose in `CLAUDE.md` line 117 (from S114 research) but was never turned into a numbered Known Issues row or fixed — it's a real, still-live inconsistency in this file, not a duplicate of a tracked/fixed item. |
| 87 | ~~OPDS pagination (`rel="next"`) is parsed by OPDSService but never consumed by any view — any paginated OPDS...~~ | ✅ Fixed S117 — both `OPDSBrowseView` and `BrowseView`'s OPDS root section now track `nextPageHref` and render a manual "Load More" affordance that fetches and appends the next page. **[MEDIUM/correctness]** `iOS/Yomi/Features/Browse/OPDSBrowseView.swift:194` — OPDS pagination (`rel="next"`) is parsed by OPDSService but never consumed by any view — any paginated OPDS catalog (e.g. Calibre-Web/Komga, which page results by default) silently truncates to page 1 with no 'load more' and no indication more content exists. `OPDSService.swift` parses and stores `nextPageHref` on `OPDSFeed` (struct field line 23; parsed from `rel=="next"` at line 220-222; assembled into the returned feed at line 235). `grep -rn "nextPageHref" Yomi --include="*.swift"` shows it is set in exactly 3 places, all inside `OPDSService.swift` itself, and read nowhere. `OPDSBrowseView.swift`'s `load()` (lines 194-209) stores the whole `OPDSFeed` in `feed` but `feedView`/`acquisitionGrid`/`navigationList` (lines 44-96, 119-134) only ever render `feed.entries` — there is no 'load more' trigger, no scroll-triggered next-page fetch, and no UI hint that a `nextPageHref` exists. `BrowseView.swift`'s `opdsSection`/`loadOPDSRoot()` (lines 209-293) have the identical gap for the OPDS root feed. A large real-world OPDS library (Calibre-Web defaults to 50 items/page) would show only its first 50 entries forever, with the app behaving as if that were the complete catalog. |
| 88 | ~~navigateToChapter's background page-fetch has no staleness/cancellation guard, unlike the S109 preload path...~~ | ✅ Fixed S117 — the completion handler now guards `currentChapterIndex == index` (the index this specific call navigated to) before applying `pages`/`isLoading`/`errorMessage`, dropping a stale result if a newer navigation has since superseded it. **[MEDIUM/correctness]** `Yomi/Features/Reader/ChapterReaderView.swift:454` — navigateToChapter's background page-fetch has no staleness/cancellation guard, unlike the S109 preload path — rapid re-navigation can let an older, slower fetch overwrite a newer one's result. Lines 452-461: ``` let path = chapters[index].path let b = bridge Task.detached(priority: .userInitiated) {     let result = b.getPageList(chapterPath: path)     await MainActor.run {         pages = result         isLoading = false         if result.isEmpty { errorMessage = "No pages found." }     } } ``` Calling navigateToChapter twice before the first fetch resolves (e.g. an impatient double-tap on the overlay's Next/Prev chapter buttons at lines 182/181, or picking two different entries from the Chapters sheet's onJumpToChapter in quick succession) starts two concurrent Task.detached blocks against the same JSBridge with no chapter-id or generation check before writing `pages`/`isLoading`/`errorMessage`. Because `getPageList` blocks synchronously on a DispatchSemaphore (JSBridge.swift, no timeout on this foreground path by design), whichever fetch happens to finish LAST wins, regardless of which navigateToChapter call was most recent — so the reader can end up displaying a previous chapter's pages (or a spurious "No pages found." from a since-superseded empty result) under the currently-selected chapter's header/title. Contrast with preloadNextChapterIfNeeded's own background fetch (lines 385-392), which explicitly re-checks `chapters[currentChapterIndex + 1].id == next.id` before applying its result — the same defensive pattern was never applied to this call site. |
| 89 | ~~Tracker auto-update fires unguarded on every currentPage change near the chapter end, unlike markChapterRea...~~ | ✅ Fixed S117 — added a `didUpdateTrackerForCurrentChapter` guard (idempotent per chapter, reset on every chapter-change path), mirroring the existing `didMarkCurrentChapterRead` pattern right next to it. **[MEDIUM/correctness]** `Yomi/Features/Reader/ChapterReaderView.swift:234` — Tracker auto-update fires unguarded on every currentPage change near the chapter end, unlike markChapterRead — reading or scrubbing through the last 2 pages re-issues searchManga+updateMangaProgress to every logged-in tracker multiple times per chapter. Lines 229-248: ``` .onChange(of: currentPage) { _, newPage in     ...     if !AppSettings.shared.isIncognito && pages.count > 0 && newPage >= pages.count - 2 {         markChapterRead()         if AppSettings.shared.trackerAutoUpdate {             let mangaTitle = manga.title             let chapNum = Int(activeChapter.chapterNumber ?? 0)             Task {                 for tracker in TrackerManager.loggedInTrackers {                     if let trackerId = await tracker.searchManga(title: mangaTitle) {                         await tracker.updateMangaProgress(trackerId: trackerId, chaptersRead: chapNum)                     }                 }             }         }     } } ``` `markChapterRead()` is idempotent (guarded by `didMarkCurrentChapterRead`, line 319), but the tracker-update block right next to it has no equivalent guard. `newPage >= pages.count - 2` is true for at least two distinct page values (pages.count-2 and pages.count-1) in normal forward reading, and for every value the scrubber (YomiScrubber, ReaderOverlayView) is dragged to inside that window — each transition re-runs a fresh `searchManga` title search plus `updateMangaProgress` against every tracker in `TrackerManager.loggedInTrackers` (up to 4: MAL/AniList/Shikimori/Bangumi). A user who scrubs back and forth near the end of a chapter, or simply pages through a short (2-3 page) chapter, fires this multiple times per chapter for no functional benefit, wasting API calls and risking tracker-side rate limiting (MAL in particular enforces strict per-minute limits). |
| 90 | ~~preloadNextChapterIfNeeded always fetches the next chapter over JSBridge/network even when it's already dow...~~ | ✅ Fixed S117 — now checks `next.isDownloaded`/`DownloadManager.shared.localURLs(for:)` first, same as `loadPages()`, before falling back to the network fetch. **[MEDIUM/correctness]** `Yomi/Features/Reader/ChapterReaderView.swift:374` — preloadNextChapterIfNeeded always fetches the next chapter over JSBridge/network even when it's already downloaded locally, so the seamless chapter-boundary crossing never works offline — unlike loadPages(), it never checks isDownloaded/DownloadManager. loadPages() (lines 469-474) correctly prefers local files first: ``` if activeChapter.isDownloaded,    let localURLs = DownloadManager.shared.localURLs(for: activeChapter) {     pages = localURLs.map { $0.absoluteString }     isLoading = false     return } ``` But preloadNextChapterIfNeeded (lines 360-394) has no equivalent check — it unconditionally does: ``` Task.detached(priority: .background) {     let result: [String]? = await withTaskGroup(of: [String]?.self) { group in         group.addTask { b.getPageList(chapterPath: path) }         group.addTask { try? await Task.sleep(for: .seconds(12)); return nil }         ...     }     ... } ``` even when `next.isDownloaded` is true and `DownloadManager.shared.localURLs(for: next)` would resolve instantly and offline. For a user reading downloaded chapters offline (a supported, expected use case per the app's own Downloads feature), every chapter-boundary preload burns the full 12s timeout trying and failing to reach the network, `nextPreload` stays nil, and the S109-111 seamless in-scroll crossing feature silently never appears — degrading exactly the scenario (offline reading) where a smooth transition matters most, while the user also incurs a background thread stuck in the still-blocking `_fetchSync` call for up to 12s per chapter boundary crossed. |
| 91 | ~~navigateToChapter() unconditionally marks the chapter being left as fully read, regardless of how much of i...~~ | ✅ Fixed S117 — the mark-read call is now gated on `(lastKnownScrollPercent ?? activeChapter.lastScrollPercent ?? 0) >= 0.9`, matching the JS 90%-completion threshold, instead of firing unconditionally on every navigation away. **[MEDIUM/correctness]** `iOS/Yomi/Features/Reader/TextReaderView.swift:355` — navigateToChapter() unconditionally marks the chapter being left as fully read, regardless of how much of it was actually read, contradicting the app's own 90%-scroll-completion mechanism. Lines 365-369: `let chapterId = activeChapter.id; let novelId = novel.id; if !AppSettings.shared.isIncognito { Task.detached(priority: .background) { try? NovelQueries.markRead(chapterId: chapterId, novelId: novelId) } }` runs BEFORE `currentChapterIndex = index` on line 373, so `activeChapter` still refers to the chapter the user is navigating AWAY from. This fires on every call path into `navigateToChapter` — Next, Prev, and jump-to-chapter from the Chapters sheet (line 243: `onJumpToChapter: { navigateToChapter($0) }`). Concrete scenario: a user opens a chapter, reads one paragraph, then taps 'Next chapter' (or 'Prev', or jumps elsewhere in the list) — the barely-started chapter is immediately marked isRead=true/readAt=now in `NovelQueries.markRead` (NovelQueries.swift:190-201), even though the separate, intentional 90%-scroll `onReadComplete` mechanism (lines 179-204, JS threshold at ReaderWebView.swift setup script line 498) never fired. This inflates read history/stats and permanently clears the chapter's 'unread' state for a chapter never actually finished. |
| 92 | ~~Tapping the currently-active chapter in the in-reader Chapters list soft-locks the reader on a permanent lo...~~ | ✅ Fixed S117 — `navigateToChapter(_:)` now early-returns a no-op when `index == currentChapterIndex`, so re-selecting the already-open chapter never sets `isLoading` and never gets stuck waiting for a `.task(id:)` re-run that was never going to happen. **[MEDIUM/correctness]** `iOS/Yomi/Features/Reader/TextReaderView.swift:712` — Tapping the currently-active chapter in the in-reader Chapters list soft-locks the reader on a permanent loading spinner because navigateToChapter(currentChapterIndex) doesn't change activeChapter.id, so .task(id:) never re-runs to clear isLoading. The Chapters sheet's row Button (lines 712-715) calls `onJumpToChapter?(idx)` -> `navigateToChapter($0)` with no guard excluding `idx == currentChapterIndex`; the row for the current chapter is not disabled. `navigateToChapter(_:)` (lines 355-378) sets `isLoading = true` (line 371) then `currentChapterIndex = index` (line 373) with the SAME value as before. Since `activeChapter.id` (used as the `.task(id:)` key on line 252, `.task(id: activeChapter.id) { await loadContent() }`) is unchanged, SwiftUI's `.task(id:)` does not cancel/restart — `loadContent()` never runs again, so `isLoading` is never set back to `false`. The view's body (lines 165-167) shows only `ProgressView()` while `isLoading` is true, so the reader is stuck on a spinner for that chapter until the user taps the bottom overlay's Prev/Next buttons (which DO change `activeChapter.id` and recover). |
| 93 | ~~Reading-progress tracking (mark-read, tracker auto-update, chapter-finished banner, and the scroll-percent ...~~ | ✅ Fixed S117 — added a `checkNoScrollNeeded()` JS check (run immediately and again on `load`) that fires `readComplete`/`scrollPosition(1)` directly when `document.body.scrollHeight <= window.innerHeight`, since such a chapter's `scroll` event would otherwise never fire. **[MEDIUM/correctness]** `iOS/Yomi/Features/Reader/TextReaderView.swift:494` — Reading-progress tracking (mark-read, tracker auto-update, chapter-finished banner, and the scroll-percent used for preload/progress display) is entirely gated on the JS 'scroll' event, which never fires for a chapter short enough to fit the viewport without scrolling. The injected setup script (lines 489-516) wires BOTH the 90%-completion signal and the scroll-percent signal exclusively inside `window.addEventListener('scroll', ...)` handlers (lines 495-513) that compute `ratio`/`pct` from `window.scrollY`. If a chapter's content plus the CSS `padding: 24px hp 200px hp` (line 110) is shorter than the viewport, `window.scrollY` never changes from 0 and the `scroll` event never fires at all — so `readComplete` (line 500) is never posted, meaning `onReadComplete` (lines 179-204: `NovelQueries.markRead`, tracker auto-update, the 'Chapter finished' banner) never runs, and `scrollPosition` (line 511) is never posted either, so `lastKnownScrollPercent` stays nil and the chapter's progress permanently reads 0% in the footer/chapter list, and the 70%-scroll preload trigger (`onScrollUpdate`, line 208) never fires for that chapter. Short chapters (interludes, teasers, author's-note-only chapters) are common in the web-novel sources this app targets, making this a real, reachable case rather than a hypothetical edge case. |
| 94 | ~~isPreloadingNextChapter is a single shared flag, not scoped to a specific chapter — a stale in-flight prelo...~~ | ✅ Fixed S117 — replaced the single bool with `preloadingChapterIds: Set<String>` keyed per chapter id, and the completion handler now also re-checks `nextChapterForPreload?.id == nextId` before writing to cache, so a stale late write can no longer resurrect an already-evicted chapter. **[MEDIUM/performance]** `iOS/Yomi/Features/Reader/TextReaderView.swift:382` — isPreloadingNextChapter is a single shared flag, not scoped to a specific chapter — a stale in-flight preload for a chapter no longer 'next' silently blocks the real S115 preload for the actual current next chapter until the stale task resolves. `preloadNextChapterIfNeeded()` (lines 382-396) guards on `!isPreloadingNextChapter`, a single `@State` boolean shared across all chapters. Scenario: at 70% scroll on chapter N, a preload for N+1 starts (`isPreloadingNextChapter = true`). Before it completes, the user taps 'Next chapter' to N+1 and quickly scrolls past 70% again — `preloadNextChapterIfNeeded()` is called for the real next chapter N+2, but its guard sees `isPreloadingNextChapter == true` (still set from the stale N+1 fetch) and returns immediately, silently skipping the preload. The legitimate N+2 preload only becomes possible again once the stale N+1 task's `await MainActor.run { ...; isPreloadingNextChapter = false }` (line 393) finally runs, delaying preload exactly in the fast-reading scenario S115 was built to help. Relatedly, the stale task's late write (`if !html.isEmpty { chapterContentCache[nextId] = html }`, line 392) can land after a jump-to-chapter's cache eviction filter has already run (`chapterContentCache = chapterContentCache.filter { $0.key == targetId }`, lines 374-377), re-inserting an entry for a chapter no longer adjacent to the current one. |
| 95 | ~~ReaderWebView's Coordinator never implements WKNavigationDelegate's decidePolicyFor navigation-action check...~~ | ✅ Fixed S117 — added `decidePolicyFor` to `Coordinator`: allows only the initial `loadHTMLString(_:baseURL: nil)` navigation (resolves to `about:blank`/nil URL) and cancels every other navigation attempt, blocking any embedded `<a href>` or JS redirect in scraped chapter HTML. **[MEDIUM/security]** `iOS/Yomi/Features/Reader/TextReaderView.swift:562` — ReaderWebView's Coordinator never implements WKNavigationDelegate's decidePolicyFor navigation-action check, so unsanitized third-party scraped chapter HTML (loaded with full JS execution and no CSP) can navigate the reader's own WKWebView to an arbitrary URL with zero interception. `Coordinator` (lines 562-620) conforms to `WKNavigationDelegate` but only implements `webView(_:didFinish:)` (line 580) — there is no `webView(_:decidePolicyFor:decisionHandler:)`. `rawContent` — raw HTML scraped from arbitrary third-party novel sites via `bridge.parseChapter` — is inserted unsanitized straight into the document body (`styledHTML`, line 152: `\(rawContent)`) and loaded via `webView.loadHTMLString(html, baseURL: nil)` (line 530) with default JavaScript execution enabled and no Content-Security-Policy meta tag anywhere in `styledHTML`'s `<head>` (lines 141-155). Any `<a href>` link or JS redirect embedded in the scraped chapter content (ads, promotional links, or a compromised source page — common on the scanlation/scrape sites this app's plugins target) will navigate the WKWebView in place, with the custom tap gesture recognizer explicitly allowed to fire simultaneously (`gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:) -> Bool { true }`, line 619) rather than intercepting it — turning the reader UI into an uncontrolled window onto whatever URL the source's HTML points at, with no confirmation and no way back except dismissing the reader entirely. |
| 96 | ~~Grid-mode multi-select checkmark badge is hardcoded to white in both selected/unselected states, missing th...~~ | ✅ Fixed S117 — `MangaCoverCell`'s selected-state checkmark now uses `AppSettings.shared.accentForeground`, same as the sibling `NovelLibraryCoverCell` badge fixed in S101. **[MEDIUM/accessibility]** `iOS/Yomi/Features/Library/MangaCoverCell.swift:77` — Grid-mode multi-select checkmark badge is hardcoded to white in both selected/unselected states, missing the WCAG-contrast fix (`accentForeground`) applied to the identical sibling badge in NovelLibraryCoverCell. MangaCoverCell.swift:72-85 renders the selection badge as `.foregroundStyle(isSelected ? .white : .white)` over `.fill(isSelected ? Color.accentColor : Color.black.opacity(0.35))` — a no-op ternary, so a selected manga cell always shows a white checkmark on the raw accent-colored circle. Compare LibraryView.swift:895-908 (NovelLibraryCoverCell, same overlay/purpose, same file family): `.foregroundStyle(isSelected ? AppSettings.shared.accentForeground : .white)`. `AppSettings.accentForeground`/`YomiTokens.Accent.foreground(for:on:)` was added S101 (Known Issue #37) specifically because most accent presets fail WCAG AA for white content on their own fill (confirmed live: 'Ink + Yellow: Resume text genuinely unreadable', 1.52:1) — that fix was applied to ~12 sites app-wide but never reached MangaCoverCell's selection badge, so selecting a manga (not a novel) with a bright/light accent (e.g. Yellow, Sky) reproduces the exact same low-contrast bug S101 fixed everywhere else. |
| 97 | ~~Chapter.swift and Category.swift still carry Spanish doc comments, violating METODOLOGIA.md's explicit "all...~~ | ✅ Fixed S117 — both files' doc comments translated to English. **[LOW/docs]** `Yomi/Models/Chapter.swift:3` — Chapter.swift and Category.swift still carry Spanish doc comments, violating METODOLOGIA.md's explicit "all code, commits, docs, and communication in English (from S15 onward)" rule and inconsistent with sibling model files that were already translated. Chapter.swift lines 3-30 are entirely Spanish ("Representa un capítulo de una obra", "Identificador único local", "ID del manga al que pertenece este capítulo", "Ruta relativa dentro de la fuente...", "Indica si el usuario ya leyó este capítulo", etc.). Category.swift lines 3-10 are the same ("Representa una categoría para organizar la biblioteca del usuario", "Identificador único local", "Posición de orden entre categorías; menor número aparece primero"). METODOLOGIA.md:27 states "All code, commits, docs, and communication in English (from S15 onward)." Manga.swift and Novel.swift (same Models/ directory) have zero Spanish comments -- fully English -- and ROADMAP.md's S78 entry (item 12) explicitly lists CategoryQueries.swift (the query file, not the model) and DatabaseManager.swift/ChapterReaderView.swift as translated, but never mentions Chapter.swift or Category.swift (the models) -- these two were missed by that earlier cleanup pass and remain the only Spanish comments left in the audited slice. |
| 98 | ~~Three query-layer functions beyond the already-tracked dead delete() trio have zero call sites anywhere in ...~~ | ✅ Fixed S117 — `DownloadQueries.deleteDownloadRecord`, `ExtensionQueries.fetchAll`, and `NovelQueries.update` all removed (each re-confirmed zero call sites first). **[LOW/dead-code]** `Yomi/Database/Queries/DownloadQueries.swift:49` — Three query-layer functions beyond the already-tracked dead delete() trio have zero call sites anywhere in the repo: DownloadQueries.deleteDownloadRecord, ExtensionQueries.fetchAll, and NovelQueries.update. Repo-wide grep (not just Features/) found zero call sites for: DownloadQueries.deleteDownloadRecord(chapterId:) (DownloadQueries.swift:49-56) -- its own doc comment even says "Does not delete the local file -- file deletion is the caller's responsibility", implying a caller that doesn't exist; ExtensionQueries.fetchAll() (ExtensionQueries.swift:19-23) -- ExtensionManager.swift only ever calls ExtensionQueries.fetchInstalled/upsert/delete (lines 43, 51, 98, 103, 139, 156, 169), never fetchAll; and NovelQueries.update(_:) (NovelQueries.swift:56-61) -- NovelQueries.upsert is used everywhere a novel needs writing instead. This is distinct from the already-documented dead trio (MangaQueries.delete/NovelQueries.delete/ChapterQueries.delete, tracked in CLOUDKIT_SYNC_DESIGN.md and ROADMAP.md/METODOLOGIA.md) -- these three have not been flagged before. |
| 99 | ~~ChapterQueries.markRead(id:) (the single-argument overload, without mangaId) has zero call sites -- only th...~~ | ✅ Fixed S117 — the dead 1-arg overload removed entirely (re-confirmed zero call sites), closing the latent trap rather than fixing its inconsistency. **[LOW/dead-code]** `Yomi/Database/Queries/ChapterQueries.swift:97` — ChapterQueries.markRead(id:) (the single-argument overload, without mangaId) has zero call sites -- only the two-argument markRead(id:mangaId:) is ever used -- and the two overloads behave inconsistently (the dead one skips touchLastRead), a latent trap if someone reaches for it later. Repo-wide grep for `ChapterQueries.markRead(id:` outside ChapterQueries.swift only matches ChapterReaderView.swift:327's `ChapterQueries.markRead(id: cid, mangaId: mid)` -- the 2-arg overload. The 1-arg overload (ChapterQueries.swift:97-109) sets isRead/readAt/progress and marks cloud-dirty but, unlike its sibling at line 112-121, never calls MangaQueries.touchLastRead(mangaId:) -- so if it were ever picked up by a future call site (plausible given the near-identical signature and no compiler warning for the ambiguity), that manga's lastReadAt / History-tab ordering would silently stop updating. |
| 100 | ~~ARQUITECTURA.md's AppSettings property count ("55 properties") is stale — actual count is 60 stored propert...~~ | ✅ Fixed S117 — updated to "60 stored properties (S116)". **[LOW/docs]** `iOS/Yomi/ARQUITECTURA.md:107` — ARQUITECTURA.md's AppSettings property count ("55 properties") is stale — actual count is 60 stored properties as of the current code. ARQUITECTURA.md:107 states "@Observable singleton, UserDefaults-backed, 55 properties." Counting `didSet {` occurrences in Yomi/AppSettings.swift gives 60 (confirmed by also counting every stored `var` declaration, excluding the 4 computed properties `colorScheme`/`canvasColors`/`blendedCanvasColors`/`accentForeground`: 64 total var declarations − 4 computed = 60 stored). This is the same class of drift Known Issue #67 fixed once already (43→55 at S113); at least 5 more properties (e.g. `trackerAutoUpdate` added S115) have been added since without updating this count. CLAUDE.md's own "Key file paths" table separately says AppSettings has "40+ props" — not technically false, but a much vaguer/staler figure than the project's own established convention of tracking an exact count. |
| 101 | ~~AppSettings.novelSepia is written on every novel-theme change but never read anywhere except a one-time leg...~~ | ✅ Fixed S117 — removed the dead write site in `TextReaderView`'s `onChange(of: novelTheme)`; the property itself stays (still legitimately read by `init()`'s migration branch). **[LOW/dead-code]** `iOS/Yomi/Features/Reader/TextReaderView.swift:268` — AppSettings.novelSepia is written on every novel-theme change but never read anywhere except a one-time legacy-migration branch that only matters for installs older than novelTheme's own introduction. TextReaderView.swift:266-269: `.onChange(of: novelTheme) { _, v in AppSettings.shared.novelTheme = v.rawValue; AppSettings.shared.novelSepia = (v == .sepia) }`. Grepping the whole app for `.novelSepia` outside AppSettings.swift finds only this one write site — no read site anywhere. Inside AppSettings.swift itself, `novelSepia` is only ever read in `init()`'s migration branch (`else if d.bool(forKey: "novelSepia") { novelTheme = "Sepia" }`), which is itself gated behind `if let saved = d.string(forKey: "novelTheme") { novelTheme = saved }` already succeeding for any install that has ever had `novelTheme` set (i.e., essentially every install post-migration). The property is marked "Legacy — kept so existing data is not lost on upgrade" but is being actively re-persisted on every theme change going forward for no functional purpose. |
| 102 | ~~Restoring a Yomi JSON backup can mark a chapter isDownloaded=true even though the backup never contains the...~~ | ✅ Fixed S117 — `decodeChapter` now always decodes `isDownloaded: false` (matching the already-hardcoded `downloadedAt: nil`), instead of trusting the backup's stale flag. **[LOW/correctness]** `iOS/Yomi/Features/More/BackupManager.swift:447` — Restoring a Yomi JSON backup can mark a chapter isDownloaded=true even though the backup never contains the actual downloaded page files, leaving a stale "downloaded" UI state until the user notices. `encodeChapter` (line 382-398) includes `"isDownloaded": c.isDownloaded` unconditionally, but the JSON backup contains no page-file data at all (downloads are on-disk files under Downloads/{mangaId}/{chapterId}, never serialized). `decodeChapter` (lines 432-455) restores `isDownloaded: d["isDownloaded"] as? Bool ?? false` (line 447) and hardcodes `downloadedAt: nil` (line 448) with no corresponding file write. After a restore-from-backup (e.g. onto a new device, or after the app's Downloads folder was cleared/Storage-view-cleared), any chapter that was downloaded at export time comes back with `isDownloaded = true` in the DB even though no file exists on disk. `DownloadManager.localURLs(for:)` (DownloadManager.swift line 110-124) gracefully returns nil when the directory is empty, so the reader itself falls back to a normal network fetch without crashing — but `MangaDetailView.swift`'s downloaded-filter/badge UI (lines 365, 483, 752-753, 862, 882, 1254, 1293, 1312) all read `chapter.isDownloaded` directly, so those chapters keep showing as "downloaded" (filterable/badged) in the UI until the user taps into one and the app quietly re-fetches it online, or manually deletes/redownloads. |
| 103 | ~~ARQUITECTURA.md's description of CFBypassManager.autoBypass ("1×1pt WKWebView ... for up to 10s") no longer...~~ | ✅ Fixed S117 — both mentions (file-tree comment + CFBypassManager section) updated to "full-size off-screen WKWebView... 30s timeout" with the Turnstile-needs-a-real-viewport rationale. **[LOW/docs]** `iOS/Yomi/Yomi/ARQUITECTURA.md:318` — ARQUITECTURA.md's description of CFBypassManager.autoBypass ("1×1pt WKWebView ... for up to 10s") no longer matches the actual implementation, which uses a full-screen off-screen WKWebView with a 30s timeout. ARQUITECTURA.md:318: "attaches a hidden 1×1pt WKWebView to keyWindow for up to 10s." The real code (CFBypassView.swift, AutoBypassHelper.run, lines 228-233): "Full-size off-screen — Cloudflare Turnstile needs a real viewport to run its JS ... let frame = CGRect(x: 0, y: screenBounds.height + 1, width: screenBounds.width, height: screenBounds.height)" — full device width/height, not 1×1pt. The timeout is `try? await Task.sleep(for: .seconds(30))` (line 244), and the polling comment at line 262 explicitly says "Poll every 0.5 s for up to 30 s (60 ticks), matching the timeout task" — 30s, not 10s. A maintainer reading ARQUITECTURA.md would misjudge both how long auto-bypass waits before giving up and why it needs a full viewport (the doc's stated rationale for "1×1pt" — hidden/invisible — contradicts the code's own comment that a real viewport is required for Turnstile to run). |
| 104 | ~~`formatReadingTime(_:)` is defined but never called anywhere in the file.~~ | ✅ Fixed S117 — removed. **[LOW/dead-code]** `iOS/Yomi/Features/Browse/NovelDetailView.swift:633` — `formatReadingTime(_:)` is defined but never called anywhere in the file. `grep -n "formatReadingTime" Yomi/Features/Browse/NovelDetailView.swift` returns only the single definition at line 633 (`private func formatReadingTime(_ seconds: Int) -> String { ... }`, lines 633-641) — zero call sites. The reading-time display actually used in `headerSection` (line 408) calls `Notation.readingTime(seconds:)` instead, making this a duplicate, orphaned helper. |
| 105 | ~~sessionSeconds is a @State variable incremented every second by a Timer for the entire time the reader is o...~~ | ✅ Fixed S117 — removed both `sessionSeconds` and the `readingTimer` that only ever incremented it; the real elapsed-time value was already computed independently via `Date().timeIntervalSince(sessionStart)`. **[LOW/performance]** `Yomi/Features/Reader/ChapterReaderView.swift:37` — sessionSeconds is a @State variable incremented every second by a Timer for the entire time the reader is open, but is never read anywhere — a dead, needlessly repeating SwiftUI state mutation. Declared line 37 (`@State private var sessionSeconds: Int = 0`), incremented once per second by two separate `Timer.scheduledTimer(withTimeInterval: 1, repeats: true)` blocks (lines 194-196 on .onAppear, and 448-450 inside navigateToChapter), and reset to 0 at lines 418/446 — but `grep -rn "sessionSeconds" Yomi` (whole project) shows zero other references anywhere in this file, in ReaderOverlayView, or in any other Swift file. The actual elapsed-time value persisted to the DB (ChapterQueries.updateProgress / MangaQueries readingSeconds, at lines 213-227, 401, 431) is computed independently via `Date().timeIntervalSince(sessionStart)`, not from `sessionSeconds` at all. So this Timer fires every second, mutating @State, forcing a SwiftUI re-evaluation of ChapterReaderView's body every second for the entire duration the reader is open, purely to update a value nothing ever reads. |
| 106 | 1379-line file mixing 5 distinct reader implementations, tap-zone layout logic, and a 216-line overlay view... | **[LOW/architecture]** S117: deliberately not fixed — a pure file split (tap-zone layouts, `ReaderOverlayView` + its 2 sheets into their own files) is mechanically low-risk but touches the exact reader code several other S117 fixes (#88-90, #105) just changed; safer as its own dedicated pass with a full re-verify afterward than bundled into this session's fix sweep. `Yomi/Features/Reader/ChapterReaderView.swift:1` — 1379-line file mixing 5 distinct reader implementations, tap-zone layout logic, and a 216-line overlay view (with two full inline Form/List sheets) with no test coverage to backstop future edits. Single file contains: ChapterReaderView (state/navigation/preload orchestration, ~490 lines), MangaReaderView + 6 inline tap-zone layout functions (lShapedZones/kindleZones/rightLeftZones/thirdsOrEdgeZones/edgeWeightedZones, ~225 lines), MangaPageView (pinch/zoom gestures), WebtoonReaderView, ChapterBoundaryCard, ContinuousHorizontalReaderView, VerticalPagedReaderView, and ReaderOverlayView (lines 1105-1321, ~216 lines, itself containing two full inline sheet bodies — a chapters List/NavigationStack and a Reader Settings Form/Picker). Given the project has zero automated tests (documented, known), a change to one reader mode's logic (e.g. the boundary-preload plumbing touched by S109-S111, or the tracker-update block above) has no isolation from the other 4 reader implementations and the overlay UI sharing the same file — a natural split point exists (e.g. tap-zone layouts into their own file, ReaderOverlayView + its two sheets into their own file) that would reduce the blast radius of future edits without changing behavior. |
| 107 | ~~updateUIView's style re-injection JS escapes backslash and backtick but not '$', so a '${...}' sequence ins...~~ | ✅ Fixed S117 — added a third `.replacingOccurrences(of: "$", with: "\\$")` escape step. **[LOW/security]** `iOS/Yomi/Features/Reader/TextReaderView.swift:543` — updateUIView's style re-injection JS escapes backslash and backtick but not '$', so a '${...}' sequence inside the interpolated style block would execute as a JS template-literal expression instead of rendering as literal CSS. Lines 543-556 build `existing.outerHTML = \`\(escaped)\`;` — a JS template literal — from `styleContent` after only `.replacingOccurrences(of: "\\", with: "\\\\")` and `.replacingOccurrences(of: "\`", with: "\\\`")`. Any `${...}` in `styleContent` would be evaluated as a JS expression by the WKWebView's JS engine rather than inserted as text. Not exploitable today — every value interpolated into the CSS (`fontSize` Int, formatted `lineSpacing`, `novelTheme.bg`/`.fg` from the fixed `YomiTokens.ReaderTheme` enum, and `AppSettings.shared.accentColor` drawn from a small fixed preset list) is app-controlled, not free-form user text — but it is an incomplete/incorrect escaping routine that would become a live self-XSS vector the moment any of those become user-enterable (e.g. a future custom-hex accent-color field). |
| 108 | MAL/Shikimori/Bangumi store an OAuth `refresh_token` but never use it — tracker sync silently dies forever once the access token expires | **[HIGH/correctness]** `Yomi/Features/More/MALService.swift:88` — all three exchange the auth code for both `access_token` and `refresh_token`, save both to Keychain, but no function anywhere ever POSTs `grant_type=refresh_token` (confirmed via repo-wide grep — `grant_type` is only ever `"authorization_code"`). `isLoggedIn` is set once at login and never re-validated against the server. Once the short-lived access token actually expires, every `searchManga`/`updateMangaProgress` call from the reader's auto-update path silently no-ops via the existing `try?`/guard pattern — no error surfaces anywhere, and the Trackers screen keeps showing "Connected" indefinitely. AniList is unaffected (Implicit Grant, no refresh_token, ~1yr token life by design). S117 audit workflow, verified. |
| 109 | None of the 4 tracker OAuth flows dismiss their `SFSafariViewController` sheet after a successful login | **[MEDIUM/ux]** `Yomi/Features/More/MALView.swift:29` — all 4 login screens (MAL/AniList/Shikimori/Bangumi) present the OAuth URL via a plain `.sheet(isPresented: $showSafari) { SafariView(url:) }` with no delegate. The `yomi://<host>/callback` redirect correctly routes through `TrackerManager.route(url:)` to set `isLoggedIn = true` on the service, but no view has any `.onChange(of: service.isLoggedIn)` to close the sheet — confirmed zero `onChange`/`dismiss` occurrences across all 4 files. Following a custom-URL-scheme redirect out of `SFSafariViewController` doesn't auto-dismiss (unlike `ASWebAuthenticationSession`, which Apple recommends for exactly this reason), so the Safari sheet stays covering the now-updated "Logged in as..." state until the user manually swipes it away. S117 audit workflow, verified. |
| 110 | `errorMessage` is set on tracker OAuth failure but never cleared, and AniList's `handleCallback` has no failure path at all | **[MEDIUM/error-handling]** `Yomi/Features/More/AniListTrackerService.swift:48` — MAL/Shikimori/Bangumi each set `errorMessage` in `handleCallback`'s catch block but never reset it (not on a fresh login attempt, not on a later successful login) — since these are `static let shared` singletons, a stale red error banner persists across app launches until another failure overwrites it. Separately, `AniListTrackerService.handleCallback`'s guard-return on a missing `access_token` fragment (denied consent, or an `#error=` fragment) leaves `errorMessage` untouched — it's assigned nowhere in the whole file except its `nil` declaration — so a failed AniList login gives the user zero feedback at all, unlike the other 3 trackers which at least show something (if often stale). S117 audit workflow, verified. |
| 111 | ~~Cancelling an in-progress chapter download still marks the chapter `isDownloaded=true` in the DB~~ | ✅ Fixed S119 alongside #149 — `performDownload` now checks `Task.isCancelled` after its page loop, removes the partial download directory and calls `markNotDownloaded`, instead of unconditionally marking the chapter Downloaded. Original finding: **[MEDIUM/correctness]** `Yomi/Features/More/DownloadManager.swift:213` — `cancel(chapterId:)` cancels the Task and resets `@Observable` state but sets no flag `performDownload(_:)` reads; that function has zero `Task.isCancelled` checks anywhere and unconditionally calls `markDownloaded(chapterId:)` + bumps `completedDownloadCount` once its page-download loop returns, regardless of whether cancellation cut it short. A chapter the user explicitly cancelled can end up showing the "downloaded" badge in `MangaDetailView` while missing some/all of its page files on disk — silently falling back to network or showing a broken partial page set, with no error surfaced. S117 audit workflow, verified. |
| 112 | `enqueue()` doesn't de-dupe against the currently-active download, only the pending queue | **[LOW/correctness]** `Yomi/Features/More/DownloadManager.swift:49` — `enqueue()` guards on `!chapter.isDownloaded` and `!items.contains(...)`, but `processQueue()` already removes the active item from `items` before it starts downloading, so re-tapping Download on the chapter that's actively downloading (reachable via `MangaDetailView`'s per-row swipe action, which — unlike the row's own inline download button — has no `activeChapterId`/queue guard) queues a redundant second full download that silently overwrites the first once it starts. S117 audit workflow, verified. |
| 113 | "Reset to defaults" in Appearance Studio doesn't reset `colorBlendLevel`, contradicting its own footer text | **[LOW/ux]** `Yomi/Features/More/AppearanceStudioView.swift:430` — `resetSection` resets canvas/accent/typography/library-display settings with a footer claiming it "Restores canvas, accent, typography, and library display to YOMI defaults," but never touches `settings.colorBlendLevel` (the "Blend into surfaces" slider directly above it on the same screen). A user who raised the blend slider still sees every canvas surface tinted after tapping Reset — the screen doesn't actually return to a clean default look as promised. S117 audit workflow, verified. |
| 114 | A manga/novel that was opened and partially read (never reaching 80%/90% completion) never appears in History | **[HIGH/correctness]** `Yomi/Database/Queries/ChapterQueries.swift:144` — `updateProgress(id:progress:readingSeconds:lastPageRead:)`, the function `ChapterReaderView`'s `.onDisappear` unconditionally calls on every reader close to persist resume position, never calls `MangaQueries.touchLastRead(mangaId:)` — only the ≥80%-completion `markChapterRead()` path does that. A manga opened and read a few pages of (well under 80%) correctly saves resume position but `Manga.lastReadAt` stays NULL forever, so it never shows up in `HistoryView` (which filters `WHERE lastReadAt IS NOT NULL`) despite being genuinely, recently read. The identical gap exists on the novel side (`NovelQueries.updateScrollPercent` also never touches `lastReadAt`). Distinct from the already-fixed Known Issue #20, which only covered the completion/manual mark-read call sites, not the ordinary in-progress save path. S117 audit workflow, verified. |
| 115 | The entire Trackers feature (More → Trackers + all 4 login screens) never wires `\.yomiCanvas`, unlike every sibling More-tab screen | **[MEDIUM/design-system]** `Yomi/Features/More/TrackersView.swift:13` — `TrackersView`'s body is a bare `List { ... }.listStyle(.insetGrouped)` with zero `\.yomiCanvas` references, plain system font styling, and the 4 login-destination views (`MALView`/`AniListView`/`ShikimoriView`/`BangumiView`) are equally unstyled — unlike `SettingsView`/`StorageView`/`MoreView`/`DownloadsView`/`InsightsView`/`UpdatesView`, which all wire the root List's background to `canvas.bg` and rows to `canvas.surface1`/`surface2`. Most visible for Paper/Sepia users (cream palette everywhere else in the app vs. a cool system gray List background here). Built S115 in one session that consistently missed the canvas pass every other screen already got. S117 audit workflow, verified. |
| 116 | `OPDSBrowseView` never wires `\.yomiCanvas`, and its 4 hand-rolled cover placeholders repeat the exact bug Known Issue #38 already fixed elsewhere | **[MEDIUM/design-system]** `Yomi/Features/Browse/OPDSBrowseView.swift:168` — the whole file has zero `\.yomiCanvas`/`canvas.`/`.background(` occurrences, so this OPDS-catalog screen renders with plain system List/ScrollView backgrounds regardless of the selected canvas. Additionally, 4 separate hand-rolled no-cover placeholders (lines 168/195/202/269) use `Color.secondary.opacity(0.3)` instead of the canvas-aware `CoverImage` placeholder — the identical "ignores canvas selection" bug #38 fixed specifically in `Core/CoverImage.swift`, but that fix never reached this file's own inline placeholders. S117 audit workflow, verified. |
| 117 | One icon-picker swatch in Appearance Studio is hardcoded `Color(.systemGray5)` in a file that otherwise consistently uses canvas tokens | **[LOW/design-system]** `Yomi/Features/More/AppearanceStudioView.swift:391` — the alternate-icon swatch placeholder fill is a fixed system gray while the rest of this exact file (which reads `canvas` live via `settings.blendedCanvasColors`) consistently uses `canvas.surface1`/`canvas.bg` for every other surface. On Ink (dark warm bg) this one swatch renders as a light gray square clashing with every other tile on the same screen — the screen dedicated to demonstrating the app's own visual identity. S117 audit workflow, verified. |
| 118 | `ChapterRow`/`ReadingStatusMenu` selection checkmark + badge use system `Color.secondary` instead of `canvas.textSecondary`, erasing the Ink-vs-Midnight warm/cool distinction | **[LOW/design-system]** `Yomi/Features/Library/MangaDetailView.swift:1241` — neither struct declares `@Environment(\.yomiCanvas)`, so `Color.secondary` renders identically for Ink (warm cream-gray `textSecondary`) and Midnight (cool white `textSecondary`) even though the design system explicitly differentiates them and both canvases force `colorScheme = .dark`. The identical pattern is duplicated in `NovelDetailView.swift:620` — notably that file *does* have `\.yomiCanvas` in scope and still bypasses it. S117 audit workflow, verified. |
| 119 | The scanlator filter-chip row hardcodes `Color.gray` for the unselected state even though `canvas` is already in scope on the same view | **[LOW/design-system]** `Yomi/Features/Library/MangaDetailView.swift:814` — `scanlatorChipRow` is a computed property on `MangaDetailView` itself (which has `@Environment(\.yomiCanvas) private var canvas` and uses it extensively elsewhere in the same file), but its `.tint(...)` calls at lines 814/821 hardcode `Color.gray` instead of a canvas-aware token like `canvas.textSecondary`. S117 audit workflow, verified. |
| 120 | `YomiScrubber` (the custom page/font-size slider used in both readers) has zero accessibility support — VoiceOver users cannot use it at all | **[HIGH/accessibility]** `Yomi/Core/YomiScrubber.swift:10` — a fully custom `GeometryReader`+`Capsule`/`Circle` slider driven purely by `DragGesture`, with no `.accessibilityElement()`, `.accessibilityLabel`, `.accessibilityValue`, or `.accessibilityAdjustableAction` (a native SwiftUI `Slider` gets all of this for free). Used at `ChapterReaderView.swift:1303` (manga page scrubber — the only way to jump to an arbitrary page) and `TextReaderView.swift:824` (novel font-size control) — both core reading-adjustment controls with no accessible alternative anywhere in the UI. S117 audit workflow, verified. |
| 121 | `TextReaderView`'s entire reader overlay has zero `accessibilityLabel` calls — every icon-only control is unlabeled | **[MEDIUM/accessibility]** `Yomi/Features/Reader/TextReaderView.swift:717` — `grep -n "accessibilityLabel" TextReaderView.swift` returns zero matches. Unlabeled: dismiss, open-chapters, view-source, font-family toggle, justify-text toggle, the 5 novel-theme swatch circles (color-only selection, same problem class as the accent picker), prev/next-chapter buttons, and the TTS play/pause toggle (never announces speaking state). Known Issue #70 already fixed the identical bug class for the *manga* reader's footer buttons — that fix never touched this sibling file. S117 audit workflow, verified. |
| 122 | The manga reader overlay's top-bar icon buttons (dismiss/chapters/source/settings) have no accessibility labels — a different set of controls than #70 already fixed | **[MEDIUM/accessibility]** `Yomi/Features/Reader/ChapterReaderView.swift:1138` — `ReaderOverlayView`'s top bar has 4 icon-only buttons (dismiss/chapters/source/settings) with no `.accessibilityLabel`, unlike the footer's prev/next-chapter buttons which #70 already labeled. VoiceOver reads the raw SF Symbol name ("chevron left") instead of anything meaningful ("Close reader"). S117 audit workflow, verified. |
| 123 | Shikimori/Bangumi's OAuth Authorization Code Grant has no `state` param and no PKCE — a login-CSRF that can silently sync a victim's reading activity into an attacker's tracker account | **[HIGH/security]** `Yomi/Features/More/ShikimoriService.swift:36` — ✅ verified S118 by reading `ShikimoriService.swift` directly: `authorizationURL()` sends no `state` param, `handleCallback` only extracts `code` from the URL with zero verification it was solicited by this app instance. Confirmed by contrast against `MALService.swift`, the cited working counterexample: MAL's `handleCallback` requires a locally-generated `codeVerifier` (stored in memory when the app itself opened the auth URL) to exchange the code — an attacker's own `code` fails that exchange. Shikimori/Bangumi have no equivalent check. Real exploit: attacker gets a valid `code` via their own login against the app's public `client_id`, gets victim to open `yomi://shikimori/callback?code=<attacker's code>`, app silently logs the victim's device into the attacker's account and pushes real reading history into it. Not yet fixed. |
| 124 | AniList's Implicit Grant `handleCallback` accepts any `access_token` in the redirect fragment with zero state/origin verification | **[HIGH/security]** `Yomi/Features/More/AniListTrackerService.swift:48` — ✅ verified S118 by reading `AniListTrackerService.swift` directly: `authorizationURL()` sends no `state`, `handleCallback` extracts `access_token` from the URL fragment and trusts it unconditionally. Implicit Grant has no code-exchange step, so there's no PKCE fallback available here even in principle — `state` is the only defense the flow has, and it's absent. Same exploit shape as #123: an attacker-obtained token delivered via `yomi://anilist/callback#access_token=...` silently logs the victim into the attacker's AniList account. Not yet fixed. |
| 125 | Chapter-update and reading-reminder push notifications show the real title on the lock screen regardless of App Lock/Secure Screen | **[MEDIUM/privacy]** `Yomi/Core/NotificationManager.swift:39` — ✅ verified S118 by reading `NotificationManager.swift` + both call sites (`UpdatesView.swift:206,281`, `YomiApp.swift:242`): `scheduleChapterNotification`/`scheduleReadingReminder` both put the real manga/novel title directly into `content.title`/`content.body` with zero `AppSettings.shared.appLockEnabled`/`secureScreenEnabled` check anywhere in the call chain — same threat model Known Issue #68 fixed for the Home Screen widget, never extended here. Not yet fixed. |
| 126 | ~~`DownloadManager.performDownload()` mutates `@Observable` state after multiple await points with no MainActor hop~~ | ✅ **Refuted S118 — not a bug.** `Yomi.xcodeproj/project.pbxproj` sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` project-wide (Xcode 26 "Approachable Concurrency"), and `DownloadManager` (like `BackupManager` and all 4 tracker services, #127/#128) is a plain class with no `nonisolated` at the type level — only specific methods that genuinely need to escape MainActor are marked `nonisolated` (e.g. `directorySize`, `JSBridge.bridge(for:)`). Under this setting, every method on these classes IS MainActor-isolated by default and correctly resumes on MainActor after any `await` that doesn't itself hop actors (`Task.detached { ... }.value` included — the detached body runs off-actor, but the awaiting call site resumes on its own actor). The cited comment ("already on MainActor — direct assignment") is accurate, not wrong. The finder agent never checked this build setting before asserting a violation — same root-cause miss as the now-refuted #130. |
| 127 | ~~`BackupManager` mutates `@Observable` iCloud/export state after real await points across every method~~ | ✅ **Refuted S118 — not a bug, same reasoning as #126.** `BackupManager` has no type-level `nonisolated`; only specific `static let`s are `nonisolated`. MainActor-isolated by default via `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. |
| 128 | ~~All 4 tracker services mutate login state after `await URLSession.shared.data(for:)` with no MainActor hop~~ | ✅ **Refuted S118 — not a bug, same reasoning as #126.** MALService/AniListTrackerService/ShikimoriService/BangumiService are all plain `@Observable final class` with no type-level `nonisolated` — MainActor-isolated by default. |
| 129 | The Home Screen widget's "last chapter" field is a hardcoded literal string ("Continue reading"), not the user's actual last-read chapter | **[MEDIUM/correctness]** `Yomi/Features/Library/LibraryViewModel.swift:227` — ✅ verified S118 by reading `writeWidgetData()` directly: line 227 hardcodes `lastChapter: "Continue reading"` for every entry — never queries `ChapterQueries`/`NovelQueries` for the real last-read chapter, contradicting the widget's own placeholder data (`"Chapter 1100"`). Not yet fixed. |
| 130 | ~~All 15 production plugin `.js` files are bundled directly into the shipped binary~~ | ✅ **Refuted S118 — not a bug, claim was backwards.** Read `project.pbxproj` directly: `membershipExceptions` inside a `PBXFileSystemSynchronizedBuildFileExceptionSet` is an **exclusion** list, not an inclusion list — it lists files the synchronized-folder mechanism otherwise-auto-includes that are explicitly excluded from that target's bundle resources, applying uniformly to both Debug and Release (confirmed against S78's own changelog language: "10 additional plugin JS files added to membershipExceptions... now excluded from the Release build bundle", and `seedBundledPlugins()`'s own doc comment: "In production the .js files are not bundled, so all guard checks silently skip (safe no-op)"). All 15 `.js` files (plus `test-source.js`) appear exactly once in the file, inside this exclusion list — no separate resources-phase entry bundles them. CLAUDE.md's/ARQUITECTURA.md's "zero plugin files ship in the binary" claim holds. |
| 131 | `SuwayomiService`'s detail/chapters/page-count REST methods have zero call sites — a Suwayomi manga's chapters can never load from `MangaDetailView` | **[HIGH/correctness]** `Yomi/Features/Extensions/SuwayomiService.swift:100` — ✅ verified S118, and worse than filed (upgraded from MEDIUM/dead-code to HIGH/correctness — a real functional bug, not just dead code). `fetchMangaDetail`/`fetchChapters(mangaId:)`/`fetchChapterPageCount`/`suwayomiMangaId(from:)` have zero call sites anywhere outside their own file (confirmed by grep). `SuwayomiBrowseView.swift:95` navigates a tapped Suwayomi manga to the shared `MangaDetailView`, which has zero `Suwayomi` references and no Suwayomi-specific handling anywhere. `SuwayomiService.toManga(item:sourceId:)` sets `sourceId: "suwayomi_\(sourceId)"` (line 130) — this can never match an entry in `ExtensionManager.shared.installed` (real JS-plugin ids like `"mangadex"` or sha256 hashes), so `MangaDetailView.loadChapters()`'s guard (`ExtensionManager.shared.installed.first(where: { $0.id == sourceId })`, line 998) always fails for a Suwayomi-sourced manga, falling into the "extension not installed" branch that only shows whatever's already cached in the local DB (empty for any manga not yet added to the library, since `toManga` sets `inLibrary: false`). Concrete effect: tapping any Suwayomi manga from Browse → detail shows no chapters, ever, with no error surfaced. Not yet fixed. |
| 132 | `MangaDetailView.formatReadingTime(_:)` is an orphaned duplicate helper, the same shape as the already-fixed Known Issue #104 in `NovelDetailView.swift` | **[LOW/dead-code]** `Yomi/Features/Library/MangaDetailView.swift:971` — ✅ verified S118 — zero call sites in the file besides its own definition. Not yet fixed. |
| 133 | Three `Notation.swift` formatters (`volumeChapter`/`novelIndex`/`novelFooter`) have had zero call sites since S80 | **[LOW/dead-code]** `Yomi/Core/Notation.swift:25` — ✅ verified S118 — repo-wide grep finds each name only at its own declaration, no Swift call sites anywhere. Not yet fixed. |
| 134 | `UpdatesViewModel`'s single-chapter mark-read methods have zero call sites — only the "mark all" siblings are wired to any UI | **[LOW/dead-code]** `Yomi/Features/More/UpdatesView.swift:49` — ✅ verified S118 — `markAllMangaChaptersRead`/`markAllNovelChaptersRead` are called from the view body (lines 489/506), `markMangaChapterRead`/`markNovelChapterRead` (single-chapter siblings, lines 49/64) have zero call sites anywhere. Not yet fixed. |
| 135 | `AniListTrackerService.redirectURI` is declared but never used, unlike the identical pattern in all 3 sibling tracker services | **[LOW/dead-code]** `Yomi/Features/More/AniListTrackerService.swift:16` — ✅ verified S118 — appears only at its own declaration in the file; MAL/Shikimori/Bangumi all pass their `redirectURI` into `redirect_uri` request params, AniList's Implicit Grant `authorizationURL()`/`handleCallback` never reference it. Not yet fixed. |
| 136 | `AdvancedSettingsView.showClearConfirm` is an unused `@State Bool` — the "Clear plugin catalog cache" button it was presumably meant to confirm fires with no confirmation dialog at all | **[LOW/dead-code]** `Yomi/Features/More/AdvancedSettingsView.swift:11` — ✅ verified S118 — the button (line 32) calls `PluginCatalogService.shared.invalidateCache()` directly with no `.confirmationDialog`/`.alert` anywhere in the file referencing `showClearConfirm`. Not yet fixed. |
| 137 | `MigrateView`'s `debounceTask` is an unused `@State Task?` — vestigial state from a debounce mechanism never implemented | **[LOW/dead-code]** `Yomi/Features/Library/MigrateView.swift:69` — ✅ verified S118 — appears only at its own declaration, never assigned or cancelled anywhere else in the file. Not yet fixed. |
| 138 | ~~`BackupManager.importBackup(from:)` restores a backup entirely on the main thread with per-row writes — a large library restore hangs the UI~~ | ✅ Fixed S119 — the file read, JSON parse and model decoding now run in `Task.detached` via a new `nonisolated static decodeBackup(at:)` (returning a `Sendable DecodedBackup`), and every restored row is written inside a **single** `appDatabase.write` transaction instead of one transaction per `*Queries.upsert` call. CloudKit dirty-marking moved to one `markCloudDirtyBatch` per record type. The ~24,000-transaction main-thread restore is now one transaction off MainActor. Original finding: **[HIGH/performance]** `Yomi/Features/More/BackupManager.swift:270-330` — verified S118. Every `mangaDicts`/`chapterDicts`/`novelDicts`/`novelChapterDicts` loop calls `MangaQueries.upsert`/`ChapterQueries.upsert`/`NovelQueries.upsert`/`NovelQueries.insertAllIgnoringConflicts([chapter])` **one row at a time** with zero `Task.detached` anywhere in the function — unlike `uploadToICloud()`/`downloadFromICloud()` in the same file, which correctly detach their I/O. `BackupManager` has no type-level `nonisolated` (confirmed against the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting, same as the now-refuted #126-128), so this genuinely runs on MainActor. Each `ChapterQueries.upsert`/`NovelQueries.insertAllIgnoringConflicts` call is its own synchronous `appDatabase.write` transaction plus a separate `markCloudDirty` write (`CloudSyncManager.swift:368-374`). Concrete scenario: restoring a backup for a ~150-manga/~12,000-chapter library issues 24,000+ sequential synchronous SQLite transactions directly on the main thread — the app is fully unresponsive for the whole restore. |
| 139 | `BackupManager.buildBackupData()` synchronously JSON-encodes the entire library on the main thread | **[MEDIUM/performance]** `Yomi/Features/More/BackupManager.swift:129-157` — verified S118. DB reads correctly use `await appDatabase.read`, but the subsequent `mangas.map { encodeManga($0) }` etc. + `JSONSerialization.data(withJSONObject:options: .prettyPrinted)` run with no `Task.detached`, directly on MainActor (same isolation reasoning as #138). Called from `exportBackup()` and `uploadToICloud()`, both `await`ing it directly on MainActor before the file-write step (which IS correctly detached). `.prettyPrinted` adds needless overhead for a machine-only backup format. Causes a visible freeze on "Export Backup"/"Upload to iCloud" for a large library. Not yet fixed. |
| 140 | `BackupManager.exportTachiyomiBackup()` does one DB round-trip per library manga instead of one bulk query, on the main thread | **[MEDIUM/performance]** `Yomi/Features/More/BackupManager.swift:110-116` — verified S118: `for manga in mangas { chaptersByMangaId[manga.id] = try ChapterQueries.fetchAll(mangaId: manga.id) }`, no `Task.detached` anywhere in the function, so it runs on MainActor. N+1 pattern — for a 200-manga library, 200 sequential synchronous DB reads instead of one bulk `SELECT ... WHERE mangaId IN (...)` grouped client-side. Not yet fixed. |
| 141 | `UpdatesView`'s "mark all read" issues 4 separate write transactions per chapter, reimplementing what `ChapterQueries.markAllRead` already does in one bulk UPDATE | **[MEDIUM/performance]** `Yomi/Features/More/UpdatesView.swift:57-61,72-76` — verified S118. `markAllMangaChaptersRead`/`markAllNovelChaptersRead` loop `ids.forEach { ChapterQueries.setRead(...) }`; `setRead` (`ChapterQueries.swift:110-127`) does its own `appDatabase.write` (UPDATE) + `markCloudDirty` (its own write) + `MangaQueries.touchLastRead` (its own write + its own `markCloudDirty` write) = 4 writes per chapter. The codebase already has the correct batched pattern one function over — `ChapterQueries.markAllRead(mangaId:)` (`ChapterQueries.swift:131-141`) does one bulk `UPDATE ... WHERE mangaId = ?` + one `markCloudDirtyBatch` call — but `UpdatesView`'s "mark all read for these specific ids" path never uses it. Concrete scenario: tapping "Mark all read" on a series with 20+ piled-up chapters issues 80+ sequential write transactions where ~3 would do. Not yet fixed. |
| 142 | Novel reader's scroll-position autosave issues 2-3 separate write transactions per debounced scroll pause, with no coalescing | **[MEDIUM/performance]** `Yomi/Features/Reader/TextReaderView.swift:206-213` — verified S118. `onScrollUpdate` fires `NovelQueries.updateScrollPercent(chapterId:percent:)` inside `Task.detached(priority: .background)` on every JS-side 400ms debounce tick. `updateScrollPercent` (`NovelQueries.swift:212-223`) does one `appDatabase.write` (UPDATE + a SELECT novelId) then `markCloudDirty` — itself `rememberMapping`'s own write, plus a third `markPending` write if `cloudSyncEngine` isn't running yet. Fires repeatedly throughout a reading session with no in-app coalescing or "already dirty" check, unlike the manga reader (`ChapterReaderView.swift`), which only persists progress once on `.onDisappear`. Runs in the background (doesn't freeze the UI) but is a real, avoidable multiplication of write I/O. Not yet fixed. |
| 143 | `MigrationService.migrate` does an O(n·m) linear chapter-number match plus up to 2 separate write transactions per matched chapter | **[MEDIUM/performance]** `Yomi/Features/Library/MigrationService.swift:44-62` — verified S118: `freshNewChapters.first(where: { $0.chapterNumber == oldNum })` runs inside `for oldCh in readOldChapters`, a linear scan repeated per already-read old chapter instead of building a `[Double: Chapter]` dictionary once. Each matched chapter can trigger `setRead` (see #141's write cascade) plus a separate `updateProgress` call. Concrete scenario: migrating a completed, fully-read 1000-chapter series issues on the order of 2,000-3,000 individual serialized write transactions. Runs inside `Task.detached` at the call site (`MigrateView.swift:295-296`) so the UI doesn't freeze, but the "Migrating…" spinner runs materially longer than necessary. Not yet fixed. |
| 144 | `novel_chapter` has no index on `isRead`, unlike its `chapter`-table counterpart — `fetchUnreadCountsByNovel()` does a full table scan on every Library load | **[LOW/performance]** `Yomi/Database/DatabaseManager.swift` (v18_indexes migration) — verified S118: `idx_chapter_unread` exists on `chapter(mangaId, isRead)` but no equivalent index exists on `novel_chapter`, confirmed by reading the full index list in `DatabaseManager.swift`'s migrations (`idx_chapter_mangaid`, `idx_chapter_unread`, `idx_novel_chapter_novelid`, `idx_manga_sourceid`, `idx_novel_sourceid` — none touch `novel_chapter.isRead`). `NovelQueries.fetchUnreadCountsByNovel()` (`NovelQueries.swift:135-147`) does `SELECT novelId, COUNT(*) FROM novel_chapter WHERE isRead = 0 GROUP BY novelId`, run on every `LibraryViewModel.loadLibrary()` call. Direct violation of this repo's own ABSOLUTE RULE ("every new `WHERE column = ?` query pattern on a large table needs a corresponding index"). Fixable with a new `v22_` migration adding `idx_novel_chapter_unread` on `novel_chapter(novelId, isRead)`. Not yet fixed. |
| 145 | ~~A manual or background chapter-update check reports "No new chapters" identically whether nothing is new or the fetch itself failed~~ | ✅ Fixed S119 — `checkUpdates(for:)`/`checkNovelUpdates(for:)` now return `Bool` (did the fetch fail, as opposed to being skipped or finding nothing), `refresh()` counts them into a new `UpdatesViewModel.failedSourceChecks`, and `runRefresh()`'s summary banner appends "· N sources failed". A library title always has ≥1 chapter upstream, so an empty remote list is treated as a real failure. **Live-verified**: seeded a library novel on the dead LightNovelPub source alongside a working MangaDex manga, tapped Refresh, banner read "No new chapters · 1 source failed" — counting the dead source and correctly *not* counting the healthy one. Original finding: **[HIGH/error-handling]** `Yomi/Features/More/UpdatesView.swift:179-183,245-249` — verified S118: `guard !remoteChapters.isEmpty else { return }`, where `remoteChapters` comes from `bridge?.getChapterList(...) ?? []` — every JS-side plugin `catch(e) {}`/`catch(e) { return []; }` (confirmed across `JSBridge.swift`) and `context.exceptionHandler` (`JSBridge.swift:64-67`, only `print()`s) swallow the real failure, so a Cloudflare block, rate-limit, or network error returns `[]` exactly like "genuinely nothing new." `runRefresh()`'s summary banner (`UpdatesView.swift:516-524`) is purely `newCount == 0 ? "No new chapters" : "N new chapters found"` — no per-source failure count anywhere. A user's temporarily-blocked or rate-limited source (common per #9/#11/#69/#86) silently reports success on both manual refresh and the #31 background check, and the user has no way to know a check even failed. |
| 146 | `BrowseView`'s Suwayomi/OPDS root-list load failures are indistinguishable from "nothing configured yet" | **[MEDIUM/error-handling]** `Yomi/Features/Browse/BrowseView.swift:286-327` — verified S118: `loadSuwayomiSources()`/`loadOPDSRoot()`/`loadMoreOPDSRoot()`'s `catch` blocks only reset the loading flag (`await MainActor.run { suwayomiLoading = false }` etc.), never set any error state. Contrast with the sibling `OPDSBrowseView.swift:231-233`'s `catch` on the identical kind of fetch, which does set `errorMessage = error.localizedDescription`. A user whose self-hosted Suwayomi/OPDS server is unreachable gets the same "Load sources"/"Load library" empty-state button shown when the feature has simply never been loaded, with zero indication why. Not yet fixed. |
| 147 | ~~All 4 tracker services' `updateMangaProgress` never surfaces failure anywhere, not even to their own `errorMessage`~~ | ✅ Fixed S119 — new shared `MangaTracker.sendProgressUpdate(_:graphQL:)` protocol extension replaces the `try? await URLSession...` call in all 4 services: it `do/catch`es, checks for a non-2xx status, checks AniList's GraphQL `errors` array inside an HTTP 200, and writes the outcome to `errorMessage` (clearing it on success, which also closes the stale-banner half of #110). `TrackersView`'s rows now render that message in red under a connected tracker, so a silently-failing sync is visible without drilling into the tracker's own screen. Original finding: **[HIGH/error-handling]** `Yomi/Features/More/MALService.swift:132-143`, and identically in `AniListTrackerService.swift`, `ShikimoriService.swift`, `BangumiService.swift` — verified S118 by reading all 4: `if let (data, response) = try? await URLSession.shared.data(for: request) { yomiLogNetwork(...) }` — no HTTP status check, no `catch`, and unlike every login/`handleCallback` path in the same files, this method never touches `errorMessage` on any outcome. Called fire-and-forget from both readers (`ChapterReaderView.swift:234-240`, `TextReaderView.swift:195-197`). A distinct, broader gap than #108 (refresh-token unused) — even with a valid, non-expired token, any transient failure (401, 429 rate-limit, network error) of the actual progress-write call is invisible everywhere, for all 4 trackers, every time. |
| 148 | ~~A migration whose new-source chapter fetch silently fails reports success and can delete the old library entry + downloaded files, leaving the manga with zero chapters~~ | ✅ Fixed S119 — `MigrationService.migrate` now fetches the new source's chapter list **first** and throws a new `MigrationError.noChaptersFromNewSource` when it comes back empty, before any write happens — so a failed migration can no longer delete the old entry or its downloads (`MigrateView` already had a "Migration failed" alert wired to that throw). `Result` also gained `newChapterCount`, and the confirmation screen now always states the new source's real chapter count instead of only a green checkmark. Original finding: **[HIGH/error-handling]** `Yomi/Features/Library/MigrationService.swift:33-36,64-76` — verified S118: `bridge.getChapterList(...)` returns `[]` on failure with no throw (same JS-exception-swallowing as #145), so `migrate()` completes "successfully" with 0 chapters persisted for the new source. `MigrateView.swift`'s `migratedConfirmation` (lines 211-227) only ever shows a green "Migrated" checkmark + a read-chapter-carryover message — never checks or mentions the new source's actual chapter count. The default "Replace" button (`MigrateView.swift:129`, `removeOld: true`) then deletes the old library entry and its downloaded files (`MigrationService.swift:66-76`) in the same action, per the code's own "Tachimanga replace convention" comment. Net effect: a transient fetch failure during migration looks fully successful and can strand the user with a chapterless manga after deleting the working original. |
| 149 | ~~`DownloadManager` marks a chapter fully "Downloaded" even when individual pages silently failed to fetch or write~~ | ✅ Fixed S119 — the page loop now counts a page as landed only when both the fetch and the `data.write(to:)` succeed; `markDownloaded` runs only when zero pages failed, otherwise the chapter is marked not-downloaded and a new `DownloadManager.failureMessage` reports "N of M pages failed to download" (surfaced via `.yomiToast` in `DownloadsView` and `MangaDetailView`). An empty page list — the plugin fetch having failed — is reported the same way instead of dropping out of the queue silently. **Also closes #111** in the same code path: a cancelled download now deletes its partial directory and marks not-downloaded instead of unconditionally marking the chapter Downloaded. Original finding: **[HIGH/error-handling]** `Yomi/Features/More/DownloadManager.swift:180-184,216` — verified S118: `let data = try? await URLSession.shared.data(from: url).0` and `try? data.write(to: fileURL)` both silently drop failures inside the `withTaskGroup` page-download loop — `completed` still increments and `progress` still reaches 100% regardless. After the loop, `try? DownloadQueries.markDownloaded(chapterId: chapterId)` (line 216) runs **unconditionally**, with no check of how many of `total` pages actually landed on disk. `DownloadManager.localURLs(for:)` later returns only the files that exist, with no signal anywhere the download was partial. Concrete scenario: a chapter downloaded over a flaky connection shows the "Downloaded" badge, and offline reading silently gets fewer pages than the chapter actually has, with no error or retry prompt. |
| 150 | `LibraryViewModel.errorMessage` is set on a DB-read failure but never read/displayed anywhere — the Library tab just looks empty | **[MEDIUM/error-handling]** `Yomi/Features/Library/LibraryViewModel.swift:184-203` — verified S118: `loadLibrary()`'s `catch` branch sets `errorMessage = error.localizedDescription` (via the `result.4` tuple slot), but `grep -n "errorMessage"` across `LibraryView.swift` returns zero matches — the property is written but never read, and the file has zero `.yomiToast`/`YomiToast` usage (confirmed by grep), unlike the already-fixed #26 paths. If `MangaQueries.fetchLibrary()` throws (DB corruption, disk I/O error), the app's primary screen silently renders its normal empty-library state, indistinguishable from "you haven't added anything yet." Not yet fixed. |
| 151 | No integrity/authenticity check anywhere in the trust chain from the Firebase-hosted plugin catalog to JSCore execution | **[MEDIUM/security]** `Yomi/Features/Extensions/PluginCatalogService.swift:6-20`, `Yomi/Features/Extensions/ExtensionManager.swift:125-176` — verified S118 by reading both files directly: `PluginCatalogEntry`'s schema (`id, name, version, language, description, iconURL, fileURL, isNSFW, repoURL, isNovel`) has no checksum/signature field, and `ExtensionManager.install()` does `try data.write(to: localURL)` on whatever bytes the fetch returns, with zero hash comparison or code signing check. HTTPS + HSTS is confirmed live on the hosting domain (independently `curl -I`'d this session), but that's the *only* protection between "whatever is on the Firebase project right now" and "arbitrary JS that runs in JSCore with real outbound network capability via `SOURCE._fetchSync`/`SOURCE.fetch` (`JSBridge.swift:832-931`, no domain allowlist)." A compromise of Firebase deploy credentials (or a MITM presenting a trusted cert, e.g. a corporate/school TLS-inspection proxy) can silently modify any plugin file or the catalog itself; every app instance picks it up on next catalog refresh/install with zero user-visible signal. Not yet fixed. |
| 152 | No content validation before a plugin install/update overwrites a previously-working plugin, and no backup-before-overwrite | **[MEDIUM/correctness]** `Yomi/Features/Extensions/ExtensionManager.swift:155-158` — verified S118 (same code read as #151): `install()` writes downloaded bytes straight to `localURL` with no check that `JSBridge(scriptURL:)` would even successfully parse/evaluate the result, and no backup of the prior working file. A truncated download, a transient CDN error served as `200`, or a bad `firebase deploy` silently replaces a working plugin with broken/empty content — discovered later only when the source stops returning results, no error at install time, no rollback path. Not yet fixed. |
| 153 | Firebase Hosting's server-side/CDN cache-control creates a staleness window the S87 client-side fix (#9) never closed | **[MEDIUM/architecture]** `/Users/martingamberg/Desktop/Projects/Yomi/Firebase/firebase.json` — verified S118, including live `curl -I` against `https://yomi-plugins.web.app/index.json` and `/mangadex.js`, both confirming `cache-control: max-age=3600` served through a Fastly CDN edge (`x-served-by: cache-eze...`), and `firebase.json` confirmed to have no `"headers"` block at all (Firebase Hosting's unmodified default). Known Issue #9 already fixed this exact header value's *client-side* staleness (adding `.reloadIgnoringLocalCacheData` to `PluginCatalogService.fetchCatalog(force:)`/`ExtensionManager.install()`) — but that only bypasses the device's own `URLCache`. It does nothing about the **CDN edge cache**, which independently holds the pre-deploy response at each edge POP for up to an hour after `firebase deploy`, regardless of what cache policy the requesting client sets (Firebase Hosting's CDN cache is keyed by the origin's own `Cache-Control` header). Net effect: after any bugfix deploy, there's still up to a 1-hour window, purely server-side, where different users (or the same user hitting a different edge POP) can nondeterministically get the still-broken version even with every client-side fix working correctly. Fixable with an explicit `"headers"` block in `firebase.json` (shorter `max-age` + `must-revalidate`, or content-hashed filenames) — a deploy-config change, not app code. Not yet fixed. |
| 154 | `PluginCatalogService.parseEntries` schema validation is all-or-nothing per catalog URL — one malformed entry silently zeroes the entire catalog with a misleading error | **[MEDIUM/correctness]** `Yomi/Features/Extensions/PluginCatalogService.swift:179-192` — verified S118: `try? JSONDecoder().decode([PluginCatalogEntry].self, from: data)` — Swift's synthesized `Array<Decodable>` decode throws on the *first* element that fails (standard Foundation behavior), so one entry with a wrong-typed or missing required field aborts the whole-array decode; `try?` then falls through to the LNReader-format attempt, then Mangayomi-format, both of which also fail against Yomi's own schema, ultimately returning `[]` for that entire catalog URL. If it's the only configured URL, the user sees the generic `"Could not load any catalog. Check your repository URLs."` (line 171) for what could be a single typo in one of 15 JSON objects — the message actively misleads about the actual cause. Not yet fixed. |
| 155 | `PluginCatalogService.fetchCatalog`'s multi-URL merge order is nondeterministic (network-completion order), not the configured-URL order its own doc comment implies | **[LOW/architecture]** `Yomi/Features/Extensions/PluginCatalogService.swift:105,127-163` — verified S118: the doc comment says "merges by id (first-wins)"; the merge loop (`for batch in results { for entry in batch { if seen.insert(entry.id).inserted {...} } }`) operates on `results`, built via `for await result in group { all.append(result) }` inside a `withTaskGroup` — `TaskGroup` yields child-task results in completion order, not submission order, so "first" means "whichever configured catalog URL's response lands first," not "the first URL in `AppSettings.shared.pluginCatalogURLs`." If two configured catalogs ever publish an entry sharing the same `id`, which one wins is a timing race that can flip between app launches. No known real-world id collision today — low severity, but a genuine ambiguity between the implied and actual precedence, worth documenting explicitly in the doc comment. Not yet fixed. |
| 156 | A stale, partially-overlapping duplicate of the Firebase `public/` directory (`yomi-firebase/`) sits at the project root with 4 of 6 shared plugin files older than production | **[LOW/hygiene]** `/Users/martingamberg/Desktop/Projects/Yomi/Firebase/yomi-firebase/public/` — verified S118 via direct `diff`: contains its own dated-Apr-2026 `index.json` (only 6 of the 15 production plugins, stale `lightnovelpub` iconURL domain — confirmed `lightnovelpub.vip` vs. the live catalog's `.com`) plus `babelnovel.js, mtlnovel.js, boxnovel.js, novelhall.js, lightnovelpub.js, readwn.js`. Direct `diff` against the live `public/` versions confirms `mtlnovel.js`, `boxnovel.js`, `novelhall.js`, `readwn.js` are all different/stale; only `babelnovel.js`/`lightnovelpub.js` happen to match. Has no `firebase.json`/`.firebaserc` of its own (can't be deployed as-is) but is a landmine for a future `cp` that reintroduces already-fixed plugin bugs by mistake. Worth deleting or clearly labeling as an abandoned scaffold. Not yet fixed. |
| 157 | `ARQUITECTURA.md`'s Firebase Hosting file tree lists only 9 of the 15 claimed production plugins | **[LOW/docs]** `Yomi/ARQUITECTURA.md:479-490` — verified S118: the tree lists `mangadex.js, asurascans.js, aquamanga.js, royalroad.js, scribblehub.js, novelfire.js, freewebnovel.js, novelbin.js, novelfull.js` (9 files, and `novelfull.js` doesn't even match any real production filename — the actual 15th-adjacent files are `boxnovel`/`mtlnovel`/`babelnovel`/`novelhall`/`readwn`/`lightnovelpub`, all six missing from this tree). Directly contradicts the same document's own Resources/ comment 358 lines earlier (which correctly lists all 15) and CLAUDE.md:6's "Firebase CDN hosts all 15 production plugins." Not yet fixed. |
| 158 | `TACHIMANGA_PARITY.md` has 7 more stale `AppSettings.swift`/`ChapterReaderView.swift`/etc. line citations, same recurring pattern as the already-fixed #65 | **[LOW/docs]** `Yomi/TACHIMANGA_PARITY.md` — verified S118 by checking each citation directly: `autoWebtoonFromTags` (claimed `AppSettings.swift:203`, actually **306**), `autoScrollSpeed` (claimed `:242`, actually **366**), `keepScreenOn` (claimed `ChapterReaderView.swift:192,199`, actually **191,195**), `webtoonHorizontalPadding` (claimed `:247`, actually **371**), `showNSFW` (claimed `:80`, actually **123**), `libraryColumns` stepper (claimed `AppearanceStudioView.swift:355`, actually **377**), `deleteDownloadAfterReading` (claimed `SettingsView.swift:209`, actually **225**). Every property/UI still exists and works as described — only the line numbers drifted after later insertions shifted them. Not yet fixed. |
| 159 | `ROADMAP.md`'s "Target plugin sources" table is stale and self-contradicts the same file's own Technical debt table 60 lines later | **[LOW/docs]** `Yomi/ROADMAP.md:2188-2199` (table) vs. `:2132` (contradicting entry) — verified S118: the leftover S20-era table claims `| Comick | Format A (JSON API) | ✅ Working — on Firebase |`, while the same document's Technical debt table, 60 lines earlier, lists `| Comick blocked by Cloudflare | api.comick.dev returns 403 from non-browser clients... | Medium |`, and `ARQUITECTURA.md:491` confirms `comick.js removed`. The table also lists a `NovelUpdates` plugin that was never built and isn't in the real 15-plugin catalog. Not yet fixed. |
| 160 | `ARQUITECTURA.md`'s `YomiEmptyState` call-site count is stale (claims 12, actually 16, and omits a whole file) | **[LOW/docs]** `Yomi/ARQUITECTURA.md:110` — verified S118 by grepping every `YomiEmptyState(` call site: `BrowseView.swift` ×6, `LibraryView.swift` ×2, `MigrateView.swift` ×2, `OPDSBrowseView.swift` ×2, `CategoryView.swift` ×1, `DownloadsView.swift` ×1, `UpdatesView.swift` ×1, `HistoryView.swift` ×1 = **16 total across 8 files** — the doc claims "12... Library, Categories, Downloads, Updates, Browse ×4, OPDS ×2, History" and omits `MigrateView.swift` (added later, S98's Migrate tab) entirely. Not yet fixed. |
| 161 | `RESEARCH.md`'s "Last updated" banner is stale again — same issue #64 already fixed once, drifted stale a second time | **[LOW/docs]** `Yomi/RESEARCH.md:2` — verified S118: banner reads "2026-08-07 (S104 §5...)" but `## 20. Competitor Deep-Dive...` (line 993, dated S114/2026-08-18) and `## 21. Tracker API Shapes...` (line 1052, dated S115/2026-08-19) were both added after that date with no banner update. Nothing enforces updating this line when new sections are appended — worth remembering as a recurring pattern, not a one-time fix. Not yet fixed. |
| 162 | `Yomi/design/DESIGN_HANDOFF.md` is a frozen S79 snapshot with every checklist still unchecked, but CLAUDE.md still calls it "start here for design/publish work" | **[LOW/docs]** `Yomi/design/DESIGN_HANDOFF.md:1-2,40-78` vs. `CLAUDE.md:30` — verified S118: the file is dated "Session S79 · 2026-07-16" and its Phase 1-5 roadmap tables show every step as `⬜` (Build + verify on simulator, Update DesignTokens.swift, Build the Appearance Studio, Apply components + screens, etc.) — all of which CLAUDE.md's own current-state record confirms were completed through S82-S95 ("Design track... all 12 blocks complete as of S95"). A session following this file's own "start here" checklist literally would be redoing 39+ sessions of already-shipped work. No functional/code impact, but a real navigational trap given CLAUDE.md actively directs sessions here first. Not yet fixed. |

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
- Next migration prefix must be `v22_` (v21_cloud_sync_pending added in S105 — durable dirty-mark queue + pending chapter-state stash, see Known Issues #41/#43)
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
