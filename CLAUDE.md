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

## Design track (S82-S95 — all 12 blocks complete)

All 16 screens designed and confirmed. Concept: **"reading instrument / living archive"** — warm editorial canvas, covers + user accent are the only color, monospace catalog notation, ink/screentone signature. Confirmed: default accent **Vermilion `#E5473A`**, default canvas **Ink (`#14110F`)**, Space Grotesk (UI) + Space Mono (notation), Newsreader serif (novel body). Design tokens live in `DesignTokens.swift`; canvas colors are wired app-wide via `\.yomiCanvas` environment (`CanvasEnvironment.swift`, set from `AppSettings.canvasColors`); notation helpers in `Notation.swift`; Appearance Studio in `AppearanceStudioView.swift`. **Full design spec**: `Yomi/design/design_handoff_yomi/YOMI Screens.dc.html` — 16 screens as HTML with inline CSS. App icon assets: `AppIcon-Ink.png` + `AppIcon-Paper.png` in `Yomi/design/design_handoff_yomi/assets/`. **All 12 blocks complete as of S95 (2026-08-05).** Blocks 1-5 screenshot-verified S85; Block 6 (Browse) S86; Block 7 (History) S91; Block 8 (Updates) S92; Block 9 (Downloads) S93; Block 10 (Insights) S94; Blocks 11-12 (More/Settings/Onboarding/empty states) S95. **S96 (2026-08-06): the full functional audit Martin asked for, done.** App Store screenshot work is unblocked. **S97-S98: Tachimanga feature-parity pass, complete — see below.**

## Current state (post S115 — 2026-08-19 · novel chapter-preload + full tracker-sync generalization)

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
