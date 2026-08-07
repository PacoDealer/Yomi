# CloudKit Multi-Device Sync — Architecture Design

Status: **implemented S103 (2026-08-06), built directly against this doc.** Scoped S102, same
treatment S90 gave the Suwayomi-server design before any code was written; S103 picked it up the same
session-day and shipped it. A few real API details below were corrected from the original scoping pass
once actual Apple documentation (not training-data memory) was checked mid-implementation — marked
inline as **[as-built]**. Remaining known gap: **no real device/iCloud account has verified an actual
end-to-end sync round-trip** — this dev simulator has no iCloud account signed in, so verification
stopped at "the code path runs cleanly and reports `.unavailable` correctly," not a live two-device
test. See the bottom of this doc for exactly what was and wasn't verified.

## Goal

Today Yomi has iCloud **backup** (`BackupManager.swift`): a full JSON snapshot uploaded to iCloud
Drive on background, manually restorable. It is a point-in-time copy, not sync — two devices don't
reconcile with each other, and restoring device B from device A's backup clobbers B's own progress.

The ask: reading progress (isRead, page position, scroll position), library membership, categories,
and notes should converge across a user's devices without them thinking about it — read chapter 12 on
the iPad, chapter 12 is read when they pick up the iPhone.

**Decided with Martin (2026-08-06), both defaults accepted:**
1. **Sync *behavior* triggers on app foreground/background, not real-time push.** Same trigger points
   the existing iCloud backup already uses — Yomi never builds any "sync happened live while both
   devices were open" UI, and a second device catches up within seconds of being *opened*, not
   instantly side-by-side. **[as-built] The entitlement itself changed mid-implementation**: Apple's
   own `CKSyncEngine` class documentation states plainly that it "requires the CloudKit and Remote
   notifications entitlements" — checked directly against developer.apple.com, not assumed. Flagged
   back to Martin before touching entitlements; his call was to add Remote Notifications (background
   mode + `registerForRemoteNotifications()`, gated behind the sync toggle so it stays dormant for
   everyone who leaves sync off) rather than gamble on undocumented behavior. This does **not** change
   the product decision above — no push-triggered UI was built, no urgency messaging — it's purely
   satisfying a stated framework requirement so `CKSyncEngine`'s own internal `CKDatabaseSubscription`
   machinery has somewhere to deliver to, opportunistically, if iOS happens to wake the app.
2. **Sync scope: metadata + reading state only, no files.** Downloaded chapter images and custom
   cover images stay device-local, matching Tachiyomi/Mihon convention — each device re-fetches
   chapter pages from the source as needed. Keeps every CKRecord tiny (no CKAsset storage/quota
   concerns) and keeps the whole design table-row-shaped instead of file-shaped. Implemented exactly
   as scoped, no changes.

## Why CKSyncEngine, not the alternatives

- **`NSPersistentCloudKitContainer`** — the "just works" Apple path, but requires Core Data. Yomi is
  GRDB/SQLite by deliberate choice (`CLAUDE.md`: "GRDB for SQLite (NOT SwiftData)"); migrating the
  persistence layer just to get sync would be a much bigger, riskier project than sync itself. Ruled
  out.
- **Raw `CKDatabase` + manual `CKQueryOperation`/`CKModifyRecordsOperation` calls** — how Yomi's own
  iCloud backup and every pre-2023 CloudKit app did it. Works, but you re-implement delta tracking,
  retry/backoff, batching, and local dirty-state bookkeeping by hand. This is what CKSyncEngine exists
  to replace.
- **`CKSyncEngine`** (iOS 17+, WWDC23) — the modern, recommended API specifically for "I have my own
  local store (any local store — Core Data, SQLite, files) and want it to mirror a private CloudKit
  database." It owns: pending-change tracking, batching modify/fetch operations, retry with
  server-driven backoff, and change-token bookkeeping. The app supplies a delegate that (a) hands over
  local rows as `CKRecord`s when asked, and (b) applies incoming `CKRecord`s back to GRDB. This is the
  right primitive for Yomi's shape. **iOS 26.2 deployment target means the iOS 17 minimum is a non-issue.**

## Key finding that shapes the whole design: chapter identity is already content-derived, not local-random

Traced `Chapter.id` and `Manga.id` through `JSBridge.swift` (the only place these rows are created):

- `Manga.id` — comes straight from the plugin's own list item (`dict["id"]`, or the raw `path`/`link`
  for LNReader-format sources). Same manga fetched from the same source on two different devices
  produces the **same id**, deterministically — it's derived from the source's own content
  (`Yomi/Features/Extensions/JSBridge.swift:1795`, `:1987`).
