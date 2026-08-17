# Roadmap — Yomi

## Strategic Goal (defined S44 research audit, 2026-04-20)

> **Make Yomi the most source-diverse iOS manga + novel reader by running plugins from every existing ecosystem — without maintaining them ourselves.**

The research audit revealed that 800+ sources are already available across four compatible JS plugin formats. Yomi currently deploys 15 hand-written plugins from Firebase. The correct strategy is not to write more plugins — it is to unlock the community ecosystems that already exist:

| Ecosystem | Format | Sources available | Yomi status |
|-----------|--------|-------------------|-------------|
| Yomi Firebase | Format A | 15 | ✅ Live |
| LNReader | Format B | **500+ novels** | ✅ Native, needs UX/docs |
| Paperback | Format C | ~100 manga | ⚠️ Partial shim |
| Mangayomi | Format D (Dart) | 195+ manga+novel | ❌ Dart extensions — cannot run in JSC |
| keiyoushi/Suwayomi | Backend | Hundreds manga | ✅ S41 integrated |
| Kavita/Komga | OPDS | User's local library | ❌ Not yet |

**No architecture rebuild needed.** JSBridge already handles multi-format detection. Format D (Mangayomi) was attempted but Mangayomi extensions are all Dart (`.dart` files, `sourceCodeLanguage: 0`) — cannot execute in JSC. Catalog parser for Mangayomi index.json format remains in PluginCatalogService for metadata display.

**Novel support remains Yomi's exclusive differentiator.** Zero other iOS App Store apps support light novels with a plugin system. LNReader (Android, 500+ sources) has no iOS equivalent except Yomi.

---

## Current state (post S111 — 2026-08-17 · backlog cleared: boundary-preload root-caused for real, AquaManga pagination fixed, 3 parity features shipped)

