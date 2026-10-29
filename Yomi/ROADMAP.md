# Roadmap — Yomi

## Strategic Goal (defined S44 research audit, 2026-04-20)

> **Make Yomi the most source-diverse iOS manga + novel reader by running plugins from every existing ecosystem — without maintaining them ourselves.**

The research audit revealed that 800+ sources are already available across four compatible JS plugin formats. Yomi currently deploys 15 hand-written plugins from Firebase. The correct strategy is not to write more plugins — it is to unlock the community ecosystems that already exist:

| Ecosystem | Format | Sources available | Yomi status |
|-----------|--------|-------------------|-------------|
| Yomi Firebase | Format A | 16 | ✅ Live (index.json 1.1.0, S181) |
| LNReader | Format B | **500+ novels** | ✅ Native, needs UX/docs |
| Paperback | Format C | ~100 manga | ⚠️ Partial shim (answered S143: possible, not now) |
| Mangayomi | Format D (Dart) | 195+ manga+novel | ❌ Dart extensions — cannot run in JSC |
| keiyoushi (Mihon) | On-device JVM | Hundreds manga | ✅ Runs on the phone since S124 (Suwayomi server still supported) |
| Kavita/Komga | OPDS | User's local library | ✅ OPDS source |

**No architecture rebuild needed.** JSBridge already handles multi-format detection. Format D (Mangayomi) was attempted but Mangayomi extensions are all Dart (`.dart` files, `sourceCodeLanguage: 0`) — cannot execute in JSC. Catalog parser for Mangayomi index.json format remains in PluginCatalogService for metadata display.

**Novel support remains Yomi's exclusive differentiator.** Zero other iOS App Store apps support light novels with a plugin system. LNReader (Android, 500+ sources) has no iOS equivalent except Yomi.

---

## S195 — download bookkeeping tests + a download-deleting bug (2026-10-29, Mac + simulator build; nothing on the phone)

Martin has build 631 on his phone (encryption + Friends done) but can't do the phone checks yet. He chose, in order:
download tests → App Store guideline re-check → competitor research.
- **#249 bug found while reading the code:** selecting chapters → Mark as read, and Mark all as read, deleted their
  downloads even with "Delete manga after reading" OFF. Now they honour the setting like the reader does.
- **#250 tests:** `scripts/download-bookkeeping-tests` (41 checks): page files (`DownloadedPages.scan`, reading order,
  split rows), resume (`DownloadedPages.prepareResume`, moved out of `DownloadManager` so it can be tested), and the DB
  flag (`DownloadQueries`, refresh keeps it). A mutant survived at first and showed `scan` depended on folder order
  with leftovers of two different splits — parts are now grouped by count.
**Verified:** sim build 0 warnings, test-all 14/14, 8 mutants caught. Not run: a real download (the sim can't reach
Keiyoushi). 📱 Add to the phone checks: download one chapter, read it offline; with the setting off, mark a
downloaded chapter read → it stays downloaded.
- **Guideline re-check** (live, guidelines updated Oct 16 2026; report `~/Desktop/Projects/Yomi/reports/S195-guidelines-recheck.md`,
  RESEARCH §27): new **2.5.19** (undocumented features / bait-and-switch) is the new risk; defence = disclosure, so the
  review-notes draft now says extensions run interpreted (no JIT), https-only, signature-checked, and 18+ asks for an
  age range. 4.7 still doesn't name JVM bytecode (Keiyoushi rests on DPLA §3.3.1(B), unchanged). 1.2 "via your website"
  still open. 📱/Martin: decide whether to give the reviewer a public-domain test repository; answer the new
  social-media age-rating questions.

## S194 — TestFlight build 631 (2026-10-28)

Martin: "Yes, upload build 631". `scripts/build-testflight.sh` → build **631** = `36e9e88` (S190–S193), local signatures
verified, upload succeeded. Only warning: no dSYM for the vendored OpenJDKRuntime.framework (crash symbols for the JVM
only; harmless). 📱 Martin: answer the encryption question + add to Friends, then the S193 phone checks (Keiyoushi
background/foreground, extension install/update through the signature check, one Cloudflare check per source + Website
logins redone, two-device sync).

## S193 part 3 — migration tests, https-only plugin code, APK signatures (2026-10-25, Mac + simulator + device compile)

Martin: "keep going: migration-chain tests, APK signature pinning, plain-http plugin code".
- **#248 migration chain tested:** `DatabaseManager.makeMigrator()` (static) + `scripts/migration-chain-tests` (SwiftPM
  with the app's GRDB pin): fresh install (integrity, FKs, tables, second run no-op) and a v1-era library with data
  upgraded step by step (v24 numbers, v25 dead imports + sync mappings, reading state kept, rows decode as the app's
  models, v32 stamps). 32 checks; breaking v24 / the v32 same-value guard fails 3.
- **#247 https only for plugin code:** JS plugin downloads, catalogs, Keiyoushi index + APK, Add repository, Install
  from URL — https and a real host, final URL re-checked after redirects. Live Yomi index: all https. Suwayomi/OPDS keep
  http (self-hosted). An http repository already saved now loads nothing (catalog) or shows the error (Keiyoushi).
- **#227 APK signatures:** `Features/Keiyoushi/ApkSignature.swift` checks Android's v2/v3 scheme (signature with the
  certificate's key + chunked file digest) and returns the certificate SHA-256. Install refuses unsigned/tampered
  APKs; an update must match the pinned key (`InstalledKeiyoushiExtension.signerSHA256`, or the APK on disk for older
  installs). `scripts/apk-signature-tests`: the 3 POC APKs = Keiyoushi's published key `9add655a…`; changed content,
  directory, signed data, truncation all refused (real APKs are read from `Tools/`, never committed; CI skips them).
**Verified:** test-all 13/13 suites, sim build 0 warnings, device build OK. Not run on the phone: a real Keiyoushi
install/update through the new check (📱 add or update one extension after the next build).

## S193 part 2 — sync engine race + Keiyoushi bridge port (2026-10-25, simulator + device compile; nothing on the phone)

Martin: "push it, then the sync and bridge fixes". Both confirmed in the code first.
- **#245 CloudKit:** the engine handle is behind a `Mutex` (was a bare global read off the main actor while enable/
  disable wrote it). The start-up drain cleared every pending mark, losing one stashed between its read and the clear —
  now it clears only what it sent, and drains again at every sync. **Verified:** `-yomiSyncSelfTest` 28/28 (4 new
  drain checks); putting the old clear back fails 2 of them.
- **#246 Keiyoushi bridge port:** a background pause during start-up was ignored and the start cached a dead port;
  a dead listener was never noticed. Now: a start overtaken by a pause doesn't keep its port, `call` restarts the bridge
  and retries once on "can't connect", and coming to the foreground re-asks the server for the live port.
  **Verified:** device + sim compile only — the simulator has no JVM. 📱 Needs a phone check: open a Keiyoushi chapter,
  background the app, come back, pages + next call still load.
test-all 11/11, sim build 0 warnings, device build OK.

## S193 — visible-bug fixes from the S192 list (2026-10-25, simulator only; nothing on the phone)