- `Chapter.id` — literally the chapter's URL/path (`JSBridge.swift:1723`: `id: chURL`). Same source,
  same chapter, same id on every device.

This means **the chapter list itself never needs to be synced.** Every device independently
reconstructs the full chapter list (name, path, chapterNumber, scanlator — all immutable metadata)
by calling the plugin's `getChapterList()`, exactly like it does today (`MangaDetailView.loadChapters()`).
Only the **mutable per-chapter state** — `isRead`, `progress`, `lastPageRead`, `readAt`,
`readingSeconds` — needs to travel through CloudKit, keyed by the same `chapterId` both devices
already agree on.

This is the single biggest scope-reducer in this design: a 3,139-chapter novel (Shadow Slave, seen
live in S88 testing) would be catastrophic to sync as 3,139 full `CKRecord`s per device. As a
**state-only** delta keyed by content-derived id, it's cheap — most chapters never get a state record
at all (only touched ones do), and the ones that do are ~5 scalar fields.

## What syncs vs what stays local

| Data | Syncs? | Why |
|---|---|---|
| Manga/Novel: `inLibrary`, `readingStatus`, `notes`, `lastReadAt` | ✅ | Small, user-authored or user-triggered state |
| Manga/Novel: `title`, `coverURL`, `summary`, `author`, `artist`, `status`, `genres`, `path`, `sourceId` | ✅ (write-once-ish) | Needed so a manga *added to library* on device A appears at all on device B before device B has ever browsed that source. Effectively immutable after first sync — see conflict policy below. |
| Chapter/NovelChapter: `isRead`, `progress`, `lastPageRead`/`lastScrollPercent`, `readAt`, `readingSeconds` | ✅ | The actual cross-device value prop |
| Chapter/NovelChapter: `name`, `path`, `chapterNumber`, `scanlator`, `releaseTime` | ❌ | Re-derived locally from the plugin every time (see finding above) — syncing it is pure waste |
| Chapter: `isDownloaded`, `downloadedAt` | ❌ | Downloaded-file state is inherently per-device (the file only exists on the device that downloaded it) |
| Category: `name`, `sort` | ✅ | Small, cheap, users expect their categories to follow them |
| `manga_category`/`novel_category` join rows | ✅ | Needed for category membership to sync |
| `customCoverPath` | ❌ | Local file path, meaningless on another device, and by decision above custom cover *images* stay local too |
| `source`/`extension` (installed plugins) | ❌ | Each device installs its own plugins independently from Firebase, same as today — no cross-device value, and syncing "isInstalled" would be actively misleading (device B would show a plugin as installed with no JS actually fetched) |
| History (derived from `lastReadAt`) | — (implicit) | Not a separate table — already covered by Manga/Novel's `lastReadAt` |

## Zone & record design

- **One custom zone in the private database**, e.g. `"LibraryZone"`. Not the default zone — a custom
  zone is required for `CKSyncEngine`'s atomic batch semantics anyway, and it keeps the design
  forward-compatible if Yomi ever wants a *second* zone for something unrelated (it won't need
  `CKShare`/multi-user sharing — this is single-user, multi-device only).
- **Record types**: `Manga`, `Novel`, `MangaChapterState`, `NovelChapterState`, `Category`,
  `MangaCategoryLink`, `NovelCategoryLink`. One type per GRDB table being synced, kept 1:1 for
  simplicity — no reason to get clever here.
- **Record IDs**: reuse the existing stable string ids directly as `CKRecord.ID.recordName`
  (`manga.id`, `"\(mangaId)_\(chapterId)"` for chapter-state records, `category.id`). No new UUID
  scheme needed anywhere — this is the direct payoff of the finding above.
- Development vs Production CloudKit environment: record types are auto-created in Development the
  first time a record of that type is saved from a debug build. Must be **manually promoted to
  Production via CloudKit Dashboard before App Store submission** — this is a one-time manual step to
  remember at ship time, easy to forget (not code, no automated check exists for it).

## Write path — hooking into the existing `*Queries` layer