**S111 — Martin asked to "fix everything from the backlog."** Triaged first: excluded anything
blocked externally (CloudKit container provisioning needs paid Apple Developer Program enrollment,
App Store Connect content is data entry not code, dead-repo plugin cleanup is a user action, a couple
of items need Martin's physical device) and worked through the six that were genuinely code-fixable.

1. **S110's chapter-boundary preload trigger — root-caused for real, not a tooling artifact.** Checked
   Apple's own docs for `.scrollPosition(id:)` (via apple-docs MCP): it must be paired with
   `.scrollTargetLayout()` on the scrolled container to actually track the visible view — neither
   `WebtoonReaderView`'s `LazyVStack` nor `ContinuousHorizontalReaderView`'s `LazyHStack` had it, so
   `visibleId` never updated regardless of whether the scroll came from a real touch or `mobile-mcp`'s
   synthetic swipe. S110's "mixing `ScrollViewReader.scrollTo` with `.scrollPosition(id:)`" theory was
   adjacent but missed the actual missing modifier. Added `.scrollTargetLayout()` to both containers.
   **Live-verified end-to-end**: temporary `NSLog` instrumentation (added, then removed before
   committing) confirmed `visibleId` progressed `cur:19 → cur:20 → boundary → next:0` across real
   swipes in the Webtoon reader, the preload actually started its background fetch, and the reader
   crossed into Chapter 7 with no tap — the full S109 feature genuinely works now, on this simulator.
2. **AquaManga runaway pagination (Known Issue #9b), open since S87.** `BrowseView.loadMore()` now
   dedups each newly-fetched page's ids against everything already loaded — a source that repeats its
   last page forever instead of returning empty (AquaManga's actual behavior) now correctly reads as
   "no new content" — plus a `maxPage = 300` hard backstop for any source where dedup alone wouldn't
   terminate. Clean build; not re-tested against AquaManga's live site this session (pure client-side
   termination logic, no network dependency in the fix).
3. **Rotation-follows-device setting** (`TACHIMANGA_PARITY.md` §8, previously missing). New
   `AppSettings.rotationFollowDevice`, read by a new `AppDelegate.supportedInterfaceOrientationsFor`
   in `YomiApp.swift` (`.allButUpsideDown` vs `.portrait`), toggle in Settings → Library. **Live-verified
   the restrictive direction**: toggled off via the real Settings UI, rotated the simulator to
   landscape, app correctly stayed portrait, confirmed by reading the persisted UserDefaults plist
   directly (not just a screenshot). The permissive direction (on → device actually rotates) couldn't
   be confirmed — `mobile-mcp`'s `mobile_set_orientation` never produced a visible rotation once
   unlocked in this session, a simulator/tooling limitation, not something the code path indicates
   should fail (see the tooling note below for why taps were unreliable around this test).
4. **Repair Database action** (`TACHIMANGA_PARITY.md` §9, previously missing). New
   `DatabaseManager.repair()` — `PRAGMA integrity_check` then `VACUUM`, run via
   `writeWithoutTransaction` since VACUUM can't execute inside GRDB's implicit write-transaction
   wrapper (confirmed against context7's live GRDB docs before writing it, no built-in `.vacuum()`
   convenience exists). New button in `StorageView.swift`'s Database section. **Live-verified**:
   tapped it in the running app, got the real alert — "No issues found. Database optimized."
5. **AppLockView restyled** to the Ink/Space-Grotesk design system — was plain
   `Color(.systemBackground)`/system font/`.borderedProminent`, predating the S79 redesign (flagged as
   a cosmetic gap in `TACHIMANGA_PARITY.md` §6). Now matches `OnboardingView`/`SecureScreenCover`'s
   established pattern of reading `YomiTokens.Canvas.ink`/`AppSettings.shared.accentColor` directly
   rather than via `\.yomiCanvas` — same reason both of those already do: a `fullScreenCover` attached
   to the WindowGroup's `ContentView()` call site sits outside `ContentView`'s own
   `.environment(\.yomiCanvas, ...)`. **Live-verified**: enabled `appLockEnabled`, cold-relaunched, and
   caught the restyled lock screen in the frame before the simulator's system passcode sheet took over
   (no Face ID enrolled in this sim) — accent-colored icon box, Grotesk title, accent pill button.
6. **Tachiyomi-compatible backup *export*** (`TACHIMANGA_PARITY.md` §5, previously one-way import
   only). New `TachiyomiBackupExporter.swift` — the reverse of the existing
   `TachiyomiBackupParser.swift`, same protobuf3 field layout and gzip-via-libz approach, wired into
   `BackupManager.exportTachiyomiBackup()` and a new section in `BackupView.swift`. Yomi-native
   sources export with `source(1) = 0` (no reverse Tachiyomi-source-ID mapping exists beyond the
   parser's existing MangaDex entry) — Tachiyomi's own restore flow already treats that as a normal
   "no matching source" case rather than a failure, so library/read-history still comes across.
   **Verified byte-for-byte, not just "compiles and produces a file"**: hand-decoded the real exported
   `.tachibk`'s protobuf bytes in a throwaway Python script and confirmed title, url, artist, status,
   favorite, and all 9 chapters' read-state/lastPageRead/chapterNumber matched the live database
   exactly (including a real mid-session state: Ch.6 showing `read=1 lastPage=18`, matching hands-on
   testing earlier in the session).

**New tooling finding, worth carrying forward**: `mobile-mcp`'s `mobile_set_orientation` can leave its
internal orientation state desynced from the simulator's actual rendered orientation — after the
rotation-lock testing above, every subsequent tap coordinate silently landed on the wrong element for
several minutes (taps meant for the Library tab bar kept reopening the reader) until
`mobile_get_orientation` was checked directly and found stuck reporting `landscape` well after the
visible UI — and even a screenshot — showed portrait. Calling `mobile_set_orientation` a couple more
times (portrait, then landscape again) to force a fresh read resolved it. **If taps start landing on
plausible-looking but wrong elements with no other explanation, check `mobile_get_orientation` before
assuming the app or a stale accessibility snapshot is at fault** — this is a new, sharper addition to
the standing `mobile-mcp` flakiness notes in `CLAUDE.md`'s MCP tools section.

Zero build warnings across all six fixes, live-verified everywhere the simulator's own constraints
allowed. `TACHIMANGA_PARITY.md`'s only remaining real gap is multi-device CloudKit sync, still blocked
on paid Apple Developer Program enrollment (Known Issue #47) — everything else left in that doc is
low-priority cosmetic/App-Store-process items not worth a dedicated session.

---

## Prior state (post S110 — 2026-08-17 · S109 live-verification found + fixed a real chapter-ordering bug; boundary-transition trigger still unconfirmed)

**S110 picked up S109's "re-verify on Martin's own device" note and tried the simulator again anyway**,
using a `sqlite3`-seeded near-chapter-end read position (since `mobile-mcp`'s swipe still can't reach an
arbitrary mid-scroll offset) plus Pulse's live Network Console as ground truth for whether the preload's
background fetch ever actually fires.

1. **Customize Tabs — now fully live-verified.** The Settings row was unreachable by a single fling
   last session; found that a *short, off-center* swipe (`x/y` near the bottom of the visible list,
   small `distance`) reliably lands a partial scroll where a full-width fling always overshoots —
   worth trying before concluding a row is unreachable. Toggled History off: the bottom tab bar
   rebuilt live (Library/Browse/Updates/More, correctly re-spaced), persisted across a full
   `stop_app_sim`+`launch_app_sim` relaunch, and re-enabling restored all 5 tabs. "More" stayed locked
   as designed. Drag-to-reorder itself still isn't exercised (no drag gesture tool available), but the
   higher-risk half — hide/show state actually persisting and driving the live tab bar — is confirmed.
2. **Found and fixed a real, pre-existing chapter-ordering bug, independent of S109's feature.**
   `MangaDetailView.loadChapters()` and both `ContinueReadingRow.swift` reader-launch paths built their
   `chapters` array directly from the source plugin's `getChapterList()` return order — confirmed via a
   live `curl` against AsuraScans' real API that this is **newest-first** (`[9,8,7,6,5,4,3,2,1]`), not
   ascending. `ChapterReaderView`'s `hasNextChapter`/`hasPrevChapter`/`navigateToChapter(index ± 1)` and
   the new boundary-preload all assume `chapters[index + 1]` means "the next-higher chapter number" —
   with a descending array this was backwards, so both the "Next Chapter" button and the boundary
   preload's target chapter would resolve to the previous chapter, not the next one, for any source
   whose API/scrape returns newest-first (likely most of them). Fixed by sorting `chapters`
   ascending by `chapterNumber` right after each load, matching `ChapterQueries.fetchAll`'s own
   `ascNullsLast` convention — `ChapterQueries.fetchAll` and `UpdatesView.swift`'s reader-launch path
   were already correct (the latter defensively re-sorts even though its source is already ascending).
   **Live-verified**: the in-reader Chapters sheet for "The Tale of Cultivation and Demon Extermination"
   now lists Ch.1→Ch.9 in order (was silently reversed before, though never actually screenshotted or
   flagged in a prior session — this bug likely predates S109 significantly).
3. **The boundary-preload trigger itself still couldn't be confirmed firing, and this session's evidence
   points at a tooling gap, not (only) a code bug.** Seeded chapter 6 (21 pages) to resume 2-3 pages
   from the end, confirmed via Pulse's Network Console + direct inspection of the simulator's Pulse
   `logs.sqlite` (ground truth, not the reader's own on-screen page counter — see below) that **zero**
   request for chapter 7's (or, pre-fix, chapter 5's) page list ever fired, across three separate
   `stop_app_sim`/`launch_app_sim` cycles and both a direct-seek and an organic multi-swipe approach to
   the threshold. Added temporary `NSLog` instrumentation directly in
   `WebtoonReaderView`'s `.onChange(of: visibleId)` and `preloadNextChapterIfNeeded()` (removed before
   committing) and confirmed via `xcrun simctl ... log show` that **the `visibleId`/`.scrollPosition(id:)`
   binding's `onChange` never fired at all** during `mobile-mcp` swipes in this run, even though the
   on-screen content visibly scrolled — meaning `currentPage` never updated internally either, and the
   reader header's own "N/21" text staying constant across many swipes (which an earlier pass in this
   same session had reasoned was just *stale accessibility-tree caching*) may instead have been literally
   true. `WebtoonReaderView` mixes the older `ScrollViewReader`/`proxy.scrollTo` API (used for the
   resume-to-saved-page jump) with the newer `.scrollPosition(id:)` reactive binding (used to detect
   which page is visible) on the *same* `ScrollView` — Apple doesn't document this combination, and it's
   a plausible root cause for `scrollPosition` silently not tracking scroll from certain gesture sources
   even though `UIScrollView`'s own content offset visibly moves. **Not ruled out**: a genuine code bug
   in the trigger logic itself. **Next session (ideally on Martin's real device, where genuine
   finger-drag touch events may behave differently from `mobile-mcp`'s synthetic swipe) should**: verify
   whether the boundary card ever appears under real touch input; if it does, this was a tooling
   artifact only; if it doesn't, add back similar `NSLog`/breakpoint instrumentation and check whether
   `visibleId` updates at all outside the simulator-automation path.

Reused the same dev-simulator library data S109 left in place. Zero build warnings across all rebuilds.
2 commits (chapter-ordering fix + doc updates) pushed to `main`.

---

## Prior state (post S109 — 2026-08-17 · chapter-boundary transition + Customize Tabs screen shipped)

**S109 shipped the two items S108 explicitly deferred**: the continuous/webtoon-reader
chapter-boundary transition (`TACHIMANGA_PARITY.md` §7, added S108 from 3 real Tachimanga
screenshots Martin sent) and the Customize Tabs settings screen S108 root-caused but didn't build
(iPhone gets zero built-in tab-customization affordance from Apple's own sidebar-only API).

1. **Chapter-boundary transition** (`ChapterReaderView.swift`). As the user nears the end of a
   chapter in Webtoon/Continuous mode, the next chapter's pages are fetched in the background and,
   once ready, a `ChapterBoundaryCard` ("Finished: Ch. N" / "Current: Ch. N+1") plus the next
   chapter's pages are appended directly into the same scroll content — crossing into them
   triggers a state swap (chapter index, active `pages`, progress bookkeeping) with no reload and
   no scroll-position jump, matching Tachimanga's reference screenshots. **Found and fixed a real
   bug while live-testing**: the preload's background fetch goes through `SOURCE._fetchSync`
   (`JSBridge.swift`), which blocks synchronously on a `DispatchSemaphore` with no timeout — an
   existing app-wide pattern, fine for a foreground chapter load the user is already waiting on,
   but my preload fires this silently in the background while the user keeps reading. Against a
   slow/rate-limited source this pegged the CPU at 99% and froze the UI (confirmed via `ps aux`
   CPU sampling, reproduced twice). Fixed with a 12s timeout race (`withTaskGroup`) so a stuck
   fetch can no longer hold up the preload state machine — cancellation can't preempt the
   underlying blocking call itself, so a truly stuck fetch still burns one background thread until
   it resolves on its own, but the app no longer hangs waiting on it. **Verified**: CPU stayed in
   the normal 0–20% range across many repeated scroll/scrub operations post-fix, vs. the prior
   sustained 99% spike. **Not verified**: the boundary card's actual on-screen appearance and the
   seamless crossing itself — blocked by two already-documented tooling limits stacking in this
   environment, not a code issue: `mobile-mcp`'s swipe gesture doesn't respect its `distance`
   parameter here (every swipe resolves to a full fling to the nearest scroll-view bound,
   confirmed by testing distances from 30 to 2000 with identical binary results — a new, sharper
   characterization of the swipe-simulation unreliability already noted since S87), compounded by
   the standing reader-header tap flakiness (S101, S108). Next session touching this should
   re-verify the visual crossing directly on Martin's own device.
2. **Customize Tabs settings screen** (new `YomiTabID.swift`, `CustomizeTabsView.swift`;
   `AppSettings.tabOrder`/`hiddenTabIDs`; `ContentView.swift` rebuilt). `ContentView`'s `TabView`
   now constructs its `Tab`s via `ForEach(visibleTabIDs)` instead of 5 static declarations — a
   sanctioned SwiftUI pattern confirmed against live Apple docs (`TabView`'s own reference page
   shows `ForEach` producing dynamic `Tab`s). `CustomizeTabsView` is a drag-to-reorder +
   toggle-to-hide list; "More" can't be hidden since it's the only way back to this screen.
   Hiding a tab that's currently selected or set as the launch tab resets both to Library.
   **Verified**: clean zero-warning build, app launches with all 5 tabs correctly ordered in the
   default configuration (screenshot-confirmed), Settings screen still renders correctly around
   the new "Customize tabs" row. **Not verified**: the drag/toggle UI itself — blocked by the same
   swipe-imprecision issue above; couldn't scroll far enough down the Settings screen with
   available tooling to reach and tap the row this session.

Both features live in `pacodealer.Yomi`'s dev simulator library (a real AsuraScans manga, in
library, mid-chapter-6 read state) — left in place for the next session's re-verification rather
than reset. Zero build warnings throughout. Commits pushed to `main`.

---

## Prior state (post S108 — 2026-08-16 · branch reconciliation + 3 parity items shipped)

**S108 opened by reconciling a real branch split**: `main` had picked up unrelated dev-tooling
commits (SwiftLint/fastlane/Pulse, 8/14) while S106/S107's CloudKit investigation lived on an
unmerged worktree branch (`worktree-cloudkit-verify-s106`, cut 8/11) — neither branch had the
other's work. Merged cleanly (docs-only diff, no code conflicts), pushed, then removed the
now-redundant worktree/branch (local + remote, confirmed with Martin before the remote delete).

**CloudKit sync stays out of scope this session** — still blocked on Apple Developer Program
enrollment (#47), Martin's call not to enroll yet. Instead worked the buildable half of
`TACHIMANGA_PARITY.md`'s backlog: dated iCloud backup list, color-blend slider, date format
picker, plus a live investigation into Customize Tabs. Known Issues re-checks (#8 needs a local
Suwayomi server, #12 needs Martin's real device) and App Store Connect prep were deliberately
**not** attempted — external-resource/input-blocked, scoped for their own future sessions.

1. **Dated iCloud backup list** — `BackupManager.uploadToICloud()` previously overwrote one fixed
   `YomiBackup.json`; now writes timestamped files (`YomiBackup-<ISO8601>.json`), keeps the last 8,
   and `BackupView.swift`'s iCloud section is a real list (date + byte size, swipe-to-delete,
   tap-to-restore-that-specific-entry) instead of a single date row. **Not live end-to-end
   verified**: the dev simulator's iCloud session had lapsed (an "Apple Account Verification /
   enter your password" system dialog was blocking the home screen at session start) — code
   review + zero-warning build only, following the same `FileManager`/ubiquity-container pattern
   the single-file version already used successfully. Next session touching Backup should
   re-authenticate iCloud on the sim first and confirm a real multi-entry round-trip.
2. **Color-blend slider** — new `AppSettings.colorBlendLevel` + `Color.mix(with:amount:)`
   (`Color+Hex.swift`), blends `bg`/`surface1`/`surface2` toward the accent color; text/hairline
   deliberately untouched so legibility isn't a moving target. Wired through
   `AppSettings.blendedCanvasColors` (parallel to, not a mutation of, `canvasColors`) into
   `ContentView.swift`'s `\.yomiCanvas` environment — applies app-wide, not just a preview toy —
   and into Appearance Studio's live preview card. **Live-verified at 60% on Paper**: visibly
   tints the whole app consistently (Library, Settings, tab bar), and the pre-existing AA contrast
   badge correctly flips to "Fail" — the slider surfaces the Paper/Sepia contrast tension flagged
   back in S101 instead of hiding it, same judgment-call precedent (expose, don't silently decide).
3. **Date format picker** — new `AppSettings.use24HourClock`/`dateOrderDayFirst`, threaded as
   explicit parameters into `Notation.historyTimestamp(_:use24Hour:dayFirst:)` rather than read
   from `AppSettings.shared` inside the enum (kept `Notation`'s `nonisolated`, detached-context-safe
   contract from S91 intact). Two toggles in Settings → General. **Live-verified both axes** by
   seeding a real `lastReadAt` via direct `sqlite3` (today, then >7-days-old) and confirming History
   rows flip "20:30"↔"8:30 PM" and "JUL 20"↔"20 JUL" after each toggle.
4. **Customize Tabs — root-caused, not fixed.** `ContentView.swift` already had per-tab
   `.customizationID`s and an `@AppStorage`-backed `.tabViewCustomization($customization)` since
   S43 (`HISTORY.md` claimed drag-to-reorder worked) — but was missing
   `.tabViewStyle(.sidebarAdaptable)`, which Apple's own docs say is required for
   `.tabViewCustomization` to do anything at all. Added the modifier (harmless, confirmed no
   visual regression on iPhone via screenshot). But watching WWDC24's actual talk — titled
   "Elevate your tab and sidebar experience **in iPadOS**", not a coincidence — surfaced the real
   finding: **the system's drag/hide editing UI only exists inside the sidebar, which only renders
   in regular-width contexts (iPad/Mac/tvOS/visionOS). iPhone compact width gets a plain tab bar
   with no built-in customization affordance at all**, confirmed live (long-pressed a tab: it just
   selected, no jiggle, no menu, identically before and after the fix). Delivering this on an
   iPhone-only app needs a real custom settings screen (reorder list + hide toggles) — Martin's
   call was to log this rather than build it this session, scoped for its own future pass.

**Tooling note**: `mobile-mcp`'s WebDriverAgent failed to connect for the first ~10 minutes of the
session (5 consecutive timeouts across a 20s wait + simulator reopen) — recovered on its own mid-
session with no intervention beyond retrying periodically. `XcodeBuildMCP`'s plain `screenshot` tool
kept working throughout, used as the fallback for the Customize Tabs visual-regression check. Also
reconfirmed the standing tab-bar coordinate-offset quirk (S99): tapping a tab's own reported
x-coordinate lands one tab to the left; a +69pt compensation reliably lands correctly on this device.

Zero build warnings throughout (Debug, rebuilt after every step). Commits pushed to `main`:
branch-merge commit, then one commit per feature (backup list, blend slider, date format picker,
Customize Tabs root-cause + doc updates).

---

## Current state (post S107 — 2026-08-11 · Known Issues backlog re-check, no code changes)

**S107: CloudKit sync still can't proceed (Martin hasn't enrolled in the Apple Developer Program yet),
so Martin asked to work the lower-priority Known Issues backlog instead** — 3 items flagged as
"re-check next session" but never re-verified: #8 (Suwayomi Latest tab), #12 (duplicate-extension
self-heal), #21 (novel-source blocked status).

**#21, re-checked live via `curl` with a real iOS Safari UA**: LightNovelPub and BabelNovel are
unchanged — both still return HTTP 403 with genuine Cloudflare markers ("Just a moment" / "Attention
Required" present in the response body). **BoxNovel is worse than last recorded, and differently
broken**: previously catalogued as a JS-only anti-bot shell (still nominally the real site, just
challenge-gated); now `boxnovel.com` returns a clean HTTP 200 whose body is a domain-parking/ad-redirect
script posting to `router.parklogic.com` — a classic expired-domain-squatting pattern, not a bot
challenge. The domain has effectively changed hands; there is no plugin-side fix for a parked domain,
only removal from the catalog if Martin wants that formalized. NovelBin (`novelarrow.com` backend)
reconfirmed HTTP 200, unaffected.

**#12, re-checked via direct `sqlite3` against the primary dev simulator's `yomi.db`**:
`SELECT name, COUNT(*) FROM extension GROUP BY name HAVING COUNT(*) > 1` returned zero rows. No
duplicates present. A weak test, though — this simulator only has 2 extensions installed (AsuraScans,
NovelFire), both freshly installed under the current id scheme, so it can't demonstrate the specific
legacy-duplicate scenario (an install predating the sha256-hash-id → stable-catalog-id migration) the
original bug required. **The user's real device was never checked and still might have legacy duplicates**
— genuinely unresolved, still worth a glance at the Plugins screen next time it's in hand.

**#8, no live re-test — no local Suwayomi server was available**, and standing one up from scratch
(Docker/JVM install, per the S89 setup notes) was judged disproportionate effort for a tab whose risk
was already rated low relative to the already-verified Popular tab. Did a targeted code read instead:
`SuwayomiService.fetchLatest(sourceId:page:)` and `fetchPopular(sourceId:page:)`
(`Yomi/Features/Extensions/SuwayomiService.swift`) both route through the identical generic
`fetch<T>()` helper — same request construction, same `200...299` status check, same JSON decode —
differing only in the URL path segment (`/latest/` vs `/popular/`). `SuwayomiBrowseView.swift`'s
`loadMore()` branch for `selectedFeed == .latest` is structurally identical to the already-verified
`.popular` branch (same manga-mapping, same pagination state updates). No divergent logic found —
raises confidence without a live server, but an actual end-to-end fetch against a running server
remains technically unverified.

**No code changes this session.** Confirmed no build regressions along the way: clean `build_run_sim`
on both the S106 real-account simulator and the primary dev simulator, zero warnings/errors.

---

## Prior state (post S106 — 2026-08-11 · CloudKit sync blocked on Apple Developer Program enrollment)

**S106: resumed the S103/S105 real-iCloud-account verification, found the real blocker.** Martin's
call, asked directly, was to prioritize this over App Store submission prep. Booted two simulators
(iPhone 17 Pro + iPhone 17 Pro Max, both iOS 26.3 — same runtime, so CloudKit's Development environment
behaves consistently across both), Martin signed a real Apple ID into both, built and launched Yomi on
each via separate XcodeBuildMCP session profiles.

**Account path now fully verified**: `CKContainer.accountStatus()` correctly resolves `.available` on
both devices (previously only ever tested against `.unavailable`, signed-out). Enabling "Sync across
devices" correctly drives a real `CKSyncEngine.sendChanges()`/`fetchChanges()` call — but both fail
immediately on both simulators with `CKError "Bad Container" (5/1014): "Couldn't get container
configuration from the server for container "iCloud.pacodealer.Yomi""`, confirmed via `xcrun simctl
spawn <device> log show` (the in-app "Could not determine iCloud account status" text is CloudKit's own
`CKError.localizedDescription` for this error, not a real account-status problem — a red herring worth
remembering if this comes up again).

**Root-caused, not just observed**: WebSearched Apple's own `CKError.Code.badContainer` documentation
plus developer-forum precedent — this error means the container was never provisioned on Apple's
servers, which only happens via Xcode's Signing & Capabilities → iCloud → CloudKit "+" flow (S103 hand-
wrote the entitlements directly instead). Asked Martin directly whether the project is enrolled in the
paid Apple Developer Program: **not yet** — this was flagged as an unpurchased cost item back in S90
(`~$111/yr` total project cost, Program membership one of two line items) but never connected to
CloudKit sync specifically until now. Container creation requires that paid enrollment regardless of
entitlements content; a free/personal team cannot provision CloudKit containers at all, so no amount of
app-side code changes would have fixed this.

**Two-device convergence, the `.serverRecordChanged` conflict path, and a real record reaching
CloudKit remain unverified — genuinely blocked, not just untested.** Next session touching this feature
starts with: (1) enroll in the Apple Developer Program, (2) open `Yomi.xcodeproj` → Signing &
Capabilities, sign in with the enrolled account, add iCloud/CloudKit, use "+" under Containers to
provision `iCloud.pacodealer.Yomi` (confirm via the CloudKit Dashboard afterward), (3) re-run this exact
two-simulator test — the sync code itself needs no changes. Full detail in
`Yomi/CLOUDKIT_SYNC_DESIGN.md`'s "What was verified, and what wasn't (S106)" section.

---

## Prior state (post S105 — 2026-08-07 · CloudKit sync code-review findings fixed)

**S105: worked through all 6 findings from S104's `/code-review` pass over the S102-S103 CloudKit sync
code** (Known Issues #41-46), per Martin's "fix all 6 findings first" call when asked where to focus.

**#41, remote-apply silently dropping chapter state for uncached manga — the real correctness bug.**
A true upsert isn't possible: the sync payload only carries read-state fields (isRead/progress/
lastPageRead/readAt/readingSeconds), not the full chapter row (title/url/chapterNumber only exist
plugin-side, by design — chapter *lists* are deliberately never synced, see
`CLOUDKIT_SYNC_DESIGN.md`). Fixed by checking `db.changesCount` after the UPDATE in
`applyRemote(record:)`: if it's zero, the change is stashed into a new `pending_chapter_state`/
`pending_novel_chapter_state` table instead of being dropped, and replayed the moment the chapter row
actually gets inserted locally — new `CloudSyncManager.applyPendingChapterStates`/
`applyPendingNovelChapterStates`, called inside the same write transaction from
`ChapterQueries.insertAllIgnoringConflicts`/`insertMangaAndChapters` and
`NovelQueries.insertAllIgnoringConflicts`.

**#42, category deletion not propagating join-table deletes.** `CategoryQueries.delete(id:)` now
reads the `manga_category`/`novel_category` rows for that category *before* the SQLite `ON DELETE
CASCADE` fires, then calls `markCloudDeleted` for each `MangaCategoryLink`/`NovelCategoryLink` —
matching the treatment the `Category` record itself already got.

**#43, dirty-marking silently no-oping during `enable()`'s async accountStatus window.**
`markCloudDirty`/`markCloudDeleted` now always persist the recordName→(type,key) mapping and, when no
engine is running yet, durably stash the mark in a new `cloud_sync_map.pendingChange` column (rather
than the old silent no-op). `enable()` drains every pending mark into the freshly-created engine's own
persisted state (`CloudSyncManager.drainPendingMarks`) immediately after `cloudSyncEngine` is assigned,
before bootstrap or first sync — this closes the window rather than just narrowing it, and survives
even if the app is killed before the next `enable()` call (the marks are on disk, not in memory).

**#44, `enable()` double-call race.** New `private var isEnabling` flag on `CloudSyncManager`, set
synchronously before the function's first `await` and cleared via `defer`. Because MainActor serializes
non-suspended code, a second concurrent caller's guard check (itself synchronous up to its own first
`await`) reliably observes the flag and returns early instead of constructing a second `CKSyncEngine`
that would silently clobber the first.

**#45, `try?` regression swallowing 2 bulk mark-read functions' DB-write errors.**
`ChapterQueries.markAllRead` and `NovelQueries.markAllChapters` reverted from `try? appDatabase.write`
back to `try appDatabase.write` (both functions already declare `throws` — the `try?` was silently
defeating S100's toast-on-failure work, Known Issue #26, for these two call sites specifically).

**#46, hardcoded `aps-environment: development` in `Yomi.entitlements`.** Rather than trust
automatic-signing entitlement rewriting to fix this at archive time (the finding's own worry: manual
signing or some CI export paths can skip it), added a dedicated `Yomi/Yomi-Release.entitlements`
(identical except `aps-environment: production`) and repointed the Yomi target's Release build
configuration's `CODE_SIGN_ENTITLEMENTS` at it directly — Debug still uses the original
`Yomi.entitlements`. This makes the correct value a build-time file choice, not a runtime signing
behavior to trust. Verified via both configs' build logs: `ProcessProductPackaging` shows
`Yomi.entitlements` for Debug, `Yomi-Release.entitlements` for Release.

New migration `v21_cloud_sync_pending` (`cloud_sync_map.pendingChange` column +
`pending_chapter_state`/`pending_novel_chapter_state` tables) — next must be `v22_`. All fixes
live-verified: clean **Debug and Release** `build_sim` (zero warnings both), `build_run_sim` launches
with no crash, and direct `sqlite3` inspection of the dev simulator's `yomi.db` confirming the
migration applied and the new column/tables exist with the expected schema.

**Still queued, not touched this session** (Martin's call: fix the 6 findings first, real-account
verification next): the S103 real-iCloud-account verification. This dev simulator still has no iCloud
account signed in, so an actual CloudKit send/fetch round-trip and real multi-device convergence remain
unverified — everything fixed this session is code-review-level correctness, not proof the sync
actually reaches CloudKit and back.

Committed and pushed to `main`.

---

## Prior state (post S104 — 2026-08-07 · piracy/App-Store-compliance audit + first-party catalog fix)

**S104: Martin asked directly whether Yomi complies with App Store regulations around piracy** — a
genuine compliance question, not a bug hunt. Fetched the live current guideline text from
developer.apple.com rather than relying on training data or `RESEARCH.md`'s existing summary (dated
S23/S32, last touched S44), then did a full fresh-user walkthrough (S96's `cfprefsd`-clear procedure +
clean reinstall) to see exactly what a brand-new user — and an App Reviewer — actually encounters.

**The applicable guideline is 5.2.2 (Third-Party Sites/Services), not 2.5.2**: "If your app uses,
accesses, monetizes access to, or displays content from a third-party service, ensure that you are
specifically permitted to do so under the service's terms of use. Authorization must be provided upon
request." **`RESEARCH.md`'s existing 2.5.2 claim was also stale and corrected this session**: it stated
"JavaScriptCore and WebKit are explicitly allowed" as a named exemption — Apple rewrote that clause
engine-agnostic in 2017; the current text has no named-engine carve-out, only a "does downloaded code
change the app's primary purpose" test (Yomi still clears it, but the doc overstated the textual basis).
Also corrected a factual precedent error: `RESEARCH.md` cited Aidoku as an "approved" App Store
precedent alongside Paperback — **Aidoku is not distributed via the App Store at all** (TestFlight/IPA
sideload only), so it's not a review precedent either way. Paperback is live but has faced a real DMCA
complaint over this exact content model — "tolerated so far," not "cleared."

**Live walkthrough finding, the real headline**: onboarding page 2/3 prints `yomi-plugins.web.app`
directly on screen ("browse the catalog to install your first one"), and page 3's CTA deep-links
straight into Plugins. That screen's **first-party Catalog (15)** — Yomi's own Firebase-hosted
`index.json`, fetched automatically, zero user action to discover — showed one-tap **Install** for all
15 entries, ~12 of which (AquaManga, Asura Scans, BabelNovel, BoxNovel, FreeWebNovel, LightNovelPub,
MTLNovel, NovelBin, NovelFire, NovelFull, NovelHall, ReadWN) are unlicensed scanlation/scrape
aggregators with no documented permission — exactly what 5.2.2 is written for. Only MangaDex (public
API under its own terms) and arguably Royal Road/Scribble Hub (platforms hosting only originally-authored
fan fiction) aren't in that category. **This is a bigger reviewer-visible signal than the LNReader repo
risk S96 already mitigated** (one-tap → "Copy URL" friction, specifically to look less turnkey) — this
first-party catalog is the developer's *own* onboarding flow pointing at it, not a third-party repo a
user had to go find.

**Martin's call, asked directly rather than decided unilaterally**: match the LNReader treatment.
Fixed in `PluginsView.swift` — a new client-side (compiled-into-the-binary, not remote-config-driven,
deny-by-default) `instantInstallSourceIDs` allowlist (`com.yomi.mangadex`, `com.yomi.royalroad`,
`com.yomi.scribblehub`); `CatalogGroupRow` now renders "Copy URL" instead of "Install" for every other
catalog entry, reusing the exact copy-to-pasteboard interaction `FeaturedRepoRow` already established
for LNReader, plus a new Catalog section footer explaining the distinction. Deliberately kept
client-side rather than adding a field to the remote `index.json`: a flag a reviewer's build doesn't
see (compiled binary) is meaningfully different from one a remote server could silently flip, which
would itself read as review-evasion if ever discovered. Zero build warnings; live-verified via
`build_run_sim` + mobile-mcp — MangaDex/Royal Road/Scribble Hub show Install, all 12 others show Copy
URL, footer renders correctly.

**Also ran**, same session, in parallel: a `/code-review` pass on S102-S103's CloudKit sync branch —
6 findings, not yet triaged/fixed (see below, next session should start here alongside the real-account
CloudKit verification already queued from S103).

**Not decided, deliberately left for Martin**: whether to also gate the *remaining* borderline entries
(BabelNovel is a commercial-ish translated-novel platform with what looks like a real JSON API, treated
conservatively as "requires manual add" here rather than researched further) — and whether the App
Store Connect review notes (already an open checklist item, see below) should proactively disclose the
third-party-source model rather than leave it to be discovered.

Committed and pushed to `main`.

---

## Prior state (post S103 — 2026-08-06 · CloudKit sync implemented)

**S103: implemented full multi-device CloudKit sync**, built directly against S102's design doc
(`Yomi/CLOUDKIT_SYNC_DESIGN.md`), same session-day as the scoping pass. This closes the last big item
on `TACHIMANGA_PARITY.md`'s backlog.

**What shipped**: new `Yomi/Sync/CloudSyncManager.swift` — a `CKSyncEngine`-backed sync engine against
a custom `LibraryZone` in the private CloudKit database, implementing `CKSyncEngineDelegate`
(`handleEvent`/`nextRecordZoneChangeBatch`), with bidirectional GRDB↔CKRecord mapping for 7 record
types (`Manga`, `Novel`, `Category`, `MangaChapterState`, `NovelChapterState`, `MangaCategoryLink`,
`NovelCategoryLink` — chapter *lists* deliberately excluded, matching S102's key finding). New GRDB
migration `v20_cloud_sync_map` (next must be `v21_`): a small reverse-index table mapping a
`CKRecord.ID`'s hashed `recordName` back to `(recordType, key)` plus a cached archived `CKRecord` per
row (needed so re-saves carry a real server `recordChangeTag` — without it CloudKit's own conflict
detection never fires). `markCloudDirty`/`markCloudDeleted` — nonisolated module-level functions,
mirroring the project's own `appDatabase`/`appRouter` pattern rather than adding a MainActor hop to
every write — hooked into ~20 call sites across `MangaQueries`, `ChapterQueries`, `NovelQueries`,
`CategoryQueries` (toggleLibrary, setRead/markRead/markAllRead, updateProgress, addReadingTime,
category CRUD + assign/unassign). New `AppSettings.cloudSyncEnabled` toggle drives
`CloudSyncManager.enable()`/`.disable()`. New distinct Settings → More → **Sync** screen
(`CloudSyncView.swift`) — deliberately separate from the existing Backup screen, matching S102's call
that live sync and point-in-time backup are different mental models. `YomiApp.swift`'s
`AppDelegate` gained `registerForRemoteNotifications()` (gated behind the sync toggle) and a
`didReceiveRemoteNotification` passthrough; scenePhase `.active`/`.background` both trigger
`CloudSyncManager.syncNow()` when enabled, mirroring the existing iCloud-backup trigger pattern.

**One real deviation from the S102 design, caught by checking Apple's actual class docs mid-build
rather than proceeding on the original assumption**: `CKSyncEngine`'s own documentation states it
"requires the CloudKit and Remote notifications entitlements" — stronger than S102's "no push
entitlement needed" framing. Flagged directly to Martin before touching entitlements; his call was to
add Remote Notifications properly (background mode + gated registration) rather than risk hitting an
undocumented restriction. This doesn't change the actual product behavior — sync still only visibly
happens on app foreground/background, nothing push-triggered was built into the UI.

**Real API-verification lesson**: the WWDC23 "Sync to iCloud with CKSyncEngine" talk's own code sample
uses `.save(recordID)`/`.delete(recordID)` — these don't compile against the shipped SDK. Checked
developer.apple.com directly once the build failed: the real cases are `.saveRecord(_:)`/
`.deleteRecord(_:)` (and `.saveZone(_:)`/`.deleteZone(_:)` for database changes), and batch scoping is
`context.options.scope.contains(pendingChange)`, not the transcript's `.zoneIDs.contains(...)`. Likely
a beta-to-GA rename. Full list of as-built corrections in `Yomi/CLOUDKIT_SYNC_DESIGN.md`'s "As-built
implementation notes" section.

**Verification is honestly bounded by this environment**: the dev simulator has no iCloud account
signed in (same constraint `BackupView` already surfaces as "iCloud not available"). Verified live: a
clean zero-warning build, `build_run_sim` launching without crashing under the new entitlements,
Settings → More → Sync rendering correctly, and toggling sync on driving a real
`CKContainer.accountStatus()` call that correctly lands on the `.unavailable` UI state for a
signed-out account. **Not verified**: any record actually reaching CloudKit's servers, the remote
fetch/merge path, conflict resolution, or real two-device convergence — those need a simulator/device
signed into a real iCloud account, which is exactly where the next session touching this feature
should start (see `CLOUDKIT_SYNC_DESIGN.md`'s testing-plan section).

Committed and pushed to `main`. **Remaining known work, project-wide**: only App Store Connect
data-entry (age rating, description, screenshots, ATS review note) — see the App Store checklist —
and, for this feature specifically, the real-account verification pass above.

---

## Current state (post S102 — 2026-08-06 · CloudKit sync scoping, superseded by S103's implementation above)

**S102: architecture-scoping session for full multi-device sync — designed, not implemented, same
treatment S90 gave the Suwayomi-server design before any code was written.** Full design at
`Yomi/CLOUDKIT_SYNC_DESIGN.md`. Two decisions confirmed with Martin up front: sync on app
foreground/background (not real-time push — avoids a Remote Notifications entitlement entirely), and
metadata + reading-state only, no files (downloaded chapters and custom cover images stay
device-local, matching Tachiyomi/Mihon convention).

**Key finding that shaped the whole design**: traced `Manga.id`/`Chapter.id` through `JSBridge.swift`
and found both are content-derived (the chapter's own URL/path, the plugin's own list-item id), not
locally-random UUIDs — meaning the same manga/chapter fetched from the same source on two devices
already gets the same id today, with zero sync code involved. Two direct consequences: (1) the
chapter list itself never needs to sync — only the ~5 mutable state fields per touched chapter
(isRead/progress/lastPageRead/readAt/readingSeconds), since every device already re-derives the full
chapter list locally via `getChapterList()`; a 3,139-chapter novel (Shadow Slave, from S88 testing)
stays cheap to sync because most chapters never get a state record at all. (2) first-sync bootstrap on
an existing library needs no special-cased merge logic — content-derived ids mean a manga that exists
identically on both the local device and in CloudKit naturally converges into one record, not a
duplicate, which is usually the hardest part of this kind of design.

Also found, by grepping every call site: `MangaQueries.delete`/`NovelQueries.delete`/
`ChapterQueries.delete` exist but are never actually called anywhere in `Features/` — "remove from
library" is `toggleLibrary()` → `inLibrary = false`, a field update, not a row delete. So CloudKit
record-deletion propagation (usually the other hardest part of a sync design) is only needed for
category deletion, which is small and self-contained.

Chose `CKSyncEngine` (iOS 17+) over `NSPersistentCloudKitContainer` (requires Core Data — ruled out,
Yomi is deliberately GRDB) and over raw manual `CKDatabase` operations (re-implements what
CKSyncEngine already owns: batching, retry/backoff, change-token bookkeeping). Proposed hook point is
a new `CloudSyncManager.swift` singleton, with `*Queries` write methods calling one new
`markDirty(recordType:recordID:)` — same choke-point pattern the codebase already uses for
`lastReadAt`/toast-on-failure (#20/#26/#35). Conflict policy: last-write-wins for everything,
including `readingSeconds` (an additive stat where this is technically imprecise) — flagged as a
known v1 tradeoff rather than solved with custom merge logic, since true concurrent-device conflicts
are rare for a reading app.

**Left open, flagged for whoever implements this rather than decided here**: one `Manga.id`
construction path (`JSBridge.swift:1795`, Mangayomi-format parsing) sets `id` to the bare path with no
`sourceId` prefix — a pre-existing id-collision risk between two different sources sharing a path
string, independent of sync, but sync would make a collision silently merge two unrelated manga into
one record instead of just showing two visually-identical local rows. Worth a quick audit of all
`Manga(id:...)`/`Novel(id:...)` construction sites before turning sync on broadly.

No implementation started this session — full narrative, data-model table, write/read path, bootstrap
flow, entitlements checklist, and testing plan all in `Yomi/CLOUDKIT_SYNC_DESIGN.md`.

---

## Current state (post S101 — 2026-08-06 · rows 31-33 shipped + theme/contrast audit)

**S101: shipped the 3 features S100 deliberately deferred (background auto-refresh, background
download, in-reader source-URL icon), plus a canvas×accent contrast audit Martin asked for that
surfaced 3 real bugs.**

**Theme audit, done first.** Computed WCAG contrast for all 4 canvases × 11 accent presets, two ways:
accent-vs-canvas.bg (icon/progress-bar usage) and white-vs-accent (button-fill-with-white-label
usage, e.g. the Continue card's Resume button). Findings: on Paper/Sepia, 9 of 11 accents are nearly
invisible as icons/progress bars against the light background (ratios as low as 1.24:1) — a real,
unfixed-this-session color-science tension between "accent is always exactly the user's chosen color"
and "some chosen colors don't read on some canvases," flagged for Martin rather than silently
recolored. More urgently: **every accent's hardcoded white button-label text was failing WCAG AA
(only Indigo cleared 4.5:1)** — confirmed live (Ink canvas + Yellow accent: "Resume" text was
genuinely unreadable, white-on-#FECA57 measures 1.52:1). Fixed with a new
`YomiTokens.Accent.foreground(for:on:)`: keeps the canvas's own ink color (what every other label on
that canvas already uses) whenever it clears 3:1 against the accent, only flipping to the opposite
pole for the accents that genuinely fail. Applied at all ~12 real accent-fill+white-text call sites
app-wide (Resume buttons, unread/NOVEL badges, empty-state CTAs, onboarding CTA, selection
checkmarks). **Live testing then surfaced 2 more real bugs Martin caught firsthand** (see below) —
first attempt at the foreground fix used a blanket "always pick whichever of white/black wins"
formula, which flipped even the *passing* default (Vermilion on Ink, ~4:1) to black, breaking the
card's established all-one-ink-color convention for no legibility gain; corrected to the
canvas-consistent 3:1-threshold version above. Second: `Core/CoverImage.swift`'s no-cover placeholder
used `Color.secondary` (system light/dark mode only) instead of canvas tokens — any manga/novel
without cover art ignored canvas choice entirely. Root-caused deeper while fixing: Kingfisher's
`KFImage.placeholder` snapshots once at mount and doesn't live-repaint on an environment-only change
(confirmed: correct from a fresh launch with the new canvas already active, stale after switching
canvas mid-session without relaunching) — fixed with `.id(canvas.name)` forcing a clean remount on
every canvas switch. Third (Martin's own catch, a design-consistency issue not a bug): novels got two
different indicator badges depending on screen — Library grid's small translucent "NOVEL" text pill
vs. the "Up next" shelf's chunky solid-accent "N" square — unified both to the pill style.

**Rows 31-33, in order shipped:**
1. **In-reader source-URL icon.** New `JSBridge.resolveSourceURL(path:)` — best-effort, no plugin
   changes: if `path` is already absolute (Mangayomi-format plugins store a full URL there) returns
   it directly; otherwise opportunistically reads the plugin's own top-level `BASE_URL`/`BASE` JS
   global back out of the JSContext (`typeof` guard, safe if undeclared) and re-prepends it. Works for
   the ~7 plugins that declare `const BASE_URL` outside an IIFE (aquamanga, freewebnovel, novelbin,
   novelfire, royalroad, scribblehub) plus any Mangayomi-format source; can't resolve one for
   esbuild-bundled IIFE plugins (`var BASE_URL` stays lexically scoped) or pure-API sources
   (MangaDex/Comick — path is an id, not a URL) — returns nil rather than guessing, callers hide the
   icon in that case. Wired into both readers: `ChapterReaderView.swift` (new globe `glassChip` between
   the list and settings icons) and `TextReaderView.swift` (same position), reusing the existing
   `DiscussWebSheet`/`WebView` sheet from the pre-existing (separate) discussion-URL feature. Verified
   live: AquaManga's globe icon appears and correctly resolves a real chapter URL. Tap-to-open itself
   hit the session's documented mobile-mcp tap flakiness (confirmed via a control tap on the
   pre-existing gearshape icon failing identically) — not re-verified past icon visibility, but the
   sheet plumbing is a verbatim reuse of the already-shipped Discuss pattern.
2. **Background auto-refresh toggle.** Real `BGTaskScheduler` wiring, not just a UI toggle:
   `BGTaskSchedulerPermittedIdentifiers`/`UIBackgroundModes: fetch` added to `Yomi/Info.plist`;
   `AppDelegate` registers `com.yomi.refresh`'s handler at launch; `YomiApp`'s `scenePhase ==
   .background` branch submits a `BGAppRefreshTaskRequest` when `AppSettings.backgroundAutoRefreshEnabled`
   is on. The handler itself reuses `UpdatesViewModel.refresh()` verbatim (the exact same code path
   Updates' manual refresh/pull-to-refresh already runs) rather than a second implementation, reschedules
   the next request before running, and cancels via `task.expirationHandler`. Toggle added to
   `SettingsView`'s Data section, default off. Live-verified: registration doesn't crash on launch,
   toggle persists and its subtitle/dependent-toggle state update correctly; actually triggering a real
   `BGAppRefreshTask` fire isn't practically testable via the simulator without attaching lldb — not
   done this session.
3. **Background download toggle.** `AppSettings.backgroundDownloadEnabled`, gated on (has no effect
   without) auto-refresh — the Settings toggle is visibly disabled/dimmed while auto-refresh is off,
   with a subtitle explaining why. Wired directly into `UpdatesViewModel.checkUpdates(for:)` — after
   inserting newly-discovered chapters, enqueues each into `DownloadManager.shared` using the bridge
   already resolved for that manga's update check. Manga only, matching `DownloadManager`'s existing
   scope (novels have no download feature at all, not just in the background).

All live-verified via `build_run_sim` + mobile-mcp/XcodeBuildMCP screenshot comparison across
multiple canvas×accent combos, zero build warnings throughout.

---

## Current state (post S100 — 2026-08-06 · S99 audit backlog cleared)

**S100: worked through S99's audit backlog (Known Issues rows 24-30, 25, 26, 34, 35) end to end, per
Martin's "let's go through all the known issues and fix them."** Explicit scope decision up front: rows
31-33 (background auto-refresh toggle, background download toggle, in-reader source-URL icon) are
confirmed-missing *features*, not bugs — Martin chose to skip building them this session and have them
written down as backlog instead (now in `TACHIMANGA_PARITY.md`'s S100 addendum), reserving this session
for actual fixes.

**Docs (trivial, done first):** age rating 17+→18+ fixed in `CLAUDE.md` + `DESIGN_HANDOFF.md` (3
mentions), project-wide grep confirmed no stragglers (#24). `README.md`'s one remaining stale
Extensions-tab reference fixed (#28). `EXTENSIONS.md` deleted — not linked from any Swift source, fully
superseded by `README.md`'s repository-based install flow (#29). `CLAUDE.md`'s own stale file-index
note about `NovelQueries.fetchLibrary()` corrected (#30).

**OPDS password → Keychain (#25):** `AppSettings.opdsPassword`'s `didSet` now writes through
`KeychainHelper` instead of `UserDefaults`, matching the MAL-token precedent; init migrates any existing
UserDefaults value once. Live-verified: set a password, force-quit (not backgrounded) and relaunch —
value survived while confirmed absent from `defaults read`, proving it round-tripped through Keychain.

**Silent DB-write failures (#26):** new reusable `Core/YomiToast.swift` (self-dismissing top banner,
`.yomiToast(_:)` modifier, matches `UpdatesView`'s existing refresh-summary banner styling) +
`YomiHaptics.error()`. Wired into `ChapterReaderView.markChapterRead` and
`MangaDetailView.toggleLibrary`'s `catch` blocks. GRDB failures are rare by nature, not reproduced live
— verified by code review + clean build.

**AquaManga reader-page bug (#34) — root-caused deeper than expected, also fully explains #9's
long-standing unverified cover fix.** Two separate bugs stacked: (1) reader pages used raw `AsyncImage`,
which can't carry any custom request config — swapped to `KFImage` at all 3 call sites
(`MangaPageView`/`WebtoonReaderView`/`ContinuousHorizontalReaderView`) so they inherit
`KingfisherManager.shared`'s config, matching `CoverImage.swift`'s existing pattern. That alone still
403'd live: Kingfisher's `ImageDownloader` defaults to `URLSessionConfiguration.ephemeral`, which keeps
its own private in-memory cookie store — invisible to `HTTPCookieStorage.shared`, exactly where
`CFBypassView` copies the `cf_clearance` cookie after a Cloudflare challenge. The S89 UA
`requestModifier` was necessary but never sufficient. Fixed by pointing Kingfisher's downloader at an
explicit session config with `httpCookieStorage = .shared` (`YomiApp.swift` init). Verified live end to
end: AquaManga's cover art and "Path of Vengeance" Ch. 2 pages 1-2 both render real art now (previously
gray placeholder / broken-image icon).

**List-mode multi-select (#35) — confirmed genuinely broken, not just untested, then fixed.** List
mode's `.contextMenu` had no "Select" entry and `MangaListRow`/`NovelLibraryListRow` had no selection UI
at all, unlike grid mode (fixed S96). Added matching selection UI to both, wired into the same
`isSelecting`/`selectedIds`/`selectedNovelIds` state grid mode already uses. Hit the exact
`NavigationLink` + `.contextMenu` "narrows tappable area, context menu never triggers" bug from row 8's
S86 finding — same fix, an explicit `.contentShape(Rectangle())` on the row container. Verified live:
long-press → Select → multi-row checkbox selection → bulk-action bar, both manga and novel rows.

**App Store readiness consolidated (#27, #36):** `ROADMAP.md`'s "App Store submission checklist" table
(below) is now the single authoritative source — updated to current accurate status (app icon done,
OPDS Keychain done) and gained an ATS-review-notes line item for #27's recommendation (not a code
change, a submission-time review note). `CLAUDE.md`'s own checklist section now points here instead of
duplicating.

**One real mistake this session, disclosed to Martin at the time:** reached for `xcrun simctl
uninstall` to clean up a stray test string that had leaked into a settings field during `mobile-mcp` tap
troubleshooting — this wiped the dev simulator's accumulated library/reading-history test data (built up
across many prior sessions), not just the one value. Not the user's real device, but avoidable — see the
new `METODOLOGIA.md` S100 lesson: use `defaults delete` or direct `sqlite3` for surgical resets, reserve
`uninstall` for genuine fresh-install testing.

All fixes verified live via `build_run_sim` + `mobile-mcp` + direct `sqlite3`/`defaults read` inspection
where UI confirmation was unreliable, zero build warnings throughout.

## Current state (post S99 — 2026-08-06 · full project audit, documentation-only — no fixes yet)

**S99: Martin asked for a full audit of "absolutely everything" — code, docs, organization, unknown
bugs, App Store readiness — before continuing feature work.** Ran 4 parallel research passes plus a
manual live-simulator spot-check, then catalogued every finding as new rows in `CLAUDE.md`'s Known
Issues table (rows 24-36) and updated `TACHIMANGA_PARITY.md`'s "needs check" rows with confirmed
answers. **Deliberately no fixes made this session** — Martin's instruction was to document everything
now and start fixing next session. Full finding text lives in `CLAUDE.md`; this entry is the narrative
summary of how the audit was run.

**1. Code quality & repo hygiene** (static Swift review, 69 files, zero simulator use): genuinely
clean after 98 sessions of iterative hardening. Zero `TODO`/`FIXME`/`HACK`, zero `try!`/`as!`, all 16
force-unwraps traced and provably safe, no Swift 6 actor-isolation violations found (the project's own
documented failure mode — MainActor-isolated statics/computed-properties read from `Task.detached` —
was specifically checked for and not found elsewhere), no stragglers of previously-fixed patterns
(`.glassEffect()` shape bug, `ContentUnavailableView` vs `YomiEmptyState`, cover-image sizing), no
secrets in tracked files, clean `build_sim` (0 warnings). Two real findings: silent `print()`-only
error handling on mark-read/toggle-library DB writes (Known Issue #26), and a stale doc comment in
CLAUDE.md's own file index (#30).

**2. Docs consistency**: found the project's docs are well-organized, not sprawling (`CLAUDE.md` is a
genuine 293-line self-sufficient entry point, not the 900+ lines feared). Real findings: **the age
rating declaration is wrong** — `CLAUDE.md` and `Yomi/design/DESIGN_HANDOFF.md` still say "17+" (the
2026 system replaced this with 18+, and every other doc already says 18+) — a real compliance risk if
uncaught before submission (#24). `README.md` (public-facing) still has one stale reference to the
removed Browse → Extensions tab, missed by a prior "fixed" pass (#28). `EXTENSIONS.md` is fully
orphaned — built around the removed tab, lists 7 of 15 plugins, duplicates README with worse content
(#29). App Store Connect readiness (age rating/screenshots/description) has zero local tracking
artifact, just a floating TODO copy-pasted across 4 docs (#36).

**3. Live simulator verification**: `build_run_sim` succeeded, 0 warnings. Definitively resolved two
long-standing `TACHIMANGA_PARITY.md` "needs check" rows to **confirmed missing**: no background
auto-refresh toggle exists anywhere in Settings/Update Rules (whether `BGTaskScheduler` silently
handles this under the hood is now a separate open code question, #31), and no background-download
toggle exists (#32). Also confirmed the in-reader header has no source-URL/globe icon (#33). Could not
reach list-mode multi-select to reconfirm Known Issue #19 due to `mobile-mcp` tap flakiness (#35).
Surfaced a **new, systematic** `mobile-mcp` quirk this session, distinct from prior flakiness: a
consistent coordinate offset specifically on the bottom tab bar (tapping the reported x-coordinate for
"More" landed on "Updates" instead; a manually-compensated x-value worked) — full-width list rows were
unaffected. Documented in CLAUDE.md's mobile-mcp section for future sessions to watch for.

**4. App Store readiness & security**: privacy manifest, entitlements, and Info.plist permissions all
checked out clean and accurate. Two real findings: a blanket `NSAllowsArbitraryLoads` ATS exception
with no per-domain scoping (#27 — functionally probably necessary for arbitrary self-hosted
Suwayomi/OPDS servers, but a known review-scrutiny trigger, recommend review-notes at submission
rather than a code change), and the OPDS server password is stored in plain `UserDefaults` instead of
`Core/KeychainHelper.swift`, inconsistent with the MAL-token precedent the codebase already established
(#25). Confirmed clean: `AppSecrets.swift` has zero git history (never leaked, not just currently
gitignored), no other credential-shaped strings in tracked files, no unused/missing entitlements.

**5. Follow-up live check (not part of the 4 forks, done directly after)**: opening AquaManga's "Path
of Vengeance" Ch. 2 in the manga reader showed a broken-image placeholder instead of real page art
(page 1/26), unchanged after a wait — not a loading state. Possibly Known Issue #9's still-unresolved
cover-loading problem (Kingfisher/Cloudflare UA mismatch) extending to reader pages, or a separate bug
— not investigated further, needs a dedicated look (#34).

**Next session starts here**: work the new Known Issues rows (24-36) in `CLAUDE.md`, roughly in
priority order — age rating fix (#24, trivial, real compliance risk) and doc cleanup (#28-30) first,
then the OPDS Keychain migration (#25) and silent-failure toasts (#26), then investigate the AquaManga
reader-page bug (#34) and re-attempt list-mode multi-select verification (#35) once `mobile-mcp` is
behaving. CloudKit sync scoping (`TACHIMANGA_PARITY.md`'s #1 remaining big item) is still separately
parked, unrelated to this audit.

## Current state (post S97 — 2026-08-06 · Tachimanga parity pass, in progress)

**S97: Martin did a live walkthrough of Tachimanga on his physical iPhone via macOS iPhone Mirroring
(screen-shared, not app-controlled — synthetic clicks are blocked by Apple for that feature) and asked
for full feature parity + "make Yomi the best possible."** Produced `Yomi/TACHIMANGA_PARITY.md`, a
verified (not memory-based) feature-by-feature audit cross-checked against actual source, then started
working through it in priority order. Real, live-verified progress this session:

1. **Fixed Cloudflare bypass missing from the novel reader path (Known Issue #11)** —
   `NovelDetailView.swift` had zero `CFBypassView` wiring, unlike `MangaDetailView.swift`; mirrored the
   proven pattern. **Also found + fixed a deeper bug while verifying live against FreeWebNovel's real
   Cloudflare Error 1015 page**: `JSBridge.swift`'s CF-detection only matched 403 + "Just a
   moment"/"cf-mitigated" — real block-page variants (1015 rate-limit, etc.) don't all match those
   strings. Broadened to any error status + a wider marker list (purely additive). Live-verified
   end-to-end: FreeWebNovel's "Shadow Slave" now shows the Bypass button and `CFBypassView` opens with
   the real page source.
2. **Added 3 new reading modes** — `ReaderMode` grows from 3 to 6: Paged Vertical (new
   `VerticalPagedReaderView`, rotate-90°/counter-rotate TabView technique), Continuous RTL/LTR (new
   `ContinuousHorizontalReaderView`, mirrors `WebtoonReaderView`'s structure). Wired into both the
   in-reader settings picker and Settings' default-mode picker. Live-verified rendering without
   crashes; swipe-to-page interaction itself wasn't independently confirmed due to the pre-existing
   documented mobile-mcp swipe-simulation unreliability in this environment (see S87 below) — the
   rotation technique is SwiftUI-standard and low-risk.
3. **Added Secure Screen** (`AppSettings.secureScreenEnabled` + a `SecureScreenCover` overlay in
   `YomiApp.swift`, shown whenever `scenePhase != .active`) — hides app content from the App Switcher
   snapshot. Free (Tachimanga gates this behind premium), on-brand (Ink canvas + app icon). Toggle
   added next to App Lock in Settings. Live-verified: toggle persists, app backgrounds/resumes cleanly.
4. **Added an Updates Summary toast** — `UpdatesViewModel.refresh()` now returns the count of
   newly-discovered chapters (diffing chapter-id sets before/after); `UpdatesView` shows a "N new
   chapters found" / "No new chapters" toast for 2s after any manual or pull-to-refresh.
5. **Corrected two false positives in the parity doc itself** — "Global Update" and "Open random
   entry" were both already implemented (`UpdatesViewModel.refresh()` triggered from Updates' toolbar;
   Library's Shuffle button) and had been wrongly flagged as missing on the first pass. A reminder that
   even a "verified against source" audit needs a second look before triggering new work.

**Not yet started, still in `TACHIMANGA_PARITY.md`'s backlog**: double-page spread support (bigger,
riskier lift — needs care around spread-pairing/progress-tracking), expanded tap-zone presets, storage
composition view, network settings exposure, dated backup history, Tachiyomi-compatible *export*,
Customize Tabs, default tab, color blend slider, date format picker, the Migrate feature (source-to-
source library migration — a real standalone feature, not a quick add), and full multi-device CloudKit
sync (the single biggest item — needs its own architecture scoping session, same treatment S90 gave
the Suwayomi-server design before any implementation). Session continues from this point.

## Current state (post S98 — 2026-08-06 · Tachimanga parity pass, part 2 — the 4 items picked up from
S97's backlog: storage view, small round-out items, double-page spreads, Migrate)

**S98 continued the parity push, working through 4 backlog items from S97 in order of increasing
complexity.** All 4 shipped, live-verified via `build_run_sim` + mobile-mcp (plus direct sqlite
inspection for Migrate, where a UI limitation in this session's tooling made pure UI verification
insufficient — see below), zero build warnings throughout. 4 commits.

1. **Storage composition view** (`StorageManager.swift` + `StorageView.swift`, replacing
   `AdvancedSettingsView`'s undifferentiated clear-cache buttons) — a real byte-accurate breakdown of
   Downloads/Image cache/Plugins/Custom covers/Web cache/Database/Other, each computed via
   `FileManager` directory enumeration (Kingfisher's `diskStorageSize` for image cache,
   `URLCache.shared.currentDiskUsage` for web cache), with Manage/Clear actions per category. **Real
   bug found and fixed live**: a `GeometryReader` used directly as List row content (to measure the
   summary bar's width) destabilized every row's layout/hit-testing below it — rows became untappable
   and the List's own scroll position desynced from what the accessibility tree reported. Fixed by
   moving the summary bar entirely outside the `List` (a plain header above it), which is also just a
   more robust pattern in general for List-embedded charts.
2. **Small Library/Settings round-out items**: category item counts on Library's tab bar (the backing
   query, `CategoryQueries.fetchItemCounts()`, already existed for More → Categories but was never
   wired into the tab bar itself — now toggleable via `showCategoryItemCounts`); a Default Category
   setting (auto-assigns new library adds, both manga and novel paths); a Default Tab setting (which
   tab opens on launch, wired into `AppRouter.init()`); an editable request timeout (10-60s) in
   Advanced → Network — mirrored into a `nonisolated(unsafe)` module var (`jsBridgeRequestTimeout`)
   since `JSBridge`'s `SOURCE.fetch` reads it from `Task.detached`, where touching `AppSettings.shared`
   directly is unsafe per this project's concurrency rules; User Agent stays fixed (now with an
   explanation: it's bound to the Cloudflare-bypass WebView's solved-challenge cookie — Tachimanga
   exposing this control isn't actually replicable without breaking the CF bypass); tap zones expanded
   from 3 to 6 presets (Default/Edge/L-Shaped/Kindle-ish/Right & Left/Disabled). Also fixed
   double-tap-to-zoom in the manga page viewer while touching that code: it only ever reset to 1x
   before, not a real double-tap-to-zoom toggle.
3. **Double-page spreads** for the manga reader (Paged RTL/LTR) — Single/Double/Automatic (spreads in
   landscape) page layout, the reader-completeness item flagged as the #2 priority in
   `TACHIMANGA_PARITY.md`. Design constraint: `currentPage` is read from many places (progress
   tracking, resume, the scrubber) and had to keep meaning "a real index into `pages`" everywhere else
   — so `MangaReaderView`'s `TabView` selection goes through a proxy `Binding` that snaps any raw page
   index down to the start of its enclosing spread, rather than changing what `currentPage` means.
   Tap-zone navigation (`tapLeft`/`tapRight`) now moves by a whole spread for the same reason. Also
   generalized the "reached last page" checks (`== pages.count - 1`) to `>= pages.count - 2`, so the
   finished-chapter banner still fires correctly when an even page count's last spread starts one page
   short of the end. Live-verified against a real installed source (AquaManga, "Path of Vengeance"):
   single mode unregressed (advances 1 page/tap), double mode renders two pages side by side and
   advances by whole spreads (1 → 3 → 5, confirmed via the on-screen page counter).
4. **Migrate tab** — the biggest lift, and the last major gap: move a library manga to a different
   installed source, preserving reading status/notes/categories, with per-chapter read-state transfer
   matched by `chapterNumber` (sources essentially never agree on chapter IDs/paths, but do agree on
   numbering). New `MigrationService.swift` (pure GRDB logic, built entirely from already-proven query
   functions — `MangaQueries.upsert`, `ChapterQueries.setRead`/`updateProgress`,
   `CategoryQueries.assign`) and `MigrateView.swift` (library-title picker → per-source parallel search
   with match-count badges, reusing `GlobalSearchView`'s established pattern → confirmation → migrate).
   Reachable from Browse's segmented control (Sources / Global search / **Migrate**, new third option).
   "Migrate and remove old entry" vs. "...and keep old entry" mirrors Tachiyomi's replace-vs-keep
   convention. **Real bug found and fixed while live-verifying — not a tooling issue, though it looked
   exactly like one at first**: the confirmation dialog's `isPresented` binding was a computed
   `Binding` derived from `migrationTarget != nil`; SwiftUI's auto-dismiss-on-button-tap calls that
   binding's setter (clearing `migrationTarget`) as part of the same transaction as the tap, so
   `performMigration`'s `guard let target = migrationTarget` — reading the property again after a
   `Task` suspension point — raced and silently saw `nil`. From the outside this looked identical to a
   dead button: the dialog would dismiss, nothing would happen, no crash, no error. Cost real
   debugging time before the actual cause (a state-race, not a tap-delivery problem) was found; fixed
   by capturing the target by value in each button's closure instead of re-reading the observable
   property inside the async task. Live-verified end-to-end via `build_run_sim` + mobile-mcp + direct
   sqlite inspection of the simulator's `yomi.db` against two real installed sources (AquaManga →
   Asura Scans, searched "solo", 10 real matches with correct badge count, migrated "Path of Vengeance"
   → "Emperor of Solo Play"): new manga row correct (`inLibrary=1`, correct `sourceId`), chapter 1
   correctly carried `isRead=1, progress=1.0` matched by `chapterNumber`, old entry correctly preserved
   per "keep old entry."

**Tooling note for future sessions**: this session hit a **separate, real** class of tap-delivery
unreliability in `mobile-mcp` (distinct from the Migrate race bug above) — plain SwiftUI `Button`
actions (not `NavigationLink`s, which were reliably tappable throughout) intermittently failed to
fire when several navigation levels deep (e.g. More → Settings → Advanced → Storage), confirmed via
a completely untouched, pre-existing button ("Export diagnostic log") exhibiting the identical
symptom. Retrying the same tap 2-3 times, or a fresh `build_run_sim` relaunch, usually cleared it.
Not a code bug — but don't assume a dead-looking button is this tooling issue without first checking
for a state race like the Migrate one above; they can look identical from the outside.

`TACHIMANGA_PARITY.md`'s remaining backlog (dated backup history, Tachiyomi-compatible *export*,
Customize Tabs, color blend slider, date format picker, full multi-device CloudKit sync — the single
biggest remaining item, needing its own architecture scoping session like S90 gave the Suwayomi-server
design) is now genuinely just the long tail — every item explicitly called out as high-value in the
audit's own priority ordering is shipped.

## Current state (post S96 — 2026-08-06 · full functional app audit, not a design block)

**S96: the systematic functional audit Martin asked for at the end of S95** — every screen walked
live via `build_run_sim` + mobile-mcp, starting from a genuinely fresh install. Found and fixed 6
real bugs, plus root-caused a long-standing simulator mystery from S95. All fixes verified live,
zero build warnings throughout.

1. **Root cause of the S95 "doesn't match the mocks" complaint, more fundamental than Known Issue
   #15 alone: `AppSettings.canvasColors` didn't actually implement "follow device" for canvas `""`.**
   `colorScheme` correctly resolved `""` to `nil` (follow system), but `canvasColors` unconditionally
   returned Ink regardless of system appearance — so on a light-mode device, native chrome (nav bars,
   search fields, tab bar material) rendered light while every custom-drawn background rendered Ink
   dark. Since `""` is not even a selectable Appearance Studio option (only a silent legacy-migration
   fallback for a true fresh install) and onboarding never sets a canvas either, **every genuine
   first-time user on a light-mode device saw this exact mismatch.** Fixed at the true root:
   `AppSettings.init()`'s fresh-install migration branch now sets `canvas = "Ink"` (the documented
   default) instead of `""`, which self-heals `colorScheme` too since it already special-cases `"Ink"`.
2. Known Issue #15 (`LibraryView` root not wired to `\.yomiCanvas`) — fixed: added
   `.background(canvas.bg.ignoresSafeArea())` to its root, matching every view since S85.
3. **Real bug: "Get plugins" (Library/Browse empty-state CTA, and Onboarding's own final page)
   silently failed to deep-link into Plugins on a genuinely first-time visit to the More tab.**
   `MoreView`'s `.onChange(of: appRouter.openMorePlugins)` only fires on a transition *observed while
   the view is live* — if More had never been visited yet this session, the flag was already `true`
   by the time `MoreView` first mounted, so no change was ever observed and the deep-link silently
   no-op'd (landing on the plain More list instead). Onboarding had already independently worked
   around this with a 0.4s `DispatchQueue` delay hack (see its S95 comment); the real fix is
   `.onChange(of:initial: true)`, which also fires for the already-true-on-mount case. Verified live
   on a fresh launch: Library's "Get plugins" now correctly lands on Plugins every time.
4. **Real bug: Library's multi-select bulk-action mode (checkboxes + Mark read/Download/Remove
   action bar, built S82) was unreachable via long-press on grid cover cells**, and had no entry
   point at all in list mode. `MangaCoverCell`/`NovelLibraryCoverCell` each had both a `.contextMenu`
   and a separate `.onLongPressGesture(minimumDuration: 0.4)` on the same view — SwiftUI's
   `.contextMenu` interaction consistently wins that composition, so the custom long-press handler
   never fired (confirmed twice, deterministically, live). Fixed by removing the now-dead
   `onLongPressGesture` and adding a "Select" item to the top of each grid cell's context menu
   instead — verified live: long-press → "Select" → full checkbox/action-bar UI now works correctly.
   List mode's total absence of a selection entry point was left as-is (fixing it properly needs
   checkbox overlays + disabled row-navigation there too, out of proportion for this pass).
5. **Real bug, broad impact: manually marking chapters read (Updates screen's mark-read/mark-all,
   and Detail's own per-chapter/bulk mark-read toggles) never updated the manga/novel's `lastReadAt`
   column** — only the reader's own auto-mark-on-finish path did. Confirmed live: marking Hellogin's
   chapters read via Updates' "Mark all read" left it permanently invisible in History (which filters
   on `lastReadAt`), and would equally have gone stale in Library's "last read" sort and the Continue
   card. Root cause: `ChapterQueries.setRead()` and `NovelQueries.markRead(chapterId:)`/
   `markAllChapters()` never called `MangaQueries.touchLastRead()`/`NovelQueries.touchLastRead()`,
   unlike their sibling functions (`markRead(id:mangaId:)`, `ChapterQueries.markAllRead(mangaId:)`)
   which already did. Fixed at the query layer (added `NovelQueries.touchLastRead(novelId:)`,
   threaded `mangaId`/`novelId` through both functions) — touches every call site: Updates (both
   manga+novel, single+bulk), `MangaDetailView`'s per-chapter toggle + "mark previous read",
   `NovelDetailView`'s equivalents, and `TextReaderView`'s own chapter-read/chapter-advance calls
   (which had the same gap even in the *organic* reading flow, not just Updates). Verified live:
   History correctly picks up a manga the moment `lastReadAt` is set.
6. **Root-caused the S95 "mysterious `#00FF00` accentColor survived `simctl uninstall`" mystery
   (Known Issue #16) — not a Yomi bug at all.** Hit the same phenomenon again this session, this time
   on `hasSeenOnboarding` (read back `true` on a supposedly-fresh install, causing Onboarding to not
   appear). Traced it: iOS Simulator's `cfprefsd` daemon caches app preferences at a **device-level**
   path — `.../data/Library/Preferences/<bundleid>.plist` — independent of the app's per-install Data
   Container UUID. `simctl uninstall` removes the app bundle and its Data Container but does **not**
   reliably clear this device-level `cfprefsd` cache, so old `UserDefaults` values can silently
   survive a full uninstall+reinstall. Workaround (now the correct QA procedure for this project,
   superseding the S95 "check for stale state" note): `xcrun simctl terminate` + `uninstall`, **then
   explicitly `rm` `.../data/Library/Preferences/<bundleid>.plist` and `launchctl stop
   com.apple.cfprefsd.xpc.daemon`** on the simulator, before reinstalling — a plain uninstall is not
   sufficient for genuine fresh-install testing on this simulator. Saved to memory
   (`feedback_yomi_qa_state`, superseding its prior "stale UserDefaults" framing with this concrete
   root cause + fix).
7. **Not a Yomi bug, informational**: 3 of 4 novel sources tried this session (LightNovelPub,
   BoxNovel, BabelNovel) currently return "No titles found" — confirmed via direct `curl` from a real
   browser UA that all 3 are presently bot/Cloudflare-gated site-side (LightNovelPub/BabelNovel: raw
   HTTP 403; BoxNovel: HTTP 200 but a JS-only anti-bot redirect shell, no real HTML). The app's
   generic "may be down or Cloudflare-protected" error message is accurate for all three. NovelBin
   (novelarrow.com backend, rewritten S88) still works correctly and was used for the rest of this
   session's novel testing instead.

**Full walkthrough coverage this session** (all live via `build_run_sim` + mobile-mcp, not just code
review): Library (both empty states, list+grid, multi-select, category tabs), Browse (source list,
Popular carousel, install flow), Manga Detail + Reader (paged RTL + webtoon auto-detect via
`autoWebtoonFromTags`, resume tracking), Novel Detail + Reader (NovelBin, theme switching, TTS
button), History, Updates (row tap → resume oldest-unread, long-press mark-all-read, filter →
Update Rules), Downloads (download → row → delete-all → confirm), Insights (stat cards, heatmap,
Most Read), More/Settings/Appearance Studio (canvas/accent live-switching)/About, and a full
Onboarding walkthrough (all 3 pages, accent tint correct, final CTA deep-links into Plugins).

**Addendum, same session — Martin's live visual review caught 2 more real bugs the walkthrough
missed:**
8. **Systemic `.glassEffect()` misuse across the whole app**: every glass panel used
   `.background { RoundedRectangle(...).glassEffect() }` — a documented iOS 26 gotcha where the
   parameterless `glassEffect()` doesn't reliably clip to the declared shape and can render as a
   Capsule instead. Circular chips looked fine by coincidence; wide panels (both readers' bottom
   bars, Library's selection action bar) rendered as an oval/blob instead of a rounded rectangle —
   most visible on the novel reader's settings panel, which Martin screenshotted looking like a gray
   blob overlapping the text. Fixed all 6 call sites to `.glassEffect(.regular, in: <Shape>)` applied
   directly to content.
9. The native `Slider` (manga reader page scrubber, novel reader font-size control) clashed
   visually with the rest of the app's thin-capsule-progress-bar design language — its default iOS 26
   thumb is a large white pill. Built `Core/YomiScrubber.swift`, a small custom scrubber matching the
   existing aesthetic, and swapped it in at both call sites.

**Addendum 2, same session — App Store exposure question raised by Martin.** Flagged: the LNReader
featured repo (500+ novel sources) was a one-tap "Add" button in the Plugins screen, reachable
straight from Onboarding's first-launch flow — more turnkey than the S90 precedent, which
deliberately kept the Suwayomi server address *out* of the binary (manual paste from README only)
specifically to reduce App Store review exposure. The underlying 2.5.2 compliance story is solid
either way (JavaScriptCore execution is Apple's documented exemption, live precedent: Paperback,
Aidoku, Tachimanga — see `RESEARCH.md` §5/§15) — this was purely about how turnkey the in-app
experience *looks* to a reviewer. Martin's call: match the Suwayomi treatment. Changed
`FeaturedRepoRow`/`AddRepoFeaturedRow` (`PluginsView.swift`) from an instant-install "Add" button to
a "Copy URL" button (with brief "Copied" feedback) — the user now copies the URL and pastes it into
the same sheet's Custom URL field themselves, identical friction to the Suwayomi flow. Also fixed
`README.md`, which is the canonical "how to install repos" guide (linked in-app as "Plugin setup
guide"): it still said "Browse → Extensions" (that tab was removed in S86 — it's "More → Plugins"
now) and its instructions now match the new copy-then-paste flow.

App Store screenshot work can now proceed — this was the last blocker noted at the end of S95.

---

## Current state (post S95 — 2026-08-05 · Blocks 11-12 — design track complete)

**S95: implemented Blocks 11 (More+Settings, N.07/N.10) and 12 (Onboarding+empty states, N.08/N.09)
— all 12 blocks of the design track are now done.** Session started from user feedback that the
simulator "looked nothing like" the mocks; the investigation and fixes below came out of that audit,
not just the two remaining blocks.

**Audit findings before starting new blocks:**
1. Accent color appeared blue instead of Vermilion in Appearance Studio — **not a code bug**: stale
   `UserDefaults` from earlier manual testing on this long-lived dev simulator (confirmed
   `AppSettings.swift`'s code default was always correct `#E5473A`). Martin fixed it live by tapping
   the red swatch. Saved as a standing QA lesson (memory `feedback_yomi_qa_state`): rule out stale
   simulator state before treating an accent/canvas mismatch as a code bug.
2. Known Issue #13 (custom fonts maybe never rendered, open since S89) — **resolved, was never
   actually broken.** Verified live via a temporary debug print: `UIFont.familyNames`/
   `fontNames(forFamilyName:)` confirm Space Grotesk and Space Mono both register correctly and
   `UIFont(name: "Space Grotesk", size:)` resolves a real font. Removed from Known Issues.
3. **Real bug found + fixed: `ContinueHeroCard`'s Resume button was clipped.** The text `VStack`
   next to the 74×104pt cover thumb had `.frame(height: 104, alignment: .top)` — copied from the
   cover's height assuming a single-line title. With a 2-line title (common), content overflowed
   past 104pt, and since the whole card is `.clipShape(RoundedRectangle)`'d (which also clips
   hit-testing, not just drawing), the overflow portion of the Resume button was neither visible nor
   tappable — exactly matching the user's two complaints (visually cropped button, taps landing on
   the wrong thing). Fix: removed the incorrect fixed height; the HStack now sizes naturally.

**Block 11 (More + Settings) — N.07/N.10:**
`MoreView.swift` rebuilt from a native `List`/`Section` to the card system (mono section headers,
`s1`-background cards, 29×29 icon chips, chevrons) — the existing section grouping (App/Library/
Sources/Reading/Tracking/Data/About) already matched N.10 exactly, so this was a pure restyle, no
information-architecture changes. `SettingsView.swift` similarly rebuilt against N.07: toggle rows,
a custom pill stepper (matching the mock's −/count/+ control) for "Items per row"/"Concurrent
downloads", and the "Sources & Servers"/"Advanced" sections (real features with no mock equivalent)
restyled to match rather than removed. About was split in two, matching the mock's own split:
Settings' own About card is now the compact Version+GitHub mock shows; the previously-duplicated
Build/Report-a-bug/Privacy-Policy content now lives solely in a new dedicated `AboutView` (More →
About), avoiding the duplication that existed before. Real Swift 6/SwiftUI bug found + fixed:
`Color.clear.frame(width: 44)` (used as a symmetric spacer to center the glass nav bar's title,
opposite the back chip) has no height constraint, so `Color` — which is greedy in any unconstrained
dimension — expanded to fill the *entire* height `.overlay(alignment: .top)` proposes (the whole
ScrollView's height), stretching the nav bar's HStack and its `.background()` to cover the full
screen, pushing the actual back-chip/title content down to wherever it happened to land relative to
scrolled content. Every other file in the app that needed this symmetric-spacer trick used
`.frame(width: 44, height: 44)` already (an explicit height); this one omission is what broke it.
Fixed in both `SettingsView.swift` and the new `AboutView`. Verified live via `build_run_sim` +
mobile-mcp: both screens' glass nav bars now render correctly pinned to the top, all rows/toggles/
steppers function, back buttons dismiss correctly. Zero build warnings.

**Block 12 (Onboarding + empty states) — N.08/N.09:**
New `Core/YomiEmptyState.swift` — a reusable empty-state component (boxed icon, title, message,
optional accent-pill action) generalizing N.09's bespoke Library glyph into a reusable boxed-SF-Symbol
treatment, since N.09 explicitly speced only the Library case but the "empty states" block name is
plural. Replaced all 12 non-search `ContentUnavailableView` call sites across `LibraryView`,
`CategoryView`, `DownloadsView`, `UpdatesView`, `BrowseView` (×4), `OPDSBrowseView` (×2), and
`HistoryView` — `ContentUnavailableView.search(text:)` call sites were left native (system-provided,
no mock equivalent, and users already recognize that pattern). `OnboardingView.swift` rebuilt
against N.08: one shared `OnboardingPage` template (150×150 icon box, wordmark/title, description,
page dots, full-width accent CTA, optional mono caption) reused across all 3 pages with per-page
content, since the mock only speced page 1's visual language, not unique page 2/3 content. Two more
real bugs found + fixed while live-verifying: (1) `UIImage(named: "AppIcon")` does not reliably load
an `.appiconset` entry — added a plain `OnboardingIcon.imageset` (a duplicate copy of
`AppIcon-Ink-1024.png`) since appiconsets aren't meant to be loaded that way; (2) every
`Color.accentColor` use in `OnboardingView` rendered as system blue instead of Vermilion, because
`fullScreenCover` presents a **separate view hierarchy that does not inherit `.tint()`** from the
presenting view — `YomiApp.swift` sets `.tint()` on `ContentView()`, not on the cover's content.
Fixed by adding an explicit `.tint(Color(hex: AppSettings.shared.accentColor))` directly on
`OnboardingView`. While chasing why onboarding wouldn't even appear during testing, found and fixed
a third, unrelated pre-existing bug: `YomiApp.swift` chained **two separate `.fullScreenCover`
modifiers on the same view** (`showOnboarding` and `isLocked`) — SwiftUI only reliably tracks one
presentation slot per view identity this way, so the first (`showOnboarding`) was silently never
presented, meaning **no user has seen onboarding since this pattern was introduced**, regardless of
`hasSeenOnboarding`. Merged into a single `.fullScreenCover` with a computed `Binding` and
if/else content (lock screen takes priority over onboarding). Verified live end-to-end via a full
`simctl uninstall` + reinstall (to force a genuine first-launch, since the normal dev simulator has
`hasSeenOnboarding=true` from months of testing): all 3 onboarding pages, the "Open Plugins"
completion action, and the real Ink app icon all render and function correctly.

**New findings, not fixed this session (for next session's planned full audit):**
- `LibraryView`'s root background is not wired to `\.yomiCanvas` — after the `simctl uninstall` test
  above, Library rendered with a plain white/system-light background instead of the Ink canvas
  (visible immediately since canvas resets to `""`/follow-device on a fresh install, and Library,
  unlike every view touched since S85, has no `.background(canvas.bg)` on its root). Block 1 was
  implemented S82, before the canvas-wiring convention was established/audited (S85's Phase 0 pass
  covered the reading surfaces, not necessarily every root list background). Needs the same
  `.background(canvas.bg.ignoresSafeArea())` treatment Blocks 3+ already use.
- A stale `#00FF00` (pure debug green) `accentColor` value was found surviving a full
  `simctl uninstall`, on this specific long-lived dev simulator — root cause not identified (not in
  any `.swift` source, scheme file, or MCP session config checked). Manually reset via
  `defaults write ... accentColor "#E5473A"`. Worth a clean-simulator sanity check next session if
  accent color ever looks wrong again after a fresh install.
- **This session's `simctl uninstall` testing wiped the dev simulator's accumulated library/download/
  history test data** (built up over 90+ sessions) — the app container is gone, not recoverable.
  Not a regression (test data only), but the next session starts from a genuinely empty library.

**Next session (per Martin's explicit request): a complete, systematic app audit** — every button,
scroll, swipe, and setting; Browse, History, Updates; manga/novel Detail; both readers; ideally
starting from the now-empty simulator to also evaluate the true first-time-user experience
(Onboarding → install a plugin → Browse → add to Library → read) end to end, not just individual
screens in isolation.

## Current state (post S94 — 2026-08-05 · Block 10 — Insights)

**S94: implemented Block 10 (Insights) of the 12-block design track against N.14 in
`YOMI Screens.dc.html`. Blocks 1-10 of 12 are now done; Block 11 (More+Settings) is next.**

`InsightsView.swift` (already a real, GRDB-backed stats screen from an earlier non-design-track pass —
streak/chapters/time/titles-started stat logic, per-title time tracking, a hand-rolled GitHub-style
contribution calendar — none of it ever restyled to the design system) was rebuilt against N.14's
floating-glass-chrome-over-content treatment, same family as Detail/Downloads (Blocks 3-5, 9):
`.toolbar(.hidden, for: .navigationBar)` + `.overlay(alignment: .top) { glassNavBar }`, single back
`.glassChip()` (no trailing action — N.14's mock has none). The 4 stat cards were restyled to match
the mock exactly (large Grotesk number + Space Mono label, no icon, no unit line — the previous
`StatCard` had all three); the mock's placeholder count of 4 lined up with the 4 stats already
computed (day streak, chapters read, time read, titles started), so no new stat was invented or
dropped. The old "Reading Activity" calendar (13 weeks, day-of-week row labels, per-column month
labels — a heavier GitHub-contribution-graph clone) was replaced with a new, simpler
`ActivityHeatmap` matching N.14's actual mock: a single `surface1` card holding a 7-row × 18-column
opacity grid (label reads "ACTIVITY · LAST 18 WEEKS" — real 18-week window, not the mock's
`hint-placeholder-count="70"` which is inconsistent with its own label) plus a legend row (oldest
month · LESS→MORE swatches · newest month) instead of per-column month labels. Opacity is
quartile-bucketed against that window's own max daily count (0.14/0.45/0.8/1.0, matching the legend
swatches exactly) rather than a continuous gradient, so the legend is literally true of the cells.

The old "Breakdown" (manga vs. novel time split) and "By Title" sections were replaced by N.14's
single "MOST READ" section — same underlying per-title time-spent computation as the old "By Title"
list, but restyled to the mock's exact row spec: real 34×48pt cover art (previously the mock's own
mini colored-gradient-letter-mark placeholder, not applicable here since real cover URLs already
exist), title + `Notation.readingTimeShort()` value on one line, a 5pt accent capsule bar below sized
relative to the top title's time. Breakdown (manga/novel split) had no equivalent in the mock and was
dropped rather than kept as an extra, non-spec section — consistent with how Block 6 (Browse, S86)
dropped its own duplicate "Extensions" sub-tab.

Real Swift 6 finding, project-wide relevance: `Manga.resolvedCustomCoverPath` and
`Novel.resolvedCustomCoverPath` (both simple, stateless path-string computed properties — no actor
affinity of their own) are MainActor-isolated purely because `SWIFT_DEFAULT_ACTOR_ISOLATION =
MainActor` applies to structs/enums, not just classes — the exact same class of bug S91 found and
fixed in `Notation`. Neither had ever been called from a `Task.detached` context before this session
(the "Most Read" cover-lookup is the first caller to do so); both are now `nonisolated` at the
property level. Any future struct with a MainActor-inferred pure computed property should get the
same fix the moment it needs to run off-MainActor, rather than restructuring the call site.

Verified live via `build_run_sim` + mobile-mcp against real on-device reading history (not seeded
placeholders): all 4 stat cards computed correctly (2-day streak, 8 chapters, 6m, 7 titles), the
heatmap's edge-month legend read "APR" → "AUG" (today is 2026-08-05, 18 weeks back lands in April) and
lit up real activity days at the correct opacity tier, and all 5 "Most Read" rows rendered real cover
art, correct `Notation.readingTimeShort()` values, and correctly-proportioned bars (down to
"Chainsaw Man" at the bottom, smallest bar). Back button confirmed dismissing correctly. Zero build
warnings.

---

**S93: implemented Block 9 (Downloads) of the 12-block design track against N.13 in
`YOMI Screens.dc.html`. Blocks 1-9 of 12 are now done; Block 10 (Insights) is next.**

`DownloadsView.swift` rebuilt against N.13, which — unlike History/Updates (Blocks 7-8, native
`.navigationTitle`) — uses the same floating-glass-chrome-over-content treatment as Detail
(Blocks 3-5): `.toolbar(.hidden, for: .navigationBar)` + `.overlay(alignment: .top) { glassNavBar }`
with `.glassChip()` back/trash buttons, reusing `MangaDetailView`'s exact `glassNavBar` pattern
rather than the native-title-bar convention, since N.13's mock is a scrolling content sheet under
floating chrome, not a flat title-bar screen. Content is two sections: "DOWNLOADING · N" (unchanged
behavior, one row per active/queued chapter job with a thin accent progress bar, re-skinned to the
44×62pt cover + Space Mono note row style) and "DOWNLOADED" — **consolidated from one row per
downloaded chapter to one row per manga** (same per-title consolidation call as Updates in S92),
showing "N chapters · size" and pushing into `MangaDetailView` (which already has full per-chapter
download management — multi-select, swipe/context-menu delete — so no new per-manga chapter-list
view was needed). Footer shows total "X MB USED · N CHAPTERS".

Two small backing-model additions: `DownloadManager.directorySize(mangaId:)` (new `nonisolated`
method — recursive `FileManager` byte count per manga's downloads folder, since no size was
previously tracked in the DB) and `DownloadManager.queueMangas: [Manga]` (replaces the old
`queueMangaTitles: [String]` — the view needs real `Manga` objects for cover art per queued row, not
just title strings). Real Swift 6 finding: `DownloadManager.shared` (the static property itself, not
just its methods) is MainActor-isolated under this project's actor-isolation default — calling
`directorySize` from `Task.detached` required capturing `let manager = DownloadManager.shared` on
MainActor *before* entering the detached task, same pattern already documented for
`ExtensionManager.shared.bridge(for:)`.

Deviations from the header row icon spec, both judgment calls (no established affordance existed for
either): the mock's queue-row "pause" icon (two vertical bars) has no real pause/resume capability in
`DownloadManager` (only cancel), so it was rendered as `xmark.circle` (cancel) instead of a pause
glyph that would misrepresent what the button does. The header's floating trash button maps to a new
`deleteEverything()` global action gated behind a `.confirmationDialog`, matching History's S91
"Clear all" convention, and only appears once there's something to delete.

Verified live via `build_run_sim` + mobile-mcp against real downloads (Asura Scans chapters, not
placeholders): downloaded 4 real chapters, confirmed the per-manga "4 chapters · 60 MB" row and "60
MB USED · 4 CHAPTERS" footer computed correctly from real on-disk file sizes, row→Detail navigation,
long-press → per-manga "Delete all downloads", and the header trash → confirmation → delete-all →
correct empty state. The active/queued progress-bar row was code-reviewed but not caught live —
Asura Scans chapters download in well under a second, faster than the screen could be reached.
Zero build warnings.

**S92: implemented Block 8 (Updates) of the 12-block design track against N.12 in
`YOMI Screens.dc.html`. Blocks 1-8 of 12 are now done; Block 9 (Downloads) is next.**

`UpdatesView.swift` moved from a native `List`/`.insetGrouped` layout (one `Section` per manga/novel,
one row per new chapter) to `ScrollView` + `LazyVStack` grouped by date bucket (Today/Yesterday/This
week/This month/Earlier), matching N.12 and the same structural move Library/Browse/History already
made. **This is a real behavior change, not just a visual one**: the mock's `it.title`/`it.note`/
`it.count` row shape is one summary row per title (not per chapter), so the old per-chapter row list
was consolidated into a single row per manga/novel showing a chapter-range note (new
`Notation.chapterRange(low:high:)`, e.g. "CH. 002–008") and a count pill. Two behaviors that were on
the old per-chapter rows had no direct equivalent in the mock and needed a judgment call:
1. **Per-chapter tap-to-read** — replaced by a trailing circular "start reading" icon button
   (`arrow.down.circle`, matches the mock's circular glyph) that jumps straight into the reader at
   the *oldest* unread new chapter, reusing the existing `loadMangaReader`/`loadNovelReader` methods
   unchanged. Picking a specific chapter (not just the oldest) is still possible — tapping the row
   body now navigates to the title's Detail view (History's existing convention), where the full
   chapter list remains browsable exactly as before.
2. **"Mark all read" header button** — moved to a long-press `.contextMenu` per row (`ScrollView`/
   `LazyVStack` has no native section headers to hang a button off, and no `.swipeActions` — same
   constraint History hit in Block 7), reusing `UpdatesViewModel.markAllMangaChaptersRead`/
   `markAllNovelChaptersRead` unchanged.
3. **The mock's second header icon** (a filter/lines glyph, next to refresh) had no stated behavior.
   Interpreted as a shortcut into the existing update-filter settings — `SettingsView.swift`'s
   `UpdatesSettingsView` (the "Update rules" toggles: notifications, skip-if-unread/not-started/
   completed, excluded categories) was previously only reachable via Settings → Downloads and was
   `private`; un-privatized it and added a direct `NavigationLink` from Updates' toolbar.

Also extracted `Notation.dateGroupLabel(for:)` + `Notation.dateGroupOrder` (Today/Yesterday/This
week/This month/Earlier bucketing) out of `HistoryView.swift`'s private `dateGroupLabel` — now shared
between History and Updates rather than duplicated, since both screens need identical date-bucket
grouping. Verified live via `build_run_sim` + mobile-mcp against real on-device data (not
placeholders): row tap → Detail navigation, start-reading icon → opens reader at the correct oldest
unread chapter (CH. 002 of a 002–008 range), long-press → "Mark all read" empties the row and shows
the correct empty state, and the filter icon → "Update Rules" settings screen. Zero build warnings.

**S91: implemented Block 7 (History) of the 12-block design track against N.11 in
`YOMI Screens.dc.html`, the block explicitly deferred across S87-S90's bugfix/infra sessions.
Blocks 1-7 of 12 are now done; Block 8 (Updates) is next.**

`HistoryView.swift` rewritten from a native `List`/`.insetGrouped` layout to `ScrollView` +
`LazyVStack` with custom section headers and rows — the same structural move Library and Browse
already made in earlier blocks, needed here for full control over the N.11 row spec (44×62pt cover,
single-line truncating title, Space Mono catalog-notation subtitle, right-aligned adaptive
timestamp + a MANGA/NOVEL kind pill) that a boxed `insetGrouped` List can't produce. Kept the
existing native `.navigationTitle` + `.searchable()` combo rather than building the mock's custom
26px header/search-pill from scratch — this matches the precedent already screenshot-verified in
Blocks 1-6 (Library, Browse both do the same thing), not a fidelity gap.

**Behavior changes from the fidelity pass:**
1. **Row subtitle now shows real catalog notation** ("CH. 042 · read to 68%" while a chapter is
   in-progress, "CH. 042" once it's finished) instead of the raw chapter title string. New
   `Notation.chapterReadTo(chapter:fraction:)` and reused `Notation.chapter()`. For manga, "touched"
   chapter selection mirrors `ContinueHeroCard.loadMeta()`'s existing pattern exactly (`isRead ||
   progress > 0`, sorted by `readAt`); for novels it mirrors the prior `HistoryView` in-progress vs.
   last-fully-read logic that already existed. Source name (e.g. "MangaDex") was dropped from the
   row per spec — detail is one tap away in Manga/NovelDetailView, and the kind pill now carries
   that visual slot instead.
2. **New `Notation.historyTimestamp(_:)`**: adaptive right-aligned time — "14:20" (today), "MON"
   (within 7 days), "JUL 28" (older) — matching N.11's three-tier time format. Independent of the
   existing 5-bucket section grouping (Today/Yesterday/This week/This month/Earlier), which was kept
   as-is since it's strictly more useful than the mock's 3-bucket illustrative example.
3. **Per-row delete moved from swipe/`EditButton` to long-press `.contextMenu`** ("Remove from
   History"), matching the `.contextMenu` convention `LibraryView` already uses for its list rows —
   `ScrollView`/`LazyVStack` doesn't support native `.swipeActions` (a `List`-only modifier), and the
   design has no visible edit-mode affordance. The "Clear all" toolbar action is now a plain
   Space Mono "Clear" text button (secondary/`tx2` color, per spec) instead of a trash icon; the
   `EditButton` is gone entirely.

**One real Swift 6 finding, not specific to this screen**: `Notation`'s static formatters are
implicitly MainActor-isolated under this project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
setting — calling `Notation.chapter()`/`chapterReadTo()` from inside `loadHistory()`'s
`Task.detached` block (needed to keep chapter-fetch DB work off MainActor) produced two Swift 6
concurrency errors. Fixed by marking the whole `enum Notation` `nonisolated` — it's pure, stateless
string formatting with no MainActor-only dependencies, so this is safe and now lets any future
screen call it from a background context too, not just this one.

Verified live end-to-end via `build_run_sim` + mobile-mcp against the real on-device library/history
data (not placeholder data): grouping, adaptive timestamps, catalog-notation subtitles, in-place
search filtering, manga→`MangaDetailView` and novel→`NovelDetailView` navigation, and long-press
"Remove from History" all confirmed working. Zero build warnings after the `nonisolated` fix.

## Current state (post S90 — 2026-08-05 · Suwayomi hosting architecture session, NOT a design block)

**S90: user's stated goal — "all Yomi users should be able to use Keiyoushi manga sources without
hosting Suwayomi-server, just like LNReader" — i.e. remove the self-host barrier to entry entirely.
No app code changed net this session (see below); the output is a hardened, ready-to-run deploy
package plus a documented decision on how it's exposed to the app. Block 7 (History) is still next
— this was explicitly deferred in favor of frontend work, see decision at the end.**

**Two architecture options were weighed.** (A) grow Yomi's own hand-written JS manga-plugin catalog
(the actual LNReader model — LNReader doesn't use Keiyoushi either, it has its own JS plugin repo)
vs. (B) host one shared Suwayomi-Server so every user gets all 1,368+ Keiyoushi extensions with zero
setup. User chose B explicitly: Keiyoushi is community-maintained and constantly updated, whereas
hand-written plugins need Martin to personally fix them whenever a source changes layout (exactly
what S87/S88 were — 3 broken scrapers fixed by hand that session alone).

**First implementation attempt was wrong and reverted.** Initially wired the shared server in as
`AppSettings.suwayomiURL`'s literal default (with a one-tap "Use Yomi Community Server" button in
`SettingsView.swift`) so every fresh install would auto-connect. User caught this: baking a
scraping-source bridge into the **App Store–reviewed binary itself** — as a default or an in-app
shortcut — is a materially different compliance posture than a user manually pasting a URL, and
risks App Review treating the binary as shipping with built-in piracy-adjacent access. Both files
were reverted to their exact original state (build-verified clean after revert). The fix instead:
**the server address lives only in `README.md`'s Keiyoushi row** — same pattern as the LNReader repo
URL directly above it — a manual copy-paste into the existing empty `Settings > Suwayomi Server`
field, never touching the binary. `git status` after this session shows only `README.md` changed in
the whole iOS repo.

**Deep research (forked, ~56 tool calls) surfaced one finding that mattered more than anything
technical**: running a *shared* server means Martin's own account/IP is the one issuing every scrape
request to third-party manga sites on behalf of every Yomi user — a more centralized, identifiable
role than each user self-hosting individually. When Kakao Entertainment sent legal threats to
Tachiyomi's contributors in Jan 2024, the app itself never hosted or fetched content (each user's
own device did) and that was still enough to end the project — this setup is a more exposed posture
than that. User accepted the tradeoff consciously after being shown the precedent, with two
mitigations: keep the deploy fully disposable, and keep Martin's name out of anything public
(WHOIS, hostnames, commits).

Research also found concrete technical gaps in the first deploy draft, both fixed in the final
design: Suwayomi-Server ships with **no auth by default** and its own wiki recommends enabling it
for public hosting (the open WebUI/API could otherwise let anyone install/remove extensions for
every user, not just browse); and a single shared IP means target manga sites can rate-limit/block
based on aggregate traffic from every Yomi user at once, not per-user behavior.

**Final hardened design** (`~/Desktop/Projects/Yomi/SuwayomiServer-Deploy/`, not part of this git
repo): Oracle Cloud "Always Free" ARM VM (2 OCPU/12GB RAM, confirmed still free-forever in 2026
research despite a mid-2026 halving from 4/24 — the only free tier with enough egress headroom;
Google Cloud's free e2-micro was checked and rejected for a ~1GB/month egress cap that an
image-serving proxy would exhaust immediately) running Suwayomi-Server + Caddy + `cloudflared`
behind a **Cloudflare Tunnel** — the VM has zero open inbound ports except SSH, since the tunnel is
outbound-only from the VM's side. Caddy applies scoped Basic Auth: only the 8 exact REST paths
`SuwayomiService.swift` calls stay open with no credentials (enumerated explicitly in `Caddyfile`'s
`@adminPaths` matcher, kept in sync with the service by hand), everything else (WebUI, extension
install/uninstall, settings, GraphQL) requires a password. VM hardened with key-only SSH, `ufw`,
`fail2ban`, `unattended-upgrades`. Needs one real domain (not free — recommended `.dev` via
Cloudflare Registrar, ~$12/yr, chosen over cheaper `.xyz`/`.site` TLDs specifically because those get
blocked by some corporate/school network filters) since a stable Cloudflare Tunnel hostname requires
a zone in the account, unlike the DuckDNS-based first draft.

**Deliverables**: `docker-compose.yml`, `Caddyfile`, `.env.example`, `.gitignore`,
`install-extensions.sh` (bulk-installs Keiyoushi extensions by language via REST, verified the repo
URL against `keiyoushi/extensions-source` to guard against impostor repos that circulated after the
2024 Tachiyomi shutdown), and `DEPLOY.md` as the source-of-truth walkthrough. Also published an
interactive HTML checklist artifact mirroring `DEPLOY.md` (7 phases, persistent per-step checkboxes,
copy-to-clipboard command blocks) for Martin to actually work through when deploying.

**Full project cost audit performed** (grepped SPM deps, entitlements, Swift source for any paid
SDK): only two real recurring costs exist anywhere in the project — Apple Developer Program ($99/yr,
confirmed not yet enrolled) and this new domain (~$12/yr, not yet purchased), ~$111/yr total. GRDB
and Kingfisher are the only two dependencies (both open source). `import StoreKit` in
`ChapterReaderView`/`TextReaderView` is only the review-prompt API, not IAP. The old `Backend/`
folder (abandoned pre-S41 Node/Railway proxy attempt, superseded by the Suwayomi bridge) was
confirmed by the user to already be deleted from Railway — not a hidden ongoing cost.

**Decision to defer deployment**: nothing in `SuwayomiServer-Deploy/` has actually been deployed yet
— domain purchase and Oracle/Cloudflare account setup are still ahead, entirely on Martin. Explicitly
deprioritized versus frontend work: this server is a supplementary feature with no ship deadline,
while Blocks 7-12 are the only thing blocking App Store screenshots and submission. **Next session:
Block 7 (History)**, in a fresh session to conserve context, since this session's research/design
work is fully captured here and doesn't need to stay loaded to continue frontend work.

---

## Current state (post S89 — 2026-08-05 · Keiyoushi/Suwayomi root-cause + fix session)

**S89 (2026-08-05): User asked how Tachimanga makes Keiyoushi work via Suwayomi-Server "the same
way LNReader works" and reported the existing Suwayomi bridge (shipped S41) still doesn't work in
practice. Found and fixed two real, independent bugs that fully explain why — not a design block;
Block 7 (History) is still next.**

Researched Tachimanga's actual architecture first (per the "never say impossible without asking
the second question" rule): confirmed it does **not** embed Keiyoushi — like Yomi, it's a thin
client against a **separately self-hosted Suwayomi-Server** (Docker/JVM/standalone jar, port 4567).
So there's no shortcut Tachimanga has that Yomi's architecture doesn't already have. But two real
bugs meant the existing bridge could never have worked even with a server configured:

1. **No App Transport Security exception, at all (new Known Issue, fixed this session).**
   `Yomi/Info.plist` had zero `NSAppTransportSecurity` config. Self-hosted Suwayomi-Server is
   almost always plain `http://` on a LAN (`http://192.168.x.x:4567`) — iOS blocks that silently
   by default. Any Suwayomi URL the user configured would fail at the network layer before ever
   reaching `SuwayomiService`. **While fixing this, found the actual mechanism was broken too**:
   the project used `INFOPLIST_ADDITIONAL_FILE` (pointing at `design/Fonts/YomiFonts.plist`) to
   merge extra keys into the `GENERATE_INFOPLIST_FILE = YES` auto-generated Info.plist — this
   silently does not merge anything (verified: `UIAppFonts` was never actually present in the
   compiled Info.plist either, going all the way back to when it was introduced in S80). **This
   means Space Grotesk/Space Mono custom fonts have likely never been registered/rendering in the
   app at all since the design system shipped in S80** — the whole app has probably been silently
   falling back to the system font this entire time. Fixed by switching the main app target from
   `GENERATE_INFOPLIST_FILE` to an explicit `Yomi/Info.plist` (same pattern `YomiWidget` already
   used successfully), with `UIAppFonts` and `NSAppTransportSecurity` (`NSAllowsArbitraryLoads`)
   written directly into it, plus adding `Info.plist` to the `Yomi` folder's
   `PBXFileSystemSynchronizedBuildFileExceptionSet` (needed or the synced-folder resource copy and
   the `INFOPLIST_FILE` build step both try to produce the same output path). Verified via
   `plutil -p` on the compiled bundle: both keys now present. **Next session: confirm live whether
   custom fonts are now visibly different from before** (screenshot compare) — could not do this
   tonight without the user around to eyeball a subtle typography diff.
2. **`SuwayomiService.fetchChapters()` had the wrong REST path (new Known Issue, fixed this
   session).** Called `/api/v1/manga/{id}/chapter/list?onlineFetch=true` — this 404s on a real
   Suwayomi-Server. The correct endpoint is `/api/v1/manga/{id}/chapters` (plural, no `/list`).
   This means **every Suwayomi/Keiyoushi manga would show "No chapters found," unconditionally**,
   regardless of the ATS bug — confirmed by direct `curl` against a real server. One-line fix.

**Both fixes live-verified end-to-end**, not just code-reviewed: downloaded and ran a real
Suwayomi-Server v2.3.2243 locally (no Docker on this Mac — used the bundled-JRE macOS-arm64
tarball release, standalone `bin/Suwayomi-Server.jar`, H2 embedded DB, `rootDir` pointed at a
scratch dir), added the real Keiyoushi repo
(`https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json`, via GraphQL
`addExtensionStore(indexUrl:)`) — 1,368 real extensions listed, 189 English non-NSFW — and
installed a real Kotlin/APK extension (`Asura Scans`, `eu.kanade.tachiyomi.extension.en.asurascans`,
v1.6.66) via `updateExtension(patch:{install:true})`. Pointed the running Yomi simulator at
`http://127.0.0.1:4567` in Settings → Suwayomi Server: "Connected — 2 sources" (proves the ATS
fix), browsed to Asura Scans' Popular feed (real live covers), opened "The Former Supreme," saw
its real 8-chapter list load (proves the endpoint fix — this was "No chapters found" before),
opened Chapter 8, and a real page image rendered in the manga reader. Full pipeline confirmed
working, matching Tachimanga's user experience exactly, using Yomi's existing S41 architecture.

**For the user, next steps to actually use this:** the demo server used tonight was ephemeral
(ran from this session's scratch directory, already stopped). For real day-to-day use, install
Suwayomi-Server persistently — either on this Mac (the same
`Suwayomi-Server-v2.3.2243-macOS-arm64.tar.gz` release, run as a login item / launchd service so
it survives reboots) or on a NAS/always-on home server (Docker image `ghcr.io/suwayomi/suwayomi-server`
is the standard way there). Then add its LAN address in Settings → Suwayomi Server exactly as
tonight. **Side note found along the way**: Suwayomi-Server has a built-in Cloudflare bypass (CEF/
embedded Chromium, confirmed downloading and working live tonight against `asurascans.com`) — worth
remembering as a possible alternative fix for Known Issues #9 (AquaManga) and #11 (FreeWebNovel)
if Yomi's own per-plugin CF-bypass work proves too fragile; bridging a stubborn source through
Suwayomi instead of hand-rolling bypass logic is a legitimate fallback, not just a Keiyoushi-only
feature.

Committed as (pending), pushed. No Firebase deploy needed (no `.js` plugin files touched).

---

## Current state (post S88 — 2026-08-05 · Known-issues fix session)

**S88 (2026-08-05): Investigated Known Issues #1 (chapters from Browse, partial) and #8
(Suwayomi manga Popular/Latest) — not a design block; Block 7 (History) is still next.**

1. **`novelfire.js` chapter truncation (#1) — root-caused and fixed.** `parseNovel` only ever
   fetched chapter-list page 1 (`/book/{slug}/chapters?page=1`, ~100 chapters/page). Verified live
   against Shadow Slave (3,139 chapters, 32 pages on the real site): the app was silently showing
   only the first 100. Rewrote to loop pages until a short/empty page confirms the last one
   (capped at 60 pages as a safety net), matching the pattern `mangadex.js`/`asurascans.js` already
   use. Verified live in-app: chapter count now reads exactly 3,139, content still loads correctly.
   Deployed as v1.1.0.

2. **`freewebnovel.js` — found a worse bug than truncation, then hit a new site-wide Cloudflare
   block.** The old scrape (`a.con` on the plain novel page) was pulling from a small "Latest
   Chapters" widget *mixed with unrelated "related novels" links* that share the same CSS class —
   not real chapters at all. Found the site's own AJAX pagination (`?ajax=chapters&page=N&pageSize=200`,
   ascending order, returns `totalPage`/`totalChapters`) and rewrote `parseNovel` to loop it
   properly — verified correct against Martial Peak (6,108 chapters) via live browser testing.
   **However**, a subsequent cold `curl` (no cookies, fresh IP context) showed freewebnovel.com now
   Cloudflare-challenges *all* non-browser requests — both the HTML page and the AJAX endpoint
   return a "Just a moment…" challenge page with no cookies present. This means the rewrite is
   correct but currently **cannot succeed via plain `SOURCE.fetch`** until CF-bypass is wired into
   the novel detail/chapter-loading path (`MangaDetailView.loadChapters()` has no bypass
   integration at all today — `CFBypassManager`/`CFBypassView` only exist in `BrowseView.swift`'s
   manga flow). Deployed as v1.1.0 anyway since it's strictly more correct than the old code and
   will start working the moment CF-bypass covers this path — **flagging as a new, currently-
   blocking issue for next session**, distinct from the pre-existing manga-source bypass flow.

3. **NovelBin (#1) — the whole domain was dead.** `novelbin.me` returned
   `DNS_PROBE_FINISHED_NXDOMAIN` live. Confirmed via web search: NovelBin rebranded to
   **NovelArrow** (`novelarrow.com`), a Next.js rebuild with a clean, cookie-free JSON API —
   verified every endpoint cold via `curl` with no session:
   - `GET /api-web/novels?limit=&page=&status=all&sort={HOT|SEARCH_KEYWORD}&genre=ALL&keyword=` —
     popular (sort=HOT) and search, real pagination via `pagination.totalPages`.
   - `GET /api-web/novels/{slug}` — full metadata (author, description, genres, status).
   - `GET /api-web/novels/{slug}/chapters?sort=asc` — **all** chapters in one response, no
     pagination needed (verified 3,139/3,139 for Shadow Slave in a single request).
   - `GET /api-web/novels/{slug}/chapters/{chapterId}` — chapter content as clean HTML.
   - Covers are predictable: `https://images.novelarrow.com/novel_480_720/{slug}.jpg`.
   Rewrote `novelbin.js` from scratch against this API (v2.0.0, then v2.0.1 fixing a
   `cheerio.load(html).text is not a function` runtime error in the description-stripping helper —
   cheerio's `load()` result isn't directly callable as a text node; switched to the same plain
   regex `stripHtml()` pattern `asurascans.js` already uses). Verified fully live in-app: search,
   popular, detail, 3,139-chapter list, and chapter content all correct.

4. **Found and fixed a real duplicate-extension-row bug while updating the three plugins above.**
   `ExtensionManager.install()` (used by both "Install" and "Update") always upserts under the
   *new* `Extension.id` without checking whether the same plugin is already installed under a
   *different* id. Yomi went through at least one ID-scheme migration (old sha256-hash ids →
   stable catalog ids like `com.yomi.novelfire`), and `PluginCatalogService.availableUpdate(for:)`
   already falls back to matching by **name** when id doesn't match — so an old-id install still
   correctly shows "Update available," but tapping Update just inserted a second row under the new
   id and left the old one in place forever. Result: Plugins and Browse's source list showed
   "NovelFire" (and FreeWebNovel, NovelBin) **twice**, one stale/unupdatable, one fresh — confirmed
   directly in the simulator's `yomi.db` (`ecef3974…`/`14be4a2c…`/`64a5417437…` sha256-id rows
   sitting alongside the `com.yomi.*` rows, all with matching `.js` files present in
   `Documents/Extensions/`, so it wasn't an orphaned-file issue). Fixed: `install()` now deletes
   any other installed extension with the same name (case-insensitive) before writing the new row.
   **Users with plugins installed since before the id-scheme migration likely have this exact
   duplication on their real device** — worth a quick Plugins-screen glance next session.

5. **Suwayomi manga Popular/Latest (#8) — root-caused via code, not a source limitation.**
   `SuwayomiSource.supportsLatest` is already decoded from the Suwayomi server's own API response
   per source (so real Keiyoushi/Tachiyomi extensions correctly report it) — but `SuwayomiService`
   never had a `fetchLatest()` method, and `SuwayomiBrowseView` never called anything but
   `fetchPopular()`. It's a client-side gap, not a source-side one. Added
   `SuwayomiService.fetchLatest(sourceId:page:)` (`GET /api/v1/source/{id}/latest/{page}`, mirrors
   the existing `fetchPopular`) and a `FeedTab` segmented picker in `SuwayomiBrowseView` gated by
   `source.supportsLatest`, matching the exact pattern `BrowseView.swift`'s `SourceBrowseView`
   already uses for direct JS-plugin sources. Compiles clean; **not live-verified** — no Suwayomi
   server was configured in this session's simulator to test against.

**Not investigated this session:** re-testing "chapters from Browse" for Asura Scans/MangaDex
(code-reviewed only — both already loop through all pages correctly, no truncation found by
inspection, so lower priority than the three novel sources above which had confirmed live bugs).

---

**S87 (2026-08-04): Bugfix pass through the Known Issues table (CLAUDE.md rows 1/3/7/8/9) —
not a design block; Block 7 (History) is still next.**

1. **App icon Xcode wiring (#3) — done.** `AppIcon.appiconset` now ships `AppIcon-Ink-1024.png`;
   added `AppIcon-Paper.appiconset`; set `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`
   in both Debug/Release configs (Xcode 26's automatic alternate-icon Info.plist generation —
   confirmed `CFBundleAlternateIcons.AppIcon-Paper` in the compiled Info.plist, no manual plist
   editing needed). Deleted the two stale empty `AppIconDark`/`AppIconMinimal` appiconsets and
   fixed `AppearanceStudioView.swift`'s icon picker (`alternateIcons` array) which still referenced
   those old placeholder names instead of `AppIcon-Paper`.

2. **Cover-cell grid sizing bug (#7) — root-caused and fixed.** `.aspectRatio(_, contentMode: .fill)`
   alone falls back to the content's own intrinsic size whenever the parent proposes an unbounded
   height — a `LazyVGrid` cell with only the column width fixed, or a `.frame(width:)` with no
   height — so cell height varied per image instead of a uniform grid (confirmed: the placeholder,
   which used `.fit`, was already consistent; only the loaded `.fill` image varied). Fixed with a
   new `coverAspectSized()` modifier in `Core/CoverImage.swift`: a `Color.clear.aspectRatio(2/3,
   contentMode: .fit)` sizer drives a deterministic width-based height, with the real image
   `.overlay`'d on top and `.clipped()`. Applied to the shared `CoverImage` component (fixes
   `NovelLibraryCoverCell`, `NovelCoverCell` in Browse, and `OPDSBrowseView` for free, since they
   all route through it) plus the duplicated inline logic in `MangaCoverCell.swift`,
   `LibraryView.swift`'s `NovelLibraryCoverCell` custom-cover branch, both cells in
   `ContinueReadingRow.swift`, and `HistoryView.swift`. Verified live: MangaDex's Popular grid in
   Browse now renders every cell at a uniform height.

3. **AquaManga "Cloudflare bypass fails" (#9) — root-caused; turned out to not be a Cloudflare
   problem at all.** User asked to try the manual shield-icon bypass live. Doing that surfaced that
   `aquareader.org` loads fine with no CF challenge for a real browser *or* for `SOURCE.fetch`
   (confirmed via temporary debug logging in `JSBridge.swift`: consistent `200 OK`, full HTML, no
   "Just a moment" interstitial). The actual problem: the site was rebuilt on a custom theme
   (no longer Madara WordPress) sometime after the plugin's last "verified live" date of
   2026-05-19 — `aquamanga.js`'s old selectors (`div.page-item-detail`, `li.wp-manga-chapter`,
   etc.) matched nothing in the new markup. Rewrote `getMangaList`/`getChapterList`/`searchManga`
   against the live DOM (verified selector-by-selector via a Chrome MCP session and a standalone
   Node harness built from the exact hand-rolled cheerio shim in `JSBridge.swift`, since the
   embedded parser is a custom implementation, not real cheerio): cards are now
   `article.aqua-archive-card`, chapters `a.aqua-ch-item` on the detail page (no AJAX fallback
   needed — it's server-rendered), and fixed a real bug in `searchManga`'s old selector
   (`div.c-tabs-item` only ever matched the single outer wrapper around all N results, not each
   result — changed to `div.row.c-tabs-item__content`, one per result). `getPageList` needed no
   change — the chapter reader page kept the old Madara markup. Deployed to Firebase as `v1.1.0`.

   **While chasing why the fix "didn't take" during testing, found and fixed two real caching
   bugs**, both `URLCache` silently serving stale CDN responses because the redeployed content at
   the same URL still matched `Cache-Control: max-age=3600` from an earlier fetch:
   `PluginCatalogService.fetchCatalog(force: true)` and `ExtensionManager.install()` now both set
   `.reloadIgnoringLocalCacheData` on the request. Without this, tapping "Update" on a plugin — or
   even a full uninstall+reinstall — could silently keep running old plugin code indefinitely if
   fetched within the CDN's cache window. This is a real fix for all users, not just AquaManga.

   **Two things found but left unfixed — pick up here next session:**
   - AquaManga's cover images still render as gray placeholders in the grid even though
     `coverURL` extraction is confirmed correct (verified via debug logging: real `.webp` URLs
     under `wp-content/uploads`). The image host is also Cloudflare-protected, and Kingfisher's
     requests don't carry the same UA the CF bypass flow solved the challenge for
     (`cf_clearance` is UA-bound, per the existing `CFBypassConstants` comment). Added a global
     Kingfisher `requestModifier` in `YomiApp.swift`'s `init()` setting
     `CFBypassConstants.userAgent` on every image request — **not yet verified whether this alone
     fixes it**, because of the next item:
   - **Runaway pagination**: `SourceBrowseView.loadMore()` (`BrowseView.swift`) fetched **100+
     pages in a matter of seconds** for AquaManga's Popular grid. `hasMoreContent` only flips
     false when a page returns an *empty* array, but AquaManga's archive (~1,495 series ÷ 24/page
     ≈ 63 real pages) apparently never returns empty past the last real page — likely serves
     duplicate/wrapped content for out-of-range page numbers, a common WordPress pagination
     fallback. This is very likely the actual reason covers never load too (100+ pages × 24
     concurrent `SOURCE.fetch`/Kingfisher requests plausibly exhausts the connection pool or
     trips Cloudflare rate-limiting). Needs a page-level dedup (compare new page's first result id
     against what's already accumulated) or a hard max-page safety cap in `loadMore()`.

4. **Manga sources Popular/Latest (#8) — not investigated.** User pushed back on the S86 "not a
   bug" verdict, asking whether Suwayomi-bridged sources (which proxy Keiyoushi/Tachiyomi
   extensions) already support a Latest feed, which would mean Popular/Latest *should* be
   achievable for manga through that path even though direct JS plugins
   (`mangadex.js`/`asurascans.js`) don't implement `getLatestManga`. Ran out of session time before
   getting to this — needs a live test with a configured Suwayomi server.

5. **Chapters from Browse, partial (#1) — not re-tested.** Original vague S37 issue; this session's
   time went entirely into #9 instead. AquaManga's own chapter list is now confirmed correct (see
   above) but the other installed sources (Asura Scans, MangaDex, NovelFire, FreeWebNovel,
   NovelBin) weren't re-checked.

**Also learned:** the `mobile-mcp` `mobile_swipe_on_screen` tool's `distance` parameter does not
reliably control scroll distance in the simulator used this session — a 1px swipe and an 800px
swipe produced the *same* large scroll jump. Fine-grained scrolling (e.g. to reach one specific row
in a long Settings list) was not achievable; had to navigate more directly instead (search, or a
shorter screen). Worth trying a different approach (e.g. explicit start/end coordinates, or a
slower multi-step gesture) next time this matters.

**S86 (2026-08-04): Block 6 — Browse, redesigned to N.06 (Browse) + N.16 (Browse — search).**
Before rebuilding, found that Browse's old "Extensions" sub-tab duplicated `More → Plugins`
(`PluginsView`) — same catalog install logic, minus repo management/install-from-URL/update-all.
The 16-screen spec only shows 2 segments on Browse (Sources / Global search), which matches: Browse
now only *consumes* installed sources; all install/repo/update management stays solely in
`PluginsView`. Removed the duplicate tab and ~250 lines of parallel catalog logic; `CatalogGroupRow`
(still used by `PluginsView`) moved there since its only remaining caller lives in that file. Entry
points that used to jump to Browse's Extensions tab (`AppRouter.openBrowseExtensions`, set from
`LibraryView`'s "Get plugins" empty state) now route to `More → Plugins` via the existing
`openMorePlugins` flag instead — same capability, no duplicate code path, and `openBrowseExtensions`
was deleted as dead state.

Rebuilt Sources tab: search pill + Sources/Global-search segmented control (N.06), installed-source
rows with a new `SourceIconBadge` (real icon via KFImage, falls back to a deterministic name-hashed
gradient + initials — not `String.hashValue`, which is randomized per process launch and would
reshuffle colors every relaunch), subtitle `"EN · MANGA"`/`"EN · NOVELS"` in Mono, and a `Popular on
<first source>` horizontal carousel reusing `MangaCoverCell`/`NovelCoverCell`. Suwayomi and OPDS
sections restyled to match but kept as their own multi-row sections (unlike the mockup's single
"Suwayomi" row) since collapsing them would hide real sub-sources, not just a visual simplification.
Global search (N.16) changed from `.searchable` + vertical per-source grids to a pushed `SearchScreen`
with horizontal per-source carousels, matching the mockup's card-rail layout; auto-focuses the
keyboard on push via `.searchable(isPresented:)`.

**Two real bugs found and fixed via live simulator testing, not just code-read:**
1. **Tap dead-zone on installed-source rows.** `NavigationLink { … } label: { SourceRow() }
   .buttonStyle(.plain).contextMenu { … }` only responded to taps directly on content (the chevron
   icon), not the row's `Spacer()`-filled middle — `.contextMenu` narrows the tap area SwiftUI would
   otherwise infer for a plain-style `NavigationLink`. Fixed with an explicit
   `.contentShape(Rectangle())` before `.overlay` on every tappable row (installed sources, Suwayomi,
   OPDS).
2. **Popular carousel silently failed to appear** despite loading real data (confirmed via a
   temporary debug label: `loaded=true mangas=10`). Root cause: `.task(id:)` was attached to a
   `Group { if cond { … } }` — when `cond` flips false→true from async state, the transition was
   sometimes dropped, leaving the Group empty with no error and no retry. Fixed by moving `.task` onto
   a persistent `VStack` whose *children* are conditional, instead of the conditional being the
   `Group`'s only child — keeps the modifier's target view identity stable across the state change.
   Worth remembering for any future `.task`-driven conditional section.

All verified live via `mobile-mcp` against the mockup: Sources list, Popular carousel, Global search
(typed "solo", got real per-source result rails), row navigation into `SourceBrowseView`. Zero build
warnings/errors.

**User live-review (same day, S86 continued): 4 issues flagged from real device screenshots, not
yet fixed — see `CLAUDE.md` Known Issues table rows 7-10 for full detail. Summary:**
1. Cover cells in the Browse grid render at inconsistent sizes (MangaDex Popular list) —
   `MangaCoverCell` has no explicit frame, relies only on `.aspectRatio`; not yet root-caused live.
2. Manga sources never show a Popular/Latest toggle (novel sources always do) — **confirmed correct
   behavior, not a bug**: `mangadex.js`/`asurascans.js` never implement `getLatestManga`, while every
   LNReader-format novel plugin gets it for free via a shared `popularNovels(showLatestNovels:)`
   contract.
3. AquaManga's Cloudflare auto-bypass times out (30s, no `cf_clearance` cookie) — unconfirmed whether
   the site needs an interactive challenge (unsolvable by the headless off-screen `WKWebView`) or is
   just down. Needs a live manual-bypass (shield icon) test.
4. Keiyoushi still isn't offered as an installable repo — **by design, not a gap**: it's Kotlin/APK,
   architecturally incompatible with JSC (documented since S18). Access exists today only via the
   Suwayomi self-hosted bridge (Settings → Suwayomi Server); Browse only shows a Suwayomi section
   once that URL is configured.

**Next session: investigate #1 and #3 above (both unconfirmed root causes), then continue to Block 7
— History.**

## Current state (post S85 — 2026-08-04 · Phase 0 fidelity fixes — all 6 gaps closed)

**S85 (2026-08-04): fixed all 6 fidelity gaps S84 found, plus one deeper root cause.** Before
touching the listed gaps, found that `YomiTokens.Canvas` (Ink/Midnight/Paper/Sepia bg/surface/text
colors) was only ever read inside `AppearanceStudioView`'s own preview card — never applied as the
real app chrome background. `ContentView`/`YomiApp` only set `.preferredColorScheme` (system
light/dark) + accent tint, so every screen rendered as plain system dark mode regardless of canvas
choice. This is the actual root cause of most of S84's "doesn't match the screens" findings, not
just missing fonts. Fixed by adding `AppSettings.canvasColors` (resolved palette, single source of
truth) + a `\.yomiCanvas` environment key (`Core/CanvasEnvironment.swift`) set once in
`ContentView` from `settings.canvasColors` and applied as the real root background; child views
read it via `@Environment(\.yomiCanvas)` instead of `.primary`/`.secondary`.

Then fixed, in order:
1. **List-mode `MangaListRow`/`NovelLibraryListRow`** (user's actual daily-driver view, was zero
   design-system treatment) — Grotesk/Mono fonts, canvas text colors, accent-colored unread count.
2. **Cover-cell catalog-index badge** — added (`Notation.catalogIndex`, Mono 700 15px accent,
   top-left) to both `MangaCoverCell` and `NovelLibraryCoverCell`, fed by a 1-based index from
   `LibraryView`'s `ForEach(Array(...enumerated()))`. Fixed source-label font (was Mono, spec says
   Grotesk) and category-tab-bar font (was system, now Grotesk) on the same pass.
3. **Continue hero** (`ContinueReadingRow.swift`) — built the missing §9.2 full-width hero card
   (`ContinueHeroCard`): cover thumb, `CONTINUE READING` label, Grotesk title, `Notation.chapterProgress`
   notation, accent Resume pill, progress hairline. Background is a genuine ambient tint **sampled
   from the cover** via a new `UIImage.averageColor()` (CIAreaAverage) in
   `Core/UIImage+AverageColor.swift`, not a fake gradient. The remaining recently-read items became
   an "Up next" shelf below it (§A.3.b), reusing the existing `ContinueReadingCell`/`ContinueReadingNovelCell`.
4. **Detail header rebuild** (`MangaDetailView.swift` + `NovelDetailView.swift`) — replaced the
   plain `List`/`Section` header with the §14 full-bleed blurred-cover backdrop (`.blur(radius: 30)`
   + dark scrim gradient) + overlapping 110×162 cover thumb + floating glass nav (`glassChip()`,
   new shared modifier in `Core/GlassChip.swift`: back/heart/overflow, 44×44 circles) replacing the
   system nav bar (`.toolbar(isSelectingChapters ? .visible : .hidden, for: .navigationBar)` —
   selection mode keeps the native bar, normal mode doesn't). Deleted the now-orphaned
   `StatusBadge`/`NovelStatusBadge` structs (colored-by-status pills, not spec'd — replaced inline
   with the flat Mono/surface chip both mockup and `Notation.status()` already implied).
5. **Reader top-bar icon set** (`ChapterReaderView.swift`) — the manga reader's top bar had a
   108pt-wide segmented Picker (RTL/LTR/vertical mode) instead of the spec'd 44pt icon chips. Moved
   the mode picker into a new "Reader Settings" sheet behind a `gearshape` chip, matching spec's
   "list, settings" pair exactly. **Novel reader top bar needed no change** — it already had only
   back/list chips with no non-conforming elements; its typography controls are intentionally
   always-visible in the bottom card (not gated behind a settings icon), which is a deliberate
   difference from the manga reader, not a gap.

All 6 fixes screenshot-verified live in the simulator (via `mobile-mcp`, pinned UDID) against the
mockup, not just code-read — per S84's own finding that compile-only checkpoints missed structural
gaps. One process note for future sessions: `mobile-mcp` element coordinates are the **top-left**
of the bounding box, not the center — tapping the reported `(x,y)` directly can miss small circular
hit targets (44×44 chips); tap `(x + width/2, y + height/2)` instead.

**Next session: Block 6 — Browse**, per the original 12-block implementation order (Library →
Library-selection → Detail → Manga Reader overlay → Novel Reader overlay → **Browse** → History →
Updates → Downloads → Insights → More+Settings → Onboarding+empty states). Phase 0 is fully closed;
no known fidelity debt remains in Blocks 1-5.

## Current state (post S84 — 2026-08-04 · Project audit + doc/repo cleanup, no design-fidelity fixes yet)

**S84 (2026-08-04):** Full project audit at user request, prompted by design-fidelity drift in the
Blocks 1-5 implementation (see S83 below — still PENDING USER REVIEW, unchanged this session).
**Fidelity audit findings** (Blocks 1-5 vs. `DESIGN_SYSTEM.md`/HTML mockup): Library's Continue hero
(§9.2) was never built — `LibraryView` still calls the pre-design-system `ContinueReadingRow`, not a
hero card; cover cells are missing the catalog-index badge (§9.1) and use Mono instead of Grotesk for
the source label; category tab labels use system font instead of Grotesk; `MangaDetailView`/
`NovelDetailView` headers are a plain `List`/`Section`, not the spec'd full-bleed blurred-backdrop +
overlapping-thumb + glass-nav structure (§14); the Manga Reader top bar had a "Discuss" chip where
the mockup has none. Root cause: each block was "token-ified" onto the *pre-existing* view structure
(colors/fonts/radii swapped in) rather than rebuilt to the mockup's actual layout — this catches
surface fidelity but misses missing/wrong components. **None of these are fixed yet** — that's Phase 0
of the next work pass, see below.
**Repo/doc cleanup done this session** (organizational audit, separate from the fidelity audit):
(1) `Yomi/HISTORY.md` created — Sessions 5-55 detail tables moved out of `ROADMAP.md` verbatim (919→193
lines) so this file stays current-state + forward-plan only. (2) `METODOLOGIA.md`: removed its
duplicate session-log table (now solely in `ROADMAP.md`/`HISTORY.md`) and its duplicate/stale
"UX research S23" and "Architecture decisions" sections (now solely in `RESEARCH.md` and
`ARQUITECTURA.md` respectively) — 1204→1009 lines, all "Technical learnings" content preserved
untouched. (3) `CLAUDE.md`: collapsed the S64→S83 duplicate history cascade down to the single current
state block (355→234 lines) — this file loads every session, so this is a permanent per-session cost
cut. (4) Fixed a real bug found during the audit: `DESIGN_SYSTEM.md` and `DESIGN_HANDOFF.md` both
pointed to the wrong HTML mockup path (`Yomi/design/YOMI Screens.dc.html`, missing the
`design_handoff_yomi/` subfolder from the S82 reorg) — corrected in both. Also fixed a
`DESIGN_SYSTEM.md`/`HANDOFF_NOTES.md` self-contradiction (2pt vs. 3pt category-tab underline — 2pt is
correct, matches shipped code). (5) Deleted `Yomi/Features/Settings/` (empty dead folder — real
`SettingsView` lives in `Features/More/`) and 8 icon-exploration PNGs `ICONS_NOTES.md` itself had
already flagged as superseded drafts. (6) **Code change**: dropped the "Discuss" chip from
`ReaderOverlayView`'s top bar in `ChapterReaderView.swift` — confirmed via `getDiscussionURL()` grep
that zero shipped plugins (Firebase or bundled) implement it, so the button was unreachable dead UI;
also doesn't match the mockup's back/list/settings top bar. `JSBridge.getDiscussionURL()` and
`DiscussWebSheet` kept in place, dormant, for a future plugin. Build verified clean
(`xcodebuild -scheme Yomi -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` → **BUILD
SUCCEEDED**). Committed + pushed as `4ca6f56`.

**S84 cont. — live simulator verification (screenshots, not just code reading):** installed +
launched on the pinned simulator (`34C346C3-F274-4DE0-A7B2-E9D2DE0CCA97`, per `.xcodebuildmcp/config.yaml`
— has the user's real saved settings, not a fresh install). Confirmed via screenshot: **(a) List
mode — the user's actual saved `libraryDisplayMode` — has ZERO design-system treatment.** Plain
system dark mode, no Ink canvas, no Grotesk, system blue instead of the user's own accent, "Continue
Reading" is the untouched old horizontal thumbnail row. This is new — the earlier code audit only
read `MangaCoverCell.swift` (grid mode); it never checked `MangaListRow` (list mode's equivalent,
same file). Since list mode is what the user actually uses day to day, this is likely the single
biggest reason S82-S83's work reads as "doesn't match the screens" — their real view was never
touched. **(b) Grid mode**: confirmed the Continue hero is genuinely missing (identical old row in
both modes) and cover cells do carry *some* tokens (accent-colored unread badge, thin progress
hairline) but no catalog-index number — matches the code audit exactly.
**New Phase 0 item added: token-ify `MangaListRow` (list mode) to the same standard as the grid
cell**, in addition to the 5 gaps already found.

**Tooling note:** `mobile-mcp` and `XcodeBuildMCP` are correctly installed and show "✔ Connected" in
`claude mcp list`, but were stale/missing from this session's tool index (likely added/connected
after this session started) — attempting to drive the simulator via blind AppleScript
(`osascript ... System Events ... click at`) mis-clicked into an unrelated desktop app twice and was
abandoned. **Decision: restart the session** so mobile-mcp loads properly, rather than continue with
unreliable coordinate-guessing. New project skill `.claude/skills/yomi-sim/SKILL.md` created,
documenting the pinned UDID, the reliable build/install/launch/screenshot pattern, and — importantly
— the settings-file read/write gotchas discovered this session (`defaults read` reports "domain does
not exist" even when real data exists on a fresh boot; direct plist file edits silently don't take
effect, must go through `defaults write`).

**Next session — Phase 0, before touching Block 6 (Browse):** verify `mobile-mcp`/`XcodeBuildMCP`
tools are now loaded (ToolSearch or check available tools directly). Then fix the 6 fidelity gaps
found (Library Continue hero, catalog-index badge, source/tab-label fonts, **list-mode `MangaListRow`
tokens**, Detail header structure, reader top-bar icon set) using a rebuild-to-mockup approach rather
than token-swap-on-old-layout. Add a mandatory screenshot-vs-mockup comparison step per block going
forward, using `mobile-mcp` for navigation — the compile-only checkpoints used for Blocks 1-5 caught
compile errors but not structural fidelity gaps, and list mode was never even looked at.

## Current state (post S83 — 2026-08-04 · Design implementation Blocks 3-5, PENDING USER REVIEW)

**Flag for next session:** this work compiles and is spot-checked but has not had a full review pass from the user, who explicitly asked to revisit it fresh. Do not treat Blocks 1-5 as finalized or start Block 6 without that review.

S83 (2026-08-04): Continued the S82 implementation plan (12 blocks, see below). **Block 3 — Detail**: `MangaDetailView.swift` + `NovelDetailView.swift` token-ified (cover radius, Grotesk/Mono fonts, `Notation.status()` badges as rounded rects instead of capsules, capsule resume button, `Notation.progress()`/`Notation.readingTime()` progress caption, leading unread-dot on chapter rows). **Block 4 — Manga Reader overlay** (done reactively after a user spot-check found the existing overlay — built pre-design-system in S68 — didn't match the mockup at all): `ReaderOverlayView` rebuilt from one full-width glass bar into individual floating glass chips + a floating rounded-rect bottom card with `Notation.pagePosition()` notation; the page slider is now interactive in every mode including vertical scroll (`WebtoonReaderView` gained a guarded `.onChange(of: currentPage)` → `proxy.scrollTo` — previously the scroll↔slider binding was one-way, so the slider existed but couldn't seek). **Block 5 — Novel Reader overlay** (done in full to hit the plan's own block-5 checkpoint): `TextReaderOverlayView` gets the same floating-chip treatment plus a new live `CH. XXX · %` progress footer wired to the already-tracked `lastKnownScrollPercent` state (previously computed but never surfaced in the UI). All three files compile clean. **Backfilled**: Blocks 1-2 (Library, Library-selection) actually shipped 2026-08-03 under S82 commits `bded9e6`/`48705b1` but were never written up here — noting that gap now.

## Current state (post S82 — 2026-08-03 · Design handoff complete, implementation starting)

S82 (2026-08-03): Pre-implementation housekeeping. No Swift code changed. (1) **Full 16-screen design handoff confirmed** — all screens designed in Claude Design (DESIGN_SYSTEM v0.2): Library, Manga Reader, Novel Reader, Appearance Studio, Detail, Browse, Settings, Onboarding, Empty state, More, History, Updates, Downloads, Insights, Library-selection, Browse-search. Handoff file at `Yomi/design/design_handoff_yomi/YOMI Screens.dc.html`. (2) **Design assets consolidated** — `DESIGN_*.md` docs + `Fonts/` moved from `Yomi/` root into `Yomi/design/`; `INFOPLIST_ADDITIONAL_FILE` in `project.pbxproj` updated to `$(SRCROOT)/Yomi/design/Fonts/YomiFonts.plist`; stale partial screen exports removed. (3) **App icon assets** landed in `Yomi/design/design_handoff_yomi/assets/`: `AppIcon-Ink.png` + `AppIcon-Paper.png`. Layered assets in `Yomi/design/icons/layers/`. (4) **Implementation plan established** — 12 blocks in order: Library → Library-selection → Detail → Manga Reader overlay → Novel Reader overlay → Browse → History → Updates → Downloads → Insights → More+Settings → Onboarding+Empty state. Compile + screenshot after blocks 1, 3, 5, 12. Next session: start Block 1 — LibraryView.

## Current state (post S81 — 2026-08-03 · Appearance Studio)

S81 (2026-08-03): Phase 3 implementation continued — Appearance Studio + canvas theming wired. (1) **`AppSettings.canvas: String`** added — primary appearance axis ("Ink" | "Midnight" | "Paper" | "Sepia" | "" follow-device). Migration in `init()` from legacy `theme` + `pureBlack` combo: Dark+pureBlack→Midnight, Dark→Ink, Light→Paper, System→"" (unchanged behavior). Default accent updated from `#FF6B6B` (Coral) to `#E5473A` (Vermilion). `colorScheme` computed var now checks canvas first, falls back to legacy `theme`. (2) **`YomiApp.swift`**: `.preferredColorScheme(settings.colorScheme)` replaces the old `.theme == "Dark" ? .dark : ...` ternary. (3) **`AppearanceStudioView.swift`** (new, `Yomi/Features/More/`): full Appearance Studio with live preview card (canvas bg, cover placeholder, Space Mono notation, accent progress bar + resume button, mini tab bar); Canvas section (Ink/Midnight/Paper/Sepia swatches with nested-surface chips + active accent ring + checkmark); Accent section (11 presets + rainbow custom-picker button + WCAG contrast badge AAA/AA/Fail); Type section (UI font picker, reading font picker, fontSize slider 14–28, line spacing segmented Tight/Normal/Airy, side margins picker); Library section (grid columns stepper, unread badge toggle); App icon section (Default/Dark/Minimal tiles with accent ring on active); Reset-to-defaults button (destructive, restores Ink + Vermilion + Serif + Grotesk). WCAG contrast computed live with full relativeLuminance formula. (4) **`SettingsView.swift`**: `appearanceSection` replaced with a single `NavigationLink("Canvas, Accent & Type") { AppearanceStudioView() }` — removed all inline appearance controls, swatch helpers, custom picker sheet, and `applyAlternateIcon` (all moved to studio). Build succeeded after each file.

## Current state (post S80 — 2026-08-02 · Design foundation)

S80 (2026-08-02): Design system foundation — no product features changed. Implemented the first three steps of the Phase 3 implementation plan from `DESIGN_HANDOFF.md`. (1) **Font bundling**: Space Grotesk (variable, wght 300–700) + Space Mono (Regular + Bold) downloaded from Google Fonts GitHub and placed in `Yomi/Fonts/`. `INFOPLIST_ADDITIONAL_FILE` added to both Debug and Release build settings in `Yomi.xcodeproj/project.pbxproj` — points to `Yomi/Fonts/YomiFonts.plist` which registers all three font files as `UIAppFonts`. Fonts are automatically picked up as bundle resources by `PBXFileSystemSynchronizedRootGroup` (no manual pbxproj file-reference edits needed). (2) **`DesignTokens.swift` rewritten**: warm-Ink surfaces, Vermilion `#E5473A` as new default accent (replaces old Coral), full canvas-preset model (`YomiTokens.Canvas` — Ink/Midnight/Paper/Sepia with bg/surface1/surface2/textPrimary/textSecondary/hairline), type-scale enum (`YomiTokens.TypeScale`), font-family enum (`YomiTokens.Font`), motion timing enum (`YomiTokens.Motion`), updated cover radius (8→10). All existing reader themes, radius, spacing, and layout tokens preserved. (3) **`Notation.swift` created** in `Yomi/Core/`: full catalog-notation formatter — `chapter(_:)` ("CH. 042"), `volumeChapter(volume:chapter:)`, `progress(_:)` ("68%"), `readingTime(seconds:)` ("◷ 12H 40M"), `readingTimeShort(seconds:)`, `chapterProgress(chapter:fraction:seconds:)`, `pagePosition(chapter:page:total:)`, `status(_:)` ("STATUS // ONGOING"), `novelIndex(_:)` ("N.07"), `catalogIndex(_:)` ("02"), `novelFooter(chapter:fraction:)`. Build succeeded on first attempt. Next: Appearance Studio implementation + component application across Library/Detail/Reader screens.

## Current state (post S79 — 2026-07-16 · DESIGN, no code)

S79 (2026-07-16): **Design track kickoff — no Swift changed.** Full design research + a justified design system delivered as three repo docs: `DESIGN_RESEARCH.md`, `DESIGN_SYSTEM.md` (v0.2), `DESIGN_HANDOFF.md` (roadmap to launch). Process: (1) read the real post-S78 state; (2) `DESIGN_RESEARCH.md` — competitive/UX/aesthetic/typography/personalization/gamification research + iOS 26 Liquid Glass (NN/g) critique-as-opportunity; (3) mined Andy's own portfolio (`Creative/Portfolio/` — Prometheus, Velvet Moon) + Pinterest (via Claude in Chrome) for design DNA; (4) `DESIGN_SYSTEM.md` v0.2 — concept "reading instrument / living archive," 6 principles, color+theming model (Ink/Midnight/Paper/Sepia/custom), type (Space Grotesk + Space Mono, modular scale, research-locked reader specs), grid/spacing, monospace notation system, iconography + app-icon direction, motion, components, and the 3 key screens (Library, Manga Reader, Novel Reader) — every decision justified. **Confirmed decisions:** accent Vermilion `#E5473A`, canvas Ink `#14110F`, ink/screentone signature texture, serif novel body, Grotesk+Mono standard (user-swappable, Type as a 3rd Appearance-Studio axis). **Tooling decision:** visuals produced in **Claude Design** (Anthropic Labs) reading this repo → handoff bundle → Claude Code. **App-icon direction now defined** (the primary App Store blocker). Next: v0.3 screen specs + Appearance Studio + icon art + implementation. App icon finalized (cont. 2026-07-18): "Y." monogram (Space Grotesk Y + Vermilion dot), Ink default + Paper alternate; assets in `Yomi/design/icons/`. See `DESIGN_HANDOFF.md` for the full launch roadmap and who-does-what.

## Current state (post S78 — 2026-06-04)

S78 (2026-06-04): Comprehensive code audit + 20 fixes. Full 6-phase audit of the entire codebase. Issues found and fixed: (1) **GRDB version pin**: changed from `branch = master` to `upToNextMajorVersion: 7.0.0` in `project.pbxproj` — eliminates silent breaking-change risk on next SPM resolution. (2) **JS bundle exclusions**: 10 additional plugin JS files added to `membershipExceptions` in `project.pbxproj` — aquamanga, babelnovel, boxnovel, freewebnovel, lightnovelpub, mtlnovel, novelbin, novelfire, novelhall, readwn now excluded from the Release build bundle (previously only 6 files were excluded; 11 were accidentally bundled). (3) **`lightnovelworld.js` deleted**: site permanently closed Jan 2026; dead file removed. (4) **MAL client ID**: moved from hardcoded string in `MALService.swift` to `Yomi/Config/AppSecrets.swift` (gitignored via `.gitignore`). (5) **`seedBundledPlugins()` guard**: wrapped in `#if DEBUG ... #endif` in `ExtensionManager.init()` — was running in every production launch. (6) **`NovelQueries.delete()` `_ =` fix**: missing `_ = try appDatabase.write` was silently discarding the discardable result warning. (7) **Dead `upsertAll`/`upsertChapters` removed**: `ChapterQueries.upsertAll()` and `NovelQueries.upsertChapters()` both used INSERT OR REPLACE (dangerous — overwrites `isRead`/progress); never called anywhere; deleted. (8) **Custom cover relative paths**: `MangaDetailView` and `NovelDetailView` now store `"Covers/<id>.jpg"` instead of `fileURL.path` (absolute path breaks on app reinstall); `Manga` and `Novel` models gain `resolvedCustomCoverPath: String?` computed property handling both legacy absolute paths and new relative paths; all 9 read sites updated to use `resolvedCustomCoverPath`. (9) **`AppSettings` off-MainActor reads in `UpdatesView`**: `checkUpdates(for:)` and `checkNovelUpdates(for:)` now capture all needed settings via `await MainActor.run { }` at function entry instead of direct `AppSettings.shared` access off-MainActor. (10) **Stable novel chapter IDs in update checks**: replaced `"\(novelId)-ch-\(localChapters.count + offset)"` (fragile — breaks when local count changes) with `SHA256(novelId + ch.path).prefix(8).hex` — IDs are now stable and collision-resistant across update runs. (11) **`OPDSService` stable entry IDs**: replaced `UUID().uuidString` fallback with `SHA256(entryTitle + navigationHref).prefix(8).hex` — OPDS entries no longer get new identity on every fetch. (12) **Spanish comments translated**: `CategoryQueries.swift`, `Manga.swift`, `Novel.swift`, `DatabaseManager.swift` (one remnant), `ChapterReaderView.swift` (one remnant) — all inline comments now in English.

## Current state (post S77 — 2026-05-19)

S77 (2026-05-19): Audit fixes pass. (1) **PrivacyInfo.xcprivacy**: added `NSPrivacyAccessedAPICategoryFileTimestamp` (C617.1) and `NSPrivacyAccessedAPICategoryDiskSpace` (85F4.1) — required by App Store review for BackupManager file operations. (2) **`v19_source_indexes` migration**: `idx_manga_sourceid` on `manga` and `idx_novel_sourceid` on `novel` — faster source-filtered queries. (3) **Library novel multi-select**: full parity with manga — `selectedNovelIds Set`, checkmark overlay, selection border, long-press trigger, Select All/Deselect All toolbar, Cancel, `markSelectedRead` + `removeSelected` for novels; `NovelLibraryCoverCell` gains `isSelecting/isSelected/onLongPress/onSelect` params. (4) **OnboardingView plugin page copy**: reframed as "user-installed plugins" for App Store reviewer clarity.

## Current state (post S76 — 2026-05-20)

S76 (2026-05-20): Verification + simulator unification — no code changes. (1) **Simulator UDID unification**: Xcode and XcodeBuildMCP were targeting two different instances of "iPhone 17 Pro iOS 26.3" (UDIDs `F31CC190` and `34C346C3`), each with isolated app data (different accent color, library, settings). Fixed by updating XcodeBuildMCP session defaults to `34C346C3-F274-4DE0-A7B2-E9D2DE0CCA97` with `persist: true` — config saved to `.xcodebuildmcp/config.yaml`; both Xcode and Claude Code now use the same instance. (2) **Comprehensive app verification** via XcodeBuildMCP + mobile-mcp automation: library grid/list modes, category tabs, sort/filter menus, context menus, novel/manga detail views, Updates tab, History tab with search, Insights calendar heatmap, iCloud backup UI, plugin management, onboarding, home screen quick actions — all confirmed working. Key limitation discovered: mobile-mcp cannot trigger SwiftUI `List` rows that use `.onTapGesture` (they render as `StaticText` accessibility elements, not `Button`; custom_actions are not tappable via coordinate injection). Manga chapter tap→reader, multi-select long-press, and reading reminder notifications remain pending manual device testing.

## Current state (post S75 — 2026-05-17)

S75 (2026-05-17): Plugin duplicate install fix. `PluginsView.installFromURL()` previously only checked `ext.id == id` when testing for existing installs — allowed re-installing a plugin already present under a different catalog ID (e.g. Firebase hash vs manual URL). Now also checks `ext.name.lowercased() == name.lowercased()` in the same `.first(where:)` guard.

## Current state (post S74 — 2026-05-16)

S74 (2026-05-16): Live-testing fixes. (1) **`ContinueReadingRow` blank state**: body used `Group { EmptyView() }.onAppear` — SwiftUI `Group` with `EmptyView` has no layout presence so `.onAppear` never fires; items were never loaded. Fixed by replacing wrapper with `VStack(spacing: 0)`. (2) **Status badge text wrapping**: `StatusBadge` (manga), `NovelStatusBadge`, and `ReadingStatusMenu` label all lacked `lineLimit(1)` + `fixedSize(horizontal: true, vertical: false)` — text like "Ongoing" and "Not set" wrapped character-by-character in narrow `HStack` containers. Fixed in `MangaDetailView.swift` and `NovelDetailView.swift`.

## Current state (post S73 — 2026-05-16)

S73 (2026-05-16): Notification deep linking. Tapping a chapter-update notification now navigates directly to the manga/novel detail view. (1) **`AppRouter`**: `pendingOpenMangaId: String?` and `pendingOpenNovelId: String?` added — cleared after navigation to avoid re-opening on tab switch. (2) **`NotificationManager.scheduleChapterNotification`**: `mediaId: String?` and `mediaType: String` params added; stored in `content.userInfo` as `["mediaId": id, "mediaType": "manga"/"novel"]`. (3) **`AppDelegate`**: conforms to `UNUserNotificationCenterDelegate`; `UNUserNotificationCenter.current().delegate = self` set in `didFinishLaunchingWithOptions`; `userNotificationCenter(_:didReceive:completionHandler:)` reads `userInfo`, sets `appRouter.selectedTab = .tabLibrary`, and routes to `pendingOpenMangaId` or `pendingOpenNovelId`; `willPresent` allows banner + sound while app is foregrounded. (4) **`UpdatesView`**: both call sites (`checkMangaUpdates` + `checkNovelUpdates`) now pass `mediaId:` and `mediaType:`. (5) **`LibraryView`**: `@State deepLinkManga: Manga?` + `showDeepLinkManga: Bool` added; `navigationDestination(isPresented: $showDeepLinkManga)` opens `MangaDetailView`; `.onChange(of: appRouter.pendingOpenMangaId)` fetches manga from DB in `Task.detached` and presents it; `.onChange(of: appRouter.pendingOpenNovelId)` fetches novel and sets `selectedNovel + showNovelDetail = true`. Also **`AppRouter.swift`** Spanish inline comment translated to English.

## Current state (post S72 — 2026-05-16)

S72 (2026-05-16): App Store review prompt + Spanish comment cleanup. (1) **App Store review prompt**: `AppSettings.chaptersReadCount: Int` incremented by `recordChapterRead()` (returns true at milestones 10, 50, 200); `ChapterReaderView` and `TextReaderView` both import StoreKit and use `@Environment(\.requestReview)` + `@State shouldRequestReview`; `.onChange(of: shouldRequestReview)` fires `requestReview()`; incognito-safe (no DB write → no count increment). (2) **Spanish comment cleanup**: `MangaQueries.swift` and `NovelQueries.swift` fully translated to English (completes the S67 cleanup that covered only `DatabaseManager` and `ChapterQueries`).

## Current state (post S71 — 2026-05-16)

S71 (2026-05-16): Reading reminders. `NotificationManager`: `scheduleReadingReminder(lastReadTitle:afterDays:)` schedules a `UNCalendarNotificationTrigger` firing at 10am on day N with "Continue [Title]?" body; `cancelReadingReminder()` removes the pending request; `checkAuthorizationStatus()` syncs `isAuthorized` on foreground. `AppSettings`: `readingReminderEnabled: Bool` (default false, opt-in) + `readingReminderDays: Int` (default 2). `YomiApp.onChange(scenePhase)`: on `.active` — cancel reminder + refresh auth; on `.background` — fetch most recently read title via `Task.detached` (MangaQueries then NovelQueries fallback), schedule reminder when enabled. `UpdatesSettingsView`: reading reminders toggle + "Remind me after" `Picker` (1/2/3 days, 1 week) shown when enabled; disabling cancels pending reminder.

## Current state (post S70 — 2026-05-16)

S70 (2026-05-16): Auto iCloud backup + Kingfisher cache fix. (1) **Auto iCloud backup**: `AppSettings.iCloudAutoBackup: Bool` (default `true`); `YomiApp.onChange(scenePhase == .background)` triggers `BackupManager.shared.uploadToICloud()` when enabled — library backed up automatically every time user leaves the app; toggle exposed in `BackupView` iCloud section. (2) **Kingfisher cache clear fix**: `AdvancedSettingsView` "Clear image cache" button now also calls `ImageCache.default.clearCache()` (Kingfisher memory + disk) in addition to `URLCache.shared` — previously tapping the button left the Kingfisher disk cache intact.

## Current state (post S69 — 2026-05-16)

S69 (2026-05-16): iCloud Drive backup sync. `BackupManager` extended with `uploadToICloud()`, `downloadFromICloud()`, `checkICloudBackup()` — all file I/O in `Task.detached` (off main thread); `buildBackupData() async throws -> Data` extracted from `exportBackup()` and shared by both local export and iCloud upload paths; `ICloudSyncStatus` enum tracks idle/uploading/downloading/success/unavailable/error; `lastICloudUploadDate: Date?` persisted to UserDefaults. `BackupView` gains an iCloud section at the top: "Back up to iCloud" button, last backup timestamp (`checkICloudBackup()` on appear), "Restore from iCloud" button guarded by `confirmationDialog`. `Yomi.entitlements` gets `com.apple.developer.ubiquity-container-identifiers: ["iCloud.pacodealer.Yomi"]`. **One-time Xcode step required**: Target → Signing & Capabilities → + Capability → iCloud → check "iCloud Documents" to activate provisioning.

## Current state (post S68 — 2026-05-15)

S67 (2026-05-15): Infrastructure fix — all four code audit issues resolved. (1) **Kingfisher image cache**: Kingfisher 8.9.0 added via SPM; `CoverImage.swift` reusable wrapper (`KFImage` with 2/3 aspect ratio, fade transition, secondary placeholder); all 21 `AsyncImage` usages across 11 files migrated to `CoverImage` or `KFImage` (readers and widget left unchanged per policy). Cover images now load instantly after first fetch from disk+memory cache. (2) **DB indexes**: `v18_indexes` migration adds `idx_chapter_mangaid`, `idx_chapter_unread` on `chapter` and `idx_novel_chapter_novelid` on `novel_chapter` — eliminates full table scans on library load and unread count queries. (3) **Double markChapterRead() fix**: `@State private var didMarkCurrentChapterRead = false` guard added to `ChapterReaderView` — prevents both `onChange(of: currentPage)` and `onDisappear` from writing to DB on the same chapter; flag resets in `navigateToChapter`. (4) **Spanish comments cleanup**: all Spanish comments in `DatabaseManager.swift` and `ChapterQueries.swift` translated to English.

S68 (2026-05-15): Performance + iOS 26 polish. (1) **Library sort optimization**: `LibraryViewModel.displayedManga` and `displayedNovels` converted from computed properties to stored properties rebuilt via `rebuildDisplayed()` — sorting only runs when data actually changes (mangas/novels loaded, unread counts changed, sortOrder/statusFilter/searchText changed, category filter resolved); previously ran on every SwiftUI render pass. (2) **iOS 26 Liquid Glass reader overlay**: `ReaderOverlayView` (manga) and `TextReaderOverlayView` (novel) both replace black gradient bars with `.glassEffect()` via `Rectangle().glassEffect().ignoresSafeArea(edges: .top/.bottom)` background pattern; controls updated from `.white` to `.primary`/`.secondary` for adaptive color with glass.

## Current state (post S66 — 2026-05-09)

S66 (2026-05-09): Novel reader justify + home screen quick actions. (1) **Text justification toggle in novel reader**: `novelJustifyText: Bool` added to `AppSettings`; `text-align: justify` / `text-align: start` injected into the CSS body in `styledHTML` based on state; new circular icon button (`"text.justify"` SF Symbol) added to Row 2 of `TextReaderOverlayView` between the font-family toggle and the margin picker; highlights white at `opacity(0.18)` when active, dims to `opacity(0.06)` when off; persisted via `onChange → AppSettings.shared.novelJustifyText`. (2) **Home screen quick actions**: `AppDelegate` class (conforming to `UIApplicationDelegate`) added to `YomiApp.swift`; wired via `@UIApplicationDelegateAdaptor(AppDelegate.self)`; `didFinishLaunchingWithOptions` registers two `UIApplicationShortcutItem` entries — "Continue Reading" (`book.fill`) and "Browse" (`safari.fill`); `performActionFor shortcutItem` dispatches to `DispatchQueue.main` and sets `appRouter.selectedTab` to the appropriate tab index. Cold-launch via `launchOptions[.shortcutItem]` omitted (deprecated in iOS 26 — `performActionFor` handles both cold and foregrounded cases on the scene lifecycle).

## Current state (post S65 — 2026-05-09)

S65 (2026-05-09): UX polish + Insights calendar. (1) **Last-read chapter label on library covers**: both `MangaCoverCell` (manga) and `NovelLibraryCoverCell` (novel) now display the most recently read chapter name as a semi-transparent dark label (`black.opacity(0.65)`) at the bottom of the cover image, stacked above the progress bar in a `VStack(spacing: 0)` inside `.overlay(alignment: .bottom)`. Only shown when `readProgress > 0`. Manga: `lastReadChapterName` = chapter with latest `readAt` date. Novel: prefers in-progress chapter (`lastScrollPercent > 0.01 && !isRead`) over last fully-read chapter. (2) **Reading activity calendar in InsightsView**: 13-week rolling contribution heatmap placed between stat cards and Breakdown section. Private `ReadingCalendarView` struct with `activityMap: [DateComponents: Int]` parameter; cell size 12pt, gap 3pt; day-of-week labels ("M"/"W"/"F") on the left; month labels ("Feb"/"Mar"/etc.) use `ZStack + .offset(x:)` to avoid width-clipping. Activity intensity: `accentColor.opacity(min(0.35 + Double(count-1) * 0.18, 1.0))`; future dates: `secondary.opacity(0.06)`; empty days: `secondary.opacity(0.15)`. Calendar data built in `loadStats()` Task.detached from `readMangaChapters` + `readNovelChapters` `readAt` dates; returned as 10th element of the result tuple; assigned to `@State private var readingCalendar: [DateComponents: Int]` in `MainActor.run`.

## Current state (post S64 — 2026-05-09)

App is feature-rich and polished. S64 (2026-05-09): Stats + polish + data freshness pass. (1) **Reading time in detail headers**: both `MangaDetailView` and `NovelDetailView` progress bar caption now appends "· Xh Ym" (computed from chapters array `readingSeconds` sum) when > 0; `formatReadingTime` private helper added to both views. (2) **InsightsView manga/novel breakdown**: new "Breakdown" section between stat cards and "By Title" shows manga vs novel chapter counts and time separately; `breakdownRow(@ViewBuilder)` renders each row; 4 new state vars threaded through `loadStats()`. (3) **InsightsView "By Title" novel badge**: novel entries now show a small accentColor "N" badge before the title (mirrors ContinueReadingRow pattern). (4) **`HistoryView` `.onAppear` refresh**: `.task` → `.onAppear` so history re-queries DB every tab visit. (5) **`LibraryView` `.onAppear` refresh**: `.task` → `.onAppear` so library reloads when returning from detail views (e.g. after marking chapters read). (6) **Library sort by reading time**: `SortOrder.readingTime = "Reading Time"` (systemImage: `"timer"`) added; sorts by `readingSeconds` DESC for both manga and novels; auto-appears in sort menu via `SortOrder.allCases`. (7) **HistoryView novel subtitle shows in-progress chapter**: prefers `lastScrollPercent > 0.01` in-progress chapter over last fully-read chapter — shows where user actually stopped. S63 (2026-05-09): Data integrity + parity + UX polish. (1) **BackupManager v3 — category export/import**: categories (id/name/sort) now included in the export payload; import restores categories via `INSERT OR IGNORE` *before* manga/novel category assignment pairs — prevents FK orphans on clean-device restore. `version` bumped to 3. (2) **Novel update smart-skip parity**: `UpdatesViewModel.checkNovelUpdates` now mirrors all 4 skip conditions from the manga path — `skipUpdateNotStarted` (no `lastReadAt`), `skipUpdateCompleted` (status contains "completed"), `skipUpdateWithUnread` (any unread chapter), and `excludedCategoryIds` (category assignment check); previously novels were always checked regardless of these settings. (3) **Library context menus** — manga grid/list + novel grid/list all have `.contextMenu` with a "Reading Status" submenu (checkmark on current) and a destructive "Remove from Library" action; status change writes via `MangaQueries.updateReadingStatus` / `NovelQueries.updateReadingStatus` in `Task.detached`, then reloads library; no navigation to detail view required. (4) **`MangaListRow` custom cover fix**: list-mode manga rows were missing the `customCoverPath` check that all other cover-rendering surfaces already had — added `UIImage(contentsOfFile:)` branch before `AsyncImage`. (5) **`ContinueReadingNovelCell` resume detection fix**: `openReader()` resume detection and subtitle filter were using `readAt != nil` (only chapters opened and fully-read to 90%+); changed to `lastScrollPercent > 0.01` to match the S62 fix already in `NovelDetailView` — chapters partially read now correctly surface as in-progress. S62 (2026-05-06): UX polish pass + reader improvements. (1) **Novel continue-reading direct navigation**: `ContinueReadingNovelCell` now opens `TextReaderView` directly; chapters from DB only, bridge from `ExtensionManager`, resume: in-progress → first unread → last. (2) **Library sort/filter persistence**: `sortOrder`/`statusFilter` in `LibraryViewModel` backed by `UserDefaults` stored-property `didSet` — survive app restarts. (3) **`resumeChapter`/`hasStartedReading` correctness**: `NovelDetailView` checks `lastScrollPercent > 0.01` — chapters opened before 90% were invisible to resume. (4) **Chapter list sheet in novel reader**: `TextReaderOverlayView` list button → `NavigationStack` sheet, `ScrollViewReader` auto-scrolls to current chapter after 100ms. (5) **Chapter list sheet in manga reader**: same pattern in `ReaderOverlayView`. (6) **Mark previous as read**: trailing swipe "Mark previous" in `ChapterRow` + `NovelChapterRow` bulk-marks all lower-indexed chapters. (7) **Chapter search**: inline `TextField` (shown when `chapters.count > 30`) in both `MangaDetailView` and `NovelDetailView`; `ContentUnavailableView` empty state. (8) **Reading progress bar in detail headers**: `ProgressView(value:total:)` above the resume button in both detail views. (9) **`ContinueReadingRow` refresh fix**: `.onAppear { Task { } }` replaces `.task { }` — re-queries on every navigation return. (10) **`ContinueReadingCell` DB fallback**: if bridge returns empty, falls back to DB chapters (mirrors MangaDetailView S55 fix). (11) **Plugin update ID matching**: `PluginCatalogService.isInstalled`/`availableUpdate(for:)` match by `ext.id` first, fall back to `ext.name`. (12) **Relative time bar in Insights**: `ZStack` + `GeometryReader` background bar scaled to `seconds/maxSeconds` ratio in the "By Title" list. S61 (2026-05-05): Chapter finished banner in `TextReaderView`. `@ViewBuilder chapterFinishedBanner` computed property: spring `.move(edge:.bottom).combined(with:.opacity)` transition, 5s auto-dismiss via `Task.sleep`, "Next →" button calls `navigateToChapter(currentChapterIndex + 1)`, "All caught up!" on last chapter, cleared in `navigateToChapter`. DB write (`NovelQueries.markRead`) remains incognito-guarded; banner always shows (in-memory UI state, not a privacy concern). S60 (2026-05-05): Novel reader scroll position + resume UX + polish pass. (1) **Mid-chapter scroll save/restore**: `v17_novel_scroll` migration adds `lastScrollPercent REAL` to `novel_chapter`; JS 400ms debounced scroll reporter posts via WKScriptMessage; `WKNavigationDelegate.didFinish` restores position after chapter loads; `flushScrollPercent()` writes on reader dismiss and chapter nav; incognito guarded. (2) **Auto-scroll to resume chapter**: `NovelDetailView` wrapped in `ScrollViewReader`; 300ms after chapters finish loading, `proxy.scrollTo("ch_<id>")` targets the first unread/in-progress chapter. (3) **In-progress progress bar**: `NovelChapterRow` shows a thin `accentColor` capsule bar for partially-read chapters. (4) **Chapter state refresh**: `NovelDetailView` re-fetches chapters from DB 500ms after reader closes (mirrors `MangaDetailView` pattern) — isRead and lastScrollPercent now reflect truth on return. (5) **BackupManager parity**: novels now encode/decode `customCoverPath` and chapters encode/decode `lastScrollPercent`. (6) **Pull-to-refresh** on both `NovelDetailView` and `MangaDetailView`. S59 (2026-05-04): Two-item polish pass. (1) `NovelDetailView.touchLastReadAt()` missed its incognito guard — was writing `lastReadAt` to DB even in incognito mode. Fixed with `guard !AppSettings.shared.isIncognito else { return }`. (2) Novel badge added to pre-install catalog view (`CatalogGroupRow` in `PluginsView`): `isNovel: Bool` field added to `PluginCatalogEntry` (excluded from `CodingKeys`, defaults `false`); `LNReaderEntry.toEntry()` sets `isNovel = true`; badge appears in catalog next to install button, consistent with the installed-extension badge from S58. S58 (2026-05-04): Novel parity pass + cover propagation. (1) **Novel custom cover**: `Novel` model + v16 DB migration (`customCoverPath` TEXT column); `Novel.init(row:)` and `encode(to:)` fixed to include `notes` (was silently dropped on every read since v15) and `customCoverPath`; `NovelDetailView` gets PhotosPicker "Change cover" via toolbar menu, saves to `Documents/Covers/<id>.jpg`; `NovelLibraryCoverCell`, `NovelLibraryListRow`, `HistoryRow`, `ContinueReadingRow`, and `UpdatesView` section headers all updated to render custom cover before falling back to `AsyncImage`. (2) **Novel chapter multi-select**: long-press any chapter row to enter selection mode; tap to toggle; bottom action bar with Read/Unread; Select All/Deselect All in toolbar; Cancel to exit — mirrors MangaDetailView. `NovelDetailView.body` refactored into `@ViewBuilder` section properties to resolve Swift type-checker timeout. (3) **Reader back buttons**: both `ChapterReaderView` and `TextReaderView` back buttons enlarged to 44×44pt with `contentShape(Rectangle())` — was ~20×22pt icon-only. (4) **Format badges**: `ExtensionRow` (Sources list) and `InstalledExtensionRow` (Extensions tab) now show "Novel" (purple) or "Manga" (blue) chip via lightweight `popularNovels` string check on the installed JS file — no JSC evaluation. Fixes confusing dual-NovelBin display. S57 (2026-05-04): Comprehensive code audit + incognito leak fixes. Four incognito-mode data leaks found and fixed: (1) `MangaDetailView.touchLastRead()` was calling `MangaQueries.touchLastRead` even in incognito — now guarded by `!AppSettings.shared.isIncognito`. (2) `TextReaderView.onReadComplete` (JS scroll 90% trigger) was calling `NovelQueries.markRead` without incognito check. (3) `TextReaderView.navigateToChapter` marked the departing chapter as read on chapter navigation without incognito check. (4) `ChapterReaderView.navigateToChapter` saved reading progress (`ChapterQueries.updateProgress`) without incognito check. `GlobalSearchView.runParallelSearch` fixed: JSBridge calls inside `withTaskGroup` were on cooperative thread pool without explicit priority — wrapped in `Task.detached(priority: .userInitiated)` per CLAUDE.md rule. Also verified: AppLock (LAContext, `.deviceOwnerAuthentication`, locks on `.background` scene phase), DownloadManager (sequential queue, concurrent page fetch with sliding window, delete-after-reading), UpdatesViewModel (smart skip conditions, parallel chapter check, notification scheduling), AniList score cache (double-optional `[String: Int?]` correctly distinguishes uncached/failed/hit), MAL tokens in Keychain, History swipe-to-delete (DB write in Task.detached), category assign/unassign, library multi-select (mark-read/download/remove all correct), extension install/remove lifecycle. S56 (2026-05-03): Live simulator audit — walked every tab and flow as a real user. Two bugs fixed: (1) `MangaDetailView.loadChapters()` guard early-return when extension not installed now fetches DB chapters instead of returning `chapters = []` — this was the root cause of persistent "No chapters found" for manga whose source plugin was uninstalled. (2) WKWebView "Restore scroll position" system prompt suppressed via `history.scrollRestoration = 'manual'` injected as a `WKUserScript` — was showing on every chapter open. Confirmed working: novel reader, manga source browse, swipe-to-delete repo, add-repo sheet, History/Updates tabs. Identified: two NovelBin entries in Sources list are legitimate different plugins (com.yomi.novelbin Yomi native vs 64a5417437b8f41aaed9eca60d4a52ce LNReader format). NovelBin Yomi-native chapter loading slow/timing out — likely Cloudflare block on the native scraper. S55 (2026-05-03): Full functional audit — live simulator walkthrough of every tab, flow, and extension lifecycle. **Critical fix:** `MangaDetailView.loadChapters()` was discarding all DB chapters when the source API returned empty (Cloudflare block, network failure, any error) — `chapters = []` even though the DB had 100+ saved chapters. Fixed with DB fallback: `if loadedChapters.isEmpty { chapters = saved }`. History/reading progress still existed; chapters were always there; just not shown. **Minor fixes:** `_ =` prefix added to 9 `appDatabase.write` calls in `NovelQueries.swift` (6) and `ExtensionQueries.swift` (2) for CLAUDE.md consistency. Haptic in `ChapterReaderView.onChange(of: currentPage)` now guarded by `pages.count > 0` — was firing spuriously during chapter navigation reset (`navigateToChapter` clears `pages = []` then sets `currentPage = 0`, triggering onChange on empty page array). **Duplicate NovelBin removed** from installed extensions — user had two NovelBin plugins with different IDs (one from Firebase catalog, one from a secondary repo). Removed the orphan via swipe-to-delete. **All core flows verified:** Library (category tabs, sort/filter menu, multi-select), Browse (source browsing with live content), History (Today/This week/This month grouping), Novel reader (text load, scroll restore, controls), Extension install/remove cycle. S54 (2026-05-03): UX blitz — (1) Category chips replaced with underline tab bar (tachiyomi-style: accentColor underline, `ScrollViewReader` auto-scroll, swipe left/right on library content to change tab). (2) Status filter row removed from library; merged into sort menu as a second section (sort order + reading status in one `Menu`). (3) Multi-select action bar now has three actions: Mark Read (`ChapterQueries.markAllRead` per manga), Download (unread chapters enqueued via `DownloadManager`), Remove. (4) Haptic feedback on page turn in manga reader (`UIImpactFeedbackGenerator(style: .light)` in `onChange(of: currentPage)`). S53 (2026-05-02): Firebase deployed (babelnovel.js + lightnovelpub.js now live). Full embedded JVM feasibility study conducted — verdict: DEFER (Java version gap: OpenJDK 8 ≠ Suwayomi requirements; NSExtension architecture required; no confirmed App Store precedent for Suwayomi JAR; +150–200MB binary). Tachimanga architecture still unconfirmed (App Store listing says native Swift/iOS 15+). `SuwayomiService.swift` and all browse UI require zero changes to point at an embedded server — that path remains viable whenever OpenJDK Mobile (Java 21, Gluon initiative) matures. S52 (2026-05-02): Full codebase + docs audit. `HistoryView` search bar added (`.searchable`, `filteredItems` computed property, `ContentUnavailableView.search` empty state). DB is at v15_novel_notes (16 migrations). Next migration prefix: `v16_`. Novel parity gaps confirmed: no custom cover PhotosPicker, no chapter multi-select mode (lower priority — image readers benefit more from these). `UpdatesViewModel` promoted to singleton (`static let shared`) so `ContentView` badge (`totalCount`) observes updates without a separate service. `NotesEditorSheet` made non-private so `NovelDetailView` reuses it. `NovelDetailView` bridge made optional + lazy-resolved from `ExtensionManager` — removes required `bridge:` argument from all call sites (Library, History, Updates, ContinueReading). Category item counts shown in `CategoryView` trailing text. Push notification setting added to `UpdatesSettingsView`. S51 (continued — 2026-04-30): `LibraryViewModel.loadLibrary()` moved to `Task.detached` (DB reads were blocking MainActor). `Extension.init(row:)` force-unwrap on `sourceListURL` replaced with a throwing guard. `JSBridge.getChapterList` for Mangayomi now extracts chapters entirely in JS — avoids `toDictionary()` cast failures, handles `url`/`link`/`id`/`href`/`path` field variants, passes scanlator. After extracting chapters, caches manga metadata (description, status, cover) in `lastMangayomiMeta`; `MangaDetailView.loadChapters` applies it to `@State manga` and persists via `MangaQueries.update` if fields were empty. `BabelNovel` plugin (v1.1.0): API calls now send `Origin`/`Referer`/`Accept: application/json`/`X-Requested-With` headers; guards against HTML response before JSON.parse; adds field-name fallbacks. `lightnovelpub.ts` icon URL updated to `.vip`. Updated `babelnovel.js` + `lightnovelpub.js` staged in Firebase folder — pending deploy (`cd ~/Projects/Yomi/Firebase && firebase deploy --only hosting`).

S51 (continued): AniList score badge added to both `MangaDetailView` and `NovelDetailView` headers — `AniListService.swift` (actor singleton, GraphQL query, in-memory cache) fetches `averageScore` from `https://graphql.anilist.co` by title; orange star badge appears next to StatusBadge. Language filter chip bar moved from Sources tab → Extensions tab; "en"/"English" deduplication via `BrowseView.displayLanguage(_:)` static mapper (15+ language codes + full names → canonical display names); language filter now applies to catalog entries not installed sources. Library list mode now respects `settings.libraryDisplayMode` for novels — added `NovelLibraryListRow` private struct; both manga and novel sections switch between `LazyVGrid` (grid) and `LazyVStack` (list) in sync. `README.md` App Store safe: removed "Download from App Store" → "Open Yomi on your device"; "Plugin Repositories" terminology; removed "in-app" language. `NovelDetailView` synopsis/metadata fix: `let novel` promoted to `@State private var novel` — after `parseNovel` returns, view updates `novel.summary`, `novel.author`, `novel.status`, `novel.coverURL` from source data; if in library, upserts updated novel to DB so next library open shows correct synopsis. LightNovelPub domain fixed: `BASE_URL` updated from `https://www.lightnovelpub.com` to `https://www.lightnovelpub.vip` in TypeScript source + rebuilt. S51 (earlier): Cloudflare auto-bypass fixed — WKWebView now full-size off-screen (Turnstile needs real viewport), 30s timeout (was 10s), polling restarts on server redirects, UA unified via `CFBypassConstants.userAgent` so `cf_clearance` is valid for URLSession requests; auto-bypass failure now shows a dismissible banner with manual bypass prompt. Settings UX restructured from 12 sections → 7 (General / Reading / Library / Appearance / Sources & Servers / Advanced / About); Manga Reader and Novel Reader settings each have drill-down sub-screens; Suwayomi and OPDS move to NavigationLink sub-screens inside Sources & Servers; Downloads section dissolved with items distributed to Reader and Library. S50: Language filter for Browse sources tab (chip bar with unique languages from installed extensions, filters visible source rows); Popular/Latest tabs now shown for ALL source types — LNReader novel sources now support Latest feed via `showLatestNovels: true` option, picker visible for both manga and novel sources; `latestNovels(page:)` method added to JSBridge; JSBridge class docstring updated to list all 4 formats; dead `filteredMangas` alias removed from LibraryViewModel. S49: Fixed Mangayomi JS plugin format (Format D) — all six bugs corrected: (1) detection now handles `class DefaultExtension extends MProvider` + `mangayomiSources[]` pattern; (2) `MProvider` base class and `SharedPreferences` shimmed pre-eval; (3) `getSrc`/`getHref` changed from methods to getter properties (plugins access them without `()`); (4) native `async/await` resolved via `evaluateScript` microtask drain (same pattern as LNReader's `callPluginMethod`) instead of broken `_resolve()` approach; (5) `getLatestUpdates` recognised alongside legacy `getLatest`; (6) `episodes` field recognised alongside `chapters` in `getDetail` return; (7) `_mapItem` field names fixed: `item.link` for id/path, `item.imageUrl` for cover. Mangayomi JS plugins (Webtoons, Mangafire, etc.) now fully functional. S48: Suwayomi onboarding UX (test connection, source count, setup guide), OPDS client (OPDSService XML parser + OPDSBrowseView, Kavita/Komga support, BrowseView integration, SettingsView section with basic auth), WidgetKit extension (YomiWidget target, ContinueReading widget small/medium/large, App Groups entitlements, WidgetDataWriter, pbxproj widget target). S47: Full LNReader/Mangayomi plugin audit — scanned all 131 English LNReader v3 plugins, identified and fixed every missing JSBridge shim: (1) `FormData` global constructor + `application/x-www-form-urlencoded` serialization in `@libs/fetch` and global `fetchApi` (fixes 52+ Madara/WordPress multisrc plugins — Scribble Hub, DaoNovel, MTL-Novel, WuxiaWorld.Site, etc.); (2) `@libs/isAbsoluteUrl` shim (RoyalRoad); (3) `@/types/constants` shim (NovelFire, already safe). S46: cheerio child combinator `>`, `each`/`map` wrapped-object handling, AO3/AllNovel fixes. ReadComicOnline and Mangapill are confirmed broken downloads (source URL `entityJY/mangayomi-extensions-eJ` repo is dead/404) — user should uninstall from Extensions tab. S45: Cloudflare auto-bypass + LNReader v3 `module.exports` fallback. S44: Format D Mangayomi JS shim, multi-format catalog parser, catalog UX overhaul. S43: Tachiyomi/Mihon `.tachibk` backup import + tab reordering. S42: Manga Notes, App Lock, TTS for novels, Global Search. S40: multi-repo plugin catalog + 6 novel plugins. S41: Suwayomi. Firebase has 15 live plugins. App Store deferred.

**S36 shipped:** NovelFire restored to catalog (security incident resolved) + Firebase deployed. Pure black OLED mode (`AppSettings.pureBlack`, Settings toggle, black tab bar). Alternate icon infrastructure: `AppSettings.alternateIconName`, SettingsView icon picker (3 slots: Default/Dark/Minimal), `AppIconDark` + `AppIconMinimal` appiconsets as placeholders. **To activate alternates:** drop 1024×1024 PNGs into appiconsets + add `CFBundleAlternateIcons` in Xcode Target → Info tab.

**S37 shipped:** Full 44-file Swift audit. 3 bugs fixed:
1. **"Failed to load: cancelled"** — `PluginCatalogService.fetchCatalog()` was catching `CancellationError` from tab switches and displaying it as an error. Fixed: `catch is CancellationError` branch added.
2. **Novel IDs in Browse unstable** — `SourceBrowseView` was using `UUID().uuidString` for novel IDs on every `loadContent()` call, making DB lookups fail on re-entry. Fixed: stable `"\(sourceId)_\(item.path)"` ID.
3. **MangaDetailView.loadChapters() silent failure** — `guard let ext else { return }` fired without clearing `isLoadingChapters` (spinner stuck forever). Also `ChapterQueries.fetchAll` was called synchronously on MainActor. Both fixed.
4. **NovelFull plugin** added to Firebase catalog (novelfull.net — verified accessible, Format B).

**App Store blockers remaining (see the full checklist below — this is now genuinely just App Store
Connect data-entry, not code):**
1. ~~App icon~~ ✅ Done S87
2. Age rating 18+, description, screenshots, support URL, ATS review notes — all App Store Connect only
3. ~~Apple Developer Program enrollment~~ ✅ Created S36

## Technical debt
| Area | Issue | Priority |
|------|-------|----------|
| ~~App icon~~ | ✅ Done S87 — designed S79/S82, wired into Xcode S87. | Done |
| ~~Firebase pending deploy~~ | ✅ Deployed S53 — babelnovel.js + lightnovelpub.js live at yomi-plugins.web.app. | Done |
| Chapters from Browse (partial fix) | Defensive fixes applied in S37 but root cause not fully confirmed. Chapters may still fail for some sources. Needs device testing with live plugins to verify. | High |
| ReadComicOnline + Mangapill broken | Source files contain "404: Not Found" — downloaded from dead `entityJY/mangayomi-extensions-eJ` GitHub repo. User should uninstall these two plugins from Extensions tab. | Medium |
| BabelNovel "No titles found" | Updated plugin (v1.1.0) adds proper API headers. Needs live testing. May need removal if API is auth-gated. | Medium |
| Comick blocked by Cloudflare | api.comick.dev returns 403 from non-browser clients. Site-level block, not Yomi's fault. | Medium |
| ~~Novel custom cover~~ | ✅ Done S58 — PhotosPicker added to NovelDetailView; v16 migration; all cover-rendering surfaces updated. | Done |
| ~~Novel chapter multi-select~~ | ✅ Done S58 — long-press to select, Read/Unread action bar, Select All/Cancel toolbar. | Done |
| ~~Novel scroll position save~~ | ✅ Done S60 — mid-chapter scroll save/restore + auto-scroll to resume chapter + in-progress progress bar. | Done |
| Alternate icons need Xcode step | AppIconDark + AppIconMinimal appiconsets are placeholders. Drop in PNGs + add CFBundleAlternateIcons in Xcode Target → Info to activate. | Low (after icon design) |
| Mangafire chapters | Mangayomi chapter extraction now done in JS (S51 fix). Needs live testing to confirm. | Low |
| LightNovelPub VIP (external LNReader plugin) | External LNReader catalog plugin — not Yomi's `lightnovelpub.ts`. Cannot fix without catalog plugin source. | Low |


## Session history

Full session-by-session build log (Sessions 5-55) moved to `Yomi/HISTORY.md` during the 2026-08-04
doc restructure — this file stays focused on current state + forward plan. See `METODOLOGIA.md` for
durable technical patterns/lessons distilled from that history.

## Competitive & UX research

See `Yomi/RESEARCH.md` §2 (Community Sentiment & User Needs) and §4 (UX & Reading Science) — the
canonical, current-est version of this research. The S23-era summary previously duplicated here was
removed during the 2026-08-04 doc restructure (it said the same things, less completely).
## App Store submission checklist
These items must ALL be complete before submitting to App Store Connect:

| Item | Status | Notes |
|------|--------|-------|
| PrivacyInfo.xcprivacy | ✅ Done S22 | NSPrivacyAccessedAPICategoryUserDefaults reason CA92.1. |
| Privacy policy URL | ✅ Done S25 | yomi-plugins.web.app/privacy — linked from Settings → About. |
| App icon | ✅ Done S87 | "Y." monogram, Ink default + Paper alternate, wired into Xcode (`ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS`). |
| Zero .js in binary | ✅ Done S19 | Confirmed — plugins on Firebase CDN only. |
| MAL token in Keychain | ✅ Done S24 | KeychainHelper + auto-migration from UserDefaults on first load. |
| OPDS password in Keychain | ✅ Done S100 | Same `KeychainHelper` pattern as the MAL token — was plain UserDefaults. |
| Age rating: 18+ | ❌ Pending | 2026 system uses 4/9/13/16/18+ (replaces old 17+). App enables NSFW content via user-installed plugins. Must declare in App Store Connect — this is an App Store Connect step, not a code change; every doc mention of the rating itself already says 18+ as of S100. |
| App description | ❌ Missing | Frame as "extensible reader — user-installed JS plugins". No source names. |
| Screenshots | ❌ Missing | iOS 26 simulator. Neutral content only (no recognizable piracy sources). Design + functional work both complete since S96 — nothing code-side is blocking this anymore. |
| Support URL | ❌ Missing | GitHub repo or a simple landing page is sufficient. |
| ATS review notes (`NSAllowsArbitraryLoads`) | ❌ Pending | Blanket exception (S89, for self-hosted Suwayomi/OPDS over HTTP) has no per-domain scoping — target hosts aren't known in advance, so scoping isn't feasible. Not a code change: add an App Store Connect review-note at submission explaining the self-hosted-server feature. Revisit scoping only if reviewers push back. |

## App Store compliance
Yomi is App Store compliant via the extension model:
- App binary ships with ZERO plugin files
- Users install plugins themselves from Firebase catalog (user action, not Apple's)
- Legal precedent: Paperback, Aidoku use identical model and are on App Store
- App Store description: "extensible reader with user-installed JavaScript plugins"
- Never reference specific source sites in App Store listing or screenshots
- Onboarding must make the install-a-source flow feel easy (under 60 seconds)

## iOS compatibility

**Deployment target: iOS 26.2** — no plan to lower to iOS 18.

The physical development device (Martin's iPhone, iOS 18.6.2) cannot run
the app until updating to iOS 26. The app depends on iOS 26-exclusive APIs:
`Tab()`, `ContentUnavailableView`, `.refreshable`, `.searchable`, `.ascNullsLast`.

If iOS 18 support is required in the future → branch `compat/ios18`, never on main.

## Target plugin sources
| Source | Format | Status |
|--------|--------|--------|
| MangaDex | Format A (JSON API) | ✅ Working — on Firebase |
| Comick | Format A (JSON API) | ✅ Working — on Firebase |
| Asura Scans | Format A (JSON API) | ✅ Working — on Firebase |
| AquaManga | Format A (scraping) | ✅ Working — on Firebase |
| Royal Road | Format B (LNReader) | ✅ Working — on Firebase |
| ScribbleHub | Format B (LNReader) | ✅ Working — on Firebase |
| NovelFire | Format B (LNReader) | ✅ Working — on Firebase |
| NovelUpdates | Format B (LNReader) | S20 backlog |

⚠️ Always verify current HTML of each source — selectors can change without notice.
