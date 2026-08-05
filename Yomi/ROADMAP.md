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

## Current state (post S93 — 2026-08-05 · Block 9 — Downloads)

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

**App Store blockers remaining:**
1. App icon (1024×1024 PNG, 3 layers for iOS 26 Liquid Glass) — user designing — **primary blocker**
2. Age rating 18+, description, screenshots — App Store Connect
3. ~~Apple Developer Program enrollment~~ ✅ Created S36

## Technical debt
| Area | Issue | Priority |
|------|-------|----------|
| App icon | 1024×1024 PNG missing — user designing. App Store primary blocker. | Critical |
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
| App icon | ❌ Missing | All required sizes. Use Asset Catalog. User designing separately. |
| Zero .js in binary | ✅ Done S19 | Confirmed — plugins on Firebase CDN only. |
| MAL token in Keychain | ✅ Done S24 | KeychainHelper + auto-migration from UserDefaults on first load. |
| Age rating: 18+ | ❌ Pending | 2026 system uses 4/9/13/16/18+ (replaces old 17+). App enables NSFW content via user-installed plugins. Must declare in App Store Connect. |
| App description | ❌ Missing | Frame as "extensible reader — user-installed JS plugins". No source names. |
| Screenshots | ❌ Missing | iOS 26 simulator. Neutral content only (no recognizable piracy sources). |
| Support URL | ❌ Missing | GitHub repo or a simple landing page is sufficient. |

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