Martin picked "visible bugs first". Each one re-checked in the code before fixing.
1. **Local novels from Continue/History** opened the detail page — `ResumeReading.novel` demanded a JS plugin. Now Local
   gets a nil bridge (the detail page's rule). Sim-verified: Old Style Book in Continue → reader directly.
2. **Duplicate-check dialog** ("Already in your library?") ignored Safe Mode — filtered in manga AND novel detail.
3. **Spanish:** the audit's "Queued" was already fixed; five plain `String`s still bypassed the catalog: novel night
   theme "Off", TTS voice "Automatic", Migrate "Local Files", manga Cloudflare chapter error, Keiyoushi "Not set".
4. **VoiceOver:** 8 icon-only buttons labelled (Library grid/list, Random title, Sort and filter; Clear search ×2;
   Cloudflare banner Dismiss ×2; Browse Bypass Cloudflare). 5 new Spanish strings in `es-10.json`, catalog 1046/1046.
**Verified:** sim build 0 warnings, `test-all.sh` 11/11, Continue → reader on the sim. Not checked: VoiceOver/Spanish on
screen (code + catalog only). **Still open from the list:** CloudKit engine global race + pending-mark window (#236),
Keiyoushi bridge port cached forever, migration-chain tests, APK signature pinning (#227), plain-http plugin code.

## S192 — JS plugin sandbox: own cookies, time limit, redirect check (2026-10-24, Mac + simulator; nothing on the phone)

Martin: "Don't upload yet. Work on the JS cookie jar / time limit next." No TestFlight upload. KNOWN_ISSUES #243.
- **Cookies:** every JS plugin has its own jar (`PluginCookieJar`, new `Features/Extensions/PluginSandbox.swift`),
  shared by every bridge built from its script, saved to `Application Support/PluginCookies/`. Cloudflare check,
  auto-bypass and the extension page's Website button hand that plugin only that site's cookies (plus the shared
  store, which covers/pages/Keiyoushi read). Removing a plugin deletes its jar.
- **Time limit:** `PluginCallGate` (the bridge's lock + a 120 s budget per outermost call). Over time → fetches throw
  "Yomi stopped this source…", the call returns empty. Paged novel lists (≤150 pages) get 120 s per page. Checked first:
  JavaScriptCore's own limit (`JSContextGroupSetExecutionTimeLimit`) is not in the iOS 27.1 SDK headers = private API.
- **Redirects** to 127.0.0.1/localhost/file are no longer followed (gap noted on #228).
- **Bug found on the way:** Storage → "Clear web cache & cookies" only cleared WebKit's data; now also the shared
  store and every jar.
- **Verified:** build 0 warnings; test-all 11/11 (new `plugin-sandbox-tests`, 33 checks, local test site, two processes
  for the relaunch check; mutants "jar = shared store" and "return partial result" both fail it); LNReader harness on
  the sim, 60 plugins, previous commit vs this one: identical per-plugin outcomes (32 ok / 27 popular / 1 chapter —
  same network); jar files present + backup-excluded in the sim container.
- **Not verified:** a real Cloudflare challenge or Website login (none reproducible in the sim); on the phone.
- **Tell Martin:** after this update each source may run its Cloudflare check once more, and Website logins have to
  be redone — old cookies aren't moved into the new per-source stores (moving them all would undo the isolation).
- **NEXT:** TestFlight build with S190–S192 (ask), phone check (Keiyoushi token, two-device sync, a Cloudflare source),
  plain-http plugin code.

### Part 2 — CloudKit chapter-state conflicts by time (#242; Martin chose the exact-time field over iCloud's save time)
- v32 `stateChangedAt` on `chapter`/`novel_chapter`/both stashes + triggers that stamp every real state change.
  Records send it; received state applies only if at least as new (`ChapterStateConflict`), else the local state is
  kept and re-sent. Same path for fetches and `.serverRecordChanged`. Reading time never lowered.
- Found + fixed on the way: #244 (novel stash replay onto the wrong chapter when the position id was taken).
- **Verified:** build 0 warnings (Yomi + YomiWidget), test-all 11/11, progress-rules-tests 23 (rule mutant caught),
  trigger checked in plain sqlite3, sim `-yomiSyncSelfTest` 22/22. **Not verified:** real CloudKit (sim not signed in).
- ✅ **DONE by Martin 2026-10-24:** `stateChangedAt` (Date/Time) added to both record types and deployed to Production.
  The steps, for the record (else chapter-state saves are refused in Production and wait, #204):
  1. [CloudKit Console](https://icloud.developer.apple.com) → `iCloud.pacodealer.Yomi` → **Development** → Schema →
     Record Types → `MangaChapterState` → add field **`stateChangedAt`**, type **Date/Time** → Save.
  2. Same for **`NovelChapterState`**.
  3. Deploy Schema Changes → the diff must list only those two fields → Deploy.

## S191 — Keiyoushi bridge token + CloudKit fixes (2026-10-24, Mac + simulator + device compile; nothing on the phone)

### Part 2 — CloudKit (S189 audit #4–#6; #7 was S190; #12 left open as KNOWN_ISSUES #242)
- **#4 → #239:** novel chapter state now carries the chapter's `path` and is matched by it; v31 adds
  `pending_novel_chapter_state.path` + `idx_novel_chapter_path`; one-time re-send so existing iCloud records gain a path.
- **#5 → #240:** fetched records written in one detached transaction (savepoint per record); sent-record caching batched.
- **#6 → #241:** sign-in / account switch re-sends the library; foreground `resume()` starts sync that never started.
- **Verified (sim):** `-yomiSyncSelfTest` (new `Yomi/Sync/CloudSyncSelfTest.swift`, DEBUG): path beats a colliding
  id, path-less records still apply by id, stash lands on the right path and empties, 3,000 records applied with the
  main actor never blocked (12 ms gap = idle; the old per-record shape: 2.1 s). Build 0 warnings, test-all 10/10.
- **Not verified:** a real CloudKit round trip — the simulator is no longer signed in to iCloud (sync engine never
  starts there), and account changes need a real device.
- **Martin — before the next TestFlight build (or novel chapter saves are refused in Production until done):**
  1. [CloudKit Console](https://icloud.developer.apple.com) → `iCloud.pacodealer.Yomi` → **Development** → Schema →
     Record Types → `NovelChapterState` → add field **`path`**, type **String** → Save.
  2. Deploy Schema Changes → the diff must list only `NovelChapterState.path` → Deploy.
  (Refused saves are not lost: they wait in "N items could not sync" and are sent again after the deploy, #204.)
  **DONE by Martin 2026-10-24** (field added in Development, Deploy Schema Changes run; not checked by me in the console).

### Part 1 — Keiyoushi bridge token

S189 audit #8. Build 621 (S190) is on TestFlight with Martin's encryption answer done.

- **What:** Yomi makes a 256-bit token once per launch (`KeiyoushiBridge.token`, `SecRandomCopyBytes`) and starts the
  server with `EmbeddedBridge.start(port, appDir, token)` (new in our M-Extension-Server patch; tokens < 32 chars
  refused). Every route — `/dalvik`, `/image/`, `/video/`, `/stop`, `/`, `/capabilities` — answers 401 without
  `X-Yomi-Bridge-Token` (`MessageDigest.isEqual`). The token survives pause/resume (same process, same token).
- **Fail closed:** `KeiyoushiJVMHost startWithToken:` only looks up the 3-argument start; an old jar is an error, never
  an unlocked server.
- **Clients:** `/dalvik` calls set the header; `bridgeImageRequest` (was `pointAtLivePort`) adds it to bridge image
  requests in Kingfisher's modifier and now also in `KeiyoushiCovers.request(for:)` (downloads), which also gained the
  live-port fix. The prefetcher already merges Kingfisher's default options by hand, so it gets the modifier.
- **Mac harness:** `run-server.sh` makes a fresh token into `$WORK/bridge.token` (0600), `Launcher.java` passes it,
  `call.py` sends it.
- **Verified:** `EmbeddedBridgeTest` 2/2 (and fails when the check is disabled); Mac bridge: no token / wrong token /
  web-style text/plain POST → 401, with token → 200; Asura popular → search → details → 346 chapters → pages → image;
  image proxy 401 without, 200 with; patch applies cleanly at the pinned commit; sim build + device build (Personal,
  runtime embedded) 0 warnings; test-all 10/10.
- **Not verified:** a run on the phone (the runtime has no simulator slice). Check: Browse Asura, open a chapter,
  background + resume mid-chapter, download a chapter.
- **Tip:** a device build with `-derivedDataPath` inside `~/Desktop` fails at codesign ("resource fork, Finder
  information, or similar detritus") — use `~/Library/Developer/Xcode/DerivedData`.

## S190 — S189 audit fixes + the unverified leads checked (2026-10-24, simulator + Mac only; nothing on the phone)

Martin: "continue, use the session wisely". Took the S189 ranked list, then ran 3 read-only verification agents
(data/library leads, JS-plugin security leads, the concurrency audit that never reported) — ~25 leads → ~20 confirmed,
all fixed except the ones listed under "still open". KNOWN_ISSUES #220–#237 has one row per fix.
**Fixed (commit `b9bdb4f` + docs):** tracker count never goes down / never 0 (#220); novel Previous/list jump resumes
the target's saved % (#221, **sim-verified**: 686 at 43 % → Next → Previous = 43 %, DB keeps 0.427); JSON restore
MERGES (downloads kept, read ORs, furthest position, phone's notes/status/cover kept) (#222); export = one read
transaction, orphans skipped on restore (#223); truncated .tachibk = "incomplete" (+ gunzip kept inflating after the
last input byte — big streams could lose their tail) (#224); reading time additive, background time dropped (#225);
CloudKit lastReadAt from the record's readAt (#226); Keiyoushi + JS plugin updates only from their origin (#227, #228);
`PluginNetworkPolicy`: SOURCE.fetch http(s) only, no loopback/link-local; path-like plugin ids refused (#228);
**all Remove-from-library paths keep downloads now** (behaviour change; Downloads deletes) + heart writes 2 columns
(#229); baseline updates silent (#230); Continue resumes Suwayomi/Local manga (#231); novels NULL numbers last (#232);
Safe Mode on Downloads/Insights/Local (#233); BG refresh honours expiry (#234); widget refreshes on background (#235);
5 concurrency races (#236); VoiceOver labels (#237).
**Verified:** sim build 0 warnings; `test-all.sh` 10/10 (new `progress-rules-tests` 14, plugin-trust 46);
ReaderUITests 13/13; Spanish catalog 1041/1041; novel jump on the sim with real WeTried content.
**Still open (next):** Keiyoushi bridge token (a remote 302 to 127.0.0.1 still reaches the bridge; touches the Kotlin
server + JNI), APK signature pinning, CloudKit session (novel state keyed by local id #4, apply on main #5, account
switch #6, engine global race), JS: shared cookie jar, no time limit, plain-http code (`NSAllowsArbitraryLoads`);
Local NOVELS from Continue; duplicate-check dialog Safe Mode; remaining icon-only buttons. Research sweeps
(competitors, guideline re-check) still not run. Phone: nothing new installed — next TestFlight build needs Martin's go.

## S189 — overnight multi-agent audit (2026-10-24, simulator + Mac only; cut short by the usage limit)

**Build 615 (`0715b3a`) uploaded to TestFlight OK** (02:33). It needs Martin: the encryption answer + the Friends group.
Warning only: no dSYM for `OpenJDKRuntime.framework`. Audit: 9 code areas, each finding re-checked by an agent that tried
to disprove it → **26 confirmed**. About 25 unverified, and concurrency + all research never finished (usage limit).
Full report: `~/Desktop/Projects/Yomi/reports/S189-audit.md` (outside the repo: it lists open security issues).
**Fixed + pushed:** `131a8b3` crafted protobuf length trapped the app (.tachibk/index.pb) + Keiyoushi packageName path
traversal; `e9d17c5` `manga.trackingTitle` was never read/written by the GRDB codec (Migrate → Tracking did nothing);
`9b15bbe` manga reader Next/Prev/list resume the saved page + a stale first load can't land on a newer chapter.
Verified: sim build 0 warnings, test-all green, ReaderUITests 13/13. Not on the phone.
**Top open (report §ranked):** JSON restore clears isDownloaded; tracker auto-update can LOWER MAL progress; novel
Prev/list jump opens at 0 % and autosaves over the saved position; CloudKit novel state keyed by device-local chapter id
(#187 is NOT harmless for sync); sync applies on main; Keiyoushi loopback bridge unauthenticated + no APK integrity /
cross-repo updates.

## S188 — REPORT (2026-10-23, Kingfisher before university + the full plan in the evening; simulator + Mac only)

**Done, each committed + pushed** (`73d0674`…`8475dc5`, details in the parts below):
1. Kingfisher 8.9.0 → 8.14.0 — build 0 warnings, test-all, ReaderUITests 13/13, perf gates 8.14 vs 8.9 identical
   within noise (93–96 MB strip peak, launch 2.15 s on both).
2. **#208** — a refresh that changes chapter URLs no longer duplicates chapters; read state, page, bookmark move to the
   new chapter (`Core/ChapterCarryOver.swift`, numbers from names, strict one-to-one). Unit tests + seeded sim run.
3. **#193/#196** flaky reader UI tests — cause: the App Store rating sheet (review counter persisted across test runs).
   Fixed under the UI-test fixture only; 20/20 after.
4. **`docs/EXTENSIONS.md`** + **Wikisource example plugin** (`docs/example-plugin/`), linked from README. Live repository
   link: `https://raw.githubusercontent.com/PacoDealer/Yomi/main/docs/example-plugin/index.json`.
   Gutenberg/Standard Ebooks ruled out by their own terms (see part 5).
5. **#218** — searching inside a JS-plugin source now asks the source (was: only filtered loaded titles).
6. **#219** — `book.open` isn't an SF Symbol (reading-status icon was blank) → `book`.
7. Audit pass: no bare `withAnimation`, no `AsyncImage`/`.tabItem`/`Text + Text`, no reader page loaded with
   `KFImage(url)`, no `AppSettings.shared` read inside `Task.detached`, all 121 symbol names exist, no new Spanish leaks
   (316 = same as before tonight).

**Not verified (needs the phone):** Kingfisher 8.14 feel + hitches (`perf-gates.sh --device`), #208 against real Aqua
(site down), per-source search in NovelFire/WeTried, the real Declared Age Range sheet (S187). No phone install, no Firebase deploy.
**Build 615 (`0715b3a`) uploaded to TestFlight after the session (S189 confirmed) — needs encryption answer + Friends group by Martin.**

**For Martin:** (a) the next phone build carries all of this — say when to `build-personal.sh --release` or upload a
TestFlight build; (b) the example plugin's repository link above is public now — add it on the phone to try it, or
tell me to change the example; (c) sim leftovers: a `http://localhost:8765/index.json` repository is still added in
the simulator (harmless, fails to refresh).

## S188 — Kingfisher 8.14 (2026-10-23, 20-minute slot before university, simulator only)

The overnight run below never started (Martin forgot to leave it running). In a 20-minute slot: **Kingfisher
8.9.0 → 8.14.0** (`Package.resolved` pin; the project range stays `upToNextMajor` from 8.0.0). Release notes 8.10–8.14
read via `gh release view`, nothing breaking. Changes that matter to Yomi: 8.14 shows memory-cached images in the
first render pass (`loadMemoryCacheSynchronously`, default ON → fewer placeholder flashes / scroll jumps in the
reader), 8.14 retain-cycle fix in `ImagePrefetcher`, 8.11 avoids full-size data copies on big downloads, 8.12
releases views while a download is in flight. Minimum toolchain is now Xcode 26 / Swift 6.2 (we're past that).
**Verified:** sim build 0 warnings, `test-all.sh` all pass, ReaderUITests 13/13 passed (179 s). **Not done:**
the S160 `footprint` memory before/after with the tall test pages, Asura chapter by hand, device. Licence texts
don't name versions, so `build-licenses.sh` wasn't needed. Next: tasks 2–6 of the plan below are still open.

### S188 part 6 — #218 per-source search asks the source (simulator)

`SourceBrowseView` (JS plugins) only filtered the titles already loaded; Keiyoushi/Suwayomi screens already searched on
submit. Now Search (return key) runs `searchManga`/`searchNovels` page 1; typing keeps the instant local filter. Verified
on Wikisource ("Declaration of Independence": none while typing → 18+ after Search) and Asura Scans JS ("Omniscient" →
Omniscient Reader's Viewpoint). Only page 1 of results — a long result list would need paging. 📱 Martin: try a search
inside NovelFire / WeTried.

### S188 part 5 — extension guide + Wikisource example plugin (simulator + live API)

`docs/EXTENSIONS.md` (linked from README) + `docs/example-plugin/` (`wikisource.js`, `index.json`, `test.mjs`). Source
choice: Martin asked for "Project Gutenberg / Standard Ebooks style" — checked live: gutenberg.org's robot policy says
the site is for human users only and blocks automated access; Standard Ebooks keeps all but its New Releases feed for
patrons and sets bot-ban links. **Wikisource** (MediaWiki Action API, made for programs; PD / CC BY-SA texts) is the same
kind of library without those problems. Plugin = Format B: Category:Novels A–Z (Popular) / newest-added (Latest, via
`options.showLatestNovels`), `list=search`, `pageimages` covers, chapters = subpage links in page order minus container
pages, chapter HTML without header/footer + a source link; descriptive User-Agent per Wikimedia policy.
**Verified:** `node docs/example-plugin/test.mjs` 11/11 against the live API with Yomi's own cheerio bundle; real
JavaScriptCore on the Mac (a small swiftc harness) — parseNovel 0.8 s; in the sim end to end through a localhost
repository: Add Repository → Install (sha256 checked) → Update 1.0.0→1.0.1 → Browse (covers) → detail "Jane Austen ·
Completed · 61 chapters" → reader shows chapter 1. Found + fixed on the way: the volume check matched "Volume 1 ·
Chapter 1" and fetched all 61 chapters (27 s → 0.8 s); summary was raw CSS from an inline `<style>`.
Guide claims checked against the code — corrected 4 before commit: novel chapters are keyed by POSITION
(`NovelDetailView`: `"\(novelId)-ch-\(index)"`), not path; no Cloudflare-cookie sharing claim; no `btoa`; Format A
chapter numbers come from the plugin, not the names.
Also found: **#218** per-source search only filters loaded titles (OPEN); **#219** `book.open` isn't an SF Symbol
(fixed; all 121 symbol-like literals checked, it was the only one).

### S188 part 4 — flaky UI tests #193/#196 fixed (simulator)

Both run ×10 alone: #196 failed 1/10 ("second Next left chapter 2 on screen"), #193 10/10. The failed run's UI
hierarchy (`xcresulttool export attachments`) showed the App Store rating sheet: `recordChapterRead()` asks at 10/50/200
read chapters and the count lives in the sim's prefs across every test run (228 tonight). DEBUG-only guard in
`AppSettings.recordChapterRead()` for `-yomiReaderFixture` (AppSettings is shared with the widget, which has no
`ReaderFixture`). Proof: counter 47 → both tests ×10 → 20/20, counter still 47. CLAUDE.md's "flaky — re-run alone" note
removed. Real users are unaffected (same thresholds).

### S188 part 3 — Kingfisher 8.14 measured (simulator, `scripts/perf-gates.sh`, same Mac, nothing else running)

| Kingfisher | Launch (first frame) | Launch wall clock | Long-strip memory peak |
|---|---|---|---|
| 8.14.0 run 1 | 2.173 s | 4.202 s | 96.0 MB |
| 8.9.0 (temporarily re-pinned) | 2.147 s | 4.196 s | 92.6 MB |
| 8.14.0 run 2 | 2.145 s | 4.171 s | 93.0 MB |

No difference beyond run-to-run noise (±3 MB). Launch is ~2.15 s on both versions vs 1.41 s at S179 — the drift is the
environment (Mac/sim state), not Kingfisher; still under the 2.5 s gate, worth a look if it keeps rising.
`backgroundDecode` NOT turned on: the simulator records no hitches, so there is no number to justify it — a device
perf run (`perf-gates.sh --device`) is the place to decide. 8.14's first-frame memory-cache load is the change most
likely to be felt (fewer placeholder flashes) and can only be judged on the phone.

### S188 part 2 — #208 duplicate chapters fixed (2026-10-23 evening, simulator)

See KNOWN_ISSUES #208. First version ran AFTER the insert and matched nothing on the sim (the new rows were already
"saved") — the 14 pure-logic checks passed anyway; only the end-to-end sim run caught it. Redone as a rename of the
saved row BEFORE the insert. Also found: Mangayomi plugins store the list INDEX as `chapterNumber`
(`JSBridge.getChapterList`), so the carry-over reads numbers from names only. Lesson → METODOLOGIA.

## S188 plan — tasks 2–6 still open (written 2026-10-22; was meant to run overnight)

Martin is asleep: **simulator + Mac only**. Never: TestFlight upload, `build-personal.sh` / phone install, `firebase
deploy`, App Store Connect, force-push, anything that needs his password or a click. Sim = iPhone 17 Pro `F31CC190`
(set XcodeBuildMCP defaults first; they drift). Ask the host for keep-awake at the start. Each task: build with 0
warnings → `scripts/test-all.sh` green → Spanish leak check (`find-unlocalized.py`) → one commit → ROADMAP note.
If a task is blocked or turns risky, write why and move to the next — never stall waiting for him.

1. **DONE S188 (bump + perf gates, part 3): Kingfisher 8.0 → latest 8.x (8.14?).** Check the real latest tag on GitHub first (not recall). Read its release
   notes between our resolved version and the target; bump the package; build; test-all; sim check of the long-strip
   reader with the 20 tall test pages (`Documents/Local/Tall Test`, S160 method: `footprint -v` peak before/after)
   and an Asura JS chapter (Absolute Regression, id 2127). Look at `backgroundDecode` (S122 stutter note) — only turn
   it on if the before/after numbers say so.
2. **DONE S188 part 2: #208 fix without Aqua (stability).** When a refresh returns chapters whose ids are all new, match old rows by
   chapter number (`ChapterRecognition`) and move path/id + keep read state, instead of adding a second copy. Pure
   logic → unit tests with a fake old/new list (Madara slug+memo case, duplicates, decimals, a genuinely new chapter).
   No live Aqua test — mark "unit-tested only, needs Aqua back".
3. **DONE S188 part 4: Flaky UI tests #193/#196.** Run each 10× alone; find the timing cause; fix the wait (not a sleep) if found.
4. **DONE S188 part 5: "How to write a Yomi extension" guide** (`docs/EXTENSIONS.md` at repo root, NOT under `Yomi/` — or exclude it from
   the bundle; run `check-bundle-docs.py`). Formats A/B, the JSBridge API actually exposed (read `JSBridge.swift`, not
   memory), the fake-cheerio limits, how to test locally, how to host an `index.json`. Example plugin = a legal
   public-domain source only (see the morning question), kept in `docs/example-plugin/`, never a scraper of a
   piracy site (S185 rule).
5. **If time is left — audit pass, report only:** grep for new `withAnimation`, `KFImage(url`, `fatalError`,
   unfiltered title lists (SafeMode), String text without `String(localized:)`. Fix only the mechanical ones; list
   the rest.
6. **Morning report** at the top of this section: what's done, commit hashes, what was verified how, what was NOT
   verified (phone, real age sheet, Aqua), and the decisions waiting for Martin. Update CLAUDE.md "Current state"
   + memory.

Still for Martin (not tonight): phone check of the age sheet + S183 list with the next build, trackers, two-device
sync, App Store listing/screenshots, tip jar.

---

## S187 — Declared Age Range gate on the 18+ switch (2026-10-20, simulator only)

AUDIT_S184 §2 E / guideline 4.7.5 ("an age restriction mechanism based on verified or declared age"). API read from
the iOS 27.1 SDK's `DeclaredAgeRange.swiftinterface` (not recall): `@Environment(\.requestAgeRange)` →
`requestAgeRange(ageGates: 18)` → `.sharing(range)` / `.declinedSharing`, throws `notAvailable`, `invalidAccount`,
`declinedOnboarding`, `network`, `invalidRequest`.

- **`Yomi/Core/AgeGate.swift`** (new): `AgeGate.outcome(lowerBound:)` — only a lower bound ≥ 18 is adult; `request()`
  maps errors to `.unavailable`. `AdultExtensionsToggle` replaces the bare Toggle in `RepositoriesView`: ON asks the
  system; adult → on; under 18 → alert "18+ extensions are for adults"; declined → alert "Your age range wasn't
  shared"; unavailable → confirmation "Are you 18 or older?" (self-declaration, still "declared age"). OFF never asks.
  Safe Mode still disables the switch. Existing `showNSFW = true` is kept (no App Store users yet).
- **Entitlement** `com.apple.developer.declared-age-range` added to `Yomi.entitlements` + `Yomi-Release.entitlements`.
  **Not yet signed for the phone** — the App ID needs the capability; automatic signing should add it on the next
  `build-personal.sh --release` / archive. If signing fails, enable "Declared Age Range" on the App ID in the portal.
- DEBUG `-yomiAgeRange adult|under|declined|unavailable` answers without the system sheet.
- Spanish: `scripts/localization/es-10.json` (7 keys) → 1037/1037. Old footer key "Off hides extensions…" now unused.
- **Verified (sim):** real API in the simulator → `familycircled` → `notAvailable` (no Apple Account) → self-declaration
  dialog → "I'm 18 or Older" → switch on, `showNSFW = true` in prefs; drag off → false with no request; `-yomiAgeRange
  under` → alert, switch stays off. Build 0 warnings, test-all all pass. **Not verified:** the real system age sheet
  (needs a device with an Apple Account), `adult`/`declined` paths on screen (same code as above, one line each).
- Sim tip: XcodeBuildMCP `tap` and the iOS Simulator `control` tap both miss this SwiftUI switch — a short
  `touch_path` drag across the knob toggles it.
- Still open from S154's list: guideline 1.2's "turned on via your website" wording for mature content — Martin kept
  the in-app switch (S154); the age gate is the 4.7.5 part only.

**NEXT:** phone check of the age sheet (with the next personal/TestFlight build) → Kingfisher 8.14 → "How to write a
Yomi extension" doc + example plugin for a legal site.

---

## S185 — Martin's audit decisions + migration-failure screen (2026-10-19, simulator + GitHub)

Martin read the S184 audit and decided §2 in one sitting. He wants Yomi **open source** so anyone can build on it and
help — not private. Decisions and what was done:

- **A — open source without the risky parts (done):** licence = **MPL-2.0** (`LICENSE` = Mozilla's text, `NOTICE` lists
  the exceptions: Mihon ports Apache-2.0, the M-Extension-Server patch, bundled third-party). Scrapers + catalog moved
  to the **Firebase folder's own git only** (`Firebase/tools/plugins-src`, `build-plugins.mjs`, `catalog-hashes.py`,
  older repo copies in `tools/archive-from-ios-repo-S185/`; predeploy hook repointed) — commit `43b302b` there.
  Removed from the iOS repo AND its history (`git filter-repo --prune-empty never`, so the commit count = build
  number is unchanged): `scripts/plugins-src/`, `scripts/catalog-output/`, 16 `Yomi/Resources/<site>.js`. Backups
  before the rewrite: `~/Desktop/Projects/Yomi/repo-backups/` (mirror + bundle). Force-pushed; 0 forks existed.
  README: repository *formats* instead of the link table; licence section. GitHub now detects MPL-2.0. The Yomi
  Catalog itself still serves from Firebase (app unchanged). Old README text with the links stays in history (public
  URLs only, not code).
- **B — TestFlight (done):** build **602** (`c26c96c`) uploaded 2026-10-19 09:06 on Martin's go — "Upload succeeded", signatures verified, bundle guard + 3 privacy manifests + codesign checked in the archive. Harmless warning: no dSYM for `OpenJDKRuntime.framework` (symbols only). Martin still answers the encryption question and adds it to Friends in App Store Connect.
- **C — GitHub settings (done):** description/homepage/topics, ruleset "Protect main" (no deletion, no force-push —
  **a future history rewrite must disable it first**), secret scanning + push protection, vulnerability alerts, stale
  branch `worktree-agency-agents-docs` deleted (its draft PR #1 was already closed).
- **D — donations:** GitHub Sponsors **and** Ko-fi. **Done S186:** both accounts exist (Sponsors payouts via Stripe to
  the **pesos** CBU; Ko-fi via PayPal — Stripe isn't offered to Argentina on Ko-fi, and PayPal AR withdraws only to a
  pesos account, dollar accounts get reversed); `.github/FUNDING.yml` = `github: PacoDealer`, `ko_fi: pacodealer`.
  No donation links inside the app or its App Store metadata (3.1.1(a): only the US storefront allows them) — in-app
  = IAP tip jar later (Paid Apps Agreement, Small Business Program). Liberapay/BMC/Open Collective considered, not added (RESEARCH §29).
- **E — Declared Age Range (4.7.5):** **done S187** (`Core/AgeGate.swift`), sim-verified; device check pending.
- **F1 — failure screen (done, #215):** `Yomi/Database/DatabaseFailureView.swift`; `DatabaseManager.open()` keeps the
  error instead of `fatalError`; YomiApp shows the screen, `startDatabaseServices()` runs only once the DB is open;
  scene phase, background refresh and CloudKit push return early while it isn't. DEBUG `-yomiFailMigrationOnce`.
  Sim: screen, pre-migration copy made, failed migration not recorded, Share = 2 files (167 MB), Try Again → Library
  162 titles. Spanish 1031/1031 (`es-9.json`). test-all 7/7 + guard, ReaderUITests 13/13, build 0 warnings.
- **F2 — Kingfisher 8.14:** after build 600, with a phone check. F3–F5 (SwiftLint, big files, listing) unchanged.

**NEXT:** Declared Age Range → Kingfisher → "How to write a Yomi extension" doc +
example plugin for a legal site (the open-source ask) (FUNDING.yml done S186).

---

## S184 — overnight audit: privacy manifests, docs inside the app, Spanish leaks, CI, GitHub (2026-10-18/19, sim + Release device build, Martin asleep)

Martin: audit everything, check the roadmap for gaps, research what we didn't consider (incl. GitHub organisation,
branch protection, donations, whether the catalog can be public under Apple's rules); don't ask. **Full report:
`Yomi/AUDIT_S184.md`** (what was fixed, decisions in order, ready-to-run GitHub commands, README draft).

- **Fixed + verified:** privacy manifests (App Group `1C8F.1`, widget + `OpenJDKRuntime.framework` manifests, DiskSpace
  `E174.1` — #212); internal docs + `AppSecrets.swift.template` + unused Space fonts no longer copied into the app (#213,
  build 515 has them); 13 Spanish leaks (#214, 1028/1028 keys); DB copied before pending migrations (#215 safety net,
  sim-verified by rolling back to v29); `scripts/test-all.sh`, `scripts/check-bundle-docs.py`, GitHub Actions **Tests**
  (green on GitHub), issue forms; Firebase folder = local git repo (no remote); doc drift (CLAUDE.md 268 → 150 lines,
  old block in HISTORY.md; `rules/grdb.md` v29 → v31; checklist rows; strategic table; README import steps).
- **Found, not done (need Martin):** public repo holds 6 scraper sources + a catalog index + the repository URL table
  while Keiyoushi's repos got a DMCA notice in March 2026 (AUDIT §2 A); next TestFlight build to replace 515 (§2 B);
  GitHub settings (§2 C); donations = GitHub Sponsors outside the app (Argentina supported, 0 %) + IAP tip jar inside
  (§2 D); Declared Age Range API for 4.7.5 (§2 E); migration-failure screen, Kingfisher 8.9 → 8.14, SwiftLint config,
  big files (§2 F).
- **Later the same night:** novel reader Content-Security-Policy (chapter HTML can't run inline handlers — #216;
  macOS WKWebView experiment + control) and Library "Remove from Library" write-then-reload race (#217, sim: title gone
  at once, restored after). Live plugin smoke test: Asura, WeTried, NovelFire, NovelBin work end to end; 9 sit behind
  bot protection (needs an in-app pass); LightNovelPub + MTLNovel unreachable from this network (AUDIT §2 G).
  TACHIMANGA_PARITY drift struck + v5.2 preview checked.
- **Tests:** sim + Release device builds 0 warnings; `scripts/test-all.sh` 7/7 + bundle guard; CI green; ReaderUITests
  13/13 + PerfUITests 3/3 after the manifest/bundle/Spanish fixes, ReaderUITests 13/13 again on the CSP + race build.

**FOR MARTIN (morning):** read `Yomi/AUDIT_S184.md` §2 — A (repo/catalog) is the one that matters; then the S183
phone check-list below still stands.

---

## S183 — Keiyoushi pages: crop + image cache survive a relaunch (2026-10-18, simulator)

- Martin (phone): **resume works** after the S182 fix — device-verified.
- The leftover from that fix: `PageLooks` (crop + background) and Kingfisher's disk cache were still keyed by the
  Keiyoushi page URL (`127.0.0.1:<port>/image/<random UUID>`, new every launch), so after each launch every Asura
  (Keiyoushi) page was downloaded again and re-measured.
- **Fix:** the chapter + index names moved out of `PageShapes` into `PageNames` (`ReaderPagePrefetcher.swift`), used by
  every per-page store: `PageShapes` + `PageLooks` key by `PageNames.key`; Kingfisher loads go through
  `PageNames.source(url)` = the page's URL with cache key `keiyoushi-page/<chapterId>#<index>` (paged `KFImage`, strip
  `StripPageImage.load`, page menu `ReaderPageActions.image`, prefetcher `ImagePrefetcher(resources:)`, and
  `PageShapes.learn`'s disk-cache path). Pages that aren't from the bridge keep their URL as the key (no change).
- Known trade-off: if a source changes a chapter's pages, a cached Keiyoushi page can be the old image until Kingfisher's
  disk cache expires it (7 days). Same assumption `PageShapes` already made in S182.
- Sim: build 0 warnings, ReaderUITests 13/13, PerfUITests 3/3. **Keiyoushi path unverified** (no JVM in the sim):
  on the phone, open an Asura chapter, kill Yomi, reopen offline-ish (or watch it) — pages above the saved one should
  appear at once without re-downloading. Not on the phone yet (needs `build-personal.sh --release`).

### S183 (same day, Martin at dinner — autonomous)
- **#106 done:** `ChapterReaderView.swift` (2,021 lines) split by pure moves into `ChapterReaderView.swift` (751),
  `ReaderPagedViews.swift`, `ReaderScrollViews.swift`, `ReaderOverlayView.swift` (sorted-line checksum of old vs new is
  identical apart from `PageRetryButton` losing `private`). Build 0 warnings, ReaderUITests 13/13, PerfUITests 3/3.
- **#203 / #209 closed** on Martin's J round 2 + the on-phone perf run (KNOWN_ISSUES).
- **Spanish, code side complete:** fresh sim build → `build-catalog.py`: app 1016/1016, widget 3/3 in Spanish;
  `find-unlocalized.py` leftovers are font names, HTTP headers, sample data, and three accessibility labels that ARE in
  the catalog (checked). Only Martin's on-phone look is left.
- Health check: chapter recognition 103, fetch interval 54, reader pages 26/26, term replace, plugin trust 14, page text
  — all pass.
- Phone: has the first S183 build (`94cee39`, cache fix). The split build could not be installed (phone away,
  "unavailable"); it is a pure move, nothing to check there.

**FOR MARTIN (S183 check-list, phone):**
1. Asura (Keiyoushi) chapter → read a few pages → kill Yomi from the app switcher → reopen the chapter: pages above
   the saved one appear at once (no spinners, no re-download); with crop borders on, no margin flash.
2. Spanish: iPhone Settings → Apps → Yomi → Language → Español; glance at Library, a title, the reader menus, More,
   and the widget; tell me any English left.
3. Decide when you want them: trackers (AniList client id, ROADMAP S170 decision 3), two-device sync test, tip jar
   (needs Paid Apps Agreement; plan in BACKLOG — Support / donate).
4. Optional: run `scripts/build-personal.sh --release` with the phone unlocked to get the latest build (`3b2b23e`+).

## S182 — CloudKit: new S167 fields into the Development schema (2026-10-18, simulator)

- Only S167 (`fc3d3c0`) changed the synced fields since the S152 deploy: `Manga.excludedScanlators` (STRING LIST),
  `MangaChapterState.isBookmarked`, `NovelChapterState.isBookmarked` (INT64). `Novel.genres` is already in Production
  (S156 console read).
- Sim iPhone 17 Pro 26.3 (F31CC190, still signed in to Martin's iCloud), Debug build (development environment). Sync was
  OFF since S153. Wrote the values straight into the sim DB (backup: `build/S182-sim-yomi-before.db`) and set
  `cloud_sync_map.pendingChange = 'save'`: hidden group **"S182 schema test"** on The Ruler Of Darkness (Keiyoushi; no
  chapter has that group, so nothing is hidden), bookmark on Absolute Regression (id 2127) chapter 159702, bookmark on
  A Regressor's Tale of Cultivation ch-0, plus the 3 novels with genres. Turned sync ON (XcodeBuildMCP tap on the row
  `e34` worked; tapping the switch itself did nothing, also not with the simulator `control` tap).
- **Saved, all three:** pending marks cleared, and each record's cached copy holds the new field (`excludedScanlators`
  with "S182 schema test"; `isBookmarked` on both chapter states). Development saves auto-create fields, so they now
  exist in the Development schema.
- **Martin:** CloudKit Console → `iCloud.pacodealer.Yomi` → Deploy Schema Changes → diff must list those three fields
  → Deploy. **DEPLOYED by Martin 2026-10-18.** Placeholder group then deleted in the sim DB + synced (cached record no
  longer holds it).
- **Personal build switched to real entitlements** (Martin's call): `Config/Personal.entitlements` = `Yomi.entitlements`
  + `com.apple.developer.icloud-container-environment = Production` (Apple doc read), so the phone syncs with the same
  data as TestFlight, not the sim's Development copy. `Personal.xcconfig` picks entitlements per target
  (`$(PERSONAL_ENTITLEMENTS_$(TARGET_NAME))`, widget keeps its own) and no longer defines `YOMI_PERSONAL`. Release
  device build SUCCEEDED, 0 warnings; signed app has CloudKit + Production + App Group, widget has the App Group;
  profile expires 2027-10-15. Installed by Martin (`build-personal.sh --release`).
- **J on the phone (Martin, 2026-10-18):** library intact, sync ON (made the whole app slow during the first upload, then
  fine), Safe Mode OK, Asura: no black pages, page counter works, a few grey boxes that load fast; backup + extension
  gear + filters "seem to work". Found: (a) reopening a chapter started at page 1, (b) widget: no cover, title cut,
  "not well designed", (c) Translate slow, odd wording, and a translated chapter isn't faster the second time.
- **(a) fixed:** the manga reader saved the page only in `onDisappear`, which never runs when Yomi is killed from the app
  switcher or by iOS. `ChapterReaderView` now also saves on `scenePhase == .background`. Sim: Tall Test paged 2/20 and
  webtoon 11/20 → Home → `simctl terminate` → relaunch → opens at 2/20 / 11/20 (DB `lastPageRead` 1 / 10; before the fix
  nothing was written). The mode picked inside the reader is per session (Settings holds the default) — unchanged.
- **(b) fixed:** `AsyncImage` never loads in a widget. The app now saves each shown cover as a ≤300 px JPEG in the App
  Group (`widget-covers/`, `WidgetDataWriter.withSavedCovers`: Kingfisher cache/download, Keiyoushi proxy, custom/local
  cover files); `WidgetReadingItem.coverFile`. Widget redesigned calm: small = cover top-left + play icon, title across the
  full width (3 lines); medium = 3 covers; large = a list of 5 ("Continue Reading"). Sim: small widget on the Home Screen
  shows the cover + title; medium/large unseen.
- **(c) partly:** translations are saved per (target language, exact chapter text) in `Caches/novel-translations`
  (400 files max); a saved chapter is put back without the Translation session. Device-unverified (the sim can't
  translate). Wording = Apple's on-device model, line by line.
- **Translate TAKEN OUT (Martin: "leave it to the backlog so we can actually improve it").** `NovelTranslation.isAvailable
  = false` hides the Reading-tab toggle and ignores saved per-novel choices (`novelTranslateIds` kept); the code, the
  cache and the strings stay. Sim: Reading tab shows Layout / Infinite scroll / Swipe / Show menu / Replacements only.
- Reader UI tests 13/13, 0 warnings.

### BACKLOG — Translate, done properly (S182)
Martin's phone, S177 version: slow (a whole chapter through Apple's on-device model before anything shows), wording
"kinda weird", nothing kept between visits (cache added S182, unverified). Read-aloud reads the original. To look at:
1. **Context:** today every LINE is a separate request, so names/pronouns/tone drift. Send whole paragraphs (or a few
   at a time) and measure on real WeTried chapters; ask Martin for the lines that read wrong + the language pair first.
2. **Speed:** show the first screen translated first (paragraphs in view → rest in the background), keep the original
   visible meanwhile; reuse the S182 cache; translate the next chapter ahead like page preload.
3. **Names:** protect character/place names with Term Replacements (S177) before translating, or a per-novel glossary.
4. **Engine:** Apple Translation only (free, on device, no key). Compare quality vs alternatives before committing —
   any server engine needs a key/cost and sends text off the phone (privacy label).
5. Read-aloud on the translated text; keep italics/links.
Turn back on = `NovelTranslation.isAvailable = true` + device check.

### Perf gates on the phone (S182, first device run)
`scripts/perf-gates.sh --device 00008150-00187C4A1EF3401C` now builds with `Personal.xcconfig` (the test install
REPLACES Martin's Yomi — with the default signing it would have synced against the Development environment) in Debug
(the reader fixture is Debug-only — a Release run found no fixture, 2 tests failed). Reinstall afterwards with
`build-personal.sh --release` (done). iPhone 17, Debug:
- Manga long strip: memory peak **43 MB** (limit 300 MB), hitch ratio **0.4 ms/s** (limit 5). Novel reader: **0.0 ms/s**.
- Launch: **not measured** — the device run records no `XCTApplicationLaunchMetric` value at all (the test passes, the
  result has no launch metric; sim records it). Open: find why (iOS build 24A94232 / Xcode metrics on device) or gate
  launch with an os_signpost instead.
- NEXT: personal build → J.
- **Launch gate on the phone (S182, later):** the device log shows `IDESchemeActionSDKRecord: operatingSystemBuild =
  24A94232, error = invalidDigitCount(94232)` before every launch — Xcode 27.1 can't parse the phone's OS build. Hitch
  and memory metrics still record with the same error, so it's a likely cause, not a proven one. Workaround:
  `testReaderLaunch` also measures `XCTClockMetric` (wall clock of `launch()`, incl. XCTest's terminate + idle wait);
  gate `Clock Monotonic Time` ≤ 6 s everywhere, the real launch gate is now `simulatorOnly`. Sim: launch 1.43 s, clock
  3.48 s. `perf-gates.sh --result` now tells device runs from the result's device id (it used to treat every
  `--result` as a simulator run and skip the hitch gates). Clock on the phone UNMEASURED — next `--device` run (it
  replaces Martin's install → reinstall with `build-personal.sh --release` after).
- **J round 2 (Martin, phone, 2026-10-18 ~13:00):** resume ✅, widget covers/titles ✅ all sizes, fast Asura scrolling
  "pretty fast, not a big deal", iCloud backup ✅ (8 backups listed), sync ON. Two findings, both fixed:
  - **Widget tap only opened the app** (medium/large should open the tapped title). Now `yomi://open?id=…&type=manga|novel`:
    small = `widgetURL`, medium/large = a `Link` per title; `WidgetReadingItem.kind` (nil in old data → opens Yomi);
    `ContentView.openTitle` → `appRouter.pendingOpen…Id`, the update-notification path. Sim: `simctl openurl` →
    Absolute Regression detail; App Group data has `kind` (novel tagged novel). Widget tap itself unseen.
  - **Resume "glitches for a second"** (pages above loading). Cause: Keiyoushi page URLs are
    `127.0.0.1:<port>/image/<random UUID>` (server `MihonImageProxy.register`), new every launch → `PageShapes` (keyed
    by URL) never matched after a relaunch, so every page above the saved one was a one-screen box that grew; and shapes
    were only saved in `onDisappear` (a kill skips it). Fix: `PageShapes.name(pages, chapterId:)` keys bridge pages as
    `chapterId#index` (`didSet` on `pages` / `nextPreload`); shapes + looks saved on `.background`. Sim can't run
    Keiyoushi → device check: resume an Asura (Keiyoushi) chapter after a kill. Not fixed: `PageLooks` (crop) and the
    Kingfisher disk cache are still keyed by the random URL → Keiyoushi pages re-download after every launch.
  - Perf `--device` twice: "Timed out while enabling automation mode" — phone screen locked; needs it awake + unlocked.
  - ReaderUITests 13/13, 0 warnings. Personal Release reinstalled on the phone (has both fixes).
- **Perf `--device` RAN (phone unlocked, Debug):** launch wall clock **2.48 s** (sim 3.48), strip memory peak **45 MB**,
  Yomi hitch ratio strip **1.3 ms/s**, novel **0**. Gate change: hitch gates now read `Hitch Time Ratio (Yomi)` — the
  scroll-signpost ratio failed at 16.3 avg from ONE 8.3 ms frame in iteration 4 (78 ms/s over a very short scroll
  interval; others 3.4/0/0/0). All gates pass. Personal Release reinstalled after.

### BACKLOG — Support / donate (Martin, 2026-10-18)
A "Support Yomi" spot (More → About?) where people can donate if they want. Before building: check the CURRENT App
Store rules live (guideline 3.1.1 in-app purchase / tips, 3.2.1 / 3.2.2 on donations, and the US external-link
rules) — tips for the developer's own app likely must be In-App Purchase (consumable "tip jar"), external donation
links (Ko-fi, GitHub Sponsors) may be refused. Keep it calm: no nagging, no locked features, one quiet row.

**Rules read live S183 (2026-10-18, developer.apple.com/app-store/review/guidelines, page date not shown):**
- 3.1.1: "Apps may use in-app purchase currencies to enable customers to 'tip' the developer" → a **tip jar of
  consumable In-App Purchases** is the allowed path everywhere.
- 3.1.1(a) / 3.1.3: outside the **United States storefront**, apps "may not include buttons, external links, or other
  calls to action that direct customers to purchasing mechanisms other than in-app purchase". The US storefront is
  exempt. So a Ko-fi / GitHub Sponsors link would be US-only (a storefront check) — not worth it; Martin is in Argentina.
- 3.2.1(vi) / 3.2.2(iv) are about charities and nonprofits, not a developer's own app — they don't apply.
- **Proposed shape (not built, Martin decides):** More → About → one "Support Yomi" row → a sheet with 3 consumable tips
  (e.g. small / medium / large, StoreKit 2 `Product.products(for:)` + `purchase()`), a thank-you line, nothing unlocked,
  never shown unprompted. Needs from Martin: **Paid Apps Agreement + banking/tax in App Store Connect**, the 3 product
  ids + prices, the wording. Testable before that with a local `.storekit` configuration file. Privacy label: purchases
  are handled by Apple (no new data collected by Yomi).

---

## S181 — I: Spanish tail (2026-10-18, simulator)

Martin asleep; told me to keep going on the roadmap without asking. Deploy, CloudKit and phone checks need him, so this
session did the part of "rest of the Spanish tail" I can do alone.

- **Found the tail with a scan, not by hunting screens:** every English-looking Swift literal that is NOT a catalog key
  (438 candidates → ~200 real UI strings; the rest were font/licence names, HTTP headers, sample preview data).
- **Biggest leak: `CalmSectionHeader` / `Section(calm:)` took `String`** — every calm section title (Settings,
  Trackers, Licences, Backup, Safe Mode, reader toolbar, …) was English in S180. Now `LocalizedStringKey`, like the
  other shared components. Same for the Extensions screen's `sectionHeader` (Instaladas / Disponibles) and the
  listen player's `controlButton`.
- **String-built text → `String(localized:)`:** toasts and alerts (reader, page actions, migrate, library), errors
  (`errorDescription` of ZIP/CBR/7z, EPUB, plugin download, Keiyoushi repo/bridge, backup parser, migration), tracker
  login errors, Safe Mode passcode messages, download wait reasons, reading-reminder notification, Updates failure
  reasons, resume button (Start / Continue), novel theme name + contrast warning, translation errors, widget fallback
  line. "No %@ chapters" (English filter word inside) → one key per filter. "Too many tries… %lld seconds" plural.
- **Names shown from data:** novel themes (built-ins localized at `NovelTheme(token)`, id stays English = stored),
  app theme + icon labels and accent names via `dynamic.json`, OCR languages via `Locale.localizedString`.
- **Widget is localized now:** `YomiWidget/Localizable.xcstrings` (4 keys), widget target got
  `SWIFT_EMIT_LOC_STRINGS = YES`; `build-catalog.py` writes both catalogs and also finds XcodeBuildMCP's DerivedData.
- Catalog 835 → **1016 keys, all Spanish** (`scripts/localization/es-7.json`). Kept English on purpose: diagnostic log,
  bug-report mail body, NSError domains, background task names, source data (genres, chapter names, "Episode n").
- Sim (`-AppleLanguages (es)`): Ajustes headers (Leyendo / Biblioteca / …), Apariencia (theme/icon/accent labels),
  Extensiones (Instaladas / Disponibles / "Inglés · Novelas") Spanish. Widget gallery and notifications unseen.
- **Spanish App Store listing drafted:** `APP_STORE_LISTING.md` §1b (subtitle, promo, description, keywords; lengths
  checked; same claims as §1). Open for Martin: Spanish app name or keep the English one.
- **Still English:** anything a plugin/server sends as an error message.
- **Plugins DEPLOYED** by Martin (after `firebase login --reauth`): live `index.json` has Asura Scans + MangaDex
  1.1.0, both live files contain the fixes. Installed copies update via the version check; missing Asura chapters
  appear at each title's next refresh.
- NEXT (needs Martin): CloudKit schema deploy → personal
  build → J (phone check: Spanish incl. widget, Safe Mode, perf `--device`, #203/#209, Translate this novel).

---

## S180 — I: #194 + #69 plugin fixes, Spanish (2026-10-18, simulator + live sites)

Martin picked all three of the rest of I.

- **#194 Asura JS 100-chapter cap — FIXED in `Firebase/public/asurascans.js` 1.1.0 (NOT deployed).** Live API probe:
  `/api/series/{slug}/chapters` sends no `meta` at all and ignores `page`, so the old `has_more` loop always stopped
  after the first 100 (newest first). `limit` > 100 is a 403; `offset` works. Now `limit=100&offset=n` until a short
  page, de-duplicated by id. Run against the live site with the real plugin file (`scripts/plugin-live/run.mjs`, Node +
  curl shim for `SOURCE.fetch`): old 100/100/100 → new **123 / 205 / 215** (Absolute Regression / Absolute Sword Sense /
  Shenwu Tianzun), every id unique; chapter 1 pages still load (22).
- **#69 MangaDex licensed chapters — FIXED in `mangadex.js` 1.1.0 (NOT deployed).** Feed now asks
  `includeExternalUrl=0` and skips `externalUrl` / `pages == 0` rows as a backstop. One Piece: 115 → 62 chapters (the
  53 dropped are MangaPlus links; 19 of them claim `pages: 1` = a placeholder image or a 404). 13 kept chapters sampled
  across the list all open (17–53 pages). Also lifted a second cap: `offset > 2000` stopped long multi-language feeds →
  `limit=500`, stop at offset + limit > 10000 (MangaDex's max); a 1,166-entry feed comes back whole in 3 requests.
  (MangaDex used here only because the bug is in the MangaDex plugin.)
- Both bumped to 1.1.0 in `index.json`, hashes refreshed with `catalog-hashes.py` (the predeploy hook redoes it).
  Originals in `Firebase/plugin-backups-S180/`. **Martin deploys:** `cd ~/Desktop/Projects/Yomi/Firebase && firebase
  deploy --only hosting:plugins`. Installed copies update through the normal version check; the missing Asura chapters
  appear at the next refresh of each title.
- **Spanish (neutral Latin American, Martin's pick — tú, no voseo).** `Yomi/Localizable.xcstrings` (835 keys, all
  Spanish) + `Yomi/InfoPlist.xcstrings` (3 permission prompts); `es` in knownRegions. The catalog is **generated**:
  `scripts/localization/build-catalog.py` reads the compiler's `.stringsdata` (build first) + `es-*.json` +
  `plurals.json` (one/other for en + es) + `dynamic.json` (keys looked up at run time); it refuses a translation whose
  format specifiers differ from its key (caught two real bugs while writing it). Code changes so text reaches the
  catalog: the English `chapter\(n == 1 ? "" : "s")` trick (25 sites) → plural keys; shared components take
  `LocalizedStringKey` (YomiEmptyState, PillButton, DeleteSwipe, MoreRow, LibraryTab/SectionHeader, StorageRow,
  settings/backup/browse/insights helpers, ReaderSegmentedRow) — pass dynamic text as `"\(value)"`; display enums and
  `Notation` (Chapter, status words, date buckets) use `String(localized:)`; raw-value enums shown via
  `LocalizedStringKey(x.rawValue)` (raw values are stored — never change them). Sim (`-AppleLanguages (es)`):
  Library, Historial, Novedades, Explorar, Más, Ajustes, manga reader + its settings sheet all Spanish; long rows fit.
- **Not translated yet:** text built as `String` deeper in (error messages from services/plugins, alerts with String
  vars, notifications other than new-chapter, widget, onboarding sub-sheets, novel reader panel except spacing rows),
  App Store listing in Spanish. Source data (genres, chapter names) stays as the source sends it.
- NEXT: Martin deploys the plugins + checks Spanish on the phone (part of J) → rest of the Spanish tail → CloudKit
  schema deploy + personal build + J.

---

## S179 — I: Safe Mode, perf gates, solid/huge CBR (2026-10-17, simulator)

Martin picked lockable SFW mode + perf gates + CBR edge cases from the rest of I.

- **Safe Mode** (`Core/SafeMode.swift`, `Features/More/SafeModeView.swift`; Settings → Privacy → Safe Mode, off by
  default). Hides sources their repository marks 18+ (Keiyoushi `contentWarning` 3, JS/LNReader `isNSFW`) and titles
  tagged Adult/Hentai/Smut/Ecchi/Mature/Pornographic/Erotica/18+/R-18/… (exact tag match, so "theme:primarily_adult_cast"
  stays) — in Library (counts, category counts, source filter, widget), Continue shelf, History, Updates (feed AND
  refresh: hidden titles aren't checked, so no notification names them), Browse sources/pinned/last used, Search all
  sources, browse results with genres, Extensions (installed + available), Migrate (sources and targets), reading
  reminder. Mixed sources stay (Keiyoushi index today: 561 safe / **486 mixed** — MangaFire, MangaDex, Bato… / 387
  18+); "Hide mixed sources" option hides them too. A title page whose genres arrive adult (mixed sites tag late) is
  covered: "Hidden by Safe Mode" + Go Back, drawn over the floating bar so ⋯ (website) is covered too. The 18+ switch in
  Repositories is disabled while Safe Mode is on (`allowsAdultExtensions`).
  **Lock:** a Yomi 4-digit passcode (not Face ID/iPhone passcode — a child knows those), SHA-256 in the keychain;
  turning Safe Mode off or showing mixed sources asks for it; stricter changes never ask. 5 wrong → 1 minute wait.
  Forgot it → reinstall (a fresh install clears a passcode left in the keychain, `clearStalePasscode`). Honest note on
  screen: untagged adult titles can still appear; Screen Time for more.
  **Verified (sim, on a copy of the S152 library):** 157 → 156 with Safe Mode ("Evolution", tagged Mature, gone; Action
  116 → 115); tagged a second title Smut in the DB → 155; relaunch keeps it on + locked; wrong code refused, right code
  works; Hide-mixed off while locked snaps back + asks; cover appears on an open page when Safe Mode turns on, Go Back
  works. Test tags reverted, Safe Mode left off. NOT checked: a real 18+ source in Browse (none installed in the sim),
  device. **Tooling:** XcodeBuildMCP/control TAPS on this screen's first switch don't flip it ON→OFF (a drag does) — first
  binding version looked dead because of that; switched to `$settings` bindings + onChange anyway.
- **Perf gates** (RESEARCH §25.10 #11): `YomiUITests/PerfUITests.swift` (added to the target in project.pbxproj — the UI
  test group is NOT a synced folder) + `scripts/perf-gates.sh` / `perf-gates.json`. Tests measure; the script reads the
  averages from the .xcresult (`xcresulttool get test-results metrics`) and fails over a limit. New fixture
  `-yomiReaderFixture manga` = Webtoon reader on 8 generated 900×16000 pages in hidden `Documents/Local/.perf-fixture`;
  DEBUG marker `reader.mangaPage` ("page/pages"). **`XCTHitchMetric` (iOS 26) records NOTHING in the simulator**, and the
  scroll signpost metric only gives scroll duration there → simulator gates = launch (1.41–1.44 s, limit 2.5) + long-strip
  memory peak (64–81 MB, limit 300 MB; `footprint` showed 105 MB/peak 168 MB); hitch gates (5 ms/s) are `deviceOnly`,
  run with `--device <id>` — their metric name "Hitch Time Ratio" is a guess until the first device run (the script
  says "not measured" if wrong). Script end to end: passed.
- **CBR solid/huge:** Unrar.swift's `extract(entry)` reopens and skips to each page; in a SOLID RAR skipping decodes, so
  a chapter was quadratic. New `Core/RarExtract.swift` walks once (Cunrar C API, data callback → file); `ComicArchive.write`
  uses it for RAR. Mac (`scripts/rar-extract-tests/run.sh`, same file compiled): 150 pages/63 MB — RAR5 solid **35.9 s →
  0.53 s**, RAR4 solid 38.7 s → 0.59 s, non-solid 0.55 → 0.52 s, all byte-identical to Unrar.swift; password →
  `.encrypted`; missing name throws. Huge: a real 796 MB RAR5 (1 GB unpacked, one 734 MB file) in 5.9 s, peak RSS 64 MB.
  Sim app: RAR5 + RAR4 solid chapters 150/150 byte-identical in Caches, each unpacked in ~1 s; password chapter shows
  "password-protected". Test archives made with RARLAB rar 7.23 (RAR5) / 6.24 (`-ma4`, RAR 7 dropped RAR4 writing),
  kept in scratch only. Test title + caches removed (157 manga).
- UI tests: ReaderUITests 13/13, PerfUITests 3/3. Builds 0 warnings (Yomi + YomiWidget).
- NEXT: rest of I (Spanish, #194 Asura 100-chapter cap, #69) → CloudKit schema deploy + personal build + J (add: Safe
  Mode on the phone, perf gates `--device` once).

---

## S178 — I: accessibility baseline + reader night theme (2026-10-17, simulator)

- **Reduce Motion** (`Core/Motion.swift`): `withMotion` / `.motion(_:value:)` / `Motion.slide(edge)` / `Motion.pop`
  replace every `withAnimation`, `.animation(_:value:)`, slide and scale transition in the app (76 call sites, 11
  files): with Reduce Motion on, changes happen at once and slides become fades — animated page turns, overlay
  slides, banners, selection toolbars, scroll-to animations, the cover shimmer. Long-strip tap-zone scrolling jumps
  (`ReaderPageActions`); the novel reader's JS uses `prefers-reduced-motion` for its smooth scrolls. Read when the
  change happens, so the setting applies to the next animation. **New code: use these helpers, not withAnimation.**
- **Increase Contrast:** `CanvasColors.increasedContrast()` — secondary text at 82 % and dividers at 45 % of the
  primary ink; `canvasColors(for:contrast:)` from ContentView/Onboarding (`\.colorSchemeContrast`). Novel reader panel:
  unselected tab/segment labels 0.6–0.75 → 0.92, swatch rings stronger. System colours and Liquid Glass adapt on
  their own (glass turned more opaque in the sim).
- **Reader night theme** (RESEARCH §25.3 #9): Settings → Novels → **Night** (theme, "When the iPhone is dark" / "At set
  times" with From/Until, default 21:00–07:00) and the reader's Look tab → **At night** menu. While night applies
  the reader shows that theme; choosing a theme in Look at night changes the night theme (what you pick is what you
  see). Checked every 30 s + on foreground. Off by default. No health claims anywhere.
- Verified (simulator): Void night theme appears ~30 s after switching the sim to dark (light text on #0D0F17);
  Increase Contrast via `simctl ui increase_contrast` darkens the panel labels; UI tests 13/13; build 0 warnings
  (Yomi + YomiWidget). NOT checked: Reduce Motion on screen (no simctl switch — code path only), the schedule mode
  on screen, the manga reader's own background "Automatic" (unchanged, already follows dark mode).
- NEXT: rest of I (Spanish, lockable SFW mode, perf gates in UI tests, #194 Asura 100-chapter cap, CBR solid/huge)
  → CloudKit schema deploy + personal build + J.

---

## S177 — I: ArcReader novel leftovers (2026-10-17, simulator)

Martin picked "ArcReader novel leftovers: term replacement, translate, letter spacing, themes" from group I.
**Letter spacing was already done (S136: Tight / Normal / Loose)** — nothing to build.

- **Themes** (`Features/Reader/NovelThemes.swift`): three more built-ins from ArcReader's list — **Sage** (#E4ECDF /
  #1F2B1C, contrast 12.2:1), **E-ink** (#EAEAE4 / #141414, 15.3:1), **Void** (#0D0F17 / #C9CEDB, 12.1:1) — and **your
  own themes**: Look tab → **New** (name, background, text colour, live sample, contrast readout, warning under 4.5:1);
  touch and hold one of yours → Edit / Delete. Look row now scrolls; each swatch shows "Aa" in its text colour.
  `NovelTheme` is a struct now (was an enum); `AppSettings.novelCustomThemes` (JSON, device-only).
- **Term replacement** (`Core/TermReplacer.swift`, v30 `term_replacement`, `TermReplacementQueries`,
  `TermReplacementViews.swift`): select text → **Replace…** (new item in the selection menu, next to Listen from Here)
  → editor prefilled with the selection; Reading tab → **Replacements** lists this novel's + all-novel rules (tap =
  edit, swipe = delete, + = add). Options: This novel / All novels, Match case (on). Whole words for spaced scripts;
  CJK/Thai terms match anywhere; longest term first, one pass (no chaining); tags/attributes/scripts untouched;
  empty replacement removes the term (translator notes). Applied in `NovelContent.html`, so reader AND read-aloud get
  it; downloads on disk unchanged. A rule change reloads the open chapter at the same spot. In backups. Tests:
  `scripts/term-replace-tests/run.sh` 18/18.
- **Translate** (`NovelTranslation.swift`): Reading tab → **Translate this novel** (remembered per novel) + **Into**
  (iPhone language or any language Apple's Translation supports). Each chapter is translated as it enters the page
  (infinite scroll too), on the iPhone, after term replacements; the system asks to download the languages first.
  Block by block, line by line (`<br>` kept); italics/links inside a paragraph are lost in the translation. Off =
  original text back. Status chip "Translating…" / error messages at the top. Read-aloud still reads the ORIGINAL
  text (and its highlight won't find it in a translated page) — not handled.
- **Bug found on the way:** `NovelReaderController.evaluate` returned nil before the page finished loading, so the
  first chapter's text query (translation) got nothing. Queries now wait for the page (`readyWaiters`).
- Verified in the simulator (iPhone 17 Pro, iOS 26.3): Sage + New theme saved/listed; Replacements add → chapter
  reloads with the replacement; selection menu Replace… prefilled; translate on → page swap (DEBUG `-yomiFakeTranslate`
  upper-cases the text, because **Translation is "not supported on simulated devices"** — the real session was
  reached and showed that message); off → original. UI tests 13/13; build 0 warnings (Yomi + YomiWidget).
- NOT checked: real translation (needs the phone: model download prompt, speed on a long chapter, pages mode with
  translated text), the colour pickers (tool can't drive them), backup round-trip of rules, VoiceOver.
- NEXT: rest of I (Martin picks) → CloudKit schema deploy + personal build + J.

---

## S176 — better voices: research (2026-10-17, Mac only, no app code)

- Full write-up: **RESEARCH §28**. Samples (same light-novel paragraph): `../reports/S176-voices/` — 1–3 Kokoro
  (af_heart, am_michael, bf_emma), 4 PocketTTS (alba), 5 Apple Samantha (default, NOT Premium).
- **Only clean path = Kokoro-82M via FluidAudio** (Swift/Core ML, Apache-2.0 code + weights, no GPL, ~330 MB optional
  download, ~1 GB RAM while speaking). **sherpa-onnx is out**: every TTS build links espeak-ng (GPL-3.0). Piper is GPL
  now; Supertonic upstream archived + OpenRAIL.
- All 5 samples transcribe word-perfect (Parakeet ASR) → the choice is about sound, which only Martin can judge.
- **Martin decides:** listen to 1–4, then the same paragraph in Yomi on the phone with an iOS **Premium** voice
  (Settings → Accessibility → Read & Speak → Voices). Kokoro clearly better → build it (plan in §28.3); not clearly
  better → keep Apple voices, close L4 "better voices", go to I.
- NOT checked: Kokoro on a physical iPhone (speed, heat, background synthesis), Premium voice side by side.
- **Part 2 — decision:** Martin listened: **Kokoro clearly better than Premium**. Before building, found FluidAudio's
  Core ML Kokoro still crashes (uncatchable libBNNS SIGSEGV) on iPhone 17 + iOS 26.6 (#844) and iOS 27.0 (#889) —
  §28 corrected. Options given: ONNX Runtime CPU route (stable evidence, ~2 sessions, +30–50 MB), Core ML experimental,
  or wait. **Martin: wait for Apple** — re-check after iOS 27.2 (FluidAudio #889 asks testers to try 27.2; watch
  whether `isBnnsCrashProneOS` stops flagging it). ONNX route stays the fallback plan. NEXT: I (ROADMAP S171).

---

## S175 — L4 CB7/7z archives (2026-10-17, simulator)

- **Library choice (checked live):** SWCompression 4.9.1 (pure Swift, MIT) — `SevenZipContainer.open(container: Data)`
  takes the whole archive in memory and decodes every entry: no for 100 MB+ CB7s on a phone. **PLzmaSDK 1.6.1** (MIT,
  wraps Igor Pavlov's **LZMA SDK 26.01**, public domain — scanned: no GPL/LGPL text) reads from a file path and
  extracts chosen items. Its Package.swift uses `unsafeFlags`; SwiftPM **refuses that for a version pin** ("contains
  unsafe build flags", tried) and **allows it for a revision pin** → Xcode package pinned to `f449bc3` (= tag 1.6.1).
- **Methods (tested on the Mac against archives written by py7zr, an independent writer):** Copy, LZMA, LZMA2 (7-Zip's
  default), PPMd → byte-identical; AES with the password ok (incl. encrypted names); **BZip2 and Deflate fail** (not in
  this LZMA SDK build); Zstandard fails (not standard 7-Zip). Yomi has no password UI (same as CBR).
- **Solid archives:** the LZMA SDK decodes the whole solid block on EVERY extract call — 150 real pages / 128 MB:
  one call per page = 26.6 s for the first 30 pages; one call for all = **1.4 s** (Mac). So `ComicArchive.write(_:)`
  unpacks a chapter in one pass (ZIP/RAR keep reading file by file); `LocalLibrary.pageURLs` uses it.
- **Code:** `Core/ComicArchive.swift` (`is7z` by magic bytes, `.sevenZip` backing, `is7zHeaderEncrypted` = packed header
  with AES coder 06F10701 → "password-protected" instead of "damaged", `unsupported7z` message names BZip2/Deflate and
  suggests LZMA2/CBZ); `LocalLibrary` (cb7/7z are normal archives now; a failed unpack removes its Caches folder);
  Info.plist `com.yomi.cb7` type + document type; picker takes cb7 + `org.7-zip.7-zip-archive`; format lists in Browse,
  Local Files and the repository help mention CB7. **Reader:** a local chapter with no pages now shows the archive's
  own error (was "No pages found." for every case, CBR included). Licences: `licence-plzmasdk.txt` + row.
- **Verified (sim):** "CB7 Test" series in `Documents/Local` (5 chapters): scan found it, cover from chapter 1; LZMA2 +
  PPMd chapters 8/8 pages, byte-identical in Caches; AES (hidden names) → "This archive is password-protected — Yomi
  can't open it."; BZip2 → the 7z method message; 150-page 128 MB LZMA2 → 1/150, all 150 byte-identical, unpack
  ~3.2 s (folder created → stamp; Debug build in the sim). UI tests 13/13, Swift 0 warnings. Test title, files and
  caches removed again (157 manga).
- **Linker warnings → fixed by vendoring (Martin's pick, same session).** Clean builds had printed 59 `ld: warning:
  could not associate debug note to atom …` — every one a constant from `src/Asm/arm64/LzmaDecOpt.S`. That file is
  dead code: nothing defines `Z7_LZMA_DEC_OPT`, so `LzmaDec.c` always builds its own `static` C decoder; the linker
  strips the asm but its debug notes stay. **PLzmaSDK is now vendored in `Vendor/PLzmaSDK`** (commit f449bc3 =
  1.6.1; `src/`, `swift/`, `libplzma.h/.hpp`, resources, LICENSE; `src/Asm/` removed; test targets dropped; see its
  `VENDORED.md`), referenced as a local package. As a local package Xcode shows its compiler warnings: 2×
  deprecated `readdir_r` in `plzma_path*.cpp` (encoder-side directory listing) → `-Wno-deprecated-declarations` on the
  C/C++ target only; code unchanged. **Result: clean Debug AND Release builds 0 warnings** (were 59); YomiWidget 0.
  Re-checked: Mac tool against the vendored copy — Copy/LZMA/LZMA2/PPMd/AES (both kinds) 8/8 byte-identical; sim app —
  LZMA2 + PPMd chapters 8/8 byte-identical, password message, and the failed chapter left no empty Caches folder.
  `scripts/build-licenses.sh` reads PLzmaSDK from `Vendor/` (output unchanged).
- NOT checked: the device (phone CPU will be slower than the sim's ~3 s for 128 MB), a CB7 made by real 7-Zip (py7zr
  only), Import through the Files picker / "Open in Yomi" with a .cb7 (types declared, not exercised), the empty-folder
  cleanup on screen (compile only), memory on a phone during a large unpack (files are written by stream, not RAM).
- NEXT: better voices (research first: size, licence, quality vs iOS Premium voices) → I (ROADMAP S171).

---

## S174 — L4 streak repair (2026-10-17, simulator)

- **What and why:** RESEARCH §25.10 #9 — Silverman & Barasch 2023 (J. Consumer Research 49(6)): after a broken streak
  people keep going far more often when they can repair it; keep it quiet. Insights had a streak, no repair.
- **Rules** (`Core/ReadingStreak.swift`, pure Foundation): streak = days in a row with a chapter read, ending today or
  yesterday (unchanged). A break can be repaired when it is **1–2 missed days** right before the current run (or before
  today/yesterday), the streak it ended was **≥ 2 days**, and **no day was repaired in the 7 days before the break**
  (one repair a week). Repaired days count as streak days. Tests: `scripts/streak-tests/run.sh` (12/12).
- **UI (Insights only — no notification, no badge):** under the numbers, "You didn't read on Friday, which ended a
  3-day streak. You can repair it once a week." + a small bordered **Repair Streak** button; after it the streak
  updates and the row goes away. Repaired days are outlined in the Activity heatmap, with a caption "Outlined days were
  repaired to keep your streak." while one is visible.
- **Storage:** `AppSettings.streakRepairedDays` ("yyyy-MM-dd"), device-only — not in Yomi's backups (they don't carry
  settings) or sync. Fine for a cosmetic number; move to the DB if streaks ever sync.
- **Verified (sim, the sim's own data):** reading on Oct 13–15, nothing Oct 16 or yet on the 17th → Insights showed 0
  + the offer for Friday (a 3-day streak) → Repair → streak 4, offer gone, Oct 16 outlined, stored as "2026-10-16"
  (read back through cfprefsd); after a relaunch still 4 + the caption. The repaired day was deleted again afterwards.
  Build 0 warnings (Yomi + YomiWidget).
- NOT checked: the device, VoiceOver reading of the row, a week-limit case on screen (tests only).
- NEXT: CB7/7z archives → better voices (research first) → I (ROADMAP S171). (CB7 done S175.)

---

## S173 — L3d text on page / OCR (2026-10-16, simulator)

- **Text on Page** (new `Features/Reader/PageText.swift`): long press a manga page → *Text on Page*, or the new reader
  toolbar button *Text on page* (`ReaderToolbarItem.pageText`, off by default — add it in the toolbar editor). Vision
  `RecognizeTextRequest` (accurate) on the device; lines joined into blocks (≈ one bubble) and blocks put in reading
  order — see "Japanese raw test" below for the rules (`PageTextLayout.swift`). Sheet: **Text** tab (selectable blocks, Copy per block)
  · **Page** tab (the page with each block outlined, tap one = copy) · Copy All (closes, toast "Text copied") ·
  Translate (Apple's `translationPresentation` sheet) · globe menu = language (`pageTextLanguage`, default Automatic;
  15 languages).
- **Tall pages are read in slices** (`PageTextRecognizer.tiles`: 1.5× the width tall, a fifth overlapping, a line in an
  overlap kept once). Without it the 900 × 16,000 px Asura page gave **"No Text Found"** — Vision scales the whole image
  down. The Page tab draws the page in ≤ 4,000 px slices (#190: one image > 4,096 px renders black on the phone).
- **VisionKit Live Text was tried first and dropped**: on the same page it highlighted nothing in the sim (same
  scaling problem, or unsupported in the sim — not separated). Our own outlines work on any page and look the same.
- **Translate is NOT on-device by default**: Apple's sheet says on first use the text goes to Apple unless the user
  chose to always translate offline in Settings. Reading the page (OCR) never leaves the phone.
- **Verified (sim):** Absolute Sword Sense ch. 203 page 2 (Asura, 900 × 16,000): 14 blocks, every bubble whole and in
  order (Copy All → `simctl pbpaste` matched the page); single-block Copy → only that bubble; Page tab outlines sit on
  the bubbles at the top and after scrolling past slice joins; tap outline → clipboard = that bubble; Translate opens
  Apple's sheet (Continue not pressed). Build 0 warnings (Yomi + YomiWidget), UI tests 13/13.
- **Japanese raw test (Martin asked, same session).** Source: Keiyoushi **MangaFire `ja`** (source id
  524110931382140732) through the Mac extension server (`Tools/keiyoushi-poc/harness/run-server.sh`, POST /dalvik),
  One Piece ch. 1, 12 pages (760 × 1200) → a folder in the sim's `Documents/Local` → Browse → Local Files. No raw source
  exists in Yomi's own catalog, MangaDex is off-limits, the sim has no JVM, and MangaFire has no Korean.
  **First result was wrong:** top row = page header + sound effect + two bubbles in ONE block, read backwards. Cause:
  sizes were compared in normalized units (width vs height of a 760 × 1200 page differ 1.6×), so columns weren't seen
  as columns. **Rewrite (`PageTextLayout.swift`, no UIKit, tested on the Mac by `scripts/page-text-tests/run.sh`):**
  pixels throughout; glyph size = a column's height per character (Vision's boxes hug glyphs — one bubble's columns
  measured 17 and 30 px wide, both 18 px per character); two lines join only when they run the same way, glyph sizes
  within 1.6×, and they sit side by side (columns, gap < 0.8 glyph, overlapping 30 % in height) or stacked (lines, gap
  < 0.9 line height, overlapping in width); rows grouped explicitly, Japanese right→left; furigana dropped (kana-only
  columns under ¾ of the page's usual glyph size); lines with no letter of the page's main script dropped (Thai/Hangul
  read from artwork on Japanese pages, Arabic digits/Hangul on English ones; Latin stays on Japanese pages).
  Automatic = right→left when kana > 20 % of the text or most Han lines are vertical; Korean/English left→right.
  **Result:** all 12 pages read bubble by bubble in order (p. 4 = 11 blocks exactly as the page reads, p. 5 = 13); the
  English Asura pages unchanged; 10/10 fixed cases (box numbers from the real pages — no images in the public repo).
  Sim: p. 4 Text tab = Mac output, Page tab outlines each vertical bubble, tap → clipboard = that bubble. Test title
  removed again (library 157 manga, local folder + DB rows deleted, Mac server stopped, downloads deleted).
- **Known OCR limits (Vision, not fixable here):** small-print errors on low-res scans (カナヅチ → カナッチ, a
  furigana-crowded caption garbled); 2× upscaling didn't help (lost a line); Han-looking junk from artwork stays
  (confidence is only 0.3 / 0.5 / 1 and real lines get 0.3); sound effects come out as their own blocks.
- NOT checked: a Korean raw page (no source reachable from the Mac set-up — synthetic case only), Chinese, the toolbar
  button on screen (compile only), the language menu re-run, the device.
- Xcode updated itself to 27.1 mid-session: stale explicit modules ("malformed or corrupted precompiled file") and
  "CoreSimulator is out of date" → delete `DerivedData/SDKExplicitPrecompiledModules` + `ModuleCache.noindex`, run
  `xcodebuild -runFirstLaunch` (worked without sudo).
- NEXT: L4 streak repair → CB7 → better voices (research first) → I (ROADMAP S171). (L4 streak repair done S174.)

---

## S172 — L3c reader extras (2026-10-16, simulator)

What the four items mean was checked on Tachimanga's changelog (tachimanga.app/docs/changelogs.html), not guessed:
v4.14 "invert double pages", v3.1 "disable pinch to zoom", v4.12 "strict scale" = *"restricts zoom to a fixed range
with no bounce"* + "reader scroll indicator" + "disable pinch when long-press scrolling", v5.1 "Customizable Reader
Toolbar" (+ v5.2 quick actions "Mark Previous Chapter as Read", "Delete Download").

- **Swap the two pages** (`doublePageInvert`, off): the pair in a two-page spread swaps sides; reading order and
  `currentPage` unchanged. Reader sheet (under Cover on its own) + Manga & Webtoon.
- **Pinch to zoom** (`readerPinchZoom`, on): off = no pinch in any manga mode (`MangaPageView` gesture, `ReaderZoom(pinchEnabled:)`).
  Pinch is also off while "scroll while held" is scrolling (long strip). **Strict scale: no setting** — Yomi's zoom was
  already clamped 1×–4× with no bounce everywhere, i.e. always "strict".
- **Scroll bar** (`readerScrollIndicator`, off): `showsIndicators` of the long-strip and continuous scroll views.
- **Custom reader toolbar** (`readerToolbarItems`, new `Features/Reader/ReaderToolbar.swift`): the bottom bar shows the
  picked buttons in order — previous/next chapter (default = the pre-S172 bar), bookmark chapter, mark previous as read,
  reading mode (menu), two-page spreads (menu), crop borders (flips the paged or strip setting for the mode open), share
  page, comments. ≤ 3 sit next to the page count, more get their own row. A button that doesn't apply is hidden at that
  moment (spreads outside right-to-left/left-to-right, comments without a discussion URL, share before a page loads).
  Editor = reader sheet → Toolbar and More → Settings → Manga & Webtoon → Reader → Toolbar (`ReaderToolbarEditor`).
  Mark previous only writes UNREAD chapters (`setReadBatch` stamps `readAt` — an early version overwrote 17 real read
  dates in the sim, caught + restored from `phone-backups/S171-sim-before-L1`); confirm dialog counts unread ones, none →
  "Earlier chapters are already read". Bookmark/mark-read changes are kept in the reader (`bookmarkOverrides`,
  `markedReadIds`) so the chapter list shows them. Delete Download (v5.2) not added.
- **Verified (sim):** Spread Test P3|P2 → swap → P2|P3; toolbar editor add (7 → row of its own), the row added while
  editing had no delete/drag handles → fixed (`.id(shown.count)`), live; bookmark → `isBookmarked = 1` in the DB; crop
  button crops live; share → share sheet; 30 Years (Asura) chapter 19 with 16 + 18 unread → dialog "2 unread", only
  those two written, again → "already read"; Webtoon via the toolbar menu → spreads button hidden. Settings screens show
  every new row. Build 0 warnings (Yomi + YomiWidget), UI tests 13/13. Sim DB rows + reader prefs restored after.
- NOT checked: the scroll bar itself on screen (the setting is wired; a screen recording couldn't separate the thin bar
  from the artwork), pinch on/off (no pinch in the sim tooling), VoiceOver labels of the menus, the device.

---

## S171 — L1 library load time · L2 novel reader vs LNReader (2026-10-16, simulator, no app code changed)

- **L1 library load time — measured, no fix needed.** Method: the phone's own DB (`phone-backups/S166-after-…`, 171
  manga / 24,043 chapters / 4 novels / 2,806 novel chapters, migrated v27→v28 by a warm-up launch) swapped into the sim,
  **Release** build, `xctrace record --template 'Time Profiler' --instrument 'Points of Interest' --launch`, three cold
  launches. `LoadLibrary` signpost: **199 / 212 / 149 ms**. The SQL itself is a small part: cold `sqlite3` timing on the
  same file — library 3 ms, manga unread counts 50 ms (uses `idx_chapter_unread` + the covering excluded-scanlator
  index), novel unread counts 3 ms; the rest is record decoding, the widget write and launch-time waiting (the work runs
  in `Task.detached`, not on the main thread). `potential-hangs`: none in any run. The sim's own DB was restored after
  (`phone-backups/S171-sim-before-L1`). NOT measured: the phone itself (an M-series Mac sim is faster — re-record during
  J if the library ever feels slow to appear).
- **L2 novel reader vs the LNReader checklist (report §"Novel reader") — all three already match:**
  1. Style set once per settings change: `NovelReaderController.setStyle` skips an unchanged stylesheet, the page swaps
     one `<style>` inside `relayout` (keeps the reading position). LNReader sets CSS variables instead — same one
     restyle per change, nothing to gain.
  2. Progress saved only when scrolling stops: `progress` is posted 400 ms after the last scroll event.
  3. Pages mode uses CSS columns (`column-width: 100vw − 2m`, S136), like `pageReader.css`.
  → No port. L2 closed.

**Martin's answers (S171): he wants ALL of L3 and L4.** L3: refresh covers/metadata during updates (+ hourly detail
auto-refresh) · extension details page (website without installing, per-extension settings from the Extensions list) ·
reader extras (double-page invert, strict scale / scroll indicator, custom reader toolbar) · copy text / OCR (Vision,
on-device). L4: **"better voices"** (his words — the goal is voices that sound better, sherpa-onnx is one way, compare
with iOS Premium/Enhanced voices first) · streak repair · CB7/7z.
Order (small + daily-use first): L3a refresh metadata → L3b extension details → L3c reader extras → L3d OCR → L4 streak
repair → CB7 → better voices (research first: size, licence, quality vs iOS Premium voices) → I → CloudKit schema
deploy + personal build + J.


**L3a done (same session, simulator) — covers + details during updates, and opening a title at most once an hour:**
- **Update rules → "Refreshing"** (new section): *Covers and details* (`updateRefreshMetadata`, default ON — Mihon's is
  off; novels/Mangayomi cost nothing extra) and *Refresh a title at most once an hour* (`detailRefreshHourly`, default
  ON; before, every open hit the source).
- **Refresh:** novels (Yomi + LNReader plugins) take cover/summary/author/status/genres from the `parseNovel` they
  already did; Keiyoushi asks `details` first (one more JVM request, failure not fatal); Mangayomi plugins use
  `lastMangayomiMeta`. The source's value replaces the saved one wherever it gives one (the detail screens still only
  fill gaps); custom covers still win on screen. **Not covered: Yomi's own manga plugins (Asura, Comick, …) — they have
  no details function**, their covers/summaries come from browse results only. Adding a `getMangaDetails` to them =
  plugin change + Firebase deploy (later, if Martin wants it).
- **v29 `lastCheckedAt`** on manga/novel (device-local, raw SQL like v27, not in the model or sync), stamped by every
  successful refresh check (`recordCheck`) and every successful source fetch on a detail screen. Detail screens skip
  the source when the title is in the library, has saved chapters on screen and was checked < 1 h ago; pull to refresh,
  the Cloudflare retry and a Keiyoushi install always force. The skip still loads the bridge (reader needs it) and
  re-reads the saved chapters (download deletes show).
- **Verified (sim):** Absolute Regression (Asura) — first open = 1 request + stamp, second open = 0 requests (Pulse
  log), pull to refresh = 1 request + new stamp. Two novels planted with summary "STALE S171" + a fake cover → Updates
  refresh restored both from the source (A Regressor's Tale even got the source's NEW cover, .webp → .png); the not-due
  novel was skipped as before. Settings screen shows the section. Build 0 warnings; UI tests 13/13.
- NOT checked: Keiyoushi (needs the iPhone build), Mangayomi plugins, the device.

**L3b done (same session, simulator) — extension details page:** tap any row in Browse → Extensions (installed or not)
→ `ExtensionDetailView` (new file, `Features/More/`): icon, version, kind, 18+, About (catalog description), Language,
Repository, Website; Add (language picker for multi-language groups / Keiyoushi language sheet) · Update to x ·
Languages · Go Back to Version · Remove (confirm, then back). The page re-reads the managers each render, so Add/Remove
show at once. **Website** opens in `CFBypassView(isWebsite: true)` — Yomi's web view, same cookies as the plugins
(like Mihon's WebView), title = host, Done always on. URL from the new `PluginCatalogEntry.site` (Yomi catalog `site`,
LNReader `site`, Mangayomi `baseUrl`) or a Keiyoushi source's `homeURL` (one button when the sources share a site, else
one per source). **Keiyoushi sources** listed (turned-on languages first, others "· Off"); a turned-on source opens
`KeiyoushiSourceSettingsView` = per-extension settings from the Extensions list. Yomi/LNReader plugins have no settings
mechanism — nothing to show. Mihon's changelog/readme: no repository format carries one, skipped.
- **Firebase `public/index.json` now has `site` for all 16 Yomi plugins** (hashes unchanged; backup
  `Firebase/index.json.before-S171`) — **DEPLOYED 2026-10-16 by Martin**; live check: 16/16 entries have `site` and
  `sha256`.
- **Verified (sim):** Asura (installed Yomi plugin) page; Keiyoushi WuxiaWorld (not installed) → Website opened
  wuxiaworld.site, Cloudflare passed in the same view; LNReader Arcane Translations → Website button + row, Add → "Added"
  + Remove appear live, Remove → confirm → back to the list with Add again. Build 0 warnings, UI tests 13/13.
- NOT checked: Keiyoushi source settings from the page (needs the JVM = iPhone build), Update/Go Back on the page (no
  update available on the sim), the device. The sim now also has LNReader's repository (added through the app).

---

## S170 — catch-up audit + three decisions (2026-10-15, no app code changed)

Martin asked: check that everything we said we'd do was done, and research + decide the open questions.
**Audit:** every ✅ in THE PLAN A–F (S161–S169) exists in code (`ReaderPagePrefetcher`, `TallPageSplitter`,
`PageListCache`, `FetchInterval`, v28 migration, `ReaderPageActions`, `PageBorders`/`PageAnalysis`/`ReaderPageLook`,
`KeiyoushiFilter`, `KeiyoushiSourceSettingsView`, `ComicArchive`); the three ported suites pass today (chapter
recognition 103, fetch interval 54, reader pages 26/26); `main` clean and = `origin/main`.
**Promised but dropped (not in THE PLAN, now added as group L below):**
- S159 leftovers: library query time with Martin's 148-title library (signpost `LoadLibrary` exists, never recorded);
  novel reader vs the LNReader checklist (report §"Novel reader") — never read through.
- TACHIMANGA_PARITY "Missing" lines THE PLAN skipped: refresh metadata + covers during updates (v4.18); auto-refresh a
  detail screen once an hour (v3.4); extension details page + open a source's website without installing (v2.1, v4.14);
  per-extension settings reachable from the Extensions list (S157: only from the source's Browse screen); double-page
  "invert"; strict scale / scroll indicator; copy text / OCR; custom reader toolbar; tracker items (v5.0).
- CB7/7z archives (S156 "not done"); neural voices (sherpa-onnx, S145 backlog); streak repair (§25.10 #9).
- Doc drift for K: the ArcReader backlog (S126) still shows [ ] for things shipped since (bookmarks, Pages mode,
  infinite scroll, swipe, voice picker, sentence highlight, auto-advance, mix with other audio); CLAUDE.md says
  "CloudKit Production `Novel.genres` exists" while ROADMAP S156 says it was NOT checked.
- **Found:** TestFlight friends see AniList, Shikimori and Bangumi in More → Trackers but none can log in — their
  client ids in `AppSecrets.swift` are empty (only MAL is set). See decision 3.

**Decisions (Martin delegated them):**
1. **MPL (`PageBorders.swift`) — KEEP it, comply.** The Yomi repo is PUBLIC (checked: `gh repo view`), so the file's
   source is already reachable; MPL §3.2 only asks that recipients of the app are told where. That is exactly what we
   already do for the patched M-Extension-Server (MPL too, licences row links its patch in this repo) — a clean-room
   rewrite would not remove the MPL from the app. To do (K): licences row "image-decoder (borders) — MPL-2.0, ported
   to Swift by Yomi" with the MPL text + a link to `Yomi/Features/Reader/PageBorders.swift` on GitHub; a row "Mihon —
   Apache-2.0" (ChapterRecognition, FetchInterval, PageBackground) with the Apache text (Mihon has no NOTICE file —
   checked). **Constraint: if the repo ever goes private, those MPL files must be hosted somewhere public first.**
2. **CloudKit / TestFlight — one step at the end of the backlog, right before the next upload:** in the simulator,
   sync once with a hidden scanlation group, a bookmarked manga AND novel chapter and a novel with genres (fields only
   reach the Development schema after a non-nil value is sent, S152) → Martin opens CloudKit Console → Deploy Schema
   Changes, the diff must show `Manga.excludedScanlators`, `MangaChapterState.isBookmarked`,
   `NovelChapterState.isBookmarked` (+ `Novel.genres` if missing — settles the S156 contradiction) → upload. Builds 504
   and 508 need nothing: 515 replaced them in Friends.
3. **Trackers — hide what can't work, register only AniList.** Code (H/K): a tracker whose client id is empty is not
   listed (Trackers screen, tracking sheet, onboarding if any). Martin, whenever convenient (2 min, his AniList
   account): anilist.co/settings/developer → new client, redirect `yomi://anilist/callback` → paste the id into
   `AppSecrets.swift`. AniList is the second tracker after MAL in the Mihon world and needs no secret; Shikimori
   (Russian) and Bangumi (Chinese) stay hidden until someone asks.
4. App Store listing: parked until we actually list (Martin). Phone build: after the backlog (Martin).

**Group L (added S170, after K):** L1 library query time (sim with Martin's data, METODOLOGIA S141) · L2 novel reader vs
LNReader checklist · L3 parity leftovers above, ranked by Martin's daily use · L4 CB7, neural voices, streak repair
(ask Martin if wanted).

**Same session — K, H, G done (simulator; build 0 warnings app + widget; UI tests 13/13):**
- **K** (`7f62239`): licences rows "Ported code" (Mihon Apache-2.0, image-decoder MPL-2.0 + link to PageBorders.swift);
  trackers without a client id hidden (`MangaTracker.isConfigured`; sim: only MyAnimeList listed); #156–#162 doc drift
  fixed (stale `Firebase/yomi-firebase/` → Trash); stale KNOWN_ISSUES rows closed, header list rewritten; ArcReader ticks.
- **H** (`13a8e7c`): `PluginScript.validate` (HTTP 2xx, not HTML, JSC syntax check, optional catalog `sha256`), atomic
  write, previous script kept → long-press "Go Back to Version x"; catalog entries decoded one by one; repositories
  merged in configured order; repository-aware matching (#171). `scripts/plugin-trust-tests` 14/14 + 301 LNReader + 22
  Yomi plugins pass. Sim end-to-end against a local test repository (broken entry skipped, wrong hash and web page
  refused with their messages, update + restore byte-identical). `scripts/catalog-hashes.py` = Firebase predeploy hook:
  **DEPLOYED 2026-10-16 by Martin** (after `firebase login --reauth`): live check 16/16 catalog hashes match the live files.
  #153 closed as not a bug (Firebase clears the CDN on deploy).
- **G** (this commit): Library filter menu → **Sources** submenu (tap cycles show only → hide → all; "Show All
  Sources" on top; duplicate names say Plugin/Keiyoushi) — sim: only Local = 9 manga, hide Local = 148 of 157, survives
  relaunch. **Per-category sort** (`librarySortByCategory`; "Sort · Action" header; All keeps the old global key) — sim:
  Action alphabetical while All stays Last Read. **Pinned sources** (context menu Pin/Unpin on Browse rows and Keiyoushi
  language rows → "Pinned" section above Last Used, `pinnedSourceKeys`) — sim, survives relaunch. **LNReader plugin
  filters**: the shim's `FilterTypes` was `{}` (every filter type undefined) → LNReader's real enum; `PluginFilter` +
  `PluginFilterSheet` (Text, Picker, Checkbox, Switch, include/exclude groups); `popularNovels(page:filters:)` sends the
  chosen values. Sim with LNReader's own Royal Road (link install): sheet listed its 11 filters, Genres → Historical
  included → Apply → a different list, filled filter icon. Yomi's own plugins declare no filters (none to show).
- NOT checked: the Continue row ignores the source filter (by design for now — it is reading history); the text
  fields in the filter sheet (automation can't type there); Keiyoushi language-row pin; anything on the phone.

NEXT (S171): L (L1 library query time, L2 novel reader vs LNReader checklist, L3 parity leftovers, L4 ask) → I (ask
Martin which) → CloudKit schema deploy + personal build + J device check.

---

## S169 — F17 crop borders · smarter two-page spreads · automatic background (2026-10-15, simulator)

Tachimanga parity (v4.18 crop borders, v5.0 manga background colour, v3.2/v4.14 separate first page + wide pages) and
S158 top-10 #10. Every algorithm was read from its live source first (not from the S158 notes): tachiyomiorg/image-decoder
`borders.cpp`/`borders.h` @f11fbd3, Mihon `ImageUtil.chooseBackground` + `readerBackgroundColor` @446f6df.
- **New files:** `Features/Reader/PageBorders.swift` (Swift port of borders.cpp — **MPL-2.0, its own header; see the
  licence note below**), `PageAnalysis.swift` (`PageSpreads` pairing rules; `PageBackground` = port of Mihon's
  chooseBackground, Apache-2.0, attribution in the file), `ReaderPageLook.swift` (`PageLook.measure` on a ≤384-px copy
  off the main thread, `PageLooks` cache in Caches/page-looks.json saved with `PageShapes`, `ReaderBackdrop`,
  `PageCrop` modifier, `ReaderBackgroundPicker`). Tests: `scripts/reader-page-tests/run.sh` (26/26).
- **Crop borders** — two toggles like Mihon: paged modes (`cropBorders`, incl. Vertical pages) and long strip +
  continuous (`cropBordersStrip`). Defaults OFF (= before). Paged: the page is laid out cropped (`PageCrop`), hidden
  for the few ms between load and measure so the margins never flash; a page measured before is cropped from its first
  frame. Strip: the decoded page is cropped before it is cut into strips; placeholders use the cropped shape so nothing
  jumps. Yomi's own guard (not in Mihon): a crop that would leave < 25 % of a side is ignored.
- **Two-page spreads** — `PageSpreads.groups`: "Cover on its own" (`doublePageCoverAlone`, default off = before), a
  page wider than 1.2 always alone, two pages pair only if their shapes differ by ≤ 0.1, and pairing restarts after a
  lone page (Mihon's experimental WebGpuViewer rules). Shapes come from `PageShapes` (now `@Observable` via
  `PageShapes.changes`, re-pairs as shapes arrive) and `PageShapes.learn` reads downloaded/local/cached pages' file
  headers when two-page mode opens (the prefetcher uses the same function now).
- **Background** — `readerBackground`: Black (default = before) · Dark grey · White · Automatic. Automatic = white or
  dark grey with the iPhone's appearance (Mihon's rule) — read from the SCREEN's traits, because the reader forces
  `.preferredColorScheme(.dark)` on itself — and in the paged modes each page sits on its own margin colour (solid, or
  Mihon's top/bottom split). Spinner and error text turn dark on a light backdrop.
- **Settings:** More → Settings → Manga & Webtoon (Pages: Cover on its own + Crop borders; Long Strip: Crop borders;
  new Background section) and a "Pages" section in the reader's own sheet for the mode being read.
- **Verified (sim):** a Local "Spread Test" chapter (8 generated pages: framed cover, white-margin pages, one wide, one
  black-top-band, one odd shape) in RTL, Always, cover alone, crop + automatic: screens were exactly [1] [2 3] [4 wide]
  [5 6] [7 odd] [8]; the cover's black frame and the white margins were cut; cover on black, others on white, page 5 on
  the black→white split; crop off in the sheet brought the margins back at once; Continuous RTL with strip crop on cut
  page 7. A real 1870 newspaper scan (Local CBR): the thick black scanner border is cut except a ~1 % strip on the
  left/top where the border isn't clean black (same edge rule as upstream — not tuned). Build 0 warnings (app + widget).
  UI tests 13/13 (all novel-reader fixture tests — they guard against regressions, none drives a manga page).
- **NOT checked:** long strip with crop on real Asura pages, landscape "In landscape" spreads, the device, memory with
  crop on (the crop shares the decoded page; strips are drawn copies as before).
- **Licence note for Martin:** `PageBorders.swift` is an MPL-2.0 port (file-level copyleft). Shipping it is allowed
  in a closed app, but that one file's source must be available to people who get the app (e.g. a public gist/repo
  linked from the licences screen). Alternatives: ship it that way, or have a fresh implementation written by someone
  who hasn't read borders.cpp. Separately, the Mihon (Apache-2.0) ports — ChapterRecognition, FetchInterval, and now
  PageBackground — have attribution comments but no entry on the licences screen yet; Apache asks for the licence text
  with redistributed derivative code. Neither is fixed here: it's Martin's call before the next TestFlight build.

NEXT (S170): G (library/browse parity) → H → K → J. **Before J: a personal build for Martin's phone** (it still has
#211 from `98af933`) — ask him. Licence note above before the next TestFlight upload.

## S168 — F16 reader gestures: tap zones per mode · page menu · scroll while held (2026-10-15, simulator)

Tachimanga parity (TACHIMANGA_PARITY "Press and hold to scroll" + "save/share a page"; S142 backlog "separate tap zones").
New file `Features/Reader/ReaderPageActions.swift` (`ReaderTapZones`, `StripScroller`, `.readerPageMenu`).
- **Tap zones per mode:** paged modes keep `tapZoneLayout` (geometry moved to `ReaderTapZones.paged`; Vertical pages
  now uses it too — before, every tap there only toggled the menu). Long strip + continuous get `stripTapZoneLayout`:
  Off (default = old behaviour) · L-shaped (Mihon's LNavigation: top band + left middle back, bottom band + right
  middle forward) · Top and bottom. Long strip moves ¾ of a screen (`StripScroller.page(by:)`, the hosting
  UIScrollView found by `EnclosingScrollViewFinder`); continuous steps one page, mirrored for RTL.
- **Long press in long strip** (`stripLongPress`): Auto-scroll on/off (default = old behaviour) · Scroll while held
  (CADisplayLink, half a screen per second, stops on release) · Share or save the page.
- **Page menu:** long press on a page → Share… (UIActivityViewController) · Save to Photos (add-only permission, new
  `NSPhotoLibraryAddUsageDescription`) · Copy Image; feedback through a non-error toast. Always on in paged modes
  and continuous; in long strip only when Long press = Share or save. Image comes from Kingfisher's cache.
- **Settings:** More → Settings → Manga & Webtoon (Pages + Long Strip sections) and a new "Gestures" section in the
  reader's own settings sheet (shows the paged or strip options for the mode being read; sheet now expands to large).
- **Bug found on the way (#211, since S164 `89eaca4` — ON MARTIN'S PHONE, build `98af933`):** in long strip and
  continuous the page counter never moved while scrolling, so the saved position (and the ≥80 % mark-read) stayed on
  the page the chapter opened at. Cause: D12b's `.id(url)` inside each page hid the `cur:N` id from
  `scrollPosition`. Reproduced on unmodified `fc3d3c0` (stash, same 3 swipes, stuck at 22/50). Fix: the page reloads
  on a URL change through `.task(id: LoadKey(url, attempt))` + `onChange(of: url)` instead. Second half: SwiftUI's
  `scrollPosition` ignores scrolling done in code, so while `StripScroller.isDriving` the page comes from
  `onScrollTargetVisibilityChange` (top-most visible page); not at rest — a sliver of the previous page under the
  status bar counts as visible there (opened at 21 instead of 22 when tried).
- **Verified (sim, Absolute Regression ch. 121, downloaded, 50 split parts):** L-shaped bottom tap = ¾ screen down,
  top tap = back to the same spot, centre = menu; hold 4.6 s moved 20,051 → 22,053 pt and stopped on release, counter
  22 → 23 after a 7 s hold; finger swipes 22 → 23 → 24 (stuck at 22 before the fix); reader opens on 22/50; page menu:
  Copy → "Page copied", Share → share sheet with the image, Save → Photos permission prompt with the new text →
  "Saved to Photos"; RTL paged thirds: left = forward (22 → 24), right = back. Build 0 warnings (app + widget).
  UI tests 12/13 in the full run, the 13th = #193 flaky, passed alone.
- **NOT checked:** Vertical pages and continuous tap zones on screen (compile + shared code only), auto-scroll with
  the new gestures, the menu on a split page vs a whole page in Photos, the device.

NEXT (S169): F17 (crop borders · double page "separate first page" + wide page alone · automatic page background) →
G → H → K → J. **Before J: a personal build for Martin's phone fixes #211** — worth doing soon, it hits his daily
Asura reading (ask him).

## S167 — E15 hidden scanlation groups · duplicate warning · chapter bookmarks (2026-10-15, simulator)

Mihon parity (research_notes `mihon_family.md` §2d/§2e). Migration **`v28_scanlator_exclusion_bookmarks`**: table
`excluded_scanlator(mangaId, scanlator)` (FK cascade) + `isBookmarked` on `chapter`, `novel_chapter` and both pending
tables. `isBookmarked` is read into the structs but never encoded — only `setBookmarked` writes it.
- **Hidden groups (manga):** Detail → Filter and sort → "Scanlation groups" (a toggle per group; "(N hidden)"; the
  last shown group can't be hidden). Saved per title, synced (`Manga.excludedScanlators`). Applied everywhere through
  ONE list, `MangaDetailView.readingList` (hidden groups out, then one-translation-per-chapter): detail list + counts
  + resume, reader Next/Prev, downloads, Continue (tap AND card label), History; in SQL via
  `ChapterQueries.notExcluded`: Library unread badges, `fetchUnread`, Updates feed. NOT applied: FetchInterval
  release days (Mihon does) and background-refresh notification counts.
- **Duplicate warning (manga + novels):** tapping the heart on a title not in the library first looks for library
  titles whose name contains this one (case-insensitive — Mihon's rule; Yomi keeps no tracker ids, so Mihon's
  shared-tracker match is skipped). Dialog "Already in your library?" lists each (source · chapters, count omitted when
  none are saved), buttons Open <title> / Add Anyway / Cancel. Removing from the library never asks.
- **Bookmarks (manga + novels):** trailing swipe "Bookmark", select bar "Bookmark"/"Unmark", accent bookmark icon on
  the row, "Bookmarked" in the Show filter (novels: the unread toggle became a Show picker, saved the same way).
  Novels outside the library can't be bookmarked (no rows). Synced on MangaChapterState/NovelChapterState.
- **Backups:** Yomi JSON (`isBookmarked` per chapter, `excludedScanlators` map; restore only adds) and `.tachibk`
  export/import (Mihon `BackupChapter.bookmark` = 5, `BackupManga.excludedScanlators` = 108 — read from the Mihon
  source) + Tachimanga `.tmb` bookmark column.
- **Two bugs found on the way:** (1) detail merges copy saved state field by field (4 places) — bookmarks were saved
  but gone on reopen; fixed, plus a source with no group keeps the saved one. (2) The Continue card LABEL picked the
  newest `readAt` (random among a bulk mark-read: showed "Chapter 106") while its tap used ResumeReading — the label now
  uses the same list + rule.
- **Verified (sim, Asura JS "Absolute Sword Sense" with a fixture: even chapters "Group A", odd "Group B"; DB backed up
  and restored after):** v28 ran on the existing 83 MB DB. Hiding Group B → 50 chapters, "49 of 50 read", resume
  Chapter 204 (was 203), Library badge 3 → 1 unread, `excluded_scanlator` row saved, reader Next from 202 → 204, Continue
  card "Chapter 204 · 98%", History "Chapter 204". Bookmark via select bar → icon + DB row; survived leaving and
  reopening (after the merge fix); Bookmarked filter shows only it. Duplicate: Asura JS "Childhood Friend of the
  Zenith" (Keiyoushi copy in library) → dialog, Open → the library copy, nothing added. Build 0 warnings.
- **NOT checked:** the novel screens (compile only — the automation's long-press kept landing on rows under the tab
  bar), Add Anyway, sync of the new fields, any backup round trip, Keiyoushi titles (no JVM in the sim), device.
- **CloudKit before the next TestFlight build:** new fields `Manga.excludedScanlators` (STRING LIST),
  `MangaChapterState.isBookmarked` + `NovelChapterState.isBookmarked` (INT64) must exist in the Production schema, or
  saves carrying them are refused (S152 rule: fields exist only once a non-nil value was sent in Development). Add to J.

NEXT (S168): F (manga reader parity: tap zones per mode · save/share page · press-and-hold scroll, then crop borders ·
double-page options · auto background) → G → H → K → J.

## S166 — E14 smart updates + per-source update streams (2026-10-15, simulator + Mac-server data + DEVICE)

`Core/FetchInterval.swift` = port of Mihon v0.21 (@446f6df, Apache-2.0) `FetchInterval` + `ReleaseSchedule` +
`ReleasePattern` (the S165 handoff said "ReleasePattern"; it exists only in v0.21 — the local mihon-clone was at
v0.19 and had the old 120-line FetchInterval, first ported by mistake, then redone after `git fetch`). From a title's
release days (source upload dates, else the days a refresh found chapters): interval = median gap (1…28, 7 if too
little), a calendar pattern when one fits (2–3 weekdays, day/weekday of the month, batches), checks spread out in a
hiatus, a late/early/extra release keeps the schedule. `Day` = timezone-free calendar day (stands in for kotlinx).
- **Tests first:** Mihon's `FetchIntervalTest.kt` (36 tests) ported → `scripts/fetch-interval-tests/run.sh`, plus Yomi
  cases → **54/54**. Mutation pass: 11 one-line breaks of the port; 5 survived Mihon's own tests (lower median,
  10-day window, 4-cycle hiatus, halfway-counts-as-late, weekday releases not snapped) → a Yomi case for each; now
  all 11 fail the suite.
- **DB `v27_fetch_interval`:** `chapter.uploadedAt` (Keiyoushi `date_upload`; JS plugins give no dates, novel
  `releaseTime` is never filled by our plugins → those use v23 `fetchedAt`), `manga`/`novel.fetchInterval` + `nextUpdate`.
  Out of the model structs, not synced. `UpdateScheduleQueries`: `setUploadDates` (Detail + refresh, Keiyoushi),
  `recordCheck` after every successful check (Mihon's rule: recompute on a release, when never computed, or when the
  stored day is behind the window), `notExpected` for the skip rule.
- **Setting:** Updates → Filter (Update Rules) → "Titles not due yet" (`skipUpdateNotExpected`), **ON by default**
  (Martin's call after the replay below; Mihon's "Outside expected release period" is off). Skipped = next expected
  day after tomorrow 00:00. Sim with no saved pref: refresh checked 148 of 154 (the 6 not due skipped).
- **Per-source streams:** `runStreams` — one stream per source, its titles one at a time; 5 plugin / 3 Keiyoushi
  streams at once, the longest stream first. Keiyoushi keeps its one-at-a-time first title per extension (APK load).
  Before: one pool of 6 over all JS titles (calls serialise per source on the bridge lock, so slots could all wait on
  one source) and 3 over Keiyoushi titles regardless of source.
- **Simulator:** v27 ran on the existing DB; refresh = 154 titles (148 Keiyoushi fail — no JVM in the sim), the 6
  checked got schedules (7-day default, little history; next day at local midnight; a title that just released → +7).
  Setting on → **148 checked, the 6 not-due skipped**; toggle screenshot OK. Pref reset to default afterwards.
- **Real data (Mac Keiyoushi server, Asura v1.6.69, all 87 Asura titles in the sim library):** every list has upload
  dates; intervals 7d×77, 8d×4, 6d×2, others ×4; 1 weekday pattern; 66/87 "not due" today. **Replay of each title's last
  5 releases (420) with daily refreshes + the rule on: 86% found the same day, 88% ≤ 1 day, p90 2 days, max 20, none
  missed; 69% fewer checks than daily.** (The other 38 sim titles, source `626267698662819838`, are Aqua Manga — #208,
  site down — not MangaFire; the harness ran the MangaFire APK on them, hence 404s. Not a MangaFire problem.)
- Build 0 warnings (Yomi + YomiWidget). NOT checked: anything on the phone — Keiyoushi refresh speed with streams
  (87 Asura titles now one at a time, was 3 at once — the extension's own rate limit already throttles, but measure
  it), background refresh, the Detail upload-date write on a real Keiyoushi title.

- **DEVICE (Release `98af933`, Martin's iPhone, 2026-10-15; DB backed up first → `phone-backups/S166-before-…1158`):**
  v27 ran on his 148 manga + 3 novels. Refresh 1 (no schedules yet → every eligible title): **~1–2 min**, 104 manga
  got a schedule (7d ×88, 2–28d the rest), 11,579 chapters got `uploadedAt`, 51 new chapters (≤ 4 per title — no
  baseline flood). Refresh 2: **~40 s, checked 43, 21 failed**. Reconciled from the pulled DB + prefs (his rules: not
  started + completed + not due): predicted exactly 43, of which 21 = Aqua (#208, site down) → **every failure is
  Aqua**. Without the new rule: 125 → **66% fewer checks**. No pre-S166 refresh timing exists to compare streams
  against. The 11 non-Aqua titles without a schedule were never checked (not started / completed).

NEXT (S167): then E15 (saved scanlator exclusion · duplicate warning · chapter bookmarks, `v28_`)
→ F → G → H → K → J.

## S165 — E13 ChapterRecognition v2 (2026-10-15, compile + Mac-server data, no sim screen)

`Core/ChapterRecognition.swift` rewritten as a port of Mihon v0.21 (`ChapterRecognition.kt` @446f6df, Apache-2.0):
volumes/seasons taken out instead of treated as noise, "Part N"/roman numerals → sub-chapter letter (27b = 27.2),
numbers every similar name shares ignored ("Group 2 Chapter 387" → 387, v1 said 2), unnumbered chapters filled from
their neighbours (2, "The Return", 4 → 3; Afterword after 100 → 100.5; Prologue → 0), "Vol.3" alone → no number (v1: 3).
- **Tests first:** Mihon's `ChapterRecognitionTest.kt` ported case by case + 6 Yomi cases →
  `scripts/chapter-recognition-tests/run.sh` (swiftc harness, no test target). **103/103 pass**; a mutated copy
  (2 expectations changed) reports exactly 2 FAILs, so the harness can fail.
- **Wired in:** `KeiyoushiMapping.chapters(from:…)` reads the WHOLE list (Detail, Updates refresh, Mass migration);
  `ChapterRecognition.numbers` accepts either order (reads reversed when the numbers go up). `refreshPaths` now also
  writes a newly recognized number onto chapters already saved (never clears one) — before, INSERT OR IGNORE froze
  the first number forever. Local files + v24 keep the single-name API (same v2 rules). No DB migration.
- **Real data (Mac Keiyoushi server, 16 popular titles, Asura v1.6.69 + MangaFire v1.6.34, 9,051 chapters):** with the
  sources' own numbers, v1 vs v2 **0 changed**. Names only vs MangaFire's 7,489 numbers: v1 7,489 right, v2 7,487 — the
  2 are Blue Lock "Chapter 314 Core (Part 1/2)" → 314.1/314.2 (Mihon's intended part letters; the source says 314 twice).
- Build 0 warnings. NOT checked: JS-plugin chapter lists (still take the plugin's number as given, no recognition),
  `.tachibk` import (keeps single-name; backups carry Mihon's numbers), any screen (Keiyoushi has no JVM in the sim).

NEXT (S166, new chat): E14 smart updates + per-source update streams (Mihon FetchInterval/ReleasePattern, tests in
`FetchIntervalTest.kt`) → E15 → F → G → H → K, then device check J.

## S164 — D12b page-list cache (2026-10-14, simulator only)

`Features/Reader/PageListCache.swift` (new), `ChapterReaderView.swift`, `SuwayomiService.swift` (`chapterRef` nonisolated).
Mihon's `ChapterCache` idea (research_notes `mihon_family.md` §1e): reopening a chapter that isn't downloaded skips the
plugin/JVM `fetchPages`.
- **URLs checked first (live, 2026-10-14):** Asura JS plugin and Keiyoushi Asura (Mac server, ext v1.6.69) both return
  `cdn.asurascans.com/...webp?v=<upload stamp>`. No signature: the same file loads with `v` removed or set to 1/999,
  `cache-control: immutable, max-age=1 year`. Keiyoushi MangaFire (v1.6.34): opaque `k99.mfcdn3.xyz/mf/<token>/h/p.jpg`.
  Two fetches gave the same 112 URLs, still 200 seven minutes later (aging past that NOT tested), `max-age` 30 days,
  **403 without the Referer** → covered by the per-host header store `KeiyoushiCovers`, which persists across launches.
  Bridge-proxied pages (`127.0.0.1/image/<id>`, Asura tiles / `fetchImage`) are never cached: their ids live only as long as the JVM.
- **Cache:** one JSON per chapter path in `Caches/PageLists` (sha256 name), 7-day max age, expired files pruned once per
  launch; skips local, Suwayomi and bridge-proxied lists. Reader's 3 sites (open, chapter nav, next-chapter preload) use
  `readerPages(bridge:path:)`; downloads still fetch fresh lists. No DB change (no `v26_` used).
- **Way out:** a page's first failure posts `PageRetry.pageFailed`; if that page belongs to a list served from the cache
  (current chapter or preloaded next), the list is fetched again **once**, the entry replaced, and pages swapped if they
  changed (same index = same source page, so `lastPageRead` keeps its meaning; downloaded chapters never use the cache).
  Strip pages got `.id(url)` so a swapped URL starts that page over. DEBUG `-yomiStalePageList` breaks every kept URL.
- **Verified (sim, Absolute Regression Ch. 123 via Asura JS, download set aside then restored):** first open
  `[PageListCache] miss … fetched 20 pages`; after an app relaunch `hit … 20 pages, no plugin call`, pages render;
  with `-yomiStalePageList` → `hit`, then `page failed, list fetched again … 20 pages`, real pages render, entry
  rewritten with the real URLs. 0 warnings (Yomi + YomiWidget). UI tests 13/13 (novel-reader suite; no manga-reader UI test exists).
  NOT checked: Keiyoushi in the reader (no JVM in the sim), paged (non-webtoon) modes with stale URLs, device.

NEXT (S165, new chat): E → F → G → H → K (ROADMAP S161), then the one batched 📱 device check (J): add to it Keiyoushi
Asura/MangaFire reopen from the cache (expect no ~4.5 s page-list wait) and a MangaFire chapter reopened after a day.

## S163 — D12 split tall pages on download (2026-10-14, simulator only)

`Features/More/TallPageSplitter.swift` (new), `DownloadManager.swift`, `ChapterReaderView.swift`, `AppSettings.swift`,
`SettingsView.swift`.
- **Split:** a downloaded page more than 3× taller than wide and > 4096 px is cut into equal parts ≤ 4096 px (rule from
  Mihon's `TallImageSplitCalculator`, Apache-2.0; cap = the reader's strip threshold, so a part never takes the strip
  path). One decode per page, split one page at a time (actor). Animated, rotated (EXIF) or undecodable pages are kept as
  fetched. Parts are **HEIC 0.8**: on 12 real Asura pages (800×~14000 webp, 11.1 MB) HEIC 0.8 = 0.93× the originals,
  JPEG 0.9 = 2.2× (first try was JPEG: Ch. 121 = 31 MB → 14 MB with HEIC). Settings → Downloads → "Split tall pages", on.
- **Files:** `<page>.dat` whole, `<page>-<part>of<count>.dat` split (`DownloadedPages`). A whole page wins over parts;
  a part set missing a part is ignored and deleted on resume, so a crash mid-split can't show a half page.
- **Progress stays in source pages:** `lastPageRead` is the original page number online, offline and on other devices.
  The reader keeps `pageSources` (source page of each local image), saves `sourcePage(currentPage)` at all three save
  points and resumes at the first part of the saved page. Progress fraction stays local (images read / images).
- **Two old reader bugs fixed on the way (#210):** a downloaded chapter always opened at page 1 (the local branch
  returned before the resume code), and chapter-to-chapter navigation ignored downloads and went to the network.
- **Verified (sim):** Mac harness compiling `TallPageSplitter.swift` — 14/14 (part sizes, remainder, non-tall/garbage
  kept, crash leftovers ignored, order 0,1a,1b,2,10, source map). Absolute Regression Ch. 121 (Asura JS): 16 pages →
  50 files (40× 900×4000 + remainders, all HEIC; 2 short webp kept); opened with saved page 5 → "16/50" (first part of
  page 5); scrolled to 23/50, closed → DB `lastPageRead = 7`, row "Page 8"; online reader resumed same chapter at 6/16.
  0 warnings (Yomi + YomiWidget). UI tests 13/13 (novel-reader suite; no manga-reader UI test exists).
- **Page-list cache NOT done** (second half of D12) — see NEXT.

NEXT (S164, new chat): D12b page-list cache — GRDB/JSON keyed by chapter path; check first that JS-plugin image URLs and
Keiyoushi CDN URLs (S159) don't expire, and give the reader a way out when a cached URL fails (refetch the list once)
before trusting it. Then E → F → G → H → K, then the one batched 📱 device check (J): also check splitting on device
(Keiyoushi Asura 900×16000 downloads; HEIC encode time per page).

## S162 — D11 robust manga downloads (2026-10-14, simulator only)

`Features/More/DownloadManager.swift`, `DownloadsView.swift`. Built to the S161 design:
- **Retries:** each page retried after 2/4/8 s on network errors, 5xx, 408, 429; other 4xx fail at once; stops on cancel.
- **Resume:** pages are written `.atomic`; a retry/resume skips `<idx>.dat` already on disk; extra pages beyond a
  shorter new page list are removed. Chapter marked downloaded only when every page is on disk.
- **Pause / Resume** in the Downloading header: the running chapter goes back to the front of the queue, its pages stay;
  queued rows say "Paused". Cancel still deletes the chapter's pages. Cancel no longer resets `isRunning` before the
  cancelled task ends (old race: a new download could start while the cancelled one was still cleaning up).
- **Low storage:** < 200 MB free (`volumeAvailableCapacityForImportantUsage`) before a chapter, or after a page write
  fails → queue pauses with "Paused — less than 200 MB free" + Resume.
- **Failed list:** "N Failed · Retry All" section in Downloads, tap a row = retry it, swipe = remove; in memory only
  (like the queue). Re-enqueueing a chapter removes it from the list.
- DEBUG args: `-yomiDownloadFlakyPages` (every page's first request fails), `-yomiDownloadFailPages` (all fail),
  `-yomiSimulateLowStorage`.
- **Sim-verified on Absolute Regression (Asura JS):** flaky pages → 3 chapters / 57 pages all completed; pause mid-Ch. 25
  at 9 pages → not marked downloaded, resume fetched only the 3 missing pages (the 9 files' mtimes unchanged); cancel
  removed Ch. 27's folder; fail-all → 56 chapters in Failed, Ch. 28 "11 of 14 failed" (3 kept from an earlier pause),
  Retry All moved them back to the queue; low storage → nothing started, message shown. 0 warnings. UI tests not run
  (no reader code touched). NOT checked: Keiyoushi downloads (no JVM in the sim), real low disk, device.

NEXT (S163, new chat): D12 split tall pages on download + page-list cache → E → F → G → H → K, then the one batched 📱
device check (J).

## S161 — THE PLAN: every open issue + all research, grouped and ordered (2026-10-14)

Sources merged: KNOWN_ISSUES open rows, ROADMAP backlogs (S142, S145, ArcReader S126), RESEARCH §25.10,
TACHIMANGA_PARITY (S148/S157 "Missing"), S158 top-10 (`reports/Reverse engineering for Yomi.md`), S159 notes.
Order rule: Martin's daily use first (Asura webtoon + WeTried novels), then robustness, then parity features,
then hygiene. Items marked 📱 need his phone; they are batched into ONE device check (group J) so he is asked once.
Execute top to bottom; one item = build 0 warnings + sim check + commit/push.

**A. Daily-use bugs (small, sim-checkable)**
1. #206 two back buttons on a title opened from a Library search.
2. #113 Appearance "Reset" skips the blend slider · #112 re-tapping Download on the active chapter · #109/#110 tracker
   login sheet doesn't close / stale error banner · #172 novels briefly listed as Manga · #176 Updates only knows
   refresh-found chapters. (Each re-checked in code first — several S117/S118 rows may be fixed already.)

**B. Webtoon reader (Asura, top-10 #1–#3)**
3. Page preload: current → next → previous → rest in growing batches, next chapter after the current one (top-10 #1;
   Martin's S159 device report "fast scrolling still waits").
4. Screen-width downsampled strips (top-10 #2; S160 made strips own their memory, decode is still full size).
5. Persisted page heights (part of top-10 #3, without the UIKit rewrite); UIKit list only if jumps remain.
6. Pinch-zoom in webtoon mode (S145 backlog) · split `ChapterReaderView.swift` (#106) while in there.

**C. Keiyoushi engine**
7. #207 zstd stand-in in the server patch → Asura genre/author filters (top-10 #4; Mac-server checkable).
8. Port check on bridge start (Mangayomi `/capabilities` idea) + jsDelivr fallback for the index (campus Wi-Fi).
9. Asura scrambled "tiles" pages in Core Graphics (S159 §3) — L. 10. #208 Madara refresh = PARKED until Aqua is back.
   (Top-10 #5 URLSession networking: demoted by S159, page list is JVM work not network.)

**D. Downloads (top-10 #6–#7)**
11. Retries 2/4/8 s, `_tmp` folder renamed on success, Pause, Retry All, low-storage check.
12. Split tall pages on download + page-list cache.

**E. Chapter lists / updates (top-10 #8–#9)**
13. ChapterRecognition v2 with Mihon's tests ported first. 14. Smart updates + per-source update streams.
15. Saved scanlator exclusion · duplicate warning on add · chapter bookmarks (needs `v27_`).

**F. Manga reader parity (Tachimanga)**
16. Separate tap zones per mode (S142) · save/share a page (long press) · press-and-hold scroll.
17. Crop borders · double page "separate first page" + wide-page alone · automatic page background (top-10 #10).

**G. Library / Browse parity**
18. Library source filter include/exclude · pinned sources · per-category sort · filters for JS/LNReader plugins.

**H. Plugin trust chain** — #151 checksum, #152 validate before overwrite + keep backup, #154 per-entry decode,
#155 deterministic merge, #153 cache headers (Firebase, deploy = Martin), #171 same-name in two repos.

**I. Later / bigger** — Spanish (§25.10 #12), lockable SFW mode, reader auto-dark at night, a11y baseline
(Reduce Motion, Increase Contrast), perf gates in UI tests (§25.10 #11), ArcReader novel leftovers (term
replacement, translate, letter spacing, themes), #194 Asura JS 100-chapter cap, #69 MangaDex plugin, CBR solid/huge.

**J. Needs Martin (📱 one batched device check, then publishing)** — install a build with S160+ fixes
(`scripts/build-personal.sh --release`); check #203/#209/preload on Asura, extension gear + filters, iCloud backup,
widget, trackers, two-device sync; then listing approval (#4), screenshots, upload (his explicit go per build).

**K. Docs hygiene + close stale rows** — #156–#162 doc drift; KNOWN_ISSUES header list (says "as of S148");
close/retire: #6, #12, #14, #21, #47 (paid Program active, CloudKit works), #49, #71 (superseded by calm design),
#78 (app is iPhone-only), #164/#193/#196 (flaky tests: keep, retry-alone rule), #55 (harmless, note only).

**S161 progress (simulator unless said):**
- ✅ A1 #206 — `navigationBarStaysHidden(_:)` on detail screens + readers (fix on the pushed side; ending the search
  before the push was tried and broke SwiftUI state). Library + History search checked; UI tests 13/13. `2893ce8`
- ✅ A2 #109/#110/#112/#172 (compile-only — OAuth, active download and first cold-launch frame aren't drivable in the
  sim), #176 (sim: re-found LOTM chapters listed in Updates), #113 obsolete. `288f53b`
- ✅ B3 page preload — `Features/Reader/ReaderPagePrefetcher.swift`: on every page change the next 6 pages (+1 behind,
  spilling into the next chapter's list) go to Kingfisher's DISK cache, 3 at a time, Low Data Mode respected; one hook in
  `ChapterReaderView` covers every mode. Asura JS ch. 122 (21 pages), 16 s after opening without scrolling: **7 page
  files cached vs 3** with `-noPagePrefetch` (DEBUG A/B arg, ch. 121); moving to page 2 added exactly page 8; footprint
  459 MB. UI tests 13/13. 📱 device: does fast scrolling through Asura (Keiyoushi) still wait?
- ⏸ B4 downsampled strips — DEFERRED: Asura pages are 900 px wide, narrower than the screen (1206 px), so screen-width
  downsampling saves nothing for Martin's main source and would blur the planned webtoon pinch-zoom (B6). Measure memory
  per Asura page on the device first (S159 leftover).
- ✅ B5 page heights saved — `PageShapes` moved to `ReaderPagePrefetcher.swift`, saved to `Caches/page-shapes.json` when
  the reader closes; the prefetcher reads each prefetched page's pixel size from the cached file's header (ImageIO, no
  decode), so pages AHEAD get their real height before they appear. Sim: after one Asura chapter the file held 7 shapes,
  6 of them for pages never displayed. UI tests 13/13. 📱 device: no jumps when resuming mid-chapter after a relaunch.
- ✅ B6 pinch-zoom in webtoon — already shipped S149 (#200, `ReaderZoom`); the S145 backlog line was stale.
- ✅ C7 #207 — pure-JVM zstd stand-in in the server patch; Asura Genres [35] + Creators load on the Mac server (iOS-mode
  jar), cache survives a restart, `zstd -d` reads it. Jar staged for the next device build.
- ✖ C8 port check: NOT needed — the bridge starts on port 0 and gets the bound port back in-process (Mangayomi's
  problem is a guessed port for a spawned process). jsDelivr index fallback DROPPED: the mirror served a stale
  index (bytes differ from GitHub, checked S161) and no GitHub block was ever seen on Martin's networks.
- ⏸ C9 Asura tiles: waits for device evidence that tile pages occur. C10 #208 parked (Aqua down).

**✅ S162 done (see above). Was: NEXT (S162) = D11 robust manga downloads** (`Features/More/DownloadManager.swift`, `DownloadsView.swift`),
designed, no code yet: per-page retries 2/4/8 s (not on 4xx except 408/429; stop when cancelled) · resume = skip
`<idx>.dat` already on disk + `.atomic` writes · real Pause/Resume (`isPaused`; pausing cancels the current task but
keeps files and puts the item back first; `processQueue` guards `!isPaused`) · free space < 200 MB → pause + message ·
failed chapters kept in a list → "N failed · Retry" row in Downloads (enqueue removes from it). Then D12 → E → F → G
→ H → K, then the one batched 📱 device check (J): build with `scripts/build-personal.sh --release` (Martin runs it).

## S160 — long-strip memory (2026-10-14)

- **#208 parked:** Martin says Aqua is down for its own server reasons, and it is the only Madara source in his
  library, so nothing to test. Read keiyoushi `MadaraBase.kt` first: chapter url = slug + memo `{mangaPath}`,
  `getChapterUrl` throws on any url containing '/'. The "match old chapters by number on refresh" fix waits for Aqua.
- **#209 fixed (sim only):** reading tall pages in Webtoon mode grew memory ~55 MB per page until the reader closed.
  Test: 20 generated 900×16000 JPEGs as a local series (`Documents/Local/Tall Test`), slider dragged page 1 → 20,
  `footprint` on the sim process. Before 908 → 1,964 MB; `.onDisappear` release → 1,385 MB; owned-bitmap strips
  → **771 → 777 MB** (flat). `footprint -v` showed the cause: ~160 ImageIO buffers of 7.3 MB = one per 900×2048 strip.
  Kingfisher memory cache capped at 256 MB (guard). Pages render correctly (screenshot), UI tests 13/13
  (`testPagesWithoutContinueEndOnNextChapterPage` flaky, passed alone).
- NOT checked: on the phone with real Asura pages (WebP from the network, not local JPEG); scroll-back placeholder flash.

- **Martin's device check (S159 Debug build, Asura in the reader):** "much better than before"; scrolling a bit fast,
  some pages still take a moment to load → page preload (top-10 #1) is the next fix. The S160 memory fix was NOT in
  that build; `scripts/build-personal.sh --release` is blocked for me by the auto-mode classifier — Martin runs it.

NEXT (new chat): Martin asked for ONE complete plan from every open issue + all research (KNOWN_ISSUES open rows,
ROADMAP backlogs, RESEARCH §25.10, TACHIMANGA_PARITY, S158 top-10 PLAN.md, S159 notes), then execute issue by issue.

## S159 — measure before porting; Keiyoushi pages native (2026-10-14)

Plan step from S158 (`research_notes/Reverse engineering for Yomi/PLAN.md`, track 5). Numbers:
`research_notes/Reverse engineering for Yomi/S159_measurements.md`.
- **REA audited** (clean: no telemetry, no install hooks, pinned jars) **and not used** — it is for binaries without
  source; Instruments, signposts and the JVM's own logging measure Yomi better.
- **Server-jar licence settled:** `kodjodevf/M-Extension-Server` = MPL-2.0 (LICENSE file). The unlicensed repo is the
  Flutter wrapper `m_extension_server`; nothing copied from it.
- **Item 5's "unmeasured guess" was measured in S134** (RESEARCH §23: 4.6–7 s CPU per Asura page in interpreted AES-GCM).
  S158's report missed it.
- **Keiyoushi reader pages now load natively.** Our pinned server (`6685bdc`) proxied EVERY page through the JVM; upstream
  `6dc99f4` (2026-10-05) returns direct URLs + headers. Bumped to `ac589a2` (v1.0.9, patch rebased — one conflict in
  `NetworkHelper.kt`), `KeiyoushiPage.headers` → per-host header store (`KeiyoushiCovers.remember(pages)`), downloader
  sends them and only saves 2xx bodies (`DownloadManager.pageData`). Phone, Asura ch. 119 (24 pages, Debug):
  **all pages 22.9 s → 1.5 s**, one page 2.3–3.8 s → 0.07–0.35 s; page list 5.1 s → 4.5 s warm (10.0 s on the first
  launch after a server bump: converted-extension cache is keyed by server revision). MangaFire on the new server:
  79/79 pages direct, 8.2 s.
- Page-list split (warm): Java HTTP ≈ 0.75 s first request (handshake ≈ 0.6 s) + 0.14 s; the remaining ~3.5 s is JVM
  work. So item 5 (URLSession under OkHttp) would save < 1 s → lower in the ranking.
- New DEBUG launch arg `-keiyoushiWireStats` (one `YOMI-WIRE` line per Java request).
- Found #208: Aqua (Madara) newest chapters fail — "Refresh the chapter list." (extension format change, not the bump).
- Asura scrambled ("tiles") pages still go through Java and likely fail (no `javax.imageio` in java.base) — native
  Core Graphics tile shuffle is the fix (S159 notes §3).
- Device-verified: probe only (same page-loading code as the reader). NOT yet: the reader screen itself, downloads,
  Aqua after a refresh. Phone has this Debug build. Not uploaded anywhere.

NEXT: Martin opens an Asura chapter in the reader; #208 (match old chapters by number on refresh); then S159 leftovers
(memory per Asura page, library query time, novel reader vs LNReader checklist) and re-rank the top-10.

## S157 — Tachimanga parity re-check + source filters (2026-10-13)

Build 1.0 (529) is uploaded (S156). Martin asked for a parity check, then to start on the gaps.

- **Parity re-check** → `TACHIMANGA_PARITY.md` "S157 re-check": Tachimanga has nothing newer than Stable v5.1; the
  S148 "Missing" list still stands. New gaps found: source filters, save/share a page. Correction: tap zones are
  one setting for every mode (the doc said separate presets existed).
- **Source filters for Keiyoushi sources (in NO build yet):** the extension server already had it
  (`filtersManga`; `getSearchManga` takes a `filterList` matched BY NAME). New `KeiyoushiFilter.swift` (model: the
  list comes with no kind field, so the kind is read from the shape of `state`; `wire` sends only what differs from
  the extension's defaults), `KeiyoushiBridge.filters` + `search(filterList:)`, `KeiyoushiFilterSheet.swift`
  (pick one, text, switch, include/exclude, sort + ascending, groups on their own screen; Reset asks the extension
  again; nothing is searched until "Search"). `KeiyoushiBrowseView`: a filter button (filled while filters are on)
  shown only when the source has filters; chosen filters make the screen a search, with or without words.
  **Checked (Mac test server, the app's own model file compiled standalone):** Asura — sort A–Z ascending, status,
  min chapters each change the results; MangaFire — Type → Manhwa + Genres (+Isekai, −Action) + sort changes them.
  **Checked (simulator, sample data, temporary launch hook — removed):** the sheet, the group screen,
  include → exclude → ignored, "2 chosen" on the group row. Build 0 warnings.
  **NOT checked:** the real Browse screen with the button and a filtered result grid (Keiyoushi does not run in the
  simulator) → a device; light theme; UI tests not run.
  **Bridge limits:** inside a group only check boxes, include/exclude and pick-one are applied (a text field, sort
  or group inside a group is ignored by the server, so Yomi hides those). **KNOWN_ISSUES #207:** filters an
  extension fetches from its site (Asura's Genres, Author/Artist) never load — zstd JNI missing in the runtime.
- Not done: filters for Yomi's own JS plugins and LNReader plugins (`plugin.filters` exists in the shim, no UI).
- #206 (double back button) still open — started, no code changed.
- **Waiting on Martin (unchanged from S156):** 529 → encryption answer + add to Friends → Asura gear check → phone
  tests (iCloud backup, widget, trackers, two-device sync) → App Store listing.
- **NEXT (parity order proposed):** #207 server patch (Asura genres) → per-mode tap zones → save/share a page →
  Retry All downloads → library source filter. Martin picks.

---

## S156 — onboarding import check + backlog (2026-10-13)

Martin's order: 1 onboarding import card → 2 backlog → 3 phone tests (iCloud backup, widget, trackers, two-device
sync) → 4 App Store listing. **Nothing uploaded; last TestFlight build is still 515.** All below = simulator only.

- **Onboarding "Import a Backup" card — checked on a real fresh install** (S96 clear procedure): picker offers
  .json/.tachibk/.tmb, the .tmb imports (148 titles, 16,723 chapters, 16,694 read), card gets its check mark.
  **Bug found + fixed (`8518620`):** after "Start Reading" the Library said "No sources yet" — it loads on appear,
  and it appears once, behind the first-run cover. Now reloads when `hasSeenOnboarding` changes. Re-run fresh: 148 shown.
- **Novel genres (`eabfc09`):** `SourceNovel.genres` (LNReader comma string or array → `JSBridge.novelGenres`),
  merged in NovelDetailView, saved by `NovelQueries.updateSourceMetadata` (a source without genres keeps the saved
  ones). The chips UI and the DB column already existed. Plugins edited in `Firebase/public/` (originals in
  `Firebase/plugin-backups-S156/`): WeTried 1.1.0 (API `tags`), NovelFire 1.2.0 (`div.categories a.property-item`,
  and the stray "Summary" heading stripped). Checked with the edited files dropped into the simulator's
  `Documents/Extensions`: both novels show chips and save them. **DEPLOYED by Martin the same day** (the permission
  system blocks `firebase deploy` from Claude); live check: index.json lists NovelFire 1.2.0 + WeTried 1.1.0 and both
  served files carry the genre code. Installed copies update through the normal extension update.
- **CloudKit — check before the next upload:** novels never had genres before, so the Production schema's `Novel`
  type may have no `genres` field (fields exist only for values that were non-nil once, S152). If it is missing,
  novel saves with genres are refused (they would show on the Sync screen, #204). The console was signed out, so
  this is NOT checked. A local EPUB with a genre was synced from the simulator in S152/S153, so it may exist.
- **Automatic backup on the phone (`039d5ed`):** More → Backup → "On This iPhone": Back Up Now, "Back up
  automatically" (default on; once a day when Yomi goes to the background, newest 8 kept), tap = restore (merge),
  swipe = delete. Files in `Application Support/Backups` (not Documents). Skipped while the library is empty.
  Checked: manual, automatic on Home, no second file the same day, restore → "Import complete", counts unchanged.
- **Dynamic Type (`56dade7`):** `YomiTokens.Font.grotesk/mono` (42 call sites, the last fixed-size text) now scale
  with the iPhone's text size, capped at 1.5×; unchanged at the default size. Library + Browse looked right at
  the largest standard size. Readers, detail screens and accessibility sizes NOT looked at; UI tests not run.
- **Found, not fixed — KNOWN_ISSUES #206:** two back buttons on a title opened from an active Library search.
- **CBR / RAR (Martin: "yes, add unrar"; research = RESEARCH §27 + §27.1):** Swift package `mtgto/Unrar.swift`
  0.5.4 (RARLAB UnRAR 7.23) added to the app target. New `Core/ComicArchive.swift` = one reader for ZIP and RAR,
  chosen by the file's first bytes; `LocalLibrary` (cover, pages, ComicInfo) uses it. New file type `com.yomi.cbr`
  in Info.plist (+ `com.rarlab.rar-archive` in the picker) — without it the picker greys the file out (S155
  lesson). Licence text: `licence-unrar.txt` (package MIT + RARLAB licence + acknowledgments, copied from the
  checkout; `build-licenses.sh` updated but NOT re-run in full) and a row in Open Source Licenses.
  **Checked (simulator, through the real Files picker):** a RAR4 file with stored pages, written by a scratch
  script and confirmed readable by macOS `bsdtar` → series + genres from its ComicInfo, cover, 5/5 pages in the
  reader; a ZIP renamed .cbr → imported with cover. Release build for iPhone compiles. Package's own 18 tests
  (compressed RAR4/RAR5, encrypted, multibyte names) pass on the Mac.
  **Checked later (S156, real files, simulator, real Files picker):** two public-domain CBRs from archive.org
  that Martin downloaded — `Illustrated Times #824 (1870)` = RAR4, compressed (method 0x33), 2 pages, 4.3 MB;
  `Illustrated Sporting News #0018 (1862)` = RAR5, 6 pages, 29.8 MB; both keep their pages inside a folder.
  "Imported 2 items", covers shown, all pages reach the reader (2/2 and 6/6), and all 8 extracted pages in
  `Caches/LocalPages` are byte-identical (md5) to what macOS `bsdtar` extracts.
  Correction: pages are NOT re-read from the archive one by one — `LocalLibrary` extracts the whole chapter
  into `Caches/LocalPages` once when it is opened (so solid archives cost one pass, and a 30 MB CBR takes
  30 MB more disk while cached).
  **Still NOT checked:** a solid archive, a very large one (hundreds of pages), a device, the licence row on
  screen, UI tests. Seen but not explained: in the RAR5 title a right-to-left swipe from page 1 showed pages
  2–3 stacked vertically; the RAR4 title behaved as plain Manga (RTL) paging.
- Also: one compiler warning removed (CFBypassView, redundant weak capture) — build is back to 0 warnings.
- **Per-extension settings (Mihon "source preferences"):** the extension server already had it
  (`preferencesManga` / `setPreferenceManga` on `POST /dalvik`; values kept by the bridge in
  `…/Tachidesk/settings/source_<id>.xml`, so no Yomi-side storage). Added `KeiyoushiPreference` +
  `KeiyoushiBridge.preferences` / `setPreference`, and `KeiyoushiSourceSettingsView` (switch, text, pick one,
  pick several) opened from a gear in `KeiyoushiBrowseView` — the gear shows only when the source has settings.
  Settings are per SOURCE id, so each language of a multi-language extension has its own.
  **Checked (Mac test server, the app's own model code compiled standalone):** Asura (1 switch) and MangaFire
  (1 pick-several + 4 switches) read, change, re-read and restore; Asura "Hide premium chapters" off → +1 chapter
  on 8 of 14 latest titles. Simulator build clean.
  **NOT checked:** the screen itself anywhere (Keiyoushi does not run in the simulator) → Martin on the TestFlight
  build; the "pick one" and text kinds (neither extension has one); settings are not in Yomi's backup; no entry
  from the Extensions list yet (Tachimanga has one there).
- **Not done:** CB7/7z.
- Simulator: Yomi data restored from `phone-backups/S156-sim-before-fresh` (163 titles); it now also has the two
  edited plugins installed by hand and iCloud signed out.
- CloudKit Production `Novel.genres` exists (STRING LIST) — read in the console after Martin signed in. No deploy needed.
- **NEXT:** ~~a real CBR from Martin~~ (done, see above) → per-extension settings with the phone
  connected → then step 3 (upload on his go, phone tests) and step 4 (listing).

---

## S155 — Tachimanga .tmb import (2026-10-13)

- **Why:** a TestFlight friend couldn't bring a Tachimanga library over — Tachimanga's .tachibk export is Premium,
  its free backup is `.tmb`, and Yomi's picker only offered `.tachibk` (the .tmb was greyed out).
- **Done:** the same "Import" row (More → Backup, and onboarding) now takes `.tmb` too.
  `TachiyomiBackupParser.parseTachimanga(at:)` reads `contents.zip → tachimanga.db` with GRDB: library titles,
  chapters that carry state, categories, history (seconds, per chapter), source names and the repository links
  (so the import sheet offers "Add" for Keiyoushi — a .tachibk from Tachimanga carries none). The preference
  plists (tracker logins) are never opened. File kind is told apart by magic bytes (PK vs gzip).
- **`ZipArchive`:** Tachimanga marks every entry ZIP64 (sizes 0xFFFFFFFF + extra field 0x0001) however small —
  the reader refused it ("too large (ZIP64)"). Per-entry ZIP64 sizes are now read; whole-archive ZIP64 still refused.
  Found only by running the real file through the picker in the simulator, not by the compile.
- **Verified (simulator, fresh DB, Martin's same-minute pair of 2026-10-08):** .tmb → 148 titles, 16,723 chapters
  (16,694 read), 5 categories, 137 category links; vs the .tachibk import: same 148 manga ids, same categories and
  links, 0 read-state differences on shared chapters, 3 unread stray chapters differ. The .tmb gives more read
  dates (143 titles with a last-read date vs 130). **Not yet on a device, and only one .tmb (Tachimanga v511) tried.**
- **Build 1.0 (515) uploaded** (`cbd130a`, 2026-10-13 12:08, "Upload succeeded", signatures verified). First build with
  the .tmb import, the 18+ switch move, iPhone-only and the new privacy link.
- **515 is in Friends; a friend imported his .tmb on his phone** (Martin, same day) — first device + second-backup proof.
- **Backup screen: one Import, one Export (Martin's request).** "Import Backup" was DEAD on device: two
  `.fileImporter`s on `BackupView`, only the last presents (the lesson OnboardingView already had in a comment).
  Now one picker for .json / .tachibk / .tmb — `BackupManager.importAnyBackup` tells them apart by first bytes —
  and Export is a menu: Yomi Backup · .tachibk. The Mihon / Tachiyomi / Tachimanga section is gone; onboarding has
  one "Import a Backup" card instead of two. No .tmb export: it is Tachimanga's whole database + extension jars.
  Simulator-checked: menu, Yomi export → share sheet, .json import ("Import complete"), .tachibk import (sheet).
  Onboarding card: compile only. **In no uploaded build yet.**
- **iCloud backup (More → Backup → iCloud) fails on every TestFlight build up to 515**: "The file doesn't exist."
  = `url(forUbiquityContainerIdentifier:)` nil. Roadmap check: S69 asked for the "iCloud Documents" capability and
  the feature was "not checked" ever since (no iCloud in sim / free-team builds). Both entitlements files listed only
  `CloudKit` under `icloud-services`. **Fix (`a150737`): `CloudDocuments` added to both**; the error row no longer
  replaces "Back Up Now" + the auto toggle; clearer message (`ICloudFolderError`). `--archive-only` build 518 signs,
  signature lists CloudDocuments + CloudKit. **Cause NOT proven** — needs a TestFlight build on Martin's phone.
- **Nothing after 515 is uploaded.** An upload of 518 was started and stopped on Martin's word before the export
  step (he wants to batch more work). Uploads need his explicit go each time.
- **NEXT (S156):** more work Martin has in mind → on his go, `scripts/build-testflight.sh` → he answers the
  encryption question → on HIS phone first: Back Up Now, restore from the list, the single Import row with a .json /
  .tachibk / .tmb, the Export menu, onboarding's one import card (compile-only so far) → then add the build to
  Friends. Still open from S154: listing approval, widget + trackers + two-device sync on TestFlight, screenshots.

---

## S154 — App Store listing drafted (2026-10-12)

- **Draft for Martin's approval: `Yomi/APP_STORE_LISTING.md`** — subtitle, promotional text, description, keywords,
  category, copyright, age rating answers (all 7 steps), Content Rights, App Review notes, competitor table, sources.
  **Nothing typed into App Store Connect**; every listing field there is still empty (read today).
- **Support page drafted: `Firebase/public/support.html`** (contact e-mail + FAQ). NOT deployed.
- Read live today: guidelines 1.2, 1.5, 2.3.x, 4.7.x, 5.2.2; Apple's age rating + field-limit help pages; the real
  age rating and Content Rights dialogs in App Store Connect (opened, cancelled); listings + recent reviews of
  Tachimanga, Paperback, Eclipse, Lipex, Suwatte, ArcReader, Panels.
- **Age rating proposal:** Unrestricted Web Access = Yes (the Cloudflare sheet has an address bar) → 16+, content
  lines like Eclipse, the two "graphic" lines = None (anything else = Unrated, not allowed on the store), then
  override to 18+.
- **Found — decide before submitting (listing doc §4):**
  1. The in-app "Show 18+ content" switch (Settings + Extensions). Guideline 1.2 allows mature content only when
     turned on "via your website"; Apple pulled Reddit clients over an in-app switch in 2016. 4.7.5 wants a
     declared-age gate. Code change, not done.
  2. Support + privacy pages share the host `yomi-plugins.web.app` with `index.json` (16 source plugins).
  3. The site's home page is still the Firebase placeholder.
  4. Content Rights is a yes/no declaration — Martin's call (lean: Yes).
- Not done: screenshots (plan in the doc), iPad layout check, the [CHECK] claims in the description (sync on two
  devices, read aloud on device, trackers, widget).
- **Martin's answers (same day) — done:** the 18+ switch stays but hidden → removed from the Extensions ⋯ menu and
  Settings → Privacy, now only in `RepositoriesView` ("Content" section), default off (unchanged). Simulator-checked
  (Privacy section without it; Repositories shows it, off). **App is iPhone-only now** (`TARGETED_DEVICE_FAMILY = 1`,
  all 6 configs; built Info.plist `UIDeviceFamily = [1]`); iPad and maybe iPhone Duo = a later update. iCloud sync
  stays in the description. Widget + trackers: to be tested on TestFlight before they are mentioned. Build 0
  warnings. Not on the phone, not uploaded. Remaining risk on the switch is written in the listing doc §4.1.
- **Martin asked Claude to research and decide points 2–4 — decided:** (2) separate neutral Firebase site
  `yomi-reader` (same project; home + support + privacy only; files in `Firebase/site/`, support.html moved there from
  `public/`); (3) Content Rights = Yes; (4) home page written. **Site NOT created, NOT deployed** — waiting for his go.
  Steps then: `firebase hosting:sites:create yomi-reader` → hosting targets in firebase.json/.firebaserc →
  `firebase deploy --only hosting:site` → check the three URLs → in-app Privacy link to the new host.
  Name `yomi-reader` looked free (404 on web.app) — only the create command proves it.
- Martin said yes to the site (name `yomi-reader`) and set the promotional text himself. `firebase hosting:sites:create`
  failed: credentials expired → he runs `firebase login --reauth`. Config is ready: `firebase.json` now has two hosting
  targets (`plugins` → public/, `site` → site/), `.firebaserc` maps them; old config in `firebase.json.before-S154`.
  **Deploy the plugin host with `firebase deploy --only hosting:plugins` from now on.**
- **2026-10-13: site LIVE.** After Martin's reauth: `yomi-reader` created, `firebase deploy --only hosting:site` →
  `https://yomi-reader.web.app/` , `/support`, `/privacy` all 200 (titles checked), unknown paths 404, no
  `index.json` there. Old `yomi-plugins.web.app/privacy` still 200 (TestFlight builds link to it). In-app Privacy
  Policy link → `yomi-reader.web.app/privacy` (MoreView; build 0 warnings; in no uploaded build yet).
- **Build 504 APPROVED by Beta App Review** (Martin's screenshot, 2026-10-13) — the Friends public link works now.
  Build 508: encryption answered, "Ready to Submit", not yet in Friends.
- **NEXT (S155):** Martin adds 508 to Friends (the + next to it) and sends friends the link → he reads/approves the
  listing draft → test widget + trackers + two-device sync on TestFlight → screenshots → type the listing into App
  Store Connect (Support `https://yomi-reader.web.app/support`, Privacy `https://yomi-reader.web.app/privacy`; the
  TestFlight Test Information still has the old privacy URL) → next upload carries the 18+ switch move, iPhone-only
  and the new privacy link.

---

## S153 — Sync fixes while build 504 waits for Beta App Review (2026-10-12)

- **#204 fixed** (`11bbc03` + this session's follow-up): a change iCloud refuses for good stays visible (More → Sync:
  "N items could not sync" + the server's reason), is sent again on the next launch and on Sync Now.
- **#205 found and fixed — more serious than #204:** records a device RECEIVED from iCloud had no cached change tag,
  so the first local edit came back as a conflict and the server copy overwrote it. Affects any second device and
  any reinstall. **Build 504 has it** → the next upload (505) should go to the Friends group before anyone relies on
  sync across two devices.
- **Verified against CloudKit** (simulator, development environment, Martin signed the simulator in again):
  fresh install → 18,060 records fetched, all with a cached record; note on a fetched title survives a sync (lost
  before the fix); forced rejection (`-yomiSyncRejectManga`) → row on the Sync screen, kept pending, retried on
  relaunch, goes through once the rejection stops. Build: 0 warnings. Probe note removed from the test record.
- Not verified: two real devices; a failed delete; Release build; nothing here is on the phone or in TestFlight.
- Simulator now holds a copy of the library from the development environment with sync ON (no longer the fresh
  install of S152).
- **Build 1.0 (508) uploaded** (`7a566e2` + docs; the number is the commit count, not 505), signatures verified,
  processing at Apple. Not added to Friends: Apple allows one build per version in review, 504 is still waiting.
  Internal group gets it automatically once Martin answers the encryption question.
- **NEXT:** Martin answers the encryption question on 508 → review result for 504 → add 508 to Friends → two-device test
  (simulator ↔ phone needs the phone on a development-environment build, or two TestFlight devices) → App Store
  listing forms.

---

## S152 — App Store Connect: build 493 into TestFlight (2026-10-11)

- **Build 1.0 (493) processed with no validation problem** (read on the TestFlight tab; the processing mail goes to
  the Apple ID address `tintin@…`, not the Gmail account Claude can read). `OpenJDKRuntime.framework` was not flagged.
- **Encryption question answered on the build** (Martin's declaration, saved in App Store Connect): "Standard
  encryption algorithms instead of, or in addition to, using or accessing the encryption within Apple's operating
  system" + distribution in France = **No**. Status went Missing Compliance → Ready to Submit, expires in 90 days.
  Every new build asks again until `ITSAppUsesNonExemptEncryption` is in Info.plist (not set yet).
- **Internal Testing group "Internal"** created (automatic distribution on — cannot be changed later), build 493
  attached, Martin added as the only tester → status Invited. He installs through the TestFlight app.
- App Store Connect → Business: Free Apps Agreement Active; Paid Apps Agreement "Pending User Info" (W-8BEN missing,
  no bank account). Only needed to charge money. Martin left the tax forms for later. W-8BEN notes: Part II (treaty)
  stays empty — Argentina is not on the IRS treaty list (irs.gov "tax treaties A to Z", read 2026-10-11); line 6a =
  CUIT/CUIL; he types the IDs and submits himself (cannot be edited after Submit).
- **Martin installed build 493 through TestFlight** (first TestFlight install) and reports the webtoon fix #203 "I
  think has worked" — soft confirmation.
- Correction: Claude said an `ITSAppUsesNonExemptEncryption` key would stop the per-build encryption question. Not
  verified — for the "standard algorithms outside Apple's OS" category the honest value is YES, and recall says YES
  without a compliance code still asks (Apple's doc page would not load to confirm). Key NOT added; the question
  takes two clicks per build.
- **CloudKit schema DEPLOYED TO PRODUCTION** (Martin clicked Deploy; verified in the console: 7 record types, Manga 22
  fields). Created by one development run in the simulator (iPhone 17 Pro 26.3 signed in to his iCloud, a copy of
  his library: 18,056 records). Found there: an empty `genres` list cannot initialise a new field → 4 novels rejected
  and dropped, sync still said success → fixed `4598c3c` (send nil when empty); the silent drop itself = KNOWN_ISSUES
  #204. `Manga.notes` never got created by data (a fetch right after the bootstrap overwrote the test note, then the
  second 18k bootstrap got rate-limited) → added by hand in the console (STRING, no indexes — sync never queries).
  Schema fields only exist for values that were non-nil at least once: after adding ANY synced field, check the
  console before deploying. Simulator Yomi then reset to a fresh install; its data is in
  `phone-backups/S152-sim-before-reset`. Development environment still holds the 18k test records (harmless).
- **#170 read against the live guidelines (2026-10-11):** 4.7 "You are responsible for all such software offered in
  your app", 5.2.2 permission from third-party services, 2.2 TestFlight builds must comply. Exposure: the welcome
  screen, Extensions empty state and Add Repository sheet link to the README (`kYomiSetupGuideURL`), which lists the
  three repository URLs with "1000+ manga sources"; More → GitHub / Report a Bug open the same page; the welcome
  cards name Mihon, Tachimanga, LNReader. Martin approved: links out of the README path, neutral card wording,
  review notes that present Yomi as a reader for own files + user-added repositories. Not yet done.
- Martin wants friends on TestFlight as soon as possible → external group + Beta App Review, after a new build with
  the genres fix and the #170 changes. Feedback email martin@gamberg.com.ar.
- **#170 done in the app (`d2b20c8`, build 502):** no link from the app to any page that lists repositories. "How
  to find repositories" → in-app "About repositories" (`RepositoryHelpView`, PluginsView.swift; sim-verified from
  the welcome screen); welcome cards / Add Repository footer / Suwayomi footer no longer name other apps or
  "1000+ sources"; About: GitHub row removed, Report a Bug = mailto martin@gamberg.com.ar with version + device.
  README: "Getting Started" (own files first, the three repository links with a responsibility note) — the README
  is where new users learn; friends get its link from Martin. Still naming other apps in the UI (not changed):
  Backup screen ("Mihon / Tachiyomi / Tachimanga"), Local Files footer, several "Keiyoushi" strings in Settings.
- **App Store wording of comparable apps (iTunes lookup API, US store, 2026-10-11):** Tachimanga, Lipex, Madomi,
  Eclipse describe ONLY local files (CBZ/EPUB) + Komga/self-hosted — no word about sources or extensions; Paperback:
  "Komga client … scripting API to extend the app"; Suwatte is the one that says it: "Install optional source
  plugins from lists you trust" + "does not include a content catalog or provide access to content. You are
  responsible for the files, services, and plugins you choose to use." All 17+ except Suwatte (12+); category
  Entertainment or Book. Aidoku: not found in the US store search.
- **Build 1.0 (502) uploaded** (genres fix + #170), verify-then-upload path of `build-testflight.sh` ran end to end.
- **TestFlight Test Information saved:** beta description, feedback + contact = martin@gamberg.com.ar, review notes
  (reader for own files; optional user-added repositories, none bundled or linked; HTTP only for self-hosted
  servers), privacy URL `https://yomi-plugins.web.app/privacy.html`.
- **Found: the in-app Privacy Policy link is dead** — `/privacy` returns 404, the page is `/privacy.html`; and the
  policy was stale (said data never leaves the device, said Yomi hosts plugins for third-party sites, contact =
  GitHub issues). Rewritten LOCALLY in `Firebase/public/privacy.html` (old one in `Firebase/privacy-2026-04-08.backup.html`)
  + `cleanUrls` in firebase.json so `/privacy` works. NOT DEPLOYED — needs Martin's OK. The site's home page is
  still the Firebase placeholder; a Support URL page is needed for the App Store listing.
- **Review-notes research (2026-10-12, live guideline text + web):** Guideline 2.3.1(a): "Don't include any hidden,
  dormant, or undocumented features… your app's functionality should be clear to end users and App Review. All new
  features… must be described with specificity in the Notes for Review… (generic descriptions will be rejected)";
  2.3.1(b): dishonesty = removal from the Developer Program. Intro "Before You Submit": "Include detailed
  explanations of non-obvious features… in the App Review notes" and give App Review everything needed to review.
  → the repository/extension feature MUST be named in the notes (leaving it out is the risky direction); a way to
  test with real content must be given (sample public-domain EPUB link). Approved "bring your own content" apps
  (IPTV players, Suwatte) state "does not provide content / users add their own" in their public listings — that
  sentence is the category convention, not a red flag. Not found anywhere: the actual notes any comparable app
  submitted, or a rejection report for Paperback/Tachimanga/Suwatte. Beta App Review is lighter than App Review.
- Martin made an app mailbox: **yomiappreader@gmail.com** — in Report a Bug (`f82c36a`) and the local privacy page.
  Firebase deploy FAILED: credentials expired (`firebase login --reauth`, Martin) — privacy page still the old one.
- **Privacy page DEPLOYED** (after Martin's `firebase login --reauth`): `https://yomi-plugins.web.app/privacy` → 200
  (cleanUrls), new text, contact yomiappreader@gmail.com. The in-app link works again for every build.
- **Build 1.0 (504) uploaded** (`f82c36a`, Report a Bug → yomiappreader@gmail.com), encryption answered (502 too).
- **SUBMITTED TO BETA APP REVIEW 2026-10-12:** external group **"Friends"**, build 504 = "Waiting for Review".
  Review notes as Martin approved (reader; CBZ/ZIP/EPUB + OPDS; extensions from a repository link, none included;
  how to test with a Project Gutenberg EPUB; no sign-in; HTTP for self-hosted servers), "Sign-in required" off,
  What to Test filled, feedback email = app mailbox, review contact = Martin's own (only Apple sees it).
  **Public link: https://testflight.apple.com/join/Jgz5CYRg** (limit 50) — testers cannot join until the build is
  approved. NOT tested: the Gutenberg EPUB named in the notes was never opened in Yomi (no download permission
  asked/answered); the Report a Bug mail row (needs a mail account).
- **NEXT (S153):** review result (App Store Connect → TestFlight → Friends, or mail to tintin@). If approved: Martin
  sends the link + the README link to friends. If rejected: read the Resolution Center message first. Then: App
  Store listing forms (age rating, description, support URL — site home page is still the Firebase placeholder,
  screenshots), #204 (silent sync drop), two-device sync test, `build-personal.sh` real entitlements, remaining
  other-app names in the UI (#170), W-8BEN/bank only if he wants paid features.

---

## S151 — Publishing path, step 2 (2026-10-11)

> **S152 starts here.** Build 1.0 (493) was uploaded 2026-10-11 and was still processing at session close.
> 1. Ask Martin for Apple's processing mail (any validation problem with `OpenJDKRuntime.framework` shows up there).
> 2. He answers the encryption question on the build (category in the submission checklist), makes an Internal
>    Testing group, installs through the TestFlight app.
> 3. His check of the webtoon reader fix (#203, on the phone, UNCONFIRMED — never reproduced).
> 4. CloudKit: one development run with the real entitlements so the schema exists → deploy to Production in
>    CloudKit Console (TestFlight builds use Production; sync does nothing there until then).
> 5. Switch `scripts/build-personal.sh` to the real entitlements (same team, now paid) — widget data + iCloud on device.
> 6. Before EXTERNAL testers: #170 (legal link), French encryption declaration research (ANSSI side), age rating 18+.
> Uploading needs the local "Apple Distribution: Martín Gamberg" certificate in this Mac's keychain; the new
> verify-then-upload path of `scripts/build-testflight.sh` has not run end to end yet. The notes below are in the
> order things happened — the early "Team ID not known" line is corrected further down (same ID, upgraded in place).

- **Apple confirmed the Developer Program membership** (welcome mail + "You now have access to App Store Connect",
  2026-10-11). Xcode on the Mac still lists only the free Personal Team `F9R33MN82P` — the paid Team ID is not known
  yet (Martin: developer.apple.com/account → Membership details, and refresh Xcode → Settings → Accounts).
- **Licence notices screen** — More → About → Open Source Licenses (`Features/More/LicensesView.swift`): App (GRDB,
  Kingfisher, Pulse in DEBUG only — it is not compiled into Release), Plugin runtime (cheerio + its 22 dependencies,
  Day.js, core-js), Reader fonts (4 × OFL), Mihon extension runtime (OpenJDK GPLv2+CPE with the source manifest,
  M-Extension-Server MPL-2.0 with the link to our patch, the libraries inside the server jar). Each row opens the full
  text (UITextView — the server-libraries file is 475 KB). Texts are in `Resources/Licenses`, collected by
  `scripts/build-licenses.sh` from the copies we build from (SwiftPM checkouts, node_modules, the jar, the JDK legal
  folder) — re-run it after any dependency change. Sim-verified (list, biggest text). Gaps → KNOWN_ISSUES #202.
- **Paid-team build**: `Config/TestFlight.xcconfig` (paid team + Keiyoushi embedded, real entitlements, no
  `YOMI_PERSONAL`) and `scripts/build-testflight.sh` (archive Release → upload; build number = commit count;
  `--archive-only` to check signing without uploading). **NOT RUN** — the Team ID placeholder is still in the xcconfig.
- Xcode rewrote `project.pbxproj` on open (reordered exceptions, "GRDB.swift" → "GRDB" comment); same content.
- Martin asked about the App Store "Xcode extensions" story: none needed (they are editor add-ons for typing code).
- Still open from S150: Martin's device check (Asura + MangaFire on the new jar, all-sources migrate).
- **Part 2 (same day).** Correction: there is NO new Team ID — Apple upgraded `F9R33MN82P` in place (Xcode now
  reports it as `Individual`, not free). It is in `TestFlight.xcconfig`. Martin: all-sources migrate device-checked ✅
  (moved several Aqua titles to other sources).
- First paid archive (`build-testflight.sh --archive-only`) **fails at signing**: Xcode issued new 1-year profiles
  with push/iCloud/App Groups enabled but EMPTY container and group lists — `xcodebuild -allowProvisioningUpdates`
  does not create `iCloud.pacodealer.Yomi` / `group.pacodealer.Yomi`. They must be registered once (Xcode →
  Signing & Capabilities, or developer.apple.com → Identifiers). Waiting on Martin.
- #202 closed: licence names checked against each project's LICENSE; missing texts + libffi in
  `scripts/third-party-licences/`, appended by `build-licenses.sh`.
- Runtime framework, static check: `Vendor/Keiyoushi` holds exactly one Mach-O (the framework binary, arm64, iOS
  platform, minos 15.0), no loose dylibs/executables, jars carry no native libraries. Nothing known to fail
  validation; only a real upload proves it.
- Export compliance (Apple help page read 2026-10-11, "Export compliance documentation for encryption"): Yomi's
  embedded OpenJDK does its own TLS, so the honest category is "industry standard algorithm, not provided within the
  Apple operating system" → needs a French encryption declaration ONLY if the app is distributed on the App Store in
  France; nothing to upload otherwise. Martin's declaration to make; `ITSAppUsesNonExemptEncryption` not set yet.
- Martin's field report: manhwa reader "skips a few pages, won't let me go up" → KNOWN_ISSUES #203, fix on phone
  (Release, paid profile — expires 2027-10-11, no more 7-day reinstalls), awaiting his check. App Store name "Yomi" is
  taken → he needs another listing name (the name under the icon stays Yomi). French encryption declaration: not
  researched yet beyond Apple's page — only matters for App Store distribution in France.
- Martin set the team + iCloud container + App Group in Xcode → **first paid archive SUCCEEDED** (build 492, 100 MB,
  real entitlements, Keiyoushi runtime inside, signature verifies). Not uploaded: the app record doesn't exist yet.
  French declaration + listing name written into the App Store submission checklist.
- App record created by Martin ("Yomi Manga and Novels Reader", non-trader for now). **Upload of build 493 REJECTED
  twice: "Invalid Signature. Code failed to satisfy specified code requirement(s)"** on app, widget and runtime.
  Root cause found by exporting locally: `codesign --verify` → "does not satisfy its designated Requirement". Xcode's
  cloud signing passes `--requirements … leaf[subject.CN] = "Apple Distribution: Martín Gamberg (F9R33MN82P)"`; the
  compiled requirement holds the **í decomposed** (`69 cc 81`) while the certificate's CN has it **precomposed**
  (`c3 ad`) → never matches. Triggered by the accent in the account name; nothing wrong with the app or the runtime.
- Martin created a local Apple Distribution certificate → local export verifies ("satisfies its Designated
  Requirement", CN bytes `c3 ad`) → **build 1.0 (493) UPLOADED to App Store Connect 2026-10-11** ("Upload succeeded",
  processing). `build-testflight.sh` now exports locally and verifies all three signatures before uploading (that
  path is written but not yet run end to end). Harmless warning: no dSYM for OpenJDKRuntime.framework.
- **NEXT:** wait for processing mail (it reports any validation problem with the runtime framework) → Martin answers
  the encryption question on the build → TestFlight → Internal Testing group → he installs via the TestFlight app.
  Then: CloudKit schema → Production (sync won't work in TestFlight before that); switch `build-personal.sh` to the
  real entitlements; reader fix #203 still awaits his check. #170 before EXTERNAL testers.

---

## S150 — Publishing path, step 1 (2026-10-10/11)

- Martin decided to enroll in the paid Apple Developer Program (individual) to give friends a TestFlight build.
  Live rules checked: internal testers ≤ 100 = users on his App Store Connect account; external ≤ 10,000 by
  email/public link, first build goes through TestFlight App Review; builds last 90 days.
- **NewPipe (GPLv3) is out of the extension-server jar.** `server/build.gradle.kts`: `compileOnly` in iOS mode, jsoup
  pinned to 1.22.2 (it came in through NewPipe; without the pin the jar fell back to 1.21.2). New jar vs old, file by
  file: removed = `org/schabi` (479), Rhino, nanojson, jsr305 — nothing left in the jar or in the two test extensions
  refers to them except the dead YouTube resolver; **all other 18k files byte-identical**. 47.9 → 45.8 MB.
  Mac run (java.base-only, `-Xint`): Asura and MangaFire popular → search → details → chapters → pages → first image OK.
  `stage-vendor.sh` now refuses a jar that contains `org/schabi`.
- New jar staged into `Vendor/Keiyoushi` and installed on the phone (Release, profile exp 2026-10-18 11:52 UTC; old jar
  kept at `Tools/keiyoushi-poc/MExtensionServer-with-newpipe.jar`). Keiyoushi on device with it: NOT yet checked by Martin.
- Martin on device: S149's ⋯ → Migrate options sheet works ✅.
- Martin's migrate feedback → done: **Skip removed** (a review row tap goes straight to the manual search; a title is
  either migrated to the suggested match or re-picked by hand) and **no picking sources** — every installed manga
  source except the title's own is searched, the match reaching the highest chapter is suggested (ties: first by
  name). Sources are asked in parallel per title, two titles at a time. Source-order list, "Most chapters" toggle and
  the `migrationTargetOrder` default are gone. Sim-verified with one target (Aqua → Asura plugin: options screen,
  review, row tap → manual search); the many-Keiyoushi-sources case (speed, picks) is device-only — unchecked.
  Novels: there is no novel migration at all yet (Migrate lists manga only; LNReader plugins are never targets).
- Source icons (Martin's screenshot): the coloured "border" was `SourceIconBadge`'s fallback gradient showing through
  the transparent margin of Mihon extension icons. Gradient + initials are now only the fallback (no icon / loading /
  failed); Keiyoushi rows pass `isMihonIcon` so the artwork is zoomed 1.2× to fill the badge. Sim screenshot checked.
  Browse → Migrate source rows show the same icons (`SourceStatus.icon`).
- Repo licence: Martin chose **all rights reserved** → `LICENSE` (MPL patch + third-party parts excepted); README said
  "MIT" since 2026-04-20, replaced. **Martin PAID the Developer Program (individual) on 2026-10-11** — waiting for
  Apple's confirmation.
- Phone has `4ab9ba6` (profile exp 2026-10-18 11:52 UTC).
- **NEXT (S151):** Martin's device check — Asura + MangaFire chapter on the new jar, all-sources migrate (speed, picks);
  licence notices screen (OpenJDK GPLv2+CPE, M-Extension-Server MPL-2.0 + our patch, bundled fonts/JS libs); once the
  enrollment is active:
  paid-team signing config with Keiyoushi embedded (today only `Personal.xcconfig` embeds it), CloudKit container,
  App Group, push, App Store Connect record, first upload. #170 before any EXTERNAL tester.

---

## S149 — Manga reader report #197–#200 (2026-10-09)

- #197 reinterpreted by Martin: page-to-page SLIDE like novel Pages mode (not chapter swipe). Taps animate; swipe was blocked by a 1x pan gesture on every page → pan only while zoomed.
- #200 pinch: tap-zone overlay swallowed all touches → zones computed from tap location; zoomed = pan, paging off, tap zooms out. Continuous/webtoon zoom still open.
- #198 Continuous RTL opened at the last page (RTL only on the stack, not the ScrollView). #199 continuous pages fit height only → fit screen.
- All sim-verified on the local "Test Hero" CBZ (tap, swipe, two-finger pinch, continuous RTL start). NOT on device yet.
- Device (Martin): paging slide + swipe and continuous ✅; asked zoom to anchor at the fingers → done. Then "fix 200 + all of 201":
  continuous/webtoon zoom (`ReaderZoom`), Tachimanga migrate options (sheet + Copy + Tracking via v26 `trackingTitle` + Remove downloads).
- Device round 2: webtoon zoom ✅, remove downloads ✅, Copy from the Migrate tab ✅ (phone DB 148→149 after adding Migrate / Copy buttons to the final dialog, `205b593`). Title page ⋯ had no Migrate entry → added (`0e3732d`).
- **NEXT (S150):** Martin checks ⋯ → Migrate → options sheet (Copy / Migrate) on device; then publishing path (S148 last bullet).

---

## S148 — Migrate by source (mass migration) (2026-10-09)

- Martin's request (S147 last bullet). Audit of the old one-title Migrate found real bugs: every carried chapter got
  `readAt = now` and the title's `lastReadAt = now` (all migrated titles would jump to the top of History and "Last
  Read"); no transaction; exact-number matching only; "remove old" deleted downloads; migrating into a saved title
  overwrote it; old entry stayed in History.
- Martin's picks: old entry leaves the Library but is kept (no delete, downloads kept); Mihon's read rule (everything
  ≤ highest read number); ordered target sources + review. Reference read live: Mihon `MigrateMangaUseCase`,
  `MigrationListViewModel`, `BaseSmartSearchEngine` (normalized Levenshtein ≥ 0.4, ported as `TitleMatch`).
- Built: Browse → Migrate = sources with title counts (missing first; "Keiyoushi"/"Plugin" label when two share a
  name) → titles (select some/all) → sheet: target sources in tap order (remembered) + "Most chapters" + carry over
  (read chapters, categories, custom cover, notes) → review (found / not found / skipped; tap = search by hand or
  skip) → migrate → summary. `MassMigration.swift` (engine), `MigrationService` rewritten (one transaction, merge,
  real dates), `MigrateView.swift` (screens + picker reused for detail-screen migration and pick mode).
- Also fixed: category counts counted titles outside the Library (`CategoryQueries.fetchItemCounts`).
- Sim-verified on a copy of Martin's real DB (Aqua Manga → Yomi's Asura JS plugin): 3 titles, read flags/dates,
  categories, History order, old entries intact. Found: Yomi's Asura JS plugin returns max 100 chapters (KNOWN_ISSUES).
- Tachimanga changelog v1.1→v5.1 re-checked against code: TACHIMANGA_PARITY.md "S148 re-check".
- Device: Release `d0d2a11` installed (exp 2026-10-16 14:28 UTC); phone DB backed up first
  (`phone-backups/S148-before-migrate`, quick_check ok, 148 library / 16,696 read). Martin's 2-title migration test
  pending (he left with the phone).

### S148 part C — local CBZ/EPUB (§25.10 #6)
- Martin's picks: EPUB = a NOVEL (TOC → chapters, novel reader with his typography/Pages/read-aloud); files come in
  two ways — Import (copied into `Documents/Local`) AND a linked Files folder; CBR/RAR skipped (KNOWN_ISSUES #195).
- Finding: iOS can only show an app's WHOLE Documents in Files, and Yomi keeps yomi.db there → no
  UIFileSharingEnabled. Instead the user links any folder once (security-scoped bookmark) — Mihon's "storage
  location" model; works for On My iPhone and iCloud Drive.
- Layout = Mihon's local source (live docs): series folder → CBZ/ZIP or image folder per chapter, cover.jpg;
  folders of series nest up to 3 levels; loose CBZs group by ComicInfo `<Series>` or file name. ComicInfo.xml gives
  number/title/summary/writer/genres.
- New: `Core/ZipArchive.swift` (no dependency — stored + deflate via Compression, memory-mapped; ZIP64/encrypted
  refused), `Features/Local/LocalLibrary.swift` (roots, scan, import, pages, `NovelContent`), `EpubBook.swift`
  (container → OPF → spine; nav.xhtml or toc.ncx titles; images inlined as data: URIs; scripts/styles stripped),
  `LocalSourceView.swift` (Browse → On This iPhone → Local Files). CBZ pages unpack once into Caches/LocalPages.
  Titles = normal rows, sourceId "local", straight into the Library; skipped by Updates, Downloads, Migrate.
  "Open in Yomi" for .cbz/.epub (CFBundleDocumentTypes + `com.yomi.cbz` UTI) → ContentView.onOpenURL imports.
  Never deletes: a missing file (offline iCloud) keeps its chapters/read state.
- Sim-verified with generated fixtures (CBZ deflate + stored + ComicInfo, image folders + cover, EPUB 3 nav +
  image + unlisted spine doc, EPUB 2 ncx + meta cover, a .cbr): link via real picker, bookmark survives relaunch,
  import via picker, CBZ/folder/EPUB reading, inline EPUB image in Pages mode, read state saved, Library/Continue.
  Bugs found while testing + fixed: picker mode lost on dismiss (Link imported instead), folder-of-series read as
  one series, Download pills shown for local titles. UI tests 12/13 + the 13th passes alone (#196).
  NOT verified: on device, iCloud Drive folder, a real-world EPUB/CBZ collection, large archives (memory/speed).
- **Device (end of S148):** Martin migrated AllManga → MangaFire ("The Fragrant Flower Blooms with Dignity") — DB
  copy vs morning backup: library 148 = 148, read through Ch. 203 carried with the ORIGINAL Oct 2 dates, category
  carried, old entry kept out of the Library with its 232 read chapters (`phone-backups/S148-after-migrate`, quick_check
  ok). Part C installed (`9955a0f`, exp 2026-10-16 14:28 UTC) — not yet tried by Martin.
- Martin's manga reader report → KNOWN_ISSUES #197–#200 (paged chapter swipe, continuous starts at the end,
  continuous over-zoomed, pinch-zoom dead everywhere). **NEXT SESSION starts there** (stability-first rule, S144).
- Privacy manifest: + File Timestamp reason 3B52.1 (user-picked files), checked against Apple's live definitions.
- Martin asked about publishing → see chat answer recorded in this entry's last bullet: blockers = paid Apple
  Developer Program, GPLv3 NewPipe in the extension-server jar, Keiyoushi (downloaded Java run on device) review
  risk vs 2.5.2/4.7, #170 legal pass, then the App Store checklist below (age rating, description, screenshots,
  support URL, ATS note). Suggested path: fix #197–#200 → legal/licence pass → paid account → TestFlight.

## S147 — Imports that work + first run that does the setup (§25.10 #6, #3) (2026-10-08)

- **Audit finding:** the `.tachibk` import existed but filed every source except MangaDex under a dead
  `tachiyomi_<id>` id — imported titles could never open or refresh. Keiyoushi runs the same Mihon extensions with
  the same source ids, so titles now come in as `keiyoushi_<id>` with the exact ids/paths the bridge makes
  (`edd3ca4`). Memo (Asura's slug, tachiyomix 1.6) re-attached the `BridgeMemo` way. Field numbers checked against
  Mihon's live `backup/models/*.kt`; manga categories are category ORDER values (Mihon's `MangaRestorer`).
- Import brings categories, real read dates (history), source names, repositories; merge never replaces and is
  idempotent. New import sheet: per source Ready ✓ / Add / Not found; repositories from the backup added only on tap.
- Martin's call on missing sources: keep them, make them movable → "Source missing" line in Library, a card on the
  detail screen (Add extension when a repo has it / Find on Another Source), listed first in Migrate. Migrate now
  searches Keiyoushi sources too (it only searched JS plugins) and is calm. Export: Keiyoushi titles keep their real
  Mihon id + memo.
- **First run** (`7d25b53`): one calm screen — import .tachibk / restore Yomi backup / add a repository / Skip for
  Now → Start Reading. Still no bundled or suggested repository (S140).
- Verified in the simulator only, with a synthetic Mihon backup built from real sim rows (Asura + MangaFire + a fake
  source): no duplicates (117/864 chapters unchanged), read flags + history dates, categories, extension install with
  only the needed language, repo add, card, Migrate list, re-import idempotent. NOT verified: opening/refreshing an
  imported Keiyoushi title and migrating to a Keiyoushi source (needs the device JVM); a real Tachimanga export —
  Martin is sending one.
- **Martin's real Tachimanga export** (148 titles, 16,724 chapters, 8 sources) found 3 bugs, fixed in `a13205d`:
  `favorite` absent = TRUE in Mihon (kotlinx omits defaults; Tachimanga never writes it) — all 148 would have
  landed outside the Library; exporter skipped false/unknown values the same way; Keiyoushi refresh never updated
  saved chapter paths (Tachimanga has no chapter memo, Asura's slug rotates) → `ChapterQueries.refreshPaths`.
  His .tachibk carries NO repositories → import sheet now offers "Add a Repository" at the top. Fresh-install sim
  run: 148/148 in library, 16,694 read, 5 categories, Keiyoushi repo → all 8 found → Add All → 148 ready.
- `.tmb` = zip(meta.json, contents.zip(tachimanga.db SQLite, extensions/*.jar, prefs incl. tracker plist — not
  opened, may hold tokens)). Extra over .tachibk: Repo table (Keiyoushi index.pb) + installed extension list.
- **Device** (Release `8d72de7`→`b511849`, exp 2026-10-14 20:46 UTC): Martin imported the .tachibk on his phone —
  sources work except Aqua Manga (site down). DB copied before/after: 148 library, 0 read chapters lost, 0
  duplicates, 5 categories / 137 links. Found + fixed on device: stale Sep 24 Keiyoushi index (#192, `8d72de7`).
  Migration v25 removed 106 dead pre-S147 `tachiyomi_` titles (12,759 chapters) — tested first on a copy of his DB
  in the sim (exact counts, 0 other changes), then on the phone (16,696 read chapters before = after).
  Phone DB copies: `~/Desktop/Projects/Yomi/phone-backups/S147-*` (first devicectl copy came out truncated at
  exactly 30,000,000 bytes — always `pragma quick_check` a copy).
- Not done: Tachimanga `.tmb` import (its .tachibk works), local CBZ/EPUB (part C).
- **Martin's request for next session (before part C): rework Browse → Migrate by SOURCE, not by title.** List
  sources (with title counts, missing sources first) → tap a source → its titles, pick some or all → migrate them
  to another source in one go (mass migration). No delete there. Reference: Mihon's Migrate (sources → titles →
  target) and Tachimanga's bulk migration (RESEARCH §24.2 "Done: bulk migration"). Current Migrate = one title at
  a time (`Features/Library/MigrateView.swift`, `MigrationService`). Old pre-S147
  `tachiyomi_` rows are left as they are (not in any library on the sim).

## S146 — More's sub-screens in the calm style (2026-10-08)

- Downloads, Categories, Insights, Trackers (+ MAL/AniList/Shikimori/Bangumi account screens), Backup, Sync →
  calm (RESEARCH §26): system nav bar (old glass back chips + `.toolbar(.hidden)` gone), `CalmList` +
  `CalmSectionHeader`, SF Pro semantic styles, no separators/cards/mono caps. One commit per screen
  (`eb0bed5` … `e817e29`). Simulator-verified only (screenshots shown to Martin before commit).
- Behaviour changes: delete = swipe → red trash on Downloads (was long-press menu), Categories (was system
  Delete), iCloud backups (was un-tinted swipe); Downloads "Delete All" in ⋯; Categories show item count or
  "Empty"; Insights numbers grouped by locale, activity grid full width (22 weeks); Bangumi row shows only its
  wordmark (it spells the name; the extra label broke alignment); tracker sign-in centred, "Sign In with …".
- Copy fixes: Sync said "the iCloud backup below" (it's in More → Backup); Backup export does NOT include settings
  (payload = categories, manga/novels, chapters, category links) — note says so.
- Not checked: iCloud backup list and Sync status rows (sim has no iCloud; free-team phone build has no iCloud
  either). Downloads "Downloading" section not exercised (no active download in the sim).
- Martin's order after this: first-run + imports (#3, #6) → legal last (incl. #170).

## S145 — Asura black pages, voices, tags (2026-10-07)

- Martin's device check of S144: Continue ✅, chapter numbers ✅, menu taps ✅, novel hold-to-select ✅, novel detail
  speed ✅. **Asura pages still broken** — not only after background: page 1 then BLACK below, no spinner/Retry.
- Root cause (device logs, `devicectl --console` + temporary NSLog in `StripPageImage`): the Asura extension returns
  each part as one **900×16000** image → 402×7147 pt cell, 21,000+ px — too tall for the GPU, renders black. Pages
  downloaded fine (1–3 s). Fix: cut pages taller than 4096 px into 2048 px strips (KNOWN_ISSUES #190). First try used
  KFImage `onSuccess` — black again intermittently; now `StripPageImage` loads via `KingfisherManager` itself.
  Martin on device: all pages load. He asked: no pinch-zoom in vertical mode (never existed — only paged).
  **Backlog (Martin chose backlog over fix):** pinch-zoom in vertical/webtoon mode (whole strip zooms while
  scrolling, like Mihon/Tachimanga; must not fight tap-menu, edge swipe-back, long-press autoscroll). Wrong turns, in order: Kingfisher 15 s timeout queue (JVM thread dump = idle), missing
  genres → paged mode (DB has "Manhwa"), black images (luma logged 130–230). Lesson: the S144 probe tested
  DOWNLOADS, never DISPLAY.
- TTS "robotic": free fix = iOS Premium/Enhanced voices (Settings → Accessibility → Spoken Content → Voices);
  Yomi already picks the best installed voice and has a picker. Neural voices (sherpa-onnx) stay in backlog.
- Correction to the S144 tags note: Keiyoushi manga DO have genres (114/115 rows on his phone); the gap is
  **novels** (`SourceNovel` drops LNReader `genres`).
- **Device perf (Release, iPhone 17), `perf-traces/s145-*`:** run 1 novel detail ×3 (long list, scroll, back):
  0 hangs, 20 hitches / 338 ms, worst 67 ms; saved list shows at once, source refresh 1.7–8.7 s behind it. Run 2
  Browse → Asura (Keiyoushi), scroll, open 2 non-library titles: 0 hangs, 12 hitches / 142 ms, worst 17 ms;
  OpenManga 0.7–1.0 s, Keiyoushi list pages 0.17–0.62 s. Tooling: Xcode 27 xctrace can't `--attach` (pid or
  name) → record.sh now tries `--all-processes` first.
- Phone: Release (S145 fix) installed, profile expires **2026-10-14 20:46 UTC**.

## S144 — Daily-driver pass: Martin's field report (2026-10-06)

- Listening settings UI (`c1b756c`): Settings → Novels → Listening = speed presets (same as the player), voice,
  highlight, continue into next chapter, play over other audio; a chosen voice only reads novels in its language.
- **Martin's rule (S144): no new features until everything works perfectly.** He read RTOC daily + tried Asura
  manhwa; reported: novel menu still opens on small scrolls, lost progress (Continue showed ~730 while he was at
  ~758), Asura chapters show page 1 and nothing else even on good Wi-Fi, app laggy (series detail), hold-to-select
  missing on novels; asked: keep each series' filter/sort. All fixed (`4a43858`, `bc31846`), KNOWN_ISSUES 181–189.
- **Lost progress — root cause on HIS data** (pulled the phone DB): an Author's Q&A (734.5) left at 85 % (under the
  90 % mark) stayed unread; every Continue used "first unread chapter with any progress". My first theory
  (duplicate chapter ids from two id schemes) was WRONG for his phone — 0 duplicates — but is a real latent bug,
  fixed too (#187). New rule `ResumeReading.chapter(in:)`: after the end of the RUN of read chapters (a lone read
  of the newest chapter = a peek, e.g. Bad Born Blood 102 with chapter 1 at 13 %). 12 standalone cases pass.
- **Keiyoushi chapter numbers**: all 9 Keiyoushi titles had 0 numbers (source -1, Mihon parses names) → port of
  Mihon's `ChapterRecognition` + migration v24 (516 rows; parser reproduces 19,014/19,034 known numbers).
- **Asura pages**: background → bridge restarts on a new port; page URLs kept the old one. DEBUG
  `-keiyoushiPageProbe` on device: 0/20 after a pause before, 40/40 after (live-port rewrite + resume on
  foreground + `PageRetry`). Throughput ~1 page/s = the Asura extension's own `rateLimit(2, 2.seconds)`.
- Menu: tap must be < 300 ms (UI test failed 2/2 before, passes after). Novel rows: Button swallowed long press.
  Filter/order/sort per series (`ChapterListPrefs`). Spanish grouping ("Chapter 1.175", "1.432").
- Lag: simulator trace of Lord of the Mysteries (1,432 rows): hangs 1,717/754/371/268 ms → one 414 ms. Novel
  list = window around Continue (−30/+70, Show 100 more). **Not measured on device yet.**
- Phone: Release `bc31846` installed, profile expires **2026-10-13 13:12 UTC**; DB compared before/after: same
  rows and read marks, 516 → 0 missing numbers.
- Answered: premium chapters — the Asura extension has "Hide premium chapters" (default ON); Yomi has no screen
  for an extension's own settings (Mihon source preferences). Backlog: per-extension Settings screen (also lets
  logged-in premium users turn it off). Martin: Tachimanga has this (premium on/off per source) — use it as the reference.
- Backlog (Martin, from Tachimanga screenshots; S145: manga have them, NOVELS are the gap): genre/tag chips on detail ("Drama · Fantasy · Manhwa"). They come
  from the SOURCE (Mihon `SManga.genre`, LNReader `genres`), not the app. Yomi already HAS the chips
  (`MangaDetailView` synopsisSection, `NovelDetailView` ~587) — the gap is data: `SourceNovel` has no `genres`
  field, so LNReader novels never get tags; JS-plugin manga only if the plugin returns `genres[]`; Keiyoushi fills
  them only when empty (`KeiyoushiMapping.genres`). Check his phone DB for which titles have `genres = '[]'` first.
- **Next:** Martin's device check of the six fixes; then measure detail/Browse lag on device (Release) and
  manga detail with huge lists (One Piece 2,440 via Keiyoushi isn't in his library).

## S143 — Read-aloud rebuilt (TTS, §25.10 #8) (2026-10-04)

- Research (live sources): background audio is allowed (Guideline 2.5.4 "audio playback"); Now Playing with plain
  `AVSpeechSynthesizer` is reported flaky (Apple forums 2021) — fallback is `write(_:toBufferCallback:)` + an audio
  player; iOS 26 renamed the voices pane to Settings → Accessibility → Read & Speak → Voices.
- Martin: listening keeps playing outside the reader (Apple Music style); other apps' audio pauses by default
  **with a setting to mix** ("customization is key").
- Built (`7021686`, sim-verified, UI tests 12/12, 0 warnings): `ListenPlayer` (app-wide; sentences via NLTokenizer,
  one utterance each; next chapter prepared halfway + announced; progress by characters; reading time; Now
  Playing + remote commands; interruptions; `audio` background mode), sentence highlight + follow in scroll and
  pages, start at first visible sentence, "Listen from Here" in the selection menu (instead of tap-a-paragraph),
  mini-player in the reader and in the tab bar accessory, full player (speed presets from a measured curve,
  voice, sleep timer, Open in reader).
- **Not verified:** lock screen / Control Center / AirPods / screen-locked playback (device only — Martin doesn't
  use TTS now, no install requested).
- **Next:** Settings → Novels → Listening UI for the new settings (`ttsVoiceId`, `ttsHighlight`,
  `ttsAutoAdvance`, `ttsMixWithOthers` — saved in code, no switches yet; replace the old speed slider), then
  More's old sub-screens in the calm style, then first-run + imports (#3, #6).
- Answered (chat): Aidoku/Paperback sources — possible, not now. Paperback is closer (JS; Yomi's S24 0.8 shim is
  stale, ecosystem moved to 0.9, ~1–2 sessions); Aidoku needs a WASM runtime + 8 host-import modules, app is GPL-3
  (~3–4 sessions). Both manga-only and mostly overlap Keiyoushi.
- Martin is pausing a few days for exams (30 % of the weekly limit used on day one).

## S142 — Keiyoushi titles in Updates + Updates Summary (2026-10-03)

- **#174 fixed** (Martin on device: "worked perfectly and quick too"): refresh checks Keiyoushi manga via
  `KeiyoushiBridge.chapters` (same mapping/insert/`markFetched` as MangaDetailView/JS path), skip settings +
  excluded categories kept (now evaluated once, off-main). Cost: Keiyoushi pool of 3, each extension's first
  title alone (loads the APK); plugins pool of 6. Progress row "Checking n of N"; afterwards "Checked N titles ·
  time · k failed ›" → **Updates Summary** sheet (Failed + reason, Retry Failed; Completed + new counts).
- Baseline rule: a title with no saved chapters, or whose every chapter id changed at once, saves chapters but
  doesn't stamp `fetchedAt` (no 800-row "new" floods). BGAppRefreshTask skips Keiyoushi (JVM in ~30 s window).
- Device check: pulled DB before/after — v23 column now present, 0 fetchedAt, chapter counts unchanged
  (no new chapters upstream). A real new chapter on device not yet observed.
- Fixed 4 warnings left by S141 (UpdateFeedEntry.chapterNumber, PluginCatalogEntry.withInstallIds, NovelQueries).
- Phone: S142 build, profile expires 2026-10-10 17:45 UTC.
- **More + About calm** (`c21b79a`): plain rows, accent icons, no cards/separators.
- **Settings calm + audit** (Martin: "thorough check without taking anything for granted"). Shared `CalmList`
  (grouped style — plain pinned the bold headers over rows; row modifiers on the List itself don't reach rows,
  so they go through a Group) + `CalmSectionHeader` / `Section(calm:)`. Regrouped: Appearance · Reading ·
  Library · Downloads · Updates · Notifications · Sources · Privacy · General. Appearance redone: theme
  Automatic (new, default for fresh installs — Martin) / Dark / Black / Light / Sepia, accent, real app-icon
  previews; preview card, accent blend slider, wrong "AAA" badge (4.5:1 ≠ AAA) and duplicate typography/library
  controls removed; OLED switch removed (= Black). Audit fixes: notification permission only asked on adding a
  MANGA (novel readers never asked) → asked on toggle + novel add, iOS-Settings link when denied; no
  NSFaceIDUsageDescription (Apple: "won't allow your app to use Face ID") → added, App Lock verifies once before
  turning on (no passcode = locked out); Settings → Novels duplicated the reader panel with different steps →
  now layout/reading/offline/listening only; keep-screen-on now covers novels; TTS "0.5×" was normal speed;
  rotation applied only on next rotation; "Clear plugin catalog cache" did nothing → reloads; Storage missed
  NovelDownloads + Keiyoushi; dead `useSystemFont`, `pureBlack`, `colorBlendLevel` removed. Time/Date default
  "Like iPhone" (Martin), old explicit choice kept. Suwayomi moved to Advanced (Martin). UI tests 12/12.
- **Keiyoushi chapter downloads** (Martin: "critical"): the queue required a JS plugin (`JSBridge`), so every
  Keiyoushi title had a disabled Download pill. Now `DownloadManager.canDownload` + pages via
  `ChapterReaderView.fetchPages` (the JVM serves descrambled 127.0.0.1 image URLs; needs Yomi open).
- **Mihon repositories** (Martin: "users should use whatever they want"): Yomi held ONE Mihon repo
  (`keiyoushiRepoURL`, adding a second replaced it) and read only `index.pb`. Now `mihonRepoURLs` (migrated),
  `KeiyoushiRepository.repos`, both `index.pb` and classic `index.min.json` (checked live: Suwayomi's and
  Kavita's repos still use JSON; Keiyoushi's JSON is an "Outdated App" stub), folder links tried as
  index.pb then index.min.json. Sim: Keiyoushi kept + Kavita added from a folder link (1 extension).

- **Device check (Martin):** Keiyoushi download + offline read ✅, Kavita repo from folder link ✅, App Lock
  (Face ID) ✅, Automatic theme ✅. Notification prompt not observed (his toggle was already on, permission
  likely granted earlier) — re-check on a fresh install.

### Backlog added S142 (Martin approved all)
- Dynamic Type in app chrome (RESEARCH §25.9 #1, §25.10 #4).
- Scheduled automatic local backups + sync status (§25.10 #5).
- Lockable SFW mode (§25.13 ranking #5).
- Reader auto-dark at night (§25.3 #9).
- Separate manga tap zones for paged vs long strip (Tachimanga v5, §25.10 #7).
- Spanish localization (§25.9 #4).

## S141 — device check, Continue/History/Updates fixes + calm pass (2026-10-03)

Martin's order: reinstall + verify #167 on device → #165 → #166 → screens. Phone reinstalled (profile exp
2026-10-10 17:45 UTC). Commits `b68f47f`, `3759c66`, `4b6a354`.

- **#167 on device:** the S140 fix didn't reach his phone's case — his WeTried was installed by link as
  "WeTried TLs" (id sha256(file URL)), the catalog says "WeTried Translations" (`com.yomi.wetriedtls`), so
  id-or-name matching never offered Update and listed it under Available as "Add" (would have installed a
  duplicate). `PluginCatalogEntry.installIds` (catalog id, sha256(file URL/file name), com.yomi.<name>),
  computed once at catalog load. First version computed them per lookup → Extensions froze (sharedNames was
  rebuilt per row × every group × hashing); now once per render. Verified on device: 1.0.2, same id, 1 row.
- **Method that worked:** copy the device's Documents + catalog prefs into the simulator container and
  reproduce there (`devicectl device copy from … --source Documents`, `defaults write … -data <hex>`).
- **#165** Continue shelf = last manga + last novel; fixed-height cells; novel without saved chapters opens
  its detail page (tap did nothing). `ResumeReading` (in ContinueReadingRow.swift) = one resume path for the
  shelf and History (Keiyoushi manga with bridge nil; one-translation-per-chapter like the detail page).
- **#166** History: NovelDetailView upserted its whole stale `Novel` (metadata refresh, touchLastReadAt,
  cover, library toggle) → rewound `lastReadAt` behind chapters read since (RTOC sat at Oct 2 15:07).
  Column-only writes now. Martin: **only reading counts** → MangaDetailView no longer touches lastReadAt on
  open. History tap = straight into the last chapter + page (Martin). Calm rows: 64 pt cover, 2-line title,
  "Chapter 722 · 30%", "15h 13m read · 19:20"; swipe → "Remove"; no separators (Martin).
- **Updates (Martin sent Tachimanga screenshots):** one row per NEW chapter, tap = read it, read ones
  dimmed, swipe → Mark Read. Needed a fetch date: migration **`v23_chapter_fetched_at`** (chapter /
  novel_chapter.fetchedAt, set only by the refresh, kept out of the model structs). Starts empty after
  install, fills on refresh. The old feed listed every unread chapter of a recently updated title ("481 new").
- **Reader bug:** leaving a manga chapter whose pages never loaded saved page 0 over the real position.
- **Open (next session):** Keiyoushi titles are NOT checked by Updates refresh (all of Martin's manga) —
  Martin approved adding it with a Tachimanga-style Completed/Failed summary; then More → Settings screens.

## S140 — Extensions redesign + plugin update bug (2026-10-03)

Martin's rules for Extensions (asked this session): **every repository needs a link** — fresh installs start with
none and Yomi suggests none; once a repository is added, **every extension in it is one tap ("Add")**; delete =
**swipe → red trash**, for installed extensions and for repositories (not the Sources tab). The onboarding links
to the GitHub guide "if this respects the rules" → logged as a legal-pass question (KNOWN_ISSUES #170).
Mid-session he asked to check whether updating extensions works — it didn't (#167).

Built (simulator-verified on iPhone 17 Pro 26.3, **not on his phone yet**):
- **Browse → Extensions** rewritten (`PluginsView.swift`): search, **Updates** (only when any, Update All),
  **Installed** (count), **Available** (language menu in the title row). App Store-style rows: 44 pt icon, name,
  one grey line ("English · Novels", "2 of 7 languages · Manga", "Version 1.0.2" on updates, repository name
  only when two rows share a name), one grey pill with accent text (Add / Update / globe for languages). No
  format tags, no versions. Section titles scroll with the rows (pinned plain-list headers drew over them).
  Toolbar = one ⋯ menu: Add Repository, Repositories, Add Extension from Link, Show 18+ Extensions.
- **Repositories** (`RepositoriesView`): in ⋯ and in **Settings → Sources & Servers → Repositories** (replaces
  the old URL list there); name + extension count + link, swipe → red trash, Copy Link in the context menu.
  `AddRepoSheet` = paste field + "How to find repositories" (README); no featured repos.
- **No repository** = empty state (Add Repository pill + guide link) under the still-listed installed ones.
- Fresh installs: `pluginCatalogURLs` defaults to `[]` (was the Yomi catalog). S104's `instantInstallSourceIDs`
  allowlist and Copy-URL rows removed.
- **Browse → Sources** + tab strip in the calm style: SF Pro, Library-style section titles ("Last Used",
  "Manga 5"), 44 pt icons, "English · Manga · Keiyoushi". `SourceIconBadge` no longer widens on non-square icons.
- Onboarding: "Add a Repository" page with the guide link; stale "More → Plugins" copy fixed (onboarding, search).
- Repository names: GitHub-hosted repos are named by owner (`repoLabel`) — the phone's "github.com" row.
- Catalog `kind` ("manga"/"novel") decoded; added to `Firebase/public/index.json` and deployed (#169).
- **Update bug (#167)** fixed: update in place under the installed id + same-name copy cleanup +
  `relinkOrphanedTitles`. Also #168 (same name in two repos merged). Keiyoushi updates were already correct
  (replace by package name; not runnable on the sim).
- UI tests 8/12 — the 4 Pages tests of #164, same as before.

NEXT: reinstall on his phone (`build-personal.sh --release`; S138 profile expires ~Oct 9) and check that his
WeTried titles survive the update + relink; then #165 Continue shelf →
#166 History → remaining screens → TTS.

## S139 — MangaDetailView in the calm style (2026-10-03)

Martin used the S138 calm build on his iPhone: "looks and feels much better". Two non-design notes, logged as
**KNOWN_ISSUES #165** (Continue reading shelf should hold only the latest title — or two: last novel + last
manga/manhwa) and **#166** (History tab "doesn't work well" — get specifics first). He approved the result from
simulator screenshots ("looks great").

Built (simulator-verified on iPhone 17 Pro 26.3, **not on his phone yet**):
- **MangaDetailView** = NovelDetailView's structure: album header (200 pt cover, cover-blur tint, title, source
  in accent, "author · status · N chapters · score"), Continue / Download pills (`detailPillLabel()` now shared;
  Download disabled without a JSBridge, i.e. Keiyoushi/Suwayomi), status/categories/note/cover/select/mark-all in
  ⋯, note only when one exists, 3-line synopsis + genre chips, plain "Chapters · x of y read" row with one
  filter/sort/order menu, calm scanlator chips, chapter rows = name + one grey detail ("Page 2 · group · Read 2
  days ago") + accent unread dot, glass select bar, scroll title bar. All loading/merge/scanlator logic untouched;
  the visible list and the select toolbar now share one `displayedChapters`.
- Removed from manga Detail: progress bar + reading-time line, header status chip, per-row download button
  (leading swipe / select bar instead), duplicate "Remove from library" in ⋯.
- Both details: select mode hides the back button and the tab bar (Tachimanga), `.scrollDismissesKeyboard`,
  title-bar threshold 470 → 410 (pills could rest under the floating buttons).
- `Notation.chapterTitle` ("Ch. 31" → "Chapter 31", real titles kept) and `Notation.plainText` (HTML entities —
  Asura synopses had `&lt;`); Continue shelf's `shortChapter` uses Notation too.
- Fixed 3 pre-existing "no calls to throwing functions" warnings in `KeiyoushiBridge` (popular/latest/search).
- UI tests 9/12; failures all in #164's set, and one #164 test passed this run (flaky).

NEXT: Extensions redesign (repos into Settings, one source list, no format tags, App Store-style rows — RESEARCH
§26 mockup) → #165 Continue shelf → #166 History → rest of the screens → TTS. Reinstall on his phone before the
profile expires (Oct 9 06:46 per S135; `build-personal.sh` prints the real date).

## S138 — Design direction: "calm" (Apple Music-inspired) — Library + novel Detail built (2026-10-03)

Martin rejected three first directions (A Native, B Shelf, C Dense — "A and C are the best but I don't really
like them"), asked for research (Mobbin, DesignRush, reading apps, a middle ground on customization) and clarified
he likes **Apple Music's design system** — colour, seamlessness, spacing between titles and artwork, how it works
together — not its features. Research → RESEARCH §26. An HTML mockup with his real covers ("Yomi calm") was
approved: "Looks good, we should try it out." He sent Tachimanga's detail + select-mode screenshots as the
feature reference; he doesn't love the Library/Browse tab icons (easy change, not done).

Built (simulator-verified on iPhone 17 Pro 26.3, **not yet on his phone**):
- **App-wide:** `YomiTokens.Font.grotesk/mono` now return SF Pro (Space Grotesk/Mono gone everywhere; the
  Appearance "UI font" picker removed); `Notation` is plain sentence case ("Chapter 42", "Ongoing", "12h 40m",
  "Jul 28" — no "CH. 042", "STATUS // …", "◷"); Ink = Apple system dark (black, #1C1C1E), Paper = system light;
  cover radius 6, side margin 20, `coverHairline()` 0.5 pt outline.
- **Library:** large title back (category chips moved into the scroll), chip-style categories, "Continue
  reading" shelf (150 pt covers, "Chapter 25 · 3%", thin progress bar) replaces the hero card + "Up next";
  section titles title2-bold; covers carry nothing — title + one grey line under ("902 unread" in accent, or
  source, or "In library" in Browse). Fixes the hero's "CH. 000" (novel chapters have no number) and the shelf
  showing the prologue instead of the resume chapter.
- **Novel Detail:** album-page header (200 pt cover, cover-blur tint under the status bar, title, source in
  accent, "author · status · N chapters"), equal Continue / Download pills, 3-line synopsis + genre chips, notes
  only when one exists (add via ⋯), reading status + note in the ⋯ menu, chapter rows with accent unread dot and
  "Reading · 40%", filter/sort in one menu, select-mode bar as a floating glass capsule, title bar that fades in
  after scrolling past the header.
- Not done: **MangaDetailView** (still old style), Browse/Sources, Extensions redesign, History/Updates/More,
  Dynamic Type (`grotesk(size)` is still fixed-size), Library list mode rows, tab icons.
- UI tests 8/12 — the 4 Pages-mode tests also fail on unmodified HEAD (Known Issue #164).

NEXT: Martin reviews on device (reinstall before the profile expires Oct 9 06:46) → MangaDetailView in the same
style → Extensions redesign (agreed: repos into Settings, one list, no format tags — App Store-style rows) → the
rest of the screens → TTS.

## S137 — Workflow research + tooling cleanup (2026-10-03)

Martin now reads light novels in Yomi daily (WeTried plugin). He asked for research on AI app development
(tools, tricks, what we missed), design (Claude Design?), and why Extensions still feel disorganized
(four repositories: Yomi, "github.com", LNReader, Keiyoushi). Agreed order: workflow fixes → design
direction → Extensions redesign → TTS → first-run + imports → legal compliance last.

Done this session:
- **CLAUDE.md 273 KB / 1,490 lines → ~8 KB / 118 lines.** Anthropic's guidance is under 200 lines; the old
  file (~68k tokens) loaded every session. Known Issues table moved verbatim to `Yomi/KNOWN_ISSUES.md`
  (open rows listed at its top); all "Prior state" blocks + design-track note appended verbatim to
  `Yomi/HISTORY.md`; MCP/tooling/key-path sections copied to `.claude/skills/yomi-sim/TOOLING-NOTES.md`.
  New path-scoped rules: `.claude/rules/grdb.md`, `.claude/rules/plugins.md`. Session close now says to
  *replace* "Current state", not append.
- **XcodeBuildMCP**: `XCODEBUILDMCP_ENABLED_WORKFLOWS=simulator,simulator-management,ui-automation,device,
  debugging,project-discovery,utilities,coverage` in user config (`~/.claude.json`). ui-automation was off,
  which is the root of the mobile-mcp tap/swipe workarounds since S109 (#49).
- **Apple Xcode MCP** added (`claude mcp add --transport stdio xcode -s user -- xcrun mcpbridge`): RenderPreview,
  live diagnostics, DocumentationSearch. Needs Xcode open; takes effect after a Claude Code restart.

Findings, not acted on yet:
- "github.com" repository = `PluginCatalogService.repoLabel` host fallback for an unrecognised catalog URL
  (phone not connected — actual URL unknown). Mihon/Aidoku keep repositories in Settings and show one source
  list filtered by language; Yomi shows repos inline + "· YOMI PLUGIN / · KEIYOUSHI" tags.
- Claude Design (Anthropic Labs, beta): use for 2–3 side-by-side directions of Library/Detail/Extensions from
  real references — not to regenerate all 16 screens (feeding it the codebase re-extracts the Space Grotesk look).
- Candidates: Paul Hudson / Antoine van der Lee SwiftUI agent skills (audit before installing), snapshot tests,
  $99 Developer Program as a workflow fix (TestFlight, no 7-day expiry).

## S136 — Batch step 6 done + typography pass (2026-10-02)

**Step 6 (perf):** runs 2–5 re-measured on the iPhone 17 (RESEARCH §23.6). Fixed what they found: `d15f611` cover
disk-cache reads off main; `2fe17c7` reader pages keep original bytes in Kingfisher's cache (it re-encoded WebP as
PNG) + background decode, and NovelDetailView's chapter rows became an Equatable `NovelChapterList` (reader push
re-diffed ~880 rows). **Runs 1–5 now have 0 hangs.** Open: Keiyoushi reader pages still via the JVM proxy.

**§25.10 #1 typography pass (`bcb95d4`, `747e08f`), on Martin's phone:**
- Fonts: Apple faces (System, New York, Georgia, Charter, Iowan, Palatino — only installed ones listed) + bundled
  OFL Literata, Newsreader, Atkinson Hyperlegible Next, OpenDyslexic (732 KB WOFF2, `scripts/build-reader-fonts.sh`),
  served to the web view as `yomi-font://` (`Features/Reader/ReaderFonts.swift`). "Serif"/"System" migrate.
- Paragraph + letter spacing, size 12–40 with readout, ~36em column cap, hyphenation when justified (`<html lang>`
  from the source — **Martin confirmed hyphens on device**), fresh installs start at the Dynamic Type body size.
- **Reader panel redesigned (Martin's pick): nav + progress on top, then Text · Look · Reading tabs.** Reading tab =
  infinite scroll / swipe / menu taps (same settings as Settings → Novels). Martin: tall on Text but fine.
- Martin caught: the menu followed the **app** theme (root `.preferredColorScheme` wins); now the overlay gets the
  reader theme's colorScheme, selected pills solid black/white.
- UI tests 7/7 (new: Text tab font pick). Not checked: iPad column cap.

**§25.10 #2 Pages mode (`bcd50c6`) — Martin on device: "works amazing", no cut lines/gaps, page info fine.**
- Reading tab → Layout Scroll | Pages. CSS columns (one screen each) + `scrollView.isPagingEnabled` = slide that
  follows the finger. Taps: left 30 % / right 30 % turn, middle = menu. Left-edge swipe = back (web view pan
  requires the nav edge recognizer to fail); chapter-swipe setting hidden in Pages; pinch off.
- "Continue into next chapter" (own setting `novelPagesContinue`, Martin's call) — off ends on a Next chapter page.
- Chapter name top + "p / n" bottom drawn natively; size/style/mode changes keep the place (chapter + percent).
- One JS controller for both layouts. UI tests 12/12 (5 new). Next: §25.10 #8 TTS (sentence highlight + auto-advance).

## S133 — Batch step 4: novel reader controller (2026-09-30)

The novel reader keeps **one WKWebView** for its lifetime; chapters are `<section data-id>` blocks put there by a JS
controller (`Features/Reader/NovelReaderWeb.swift`: `NovelReaderController` + `ReaderWebView` + `NovelReaderScript`).
- **#1 Next chapter does nothing** — fixed by design: changing chapter calls `yomi.show(...)` on the same web view;
  nothing depends on SwiftUI tearing the view down any more. Loading/error show as an overlay above it (+ Try again).
- **#3 short scroll opens the menu** — taps are DOM `click` (WebKit sends none after a scroll), ignored after a move
  >8 px, a fling-stop (scroll <150 ms before the touch) or with a text selection. Native tap recognizer removed.
  Option: one or two taps (Settings → Reader → Novels → Show menu with).
- **#2 infinite scroll** (default on, toggle in the same screen): near the end (1.5 screens left) JS posts `needNext`,
  Swift appends the next chapter under a "CHAPTER N" divider; `current` events move the overlay/progress/reading time
  to the chapter under the reading line (30 % down) without a reload; `complete` (90 % seen) is per chapter; more
  than 4 chapters → the oldest far-above one is dropped on scroll idle with scroll compensation.
- **#4 swipe** left = next, right = previous (horizontal >25 % width and >2× vertical, <800 ms, not from the left
  24 px, not zoomed, no selection). Toggle in settings.
- Style is only re-sent when the CSS string changes (was every scroll tick). Hidden overlay is no longer rendered
  (VoiceOver could reach it). Dead `readingTimer` removed.
Tests: `YomiUITests` 5/5 pass (Next, short drag, infinite scroll, swipe, hidden menu out of the a11y tree). Note:
launch-arg booleans must be plist (`<false/>`) — `"NO"` arrives as a string and `as? Bool` drops it.
Sim-checked visually (divider, footer switching CH. 001 ↔ 002). Not yet on device; scroll-compensation on drop and
memory with long real chapters are unverified (§23.3). Next: Martin ranks §25.10, reinstall on his phone, then step 5.

## S132 — Research audit + UX/UI evidence review (2026-09-29, research only)

Martin (going to sleep): check whether the research was actually applied, re-verify it against trustworthy sources,
and research UX/UI for novels + manga/manhwa/manhua (reviews, Reddit, GitHub, studies). Output: **RESEARCH.md §25**.
No code changed; the S128 batch plan below is unchanged (next = step 4 reader controller).
For Martin to dissect next session — §25.10 ranked list (not scheduled yet):
1. Reader typography pass (Dynamic-Type default, `max-width` column, paragraph/letter/word spacing, `hyphens`, fonts).
2. Pages mode for novels (option). 3. First-run setup that does the work + fix stale "More → Plugins" copy.
4. Accessibility baseline (Dynamic Type, Reduce Motion, overlay a11y). 5. Scheduled local auto-backup + sync status.
6. Tachimanga `.tmb` + local CBZ/EPUB import. 7. Tachimanga v5 manga-reader parity items. 8. TTS highlight +
auto-advance. 9. Streak repair. 10. App Store copy per §25.7. 11. XCTHitchMetric gates. 12. Spanish localization.
Part 2 (Reddit, §25.13): **Lipex** (App Store, July 2026) now runs LNReader repos on iOS; Keiyoushi supports only
Android apps since 2026-07-29; bulk migration + multi-source per title and a PIN-locked SFW mode move up; volume-button
page turns are banned by Guideline 2.5.9; TMO (Spanish) raided Apr 2026, FAKKU DMCA'd self-hosted readers Mar 2026.

## S128 — Martin's field report + plan (2026-09-25)

**Rule for this phase: no fixes until the audit + research are done; then fix everything together** (Martin).

From daily use (novels, on his iPhone):
1. **Next chapter does nothing** — has to quit the reader and reopen. Suspect (unverified): `ReaderWebView.updateUIView`
   only re-injects `<style>`, never the body; the view is rebuilt only when `isLoading` renders true in between, which a
   preload-cache hit can skip → old chapter stays on screen. Reproduce first.
2. **Infinite scroll** into the next chapter (already in the ArcReader list below).
3. **A short scroll opens the menu.** Cause: the tap recognizer returns `true` from
   `shouldRecognizeSimultaneouslyWith` for every gesture, so a small drag / touch-to-stop-a-fling counts as a tap.
   Wants it less sensitive, tap only.
4. **Swipe to previous/next** — plan properly (tap zones, swipe vs. scroll vs. text selection).
5. **The app doesn't feel smooth** — worst: **Browse, opening a novel/manga, and everything in general.**

Plan: (a) write down ✅ → (b) project audit → (c) deep research per topic (reader rendering architecture —
WKWebView vs TextKit vs native paragraph list, which gates infinite scroll/pages/swipe/TTS highlight/translation;
gesture design; infinite-scroll data model; SwiftUI/iOS performance + measurement; testing) → (d) one batched fix pass.

(b)+(c) done → RESEARCH.md §23. Proposed batched pass, in order (awaiting Martin's OK):
0. Baseline: Instruments (Animation Hitches + Time Profiler) on his iPhone + signposts for "tap title → chapters
   visible"; add a test target (Swift Testing + 2–3 reader XCUITests), failing tests for #1 and #3 first.
1. Detail screens show saved chapters instantly, refresh from the site behind them (manga + novel).
2. Grids: one aggregate query per screen instead of 4 per cover cell; downsample covers; drop per-cover fade.
3. Cache one JSBridge per source off the main thread (Browse, detail, Continue Reading, Updates).
4. Novel reader rebuilt around one JS controller in the same WKWebView (decision §23.3): proper chapter loading
   (fixes #1), `click`-based taps + 1/2-tap option (#3), swipe prev/next (#4), infinite scroll via appended chapter
   sections (#2), no style re-inject on scroll.
5. Smaller: Library reload-on-appear, `averageColor` CIContext, Browse `duplicateNames`, detail `.task` fan-out.
6. Re-measure against step 0; install on his phone.

**S129 — step 0 baseline DONE** (RESEARCH §23.6, numbers in the table there). Headlines: scrolling is fine; freezes
come from the JS bridge built on main (800 ms opening a novel), the novel detail list rendering ~880 rows eagerly
and re-rendering under the reader, and `WKWebView.init` on main; Browse is slow because the Keiyoushi JVM runs
interpreted (one core pinned for the whole load). Bug #1 reproduced on device. Order revised in §23.6.
Tests (step 0, second half): `YomiUITests` target (in the Yomi scheme) + DEBUG `-yomiReaderFixture` (opens the
reader on a 3-chapter offline novel, `Features/Reader/ReaderFixture.swift`). Run:
`xcodebuild test -scheme Yomi -destination 'id=F31CC190-186D-4598-9ED8-225821907550' -only-testing:YomiUITests`.
- `testShortDragDoesNotOpenMenu` **FAILS** — bug #3 reproduced (a 4 %-of-screen drag opens the menu).
- `testNextChapterShowsNewText` **passes** — bug #1 does NOT reproduce in isolation, even after reading to the end
  (preload cache). So §23.1's cache-hit theory is not sufficient. Martin reproduced it on device (run 4). Differences
  left: library novel (download-ahead running), reader pushed from NovelDetailView (which re-renders under the reader,
  §23.6), real network. Next: extend the fixture to go through NovelDetailView with an in-library novel.
- A11y bug found: the faded-out reader overlay (opacity 0) stays in the accessibility tree — `.accessibilityHidden`
  on it has no effect (glass content). VoiceOver can reach invisible controls. Fix in step 4 (remove it from the tree
  when hidden); tests read a DEBUG `reader.menuState` marker meanwhile.

## Backlog — novel reader parity with ArcReader (S126, 2026-09-24)

Martin reads novels in ArcReader today; he sent 24 screenshots of it (reader settings, TTS, audio, downloads,
library, sources) so this list exists and doesn't have to be re-derived. Unchecked = not in Yomi yet (ticks re-checked S170 against the S133–S167 entries). Suggested
order from S126: **offline + preload first** (loading is where ArcReader feels smoother), then infinite scroll, then
TTS. Translation (Apple Translation framework, RESEARCH §22.11) stays the headline item across all of this.

**Chapter list (Tachimanga)**
- [x] Read before / Select range / Select all / Invert (S126, `1f61fdb`)
- [x] Bookmark a chapter (+ bookmark filter) — needs a `v23_` migration on `chapter` + `novel_chapter`, CloudKit mapping (S167)
- [x] Download from the selection bar for novels (S127)

**Reader — Text**
- [x] Font browser beyond serif/sans (ArcReader lists Google Fonts with a live preview; bundled fonts at least: Newsreader, Lora, Quicksand…) (S136: Apple faces + 4 bundled OFL fonts; no Google Fonts browser)
- [x] Letter spacing (Tight / Normal / Loose) separate from line height (S136)
- [x] Font size as a number readout (ArcReader shows "20") (S136)

**Reader — Look**
- [x] More themes (ArcReader: Light, Sage, Void, E-ink, Sepia, Dark, AMOLED) + **custom themes** ("New") (S177: Sage, E-ink, Void + New/edit/delete own themes)
- [ ] Background textures (Midnight, Ember, Rose, Cream, Paper, Dusk, Slate, Forest, Vignette, Parchment, Linen)

**Reader — Reading**
- [x] **Pages mode** (paged, with chapter line on top + page number at bottom, each hideable) alongside Scroll (S136)
- [x] **Infinite scroll** into the next chapter (Off = chapter ends at its last line with Next waiting) (S133)
- [ ] Tap zones: Bottom only / Top + bottom / Off, and **tap scroll** amount (Short / Half / Full, slider %, keeps last lines visible)
- [x] Swipe left/right to change chapter (toggle) (S133)
- [ ] On-screen clock (Off / Top / Bottom)
- [ ] Chapter length readout: Off / Words / **Time left** (estimated from the reader's own pace)
- [x] Toolbar opens on 1 tap / 2 taps (S133)
- [ ] Italic dialogue + drop cap (both toggles; drop cap scroll mode only)
- [ ] Customizable toolbar buttons
- [ ] Reload chapter (refetch when text looks wrong); report chapter
- [ ] Skeleton loading state ("Extracting chapter content…" + tips) instead of a spinner

**Text selection ("hold selection" default action)**
- [ ] Highlight, Copy, **Translate**, **Quick translate**, **Dictionary**, Speak, Listen from here, Pronounce, Replace (S177: **Replace…** added; whole-chapter translate in the Reading tab; Copy/Look Up/Translate are the system menu's own)
- [x] **Term replacement** list (rename a term everywhere — fixes inconsistent MTL/fan-TL names) (S177)

**Text-to-speech**
- [x] Voice picker (system voices) + premium neural voices (ArcReader: sherpa-onnx, 140 downloadable voices — §22.11) (S143 system voices; neural voices still open)
- [x] Speed presets 0.75×–3× (S143)
- [x] Auto-advance chapters (offline if downloaded, stream otherwise) (S143)
- [x] Play alongside other apps' audio vs. own lock-screen/headphone controls (S143 + mix setting S144)
- [x] Full-screen player option; **tap a paragraph to jump**; dim other paragraphs; follow position Center/Top (S143 full player + "Listen from Here"; no dimming/follow choice)
- [ ] Pronunciation text filters
- [x] Sentence/paragraph highlight while reading (Yomi today speaks the whole chapter as one utterance) (S143)

**Audio experience**
- [ ] Ambient sounds + background music (start with the reader, shuffle, duck under narration)

**Downloads (novels have none today)**
- [x] Download novel chapters / whole novel for offline reading (S127 — selection bar Download/Delete, ⋯ → Download: next 10 unread / all unread / all)
- [x] **Download ahead** (keep next 5/10/20/30 chapters on device as you read) (S127 — Settings → Novels → Offline, default 5, library novels only)
- [ ] Remove read chapters (keep last N; keep bookmarked/highlighted)
- [x] Wi-Fi only (S127b — app-wide "Download only on Wi-Fi", default on, manga + novels)
- [ ] Auto-download new chapters (novels)

**Library / discovery**
- [ ] "Picking up where you left off" card showing **CH x / total** + % for novels
- [ ] **Other sources** for the same novel, sorted by chapter count (migrate/global-search per title)
- [ ] Add a novel by pasting its URL / from an in-app browser ("Add Novel" sheet)
- [ ] Separate Novels / Books (EPUB import) shelves

**Notifications / community** (lower priority)
- [ ] Reading reminders + streak nudge, new-chapter and download-complete notifications (some exist — audit)
- [ ] Per-chapter comments + ratings (ArcReader runs its own Supabase backend — out of scope without a server)

---

## Current state (post S127 — 2026-09-25 · novel downloads + download-ahead)

- Martin picked **novel downloads + download-ahead** from the ArcReader backlog.
- New `Features/More/NovelDownloadManager.swift`: `NovelDownloadStore` (files at
  `Documents/NovelDownloads/<hash(novelId)>/<hash(chapter path)>.html` + `novel.json`; "downloaded" = file exists, so
  **no migration, no CloudKit mapping**) and `NovelDownloadManager` (one worker, one chapter at a time, 250 ms apart,
  own bridge per source, stops a novel after 3 misses in a row with a toast).
- Keyed by chapter **path**, not `NovelChapter.id` — ids are `<novelId>-ch-<index>` and shift when a source inserts
  a chapter.
- Reader: `loadContent` and the 70 % preload read the local file first; opening a chapter queues the next N
  (`AppSettings.novelDownloadAhead`, default 5, Off/5/10/20/30) **at the front** of the queue, library novels only.
- Detail: download icon / spinner per row, selection bar Download + Delete, ⋯ → Download (next 10 unread / all
  unread / all) + Delete downloads. Downloads screen: one row per novel (in progress and downloaded).
- **Sim-verified** (iPhone 17 Pro 26.3, A Regressor's Tale on WeTried): reader on ch 25 → 26–30 on disk; Next → ch 31
  queued; Next 10 unread → 25–34; select 25+26 → Download disabled, Delete removed both files and icons; Downloads
  lists "Novel · 8 chapters · 249 KB". **Not verified**: reading with the network actually off, the in-progress
  Downloads row, the Settings picker UI.
- Not in this pass: auto-download new chapters, remove-read-chapters.
- **S127b — "Download only on Wi-Fi"** (Martin: don't spend users' cellular data). `Core/NetworkMonitor.swift`
  (`NWPathMonitor`): metered = `isExpensive` (cellular **or personal hotspot**) or `isConstrained` (Low Data Mode).
  `AppSettings.downloadOnlyOnWiFi`, **default on**, Settings → Data. Covers manga + novel downloads, download-ahead
  and background downloads; both queues `await waitUntilDownloadsAllowed()` between items (never mid-chapter), keep
  the items queued and resume on their own when Wi-Fi returns. Downloads screen: "Waiting for Wi-Fi" banner +
  one-off **Download on cellular now** (withdrawn when both queues drain). Toast "Queued · waiting for Wi-Fi" on the
  detail screens. Reading is never gated; the 70 % next-chapter preload is skipped only in Low Data Mode. Until the
  first path update arrives the network counts as unknown and nothing downloads. DEBUG launch arg
  `-yomiSimulateCellular` makes the simulator look metered. **Sim-verified**: queued → nothing downloaded, banner +
  row "Waiting for Wi-Fi", toast, one-off cellular downloaded the 2 queued then was withdrawn (next 847 waited),
  toggling the setting off resumed at once. Toggling it back on wasn't clickable through mobile-mcp (switch under the
  floating nav / list scrolls under the tap) — same gate as the first case, not separately seen.

## Prior state (post S126 — 2026-09-24 · WeTried plugin, Tachimanga chapter selection, novel-library bug)

- New Firebase plugin `wetriedtls.js` (HeanCMS JSON API; v1.0.2 retries search with curly apostrophes) — Martin
  reads *A Regressor's Tale of Cultivation* there. Copy-URL install (not on the instant-install allowlist).
- `1f61fdb`: Read before / Select range / Invert on manga + novel detail; bulk mark-read batched.
- **Bug fixed**: `NovelDetailView.toggleLibrary` upserted a copy, so opening any chapter afterwards
  (`touchLastReadAt`) wrote `inLibrary=false` back — heart then read silently dropped the novel. Chapters on screen
  are now persisted on add. Verified against the simulator's `yomi.db`; Martin confirmed Read before on device.
- ArcReader parity backlog above.

## Prior state (post S124 — 2026-09-24 · Keiyoushi extensions inside Yomi, on-device)

**S124 (2026-09-24) — KEIYOUSHI RUNS INSIDE YOMI ON MARTIN'S iPHONE, no server.** Commits `c3c202b`…`680d9b2`.
1. **PoC Phase 1 passed** on the iPhone 17 (lab app `Labs/YomiBridgeLab`, table in `KEIYOUSHI_POC.md`). iOS HotSpot
   ignores `-Djava.home` → the runtime framework carries its Java home at `OpenJDKRuntime.framework/lib`.
2. **Converted extension jars persist** (bridge patch): first call after relaunch Asura 6.0 → 1.6 s, MangaFire 3.5 → 0.5 s (Mac).
3. **Personal build** (`Config/Personal.xcconfig`, `scripts/build-personal.sh`): free Personal Team, no push/iCloud/App
   Group (free team can't sign them — widget shows its placeholder), `YOMI_PERSONAL` disables CloudKit sync. Device-only.
4. **Keiyoushi in Yomi** (`Yomi/Features/Keiyoushi/`): `KeiyoushiJVMHost.mm` (dlopen'd runtime, embedded by the
   'Embed Keiyoushi runtime' build phase only when `YOMI_EMBED_KEIYOUSHI=YES`; stage with `scripts/keiyoushi/stage-vendor.sh`),
   `KeiyoushiRepository` (index.pb decode, install = APK to App Support), `KeiyoushiBridge` (POST /dalvik),
   `KeiyoushiBrowseView`, `KeiyoushiExtensionsView` (More → Keiyoushi). sourceId `keiyoushi_<Mihon id>`, chapter path
   `keiyoushi://…`. **Verified by Martin on device**: repo load, install, browse, read Asura + MangaFire.
5. **One translation per chapter** (MangaDetailView `readingChapters`, star chips = preferred group per title).
   MangaFire 1,516 → 924.
6. **Bug found on device + fixed**: History lost Keiyoushi reads — whole-row `MangaQueries.update` lost-update race on
   reader close + Browse-model rows overwriting saved state. Now `addReadingSeconds`/`updateSourceMetadata`/
   `updateCustomCover` + `adoptSavedState`. Affected JS/Suwayomi titles too.
**Next (Martin tests today):** his feedback first; then Updates/Downloads for Keiyoushi titles (not routed yet), Mihon
backup import mapping by source id, zstd stand-in, Asura tile pages (CoreGraphics Bitmap), MangaFire captcha via
WKWebView, dropping NewPipe (GPLv3) from the jar. Next migration prefix still `v23_`.

## Prior state (post S123 — 2026-09-24 · Keiyoushi on-device PoC — Mac phase verified)

- **Next session = `KEIYOUSHI_POC.md` Phase 1** (lab app on Martin's iPhone 17, free Personal Team). Start without asking.
- Done S123: ArcReader APK teardown (`RESEARCH.md` §22.11); Mac-side PoC — Asura Scans + MangaFire run end to end on
  a java.base-only interpreter JVM through our patched M-Extension-Server (§22.12); reproducible `setup.sh` (58 s from
  zero); OpenJDK Mobile → `OpenJDKRuntime.framework` links for iphoneos.
- New backlog items from S123: zstd stand-in for KeiSource's filter cache; CoreGraphics `Bitmap` for Asura tiles;
  MangaFire captcha via WKWebView cookies; persist converted jars; **per-title "one translation per chapter" dedupe**
  (Keiyoushi sources return official + unofficial copies of the same chapter); drop NewPipe (GPLv3) before shipping.

## Prior state (post S122 — 2026-09-23 · DIRECTION RESET — research only, no code changes)

**Martin's brief:** finish Yomi no matter what. Tachimanga feels smoother and hand-crafted; Yomi stutters/freezes and he
never uses it; Space Grotesk made it look AI-generated. **Top priority: Keiyoushi + LNReader sources must work like in
Tachimanga — paste a repo URL, never maintain a source.** No server unless truly necessary. Everything is in
`RESEARCH.md` §22 (read it before any source/perf/design work). Headlines:

1. **Tachimanga runs Keiyoushi ON THE PHONE** (embedded Suwayomi fork + JVM, downloads Keiyoushi `.jar`s) — corrects S89.
   Madomi does the same on the App Store. Open-source stack for Yomi exists: official OpenJDK Mobile (Zero interpreter)
   + M-Extension-Server (MPL-2.0, iOS build) as used by Mangayomi. **Proposed next step: on-device proof of concept on
   Martin's iPhone** (one Keiyoushi extension → Popular + a chapter; measure start time, RAM, app size). If it works,
   the S90 hosted-server plan is dropped.
2. **Keiyoushi changed format 2026-08-13** → `https://github.com/keiyoushi/extensions/raw/repo/index.pb`; old JSON URL
   returns a fake "Outdated App" entry. 1,397 extensions, each with `.apk` + `.jar`.
3. **LNReader needs no server — Yomi's hand-written cheerio is the bug.** `.remove()/.contents()/.get()` throw,
   `.a.b`/`:nth-child`/`:contains` silently wrong; 147/280 plugins call `.remove()`. Fix: bundle real
   cheerio/htmlparser2/dayjs.
4. **Stutter root causes (code-read, not yet profiled):** no Kingfisher `backgroundDecode`/downsampling/prefetch; webtoon
   LazyVStack placeholder jumps; novel reader re-injects `<style>` every scroll tick; `averageColor` CIContext on main;
   Library full reload on every appear; **zero automated tests**.
5. **Hosting:** only matters if on-device fails. Firebase Spark can't run a JVM; Workspace gives no Cloud credit;
   Railway ≈ $5–10/mo; Oracle free now 2 OCPU/12 GB with idle reclaim.
6. **Design:** Martin wants away from the Space Grotesk/Space Mono look; direction to decide together from screenshots.
7. **Take from ArcReader:** paste-link import, on-device TTS, tap-to-define, highlights, doc import, download-ahead.
   **From Madomi:** Tachimanga `.tmb` + Mihon `.tachibk` backup import.

**Open questions for Martin (answer first thing next session):** (1) PoC first, or stutter fixes first? (2) Which iPhone
model? Unverified items to not assume: `RESEARCH.md` §22.10.

**Also stale in this file:** the Strategic Goal table above (LNReader "✅ Native", keiyoushi "✅ S41 integrated") —
both overstated; see §22.3/§22.4.

---

## Prior state (post S120 — 2026-08-27 · 11 backlog findings fixed: Suwayomi reader, tracker CSRF + token refresh, History, error surfacing, dead code)

**S120 took the two items S119's handoff named as highest-value.** **#131**: a Suwayomi-sourced
manga's detail screen showed no chapters, ever — its `sourceId` can never match an installed JS
plugin, so `MangaDetailView` fell into the extension-not-installed branch and the service's own
REST detail/chapters/page methods had zero call sites. Added a Suwayomi branch to `loadChapters()`,
made `ChapterReaderView.bridge` optional with a `fetchPages(bridge:path:)` router, and — found by
live-testing, not reading — removed two further `bridge != nil` gates that hid the Start-reading
button and made every chapter row's tap a no-op. Verified end to end against a local stand-in
server (no Docker/JDK 21 on this machine): detail metadata + all 5 chapters + reader pages.
**#123/#124/#135**: all 4 trackers now send an unguessable per-attempt OAuth `state` and verify it
single-use on callback, so an attacker-delivered `yomi://<host>/callback` can no longer silently
log a victim's device into the attacker's tracker account. **#108**: the `refresh_token` all three
code-grant services saved at login and never used is now wired up — a new `refreshAccessToken()` on
`MangaTracker` plus a `sendAuthorized(_:)` helper that refreshes and retries once on a 401, so
tracker sync no longer dies permanently the first time an access token expires (and a genuinely
dead session now says so instead of showing "Connected" forever). Both are compile + review only —
a real OAuth round-trip still needs the client credentials #115 notes are missing. **#114**: a
manga or novel read but never finished now reaches History — `ChapterQueries.updateProgress` and
`NovelQueries.updateScrollPercent` touch `lastReadAt` (the novel side throttled to once a minute
inside its own transaction, since it fires every ~400ms), live-verified via a partial read showing
up as "CH. 001 · read to 33%". **#150**: a failed library read now says so ("Couldn't load your
library" + the real error + Try again) instead of rendering as an ordinary empty library —
live-verified by renaming the `manga` table out from under the app. **#125**: notification titles
are withheld while App Lock/Secure Screen is on, matching #68's widget guard. **#132-137**: six
confirmed-dead symbols removed. Full detail in `CLAUDE.md`'s S120 entry and the Known Issues table.

---

## Prior state (post S119 — 2026-08-27 · all 5 HIGH audit findings fixed)

**S118 finished the 23-dimension audit** (verified S117's 15 unverified rows — 11 confirmed, 4
refuted — then ran the last 4 dimensions, 25 more confirmed findings, `CLAUDE.md` rows 138-162;
89 findings total across the whole audit, audit-only, no fixes).

**S119 started the fix backlog with the 5 HIGH findings S118's handoff named first — all fixed:**
`BackupManager.importBackup` no longer restores a library on the main thread with a transaction per
row (#138); a chapter-update check now distinguishes a failed fetch from "nothing new" and says so
in the refresh banner (#145); all 4 tracker services now surface a failed progress sync instead of
swallowing it, via one shared `MangaTracker.sendProgressUpdate` helper (#147); a migration whose
new-source fetch fails now throws before touching the library rather than deleting the working
original (#148); and a partially-failed or cancelled download no longer marks itself "Downloaded"
(#149, also closing #111). Clean zero-warning build; #145 live-verified end-to-end against a
genuinely dead source. Full detail in `CLAUDE.md`'s S119 entry and the Known Issues table.

---

## Prior state (post S117 — 2026-08-22 · S116 backlog fixed + remaining 15-dimension audit, 30 new findings)

**S116 ran an "absolutely everything" full-project audit** (23-dimension multi-agent `Workflow`,
every finding independently re-verified) but was interrupted twice by the account's own session
limit — 8 of 23 dimensions completed (34 confirmed findings, `CLAUDE.md` Known Issues rows 74-107),
15 never ran. **S117 fixed 32 of those 34 findings directly** across ~19 files — CloudKit
dirty-marking gaps on chapter upsert/backup-restore, a novel-reader soft-lock, a missing WKWebView
navigation-policy check (unsanitized scraped HTML could otherwise navigate the reader out), an
unguarded tracker auto-update firing redundant API calls, OPDS pagination never being consumed, a
wrong Tachiyomi-import match-count, plus assorted dead code and stale docs. The 2 left unfixed are
deliberate calls, not gaps: #78 (iPad's two independent tab-visibility stores need a real product
decision) and #106 (a `ChapterReaderView.swift` file split, deferred since this session's own fixes
already touched that file). Full detail in `CLAUDE.md`'s S117 entry and the Known Issues table
itself. Clean zero-warning build, live-verified via `build_run_sim`+mobile-mcp across Library/
Browse/Plugins/Sync.

**Then ran the remaining 15 audit dimensions** as a leaner single-pass `Workflow` (no
high-severity-recheck/completeness-critic stages). **Hit the account's rate limit twice more** —
resumed once via `resumeFromRunId`, then stopped on Martin's call after the second hit rather than
risk a third. 14 of 15 dimensions got their finder agent to run (Performance, Docs-vs-code, Error
handling, and Backend/Firebase never did). **30 new findings, `CLAUDE.md` Known Issues rows
108-137**: 15 independently verified, 15 found but never re-verified before the limit hit again
(marked UNVERIFIED in the table — treat as leads, not settled). Headline verified item: tracker
OAuth refresh tokens are saved but never used, silently killing MAL/Shikimori/Bangumi sync forever
once the access token expires (#108). Headline unverified item, highest priority to confirm: a
claim that all 15 production plugins ship bundled inside the binary, contradicting this repo's own
"zero plugin files in the binary" App Store compliance claim (#130). No fixes applied — audit only.
Full detail in `CLAUDE.md`'s S117 entry.

---

## Prior state (post S115 — 2026-08-19 · novel chapter-preload + tracker-sync generalization)

**S115 shipped two items Martin chose from S114's research backlog.** (1) **Novel chapter-preload** —
`TextReaderView.swift` backgrounds a fetch of the next chapter once scroll passes 70%, cached and
consumed on nav instead of re-fetching; a jump-to-chapter evicts stale cache entries. (2) **Tracker
sync — corrected a wrong research premise before building anything**: S114 claimed "Yomi has zero
tracker integration," but real working MAL sync already existed (`MALService.swift`); the research
session never checked. Generalized it into a `MangaTracker` protocol and added AniList, Shikimori, and
Bangumi (Martin's picks) behind it — new `TrackerManager` fans reader chapter-finish events out to
every logged-in tracker and centralizes OAuth-callback routing; new `TrackersView.swift` (More →
Trackers) replaces the old single MyAnimeList row; new `AppSettings.trackerAutoUpdate` toggle closes a
real pre-existing gap (auto-update had no opt-out). Found and fixed a real prerequisite bug along the
way: `Info.plist` had no `CFBundleURLTypes` entry at all, so `yomi://` callbacks — including MAL's
existing one — could never have reached the app. Shikimori/Bangumi both require an embedded
`client_secret` (no PKCE option in either API) — flagged to Martin directly, who confirmed embedding it
is fine, same as other open-source tracker clients. Full technical detail (API research, the
`RESEARCH.md` §20 correction, and a build-error red herring worth remembering) is in `CLAUDE.md`'s S115
current-state entry and `RESEARCH.md` §21. Zero-warning build on `Yomi`+`YomiWidget`, live-verified via
`build_run_sim`+mobile-mcp. AniList/Shikimori/Bangumi OAuth stays unverified until Martin registers real
app credentials for each (`AppSecrets.swift` has the registration URLs).

---

## Prior state (post S114 — 2026-08-18 · external competitor/architecture research, no code changes)

**S114 was a general research conversation, not a Yomi coding session — no code touched.** Martin
asked to investigate the Swift-ecosystem competitor landscape (found via GitHub search, not memory),
then to go deeper on specific architecture questions that came up along the way, then to commit and
push the findings so they're not lost. Full detail (code-cited, not just README claims) is in
`Yomi/RESEARCH.md` §20 — summary:

- **New competitors surveyed**: Ito (`itoapp/Ito` — unified manga+anime+novel, WASM plugins, exact same
  positioning as Yomi but 2 stars and currently *unbuildable*, its plugin runtime is a private
  dependency) and Nyora (`Nyora-Manga/nyora-ios` — Aidoku fork adding Supabase-based cloud sync instead
  of CloudKit). Neither is a real threat yet; both worth a periodic re-check. Ito's fuzzy plugin-ID
  matcher (Jaro-Winkler + margin-check) is worth stealing the shape of if Yomi ever adds
  import-from-Aidoku/Paperback.
- **Plugin architecture question, settled with real code, not assumption**: is Aidoku's WASM/Wasm3
  approach actually better than Yomi's JSCore/JSBridge model? No — direct comparison of the real source
  on both sides found no meaningful startup-cost or execution-speed difference (both parse-once-cache,
  both are network-latency-bound not CPU-bound, both sandbox via an explicit host-function-import
  allowlist). **Found a real, unrelated bug in Yomi's own code while doing this comparison**: Aidoku
  auto-retries every Cloudflare-blocked request transparently everywhere; Yomi's
  `CFBypassManager.autoBypass` is only wired into `BrowseView.swift` — opening a manga or reading a
  chapter falls straight to the manual "Bypass Cloudflare" button with no auto-attempt first. **Not
  fixed this session** — a real, scoped candidate for whoever picks this up next.
- **Yuedu-reader's "Legado-format" declarative source rules** were investigated as a possible
  lower-App-Store-review-risk alternative to Yomi's JS-plugin model, and ruled out — it's a hybrid with
  a full 1,331-line JSCore engine underneath for anything beyond trivially-scriptable sources, not
  actually declarative where it matters. Along the way, Yomi's own `TextReaderView.swift`
  (WKWebView-based novel rendering) was re-examined against Yuedu's native-CoreText approach and
  **confirmed correct as-is** — live CSS-based theming is the reason, and it's a genuine advantage (not
  a cost) for the backlogged Yomitan-style dictionary-lookup feature idea, since Yomitan itself is
  DOM-Range/Selection-based.
- **Keiyoushi-via-Suwayomi (S89/S90) re-confirmed as the right call with real current numbers**, after
  Martin asked whether to look for alternatives: 1,368+ sources vs. Aidoku-Community/sources (133, would
  cost Yomi an entire new Rust/WASM host-shim to maintain) vs. inkdex/extensions (71, 2-maintainer bus
  factor). No action needed beyond eventually working through the already-written deployment checklist.
- **Hands-on**: built real Aidoku and Nyora from source. Aidoku builds and runs clean on Simulator.
  **Nyora cannot run on Simulator at all** — confirmed definitively by asking Xcode for the scheme's
  actual destination list (zero concrete simulators offered; its custom parser engine is a device-only
  compiled binary). Martin then drove the running Aidoku build directly and found a shipped, production
  OCR-based dictionary-lookup feature (a concrete reference design for Yomi's own backlogged idea,
  applied to manga page images rather than novel-reader DOM text), Suwayomi as a first-class built-in
  Aidoku source (independently validates the S89/S90 bridge strategy), Aidoku's own iCloud Sync still
  labeled experimental/may-lose-data, and a real feature gap — Aidoku has native tracker sync
  (AniList/MAL/MangaBaka/Shikimori/Bangumi), Yomi has none.

**No code changed, no build run against this repo, no Known Issues added.** Next session picking any
of this up should start with `Yomi/RESEARCH.md` §20 for full citations.

---

## Prior state (post S113 — 2026-08-17 · S112 backlog cleared)

**S113 worked through the S112 audit backlog end to end**, per Martin's "work through the S112 backlog"
ask. Scoped down to code-fixable items in this repo up front, same call S111 made: excluded #47
(CloudKit container provisioning — still blocked on paid Apple Developer Program enrollment, not
fixable in code) and #69 (the MangaDex plugin's licensed/external-chapter bug — the plugin source is
hosted separately at `yomi-plugins.web.app`, not present in this repo/machine). #55 (duplicate `v4`
migration prefix) needed no fix — it's informational only, GRDB keys migrations by string name so it's
harmless, just a note for the next migration.

**Fixed all other 17 items**, roughly by theme:
- **Correctness/data-loss class**: #52 — `YomiApp.init()`'s `try? DatabaseManager.shared.setup()`
  replaced with `do/catch` + `fatalError(...)` carrying the real error, so a corrupt-DB/migration
  failure fails loudly at the actual point of failure instead of a mystifying force-unwrap crash three
  calls downstream. #53/#54 — `MangaQueries`/`NovelQueries`' `clearLastRead` and `touchLastUpdated` now
  call `markCloudDirty`, closing the same "sync gap" bug class S105 already fixed at other call sites.
- **Privacy**: #68 — the Home Screen widget was showing reading history with zero authentication for
  an 18+ rated app, regardless of App Lock/Secure Screen. Fixed two ways: `LibraryViewModel.writeWidgetData()`
  now guards on both settings and writes an empty array when either is on, and `AppSettings`'s `didSet`
  for both now clears any already-written widget data immediately when the setting flips on, rather than
  waiting for the next Library refresh (which might not happen for a while). Live-verified the guard
  end-to-end: seeded a manga into the library with `lastReadAt` via direct `sqlite3`, relaunched, confirmed
  the App Group's `group.pacodealer.Yomi.plist` populated with real `widgetReadingItems` JSON while
  unprotected. Didn't separately live-tap-verify the `didSet` clear specifically — both `mobile-mcp` and
  `XcodeBuildMCP`'s `tap` (not enabled this session's tool config) failed to register a tap on the App
  Lock switch, the same tooling limitation documented since S109. The code path is a 2-line symmetric
  addition to the already-verified guard and compiled clean.
- **Concurrency**: #57/#58 — `SourceBrowseView`'s `loadContent()`/`loadMore()` both dispatched their own
  `Task.detached` against the same cached `JSBridge` with no mutual exclusion (`loadMore()`'s guard now
  also checks `!isLoading`), and two `isLNReaderPlugin` reads happened on MainActor outside their
  function's `Task.detached` block (moved inside, alongside the JSContext work they gate — matches
  `JSBridge`'s own "never call from MainActor" rule and the two call sites that already did this right).
  Same root file, fixed together.
- **Correctness, smaller**: #60 — migrating away from a source with "remove old entry" now also deletes
  the old manga's `Downloads/{id}` directory, matching the app's other two "remove from library" cleanup
  paths (previously left orphaned files silently enumerated forever). #61 — `CustomizeTabsView`'s
  "reassign default tab if you just hid it" fallback was a no-op exactly when the hidden tab was Library
  (`= AppRouter.tabLibrary`, i.e. itself) — fixed to reassign to the first still-visible tab, falling back
  to `.more`. Caught and fixed the identical bug in the adjacent `router.selectedTab` fallback right next
  to it, same root cause, not itself in the Known Issues list but obviously the same class.
- **Code quality**: #56/#59 — removed 5 confirmed-dead functions (`MangaQueries.insert`,
  `NovelQueries.insert`, `ChapterQueries.insert` single-row variant, `NovelQueries.upsertChapter`,
  `JSBridge.isPaperbackPlugin`) after re-confirming zero call sites each. #70 — added
  `"Previous chapter"`/`"Next chapter"` accessibility labels to the reader's chapter-nav buttons.
- **Docs**: #62-67, all fixed — wrong default accent color, stale DB schema block (now cites
  `v21_cloud_sync_pending`/S105 and includes `pendingChange` + the two `pending_*_chapter_state` tables),
  stale `RESEARCH.md` banner date, two stale line-number citations in `TACHIMANGA_PARITY.md`, a stale
  `YomiApp.swift` file-index entry (still described the pre-S95 unmerged-`fullScreenCover` pattern), and
  an undercounted `AppSettings` property count (43 → 55).

Clean **zero-warning build** on both the `Yomi` and `YomiWidget` schemes throughout (`YomiWidget` needed
a rebuild since `AppSettings.swift`/`WidgetDataWriter.swift` are shared code). App launched clean via
`build_run_sim` with the new fail-loud DB path in place — no regression. 14 files touched, all edits
scoped tightly to the issue they addressed. **Left deliberately unfixed, matching S112's own framing**:
#71 (empty-state illustration drift from spec) — the component's own code comment already calls this a
deliberate simplification, not a bug, so left as-is rather than second-guessing that call unprompted.

---

## Prior state (post S112 — 2026-08-17 · full project audit, documentation-only)

**S112 re-ran S99's "audit absolutely everything" methodology, 13 sessions later, as an independent
re-verification rather than a trust of the old pass.** Split into 7 parallel research dimensions
(core/database/app-entry/sync, extensions/plugins/browse/reader, library/more/history/onboarding,
docs-vs-code, App Store compliance, security & privacy, and a live simulator/build-health walkthrough),
each running its own adversarial verify pass on every finding before it was allowed to surface — every
row in the new Known Issues entries below was independently re-read against the live file/line before
being trusted, not carried over from the sub-agents' first-pass claims. **Deliberately no fixes made
this session**, same as S99 — findings only, catalogued as new Known Issues rows 52-71 for a future
session to triage and work through.

**Headline: no regressions found in the S99-era fixes.** Every S100-S111 fix spot-checked as part of
this pass (the S104 instant-install plugin allowlist, S105's CloudKit dirty-marking/pending-state
fixes, S109-S111's chapter-boundary preload chain, the S101 accent-contrast/no-cover-placeholder work)
was independently reconfirmed still in place and working as documented — genuinely clean after 111
sessions of iterative hardening, consistent with S99's own "code quality held up" verdict. **App Store
compliance stayed clean too**: the S104 `instantInstallSourceIDs` allowlist still gates exactly the 3
lower-risk sources (MangaDex/Royal Road/Scribble Hub) with the other 12 still behind Copy URL + manual
add; no new store-policy regression was found. The one plugin-facing bug this session did surface
(#69, MangaDex's plugin not filtering MangaDex's own licensed/external-only chapters, confirmed live
against the real MangaDex API) is a UX dead-end, not a compliance issue — MangaDex being on the
allowlist is unaffected.

**20 new issues found, roughly:** 3 high, 8 medium, 9 low. Two threads worth flagging up front:
(1) **A new, previously-undocumented privacy gap** — the Home Screen widget (`WidgetDataWriter.swift`)
writes reading-history titles and cover art to the shared App Group completely unconditionally, with
no check of `AppSettings.appLockEnabled`/`secureScreenEnabled` anywhere in its call chain (#68) — for
an app whose content is rated 18+, this is a real (if low-severity, since it needs Home Screen/Today
View access) gap between what App Lock/Secure Screen promise and what they actually hide. (2) **A
small cluster of CloudKit sync gaps parallel to the S105 fixes**: `clearLastRead`/`touchLastUpdated`
across both `MangaQueries` and `NovelQueries` never call `markCloudDirty` (#53, #54) — the exact same
class of bug S105 fixed at 6 other call sites, just missed at these four. Beyond those two threads,
findings split fairly evenly between doc drift (6 stale `ARQUITECTURA.md`/`RESEARCH.md`/
`TACHIMANGA_PARITY.md` citations and facts — #62-67, none of them serious, all citation/line-number or
single-fact staleness from code moving underneath the doc), small code-quality items (a self-cached
`JSBridge` reused across concurrent `Task.detached` calls with no mutual exclusion in
`SourceBrowseView`, #57; two MainActor reads of a JSContext property that should be
`Task.detached`-only, #58; orphaned downloaded files after a library migration removes the old entry,
#60; a self-referential no-op fallback when hiding your current default tab via Customize Tabs, #61;
dead code, #56/#59), and two smaller live-UI findings (missing `accessibilityLabel`s on the reader's
chapter-nav buttons with backwards default VoiceOver semantics, #70; the Library empty state's
illustration not matching the design spec's crosshair motif, a known/deliberate simplification per
its own code comment, #71).

**Next session starts here**: work rows 52-71 in `CLAUDE.md`, roughly in priority order — the silent
`try?` around `DatabaseManager.setup()` (#52, real crash-risk-at-a-distance) and the MangaDex
chapter-filtering fix (#69, live user-facing dead end on an allowlisted source) first, then the
CloudKit dirty-marking gaps (#53/#54, same fix shape as S105's #41-46), then the widget privacy gap
(#68) and the doc-staleness cleanup (#62-67, all quick). CloudKit sync itself is still separately
blocked on Apple Developer Program enrollment (#47, unchanged).

**Methodology note**: this audit ran as an explicit multi-agent `Workflow` (7 finder agents → 7
independent verifier agents → 1 synthesis agent, ~15 agents total, per-dimension pipelining so
verification of one dimension started while others were still finding). Every confirmed/plausible
finding above was re-checked by a second agent against the live file before being trusted — none of
the raw first-pass findings from the 7 finders were taken at face value.

---

## Prior state (post S111 — 2026-08-17 · backlog cleared: boundary-preload root-caused for real, AquaManga pagination fixed, 3 parity features shipped)

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

> ⚠️ **S122 correction:** the "Tachimanga does not embed Keiyoushi" finding below is wrong — Tachimanga runs Suwayomi on-device. See `RESEARCH.md` §22.1.

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
| PrivacyInfo.xcprivacy | ✅ Re-done S184 | App: UserDefaults CA92.1 + 1C8F.1 (App Group), FileTimestamp C617.1 + 3B52.1, DiskSpace E174.1. Widget has its own (UserDefaults). `OpenJDKRuntime.framework` gets one from `embed-runtime.sh` (FileTimestamp, DiskSpace, SystemBootTime — `nm -u` S184). Kingfisher/GRDB/PLzmaSDK ship theirs. Builds ≤ 515 lacked the widget + JVM manifests. |
| Privacy policy URL | ✅ Done S25 | yomi-plugins.web.app/privacy — linked from Settings → About. |
| App icon | ✅ Done S87 | "Y." monogram, Ink default + Paper alternate, wired into Xcode (`ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS`). |
| Zero .js in binary | ✅ Done S19 | Confirmed — plugins on Firebase CDN only. |
| MAL token in Keychain | ✅ Done S24 | KeychainHelper + auto-migration from UserDefaults on first load. |
| OPDS password in Keychain | ✅ Done S100 | Same `KeychainHelper` pattern as the MAL token — was plain UserDefaults. |
| Age rating: 18+ | ❌ Pending | 2026 system uses 4/9/13/16/18+ (replaces old 17+). App enables NSFW content via user-installed plugins. Must declare in App Store Connect — this is an App Store Connect step, not a code change; every doc mention of the rating itself already says 18+ as of S100. |
| App description | ❌ Missing | Frame as "extensible reader — user-installed JS plugins". No source names. |
| Screenshots | ❌ Missing | iOS 26 simulator. Neutral content only (no recognizable piracy sources). Design + functional work both complete since S96 — nothing code-side is blocking this anymore. |
| Support URL | ✅ Live (S154/S184 check) | https://yomi-reader.web.app/support (privacy: /privacy, home: /). |
| French encryption declaration | ❌ Pending (S151) | Yomi's embedded OpenJDK does its own TLS = "industry standard algorithm, not provided within the Apple operating system" (Apple help: Export compliance documentation for encryption, read 2026-10-11). Needed ONLY for App Store distribution in France; uploaded in App Store Connect → App Information → App Encryption Documentation, Apple reviews in ~2 business days, then a key goes in Info.plist. NOT yet researched: the French (ANSSI) side — the form and any waiting period. Martin wants to do it if it isn't hard; until done, leave France out of availability. Not needed for TestFlight. |
| App Store name | ✅ S151 | "Yomi" is taken → listing name **"Yomi Manga and Novels Reader"** (28 chars). Home-screen name stays Yomi. |
| ATS review notes (`NSAllowsArbitraryLoads`) | ❌ Pending | Blanket exception (S89, for self-hosted Suwayomi/OPDS over HTTP) has no per-domain scoping — target hosts aren't known in advance, so scoping isn't feasible. Not a code change: add an App Store Connect review-note at submission explaining the self-hosted-server feature. Revisit scoping only if reviewers push back. |

## App Store compliance
Yomi is App Store compliant via the extension model:
- App binary ships with ZERO plugin files
- Users install plugins themselves from Firebase catalog (user action, not Apple's)
- Precedent: Paperback, Tachimanga, Suwatte, Eclipse, Lipex are on the App Store with user-added sources (checked 2026-10-11). **Aidoku is NOT on the App Store** (its own FAQ: no App Store plans yet) — do not cite it
- App Store description: "extensible reader with user-installed JavaScript plugins"
- Never reference specific source sites in App Store listing or screenshots
- Onboarding must make the install-a-source flow feel easy (under 60 seconds)

## iOS compatibility

**Deployment target: iOS 26.2** — no plan to lower to iOS 18.

(S184: Martin's iPhone 17 runs iOS 26 — the old iOS 18.6.2 note is gone.) The app depends on iOS 26-exclusive APIs:
`Tab()`, `ContentUnavailableView`, `.refreshable`, `.searchable`, `.ascNullsLast`.

If iOS 18 support is required in the future → branch `compat/ios18`, never on main.

## Target plugin sources

> **STALE (S20-era, kept for history — #159).** Comick and NovelUpdates are not in the catalog; the live list is
> `Firebase/public/index.json` (16 entries, see ARQUITECTURA "Firebase Hosting").

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