Every local mutation already funnels through `MangaQueries`, `ChapterQueries`, `NovelQueries`,
`CategoryQueries` (per `CLAUDE.md`'s own absolute rule: "All `*Queries` methods must be
`nonisolated`"). That's the one choke point to hook, instead of touching call sites all over
`Features/`.

Proposed: a new `Yomi/Sync/CloudSyncManager.swift` (`@Observable` singleton, mirrors
`ExtensionManager`/`BackupManager`'s existing pattern) owning one `CKSyncEngine` instance. Each
`*Queries` write that touches a synced field calls a single new method,
`CloudSyncManager.shared.markDirty(recordType:recordID:)`, which appends to
`engine.state.add(pendingRecordZoneChanges:)`. `CKSyncEngine` batches these internally and sends them
on its own schedule — the app doesn't manage batching or timing, just marks what changed.

Concretely, the touch points are small and already enumerable from the Known-Issues history (these
are the same call sites #20/#26/#35 already touch for `lastReadAt`/toast-on-failure):
- `MangaQueries`/`NovelQueries`: `toggleLibrary`, `updateReadingStatus`, `update` (notes)
- `ChapterQueries`/`NovelQueries`: `setRead`, `markRead`, `markAllRead`/`markAllChapters`,
  `updateProgress`, `addReadingTime`
- `CategoryQueries`: `insert`, `rename`, `delete`, `updateSort`, `assign`, `unassign`

`CloudSyncManager.shared` would be MainActor-isolated (same as `ExtensionManager.shared` — see the
existing absolute rule "capture a local closure before entering Task.detached"), so `markDirty` calls
from inside `Task.detached` contexts need the same capture-before-detach pattern already established
project-wide. Not a new problem, just the existing one applied to a new singleton.

## Read/merge path — `CKSyncEngine` delegate + per-field conflict policy

`CKSyncEngine`'s delegate receives batches of remote `CKRecord` changes (fetched automatically after
each sync). The app maps each back to a GRDB upsert via the existing `*Queries.upsert`/`upsertAll`
methods (already exist for exactly this "insert-or-merge" shape, per `ARQUITECTURA.md`).

Conflict policy, since two devices can both change the same record between syncs:

- **Scalar "latest state wins" fields** (`isRead`, `progress`, `lastPageRead`, `readingStatus`,
  `inLibrary`, category assignment): CloudKit's own server record-change-tag mechanism already gives
  last-write-wins for free — accept it as-is. A real conflict here (reading the same chapter
  differently on two offline devices before either syncs) is a rare, low-stakes edge case; the losing
  device's local read-state gets overwritten on next sync. No custom merge logic needed.
- **`readingSeconds` (additive stat)** — this is the one field where naive last-write-wins is
  *wrong*, not just imprecise: it silently drops one device's reading-time contribution instead of
  summing it. **Flagging this rather than deciding unilaterally** (same call as S101's Paper/Sepia
  accent-contrast tension): the correct fix is summing rather than overwriting, but summing needs
  either a custom `CKRecord` merge (compare-and-swap using CloudKit's `recordChangeTag` retry loop) or
  accepting that the Insights streak/total-time stats can occasionally undercount after a sync
  conflict. Recommend **v1 accepts last-write-wins here too** (simplicity, and true concurrent-reading
  conflicts are rare) and revisit only if Insights numbers visibly drift in practice.
- **Manga/Novel catalog fields** (`title`, `coverURL`, `summary`, etc.) — effectively write-once:
  populated when a manga is first added to the library, rarely touched again except by
  `loadChapters()`'s Mangayomi-metadata backfill (`MangaDetailView.swift:1017-1031`). Last-write-wins
  is fine; no realistic conflict scenario.

## Bootstrap flow — enabling sync with existing local data

This is the part that most needs to be gotten right, since every existing user already has a real
library before this feature ships.

1. User flips a new "Sync across devices" toggle (Settings, next to the existing iCloud backup
   section — see UX below).
2. On first enable, `CloudSyncManager` does **not** wait for a remote fetch to decide what's
   authoritative. It walks the local GRDB library (`MangaQueries.fetchLibrary()` +
   `NovelQueries.fetchLibrary()` + all chapter states + categories) and marks every row dirty —
   i.e. pushes the entire local library up as the initial `CKSyncEngine` batch.
3. `CKSyncEngine` also performs its own initial full fetch of the zone in parallel. Because record IDs
   are content-derived (the key finding above), **a manga/chapter that exists identically on both the
   local device and in CloudKit merges into one record, not a duplicate** — there's no
   "two libraries got concatenated" failure mode to design around, which is the usual hard part of
   this kind of bootstrap.
4. Second-device-enables-sync case: same code path. That device's (possibly empty, possibly
   different) local library pushes up, CloudKit's existing records pull down, same id-based merge
   applies. No special-cased "first device vs. joining device" logic needed anywhere.

## Deletion — turns out there's almost nothing to design

Checked whether "remove from library" needs tombstone propagation (the usual hard part of any sync
system). It doesn't, here: `MangaQueries.delete`/`NovelQueries.delete`/`ChapterQueries.delete` exist
but **are never called from any `Features/` call site** (grepped project-wide). "Remove from library"
in the actual UI is `toggleLibrary()` → `inLibrary = false`, a field update, not a row delete
(`MangaDetailView.swift:930-934`). Rows persist indefinitely (history, browse-cache) whether or not
they're in the library.

This means CloudKit record deletion — `CKSyncEngine`'s delete-propagation path — is **not needed for
v1 at all**. `inLibrary: false` syncs as an ordinary field update through the same last-write-wins
path as everything else. Category deletion (`CategoryQueries.delete`, which *is* called from
`CategoryView.swift`) is the one real delete path in the app and does need a `CKRecord` deletion sent
through the engine — small, self-contained, no cascading-tombstone design needed since
`manga_category`/`novel_category` rows are `ON DELETE CASCADE` locally and the small number of
per-category link records can just be deleted alongside it.

## Settings / UX

- New toggle in `SettingsView`, in the same section as the existing "Back up to iCloud" control
  (`BackupView`) — but a visually distinct control, not folded into it, since it's a different
  feature (live sync vs. point-in-time backup — see relationship note below).
- Needs the same account-status handling the existing `BackupManager`/`ICloudSyncStatus` already
  established: `CKContainer.default().accountStatus()` checked before enabling; if the user isn't
  signed into iCloud, show the same "iCloud unavailable" state pattern already in `BackupView`,
  don't silently no-op.
- A small status row ("Last synced: 2m ago" / "Syncing…" / "Sync error — tap for details") — same
  shape as the existing `lastICloudUploadDate` display in `BackupView`, reusing that pattern rather
  than inventing a new one.

## Entitlements & one-time Xcode steps (new, beyond what backup already set up)

The existing `Yomi.entitlements` only has `ubiquity-container-identifiers` (iCloud Drive, for JSON
backup) — CloudKit is a separate capability:
1. Xcode → Signing & Capabilities → **+ Capability → iCloud** → check **CloudKit** (in addition to
   the already-checked "iCloud Documents"). This adds
   `com.apple.developer.icloud-services: [CloudKit]` and
   `com.apple.developer.icloud-container-identifiers` to the entitlements file.
2. A CloudKit container needs to exist — Xcode auto-creates one matching the bundle id
   (`iCloud.pacodealer.Yomi`, reusing the existing identifier is fine and keeps this one iCloud
   container serving both Drive-backup and CloudKit-record purposes) the first time the capability is
   added, or one can be picked explicitly in CloudKit Dashboard.
3. **No** Push Notifications / Remote Notifications background mode needed — direct consequence of
   the "sync on foreground/background, not real-time" decision above. This is the main entitlement
   complexity avoided by that choice.

## Testing plan

Two-simulator testing (the same category of thing S89 did for Suwayomi with a real local server):
boot two simulators signed into the **same** sandboxed Apple ID (CloudKit Development environment
supports this), make a change on one (mark a chapter read), foreground/background the other, confirm
it appears. CloudKit Dashboard (Development environment) is the ground truth for "did the record
actually reach the server" independent of whether the second device's fetch worked — same debugging
value as `sqlite3`-direct-inspection already is for local GRDB state (S98's Migrate testing
precedent).

## Known open questions — flagged, not decided here

1. **`Manga.id`/`Novel.id` are not always source-qualified.** Traced one code path
   (`parseMangayomiItem`, `JSBridge.swift:1795`) where `id` is set to the bare `path`/`link` with no
   `sourceId` prefix — meaning two *different* sources with the same content path could theoretically
   produce the same `Manga.id` today, independent of sync. This is a pre-existing property of the id
   scheme, not something sync introduces, but sync would make a collision more consequential (two
   unrelated manga from two sources would silently merge into one CloudKit record instead of just
   being two visually-identical-but-separate local rows). Worth a quick audit of all `Manga(id:
   ...)`/`Novel(id: ...)` construction sites before turning sync on broadly — out of scope for this
   design pass, flagged for whoever picks up implementation.
2. **`readingSeconds` last-write-wins** (see conflict policy above) — accepted as a v1 tradeoff,
   revisit if it matters in practice.
3. **Relationship to the existing iCloud JSON backup**: recommend keeping both, not merging them.
   Backup is disaster recovery / export-portability (survives a full CloudKit container reset,
   works even if sync is off, doubles as the Tachiyomi-import counterpart). Sync is the live
   cross-device feature. Different failure modes, worth keeping architecturally separate even though
   they'll look adjacent in Settings.

## As-built implementation notes (S103)

A few details were refined during implementation beyond what this doc originally scoped — recorded
here so the doc stays accurate as the reference, not just as history:

- **`CKRecord.ID.recordName` is a SHA256 hash of the local key, not the raw id.** This doc originally
  said "reuse the existing stable string ids directly as `CKRecord.ID.recordName`" — implemented
  differently once the actual constraint was considered: local ids are often full source URLs (a
  chapter's path), which risk CloudKit's recordName length limits and have no guaranteed-safe
  character set. `recordName = "\(typePrefix)_\(sha256Hex(key))"` sidesteps this entirely (fixed
  length, always-safe characters) at the cost of needing a small reverse-lookup table.
- **New GRDB table `cloud_sync_map`** (migration `v20_cloud_sync_map`, next migration must be `v21_`):
  `(recordName TEXT PK, recordType TEXT, key TEXT, recordData BLOB)`. Two jobs: (1) reverse-map a bare
  `CKRecord.ID` back to "which type, which GRDB row" when `CKSyncEngine` asks for a send batch (it
  only ever hands back record IDs, not app-level context); (2) cache the last-known-good `CKRecord`
  (archived via `NSKeyedArchiver`/`NSSecureCoding`) so the next save carries a real server
  `recordChangeTag` instead of being a "fresh" record with no tag — without this, CloudKit's own
  conflict detection (`.serverRecordChanged`) would never fire, silently defeating the last-write-wins
  policy this doc scoped rather than implementing it.
- **Real `CKSyncEngine` API names differ from the WWDC23 session's own code sample.** Verified against
  live developer.apple.com docs (not training-data memory) after the transcript's `.save(recordID)` /
  `.delete(recordID)` failed to compile: the shipped API is `.saveRecord(_:)` / `.deleteRecord(_:)` on
  `PendingRecordZoneChange`, `.saveZone(_:)` / `.deleteZone(_:)` on `PendingDatabaseChange`, and batch
  scoping is `context.options.scope.contains(pendingChange)`, not `context.options.zoneIDs.contains(...)`.
  Likely a beta-to-GA rename between when that talk was recorded and shipping iOS 17. Lesson for any
  future CloudKit/CKSyncEngine work: treat WWDC transcript code as directionally correct, verify exact
  symbol names against the live doc site before trusting a compile.
- **This project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` build setting applies to free-standing
  `enum`s too, not just classes** — `CloudRecordType`'s computed properties needed an explicit
  `nonisolated` (on the whole enum declaration, matching the existing `Notation` enum's precedent —
  see `METODOLOGIA.md`) since they're called from the sync engine's own non-MainActor delegate
  callbacks.
- **Deletion propagation stayed exactly as scoped**: only `CategoryQueries.delete` and
  `unassign`/`unassignNovel` (the manga/novel-category join rows) ever call `markCloudDeleted`.
  Everything else (`MangaQueries.delete`, `NovelQueries.delete`, `ChapterQueries.delete`) remains
  genuinely uncalled from `Features/`, exactly as found during scoping.

## What was verified, and what wasn't (S103)

This dev simulator has **no iCloud account signed in** (confirmed via the existing `BackupView`'s own
"iCloud not available" state, unrelated to this feature). That bounds what live-testing could actually
prove:

**Verified live**: clean `build_sim` (zero errors/warnings) after fixing the real API names above;
`build_run_sim` launches without crashing (the new entitlements — CloudKit services, Remote
Notifications background mode — didn't break code signing for the simulator target); the new Settings
→ More → Sync screen renders correctly; toggling "Sync across devices" on triggers a real
`CKContainer(identifier:).accountStatus()` call end-to-end and correctly lands on the `.unavailable`
UI state (icloud.slash icon, "iCloud account unavailable" text) exactly as designed for a
signed-out account; toggling back off cleanly calls `disable()` with no crash; normal navigation
through Library/Manga Detail/Reader after all the `*Queries` hook changes shows no regressions.

**Not verified, and can't be from this environment**: an actual record ever reaching CloudKit's
servers; the fetch/merge path (`applyRemote(record:)`) against a real remote change; the
`.serverRecordChanged` conflict path; the bootstrap push against a real account; two-device
convergence. All of this needs a simulator (or device) signed into a real iCloud account with this
container's CloudKit schema promoted at least to Development — **the next session that touches this
feature should start there**, per the testing plan above, before trusting it beyond what's written
here.

## Effort estimate — superseded, implementation is done

(Original pre-implementation estimate removed — see the As-built section above for what actually
shipped and the Effort/testing note for what's still unverified.)
