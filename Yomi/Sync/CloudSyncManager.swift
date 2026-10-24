import Foundation
import CloudKit
import CryptoKit
import GRDB
import Observation

// MARK: - CloudSyncStatus

enum CloudSyncStatus: Equatable {
    case idle
    case syncing
    case success
    case unavailable
    case error(String)
}

// MARK: - CloudRecordType
//
// One CKRecord type per synced GRDB concept. See Yomi/CLOUDKIT_SYNC_DESIGN.md for the full
// data-model table (what syncs vs. what stays device-local) and rationale.

nonisolated enum CloudRecordType: String, CaseIterable {
    case manga
    case novel
    case category
    case mangaChapterState
    case novelChapterState
    case mangaCategoryLink
    case novelCategoryLink

    var ckRecordType: String {
        switch self {
        case .manga:              return "Manga"
        case .novel:               return "Novel"
        case .category:            return "Category"
        case .mangaChapterState:   return "MangaChapterState"
        case .novelChapterState:   return "NovelChapterState"
        case .mangaCategoryLink:   return "MangaCategoryLink"
        case .novelCategoryLink:   return "NovelCategoryLink"
        }
    }

    var recordNamePrefix: String {
        switch self {
        case .manga:              return "manga"
        case .novel:               return "novel"
        case .category:            return "category"
        case .mangaChapterState:   return "mcs"
        case .novelChapterState:   return "ncs"
        case .mangaCategoryLink:   return "mcl"
        case .novelCategoryLink:   return "ncl"
        }
    }

    init?(ckRecordType: String) {
        guard let match = CloudRecordType.allCases.first(where: { $0.ckRecordType == ckRecordType }) else {
            return nil
        }
        self = match
    }
}

// MARK: - Module-level sync engine handle
//
// nonisolated(unsafe), mirroring this project's own established pattern for infrastructure globals
// (`appDatabase` in DatabaseManager.swift, `appRouter` in AppRouter.swift) rather than routing every
// *Queries write through a MainActor hop. CKSyncEngine's `state.add(pendingRecordZoneChanges:)` is
// documented as safe to call from any thread — it just enqueues an intent, the engine's own send
// loop (on whatever thread it chooses) later calls back into `nextRecordZoneChangeBatch` to build the
// actual CKRecord. So the *Queries write layer can mark a row dirty synchronously, exactly like every
// other Queries write, with zero added latency and no actor-hop bookkeeping.

nonisolated(unsafe) private var cloudSyncEngine: CKSyncEngine?
nonisolated(unsafe) private var cloudSyncZoneID = CKRecordZone.ID(
    zoneName: "LibraryZone", ownerName: CKCurrentUserDefaultName
)

/// Marks a local row dirty for the next CloudKit sync. Safe to call from any context, including
/// inside any `nonisolated static func` on `MangaQueries`/`ChapterQueries`/`NovelQueries`/
/// `CategoryQueries`. No-ops (durably, not silently) if sync isn't enabled yet — the mapping is
/// always persisted, and if no engine is running the mark is stashed in `cloud_sync_map.pendingChange`
/// instead of the engine's in-memory state, then drained into a real engine the next time
/// `CloudSyncManager.enable()` runs (closes the async window during its own accountStatus check —
/// see code-review finding #43).
nonisolated func markCloudDirty(_ type: CloudRecordType, key: String) {
    let recordID = CloudSyncManager.recordID(type: type, key: key, zoneID: cloudSyncZoneID)
    CloudSyncManager.rememberMapping(recordName: recordID.recordName, type: type, key: key)
    guard let engine = cloudSyncEngine else {
        CloudSyncManager.markPending(recordName: recordID.recordName, change: "save")
        return
    }
    engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
}

/// Marks a local row as deleted for the next CloudKit sync (category deletion, category
/// unassignment — the only two real per-row delete paths this app has; see
/// Yomi/CLOUDKIT_SYNC_DESIGN.md's "Deletion" section for why nothing else needs this). See
/// `markCloudDirty` above for the durable-pending-mark behavior when no engine is running yet.
nonisolated func markCloudDeleted(_ type: CloudRecordType, key: String) {
    let recordID = CloudSyncManager.recordID(type: type, key: key, zoneID: cloudSyncZoneID)
    CloudSyncManager.rememberMapping(recordName: recordID.recordName, type: type, key: key)
    guard let engine = cloudSyncEngine else {
        CloudSyncManager.markPending(recordName: recordID.recordName, change: "delete")
        return
    }
    engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
}

/// Batched form of `markCloudDirty` for bulk writes (e.g. "mark all chapters read") — does the
/// mapping-remember and pending-stash work for the whole key list in one database transaction each,
/// instead of the 2 separate transactions `markCloudDirty` performs per call. See code-review
/// finding #74.
nonisolated func markCloudDirtyBatch(_ type: CloudRecordType, keys: [String]) {
    guard !keys.isEmpty else { return }
    let recordIDs = keys.map { CloudSyncManager.recordID(type: type, key: $0, zoneID: cloudSyncZoneID) }
    CloudSyncManager.rememberMappingBatch(recordNames: recordIDs.map(\.recordName), type: type, keys: keys)
    guard let engine = cloudSyncEngine else {
        CloudSyncManager.markPendingBatch(recordNames: recordIDs.map(\.recordName), change: "save")
        return
    }
    engine.state.add(pendingRecordZoneChanges: recordIDs.map { .saveRecord($0) })
}

// MARK: - CloudSyncManager

@MainActor
@Observable
final class CloudSyncManager: NSObject {

    static let shared = CloudSyncManager()

    // MARK: UI-facing state

    var status: CloudSyncStatus = .idle
    var lastSyncDate: Date? = UserDefaults.standard.object(forKey: "lastCloudSyncDate") as? Date
    var isAccountAvailable = false

    /// Changes the server refused for good (recordName → what was sent + why). CKSyncEngine forgets such a
    /// change, so without this list the next sync would report success (#204). An entry leaves when the
    /// record is sent successfully; each one is also stashed in `cloud_sync_map.pendingChange`, so the next
    /// `enable()` (next launch — maybe a newer build) sends it again.
    private(set) var failedChanges: [String: FailedChange] = [:]

    struct FailedChange: Equatable {
        var isDelete: Bool
        var reason: String
    }

    /// Guards `enable()` against a double-call race (code-review finding #44): cold-launch auto-enable
    /// and a fast manual Settings toggle can both reach the `await container.accountStatus()` call
    /// before `cloudSyncEngine` is assigned. Set synchronously before the first `await`, so the second
    /// caller's guard check (itself synchronous up to its own first `await`, and MainActor-serialized
    /// against the first) reliably sees it.
    private var isEnabling = false

    // MARK: Config

    private static let containerIdentifier = "iCloud.pacodealer.Yomi"
    private static let zoneName = "LibraryZone"

    private static let stateFileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("CloudSyncEngineState.data")
    }()

    // Lazy so a build without the iCloud entitlement (YOMI_PERSONAL, below) never constructs it.
    @ObservationIgnored private lazy var container = CKContainer(identifier: CloudSyncManager.containerIdentifier)
    private let zoneID = CKRecordZone.ID(zoneName: CloudSyncManager.zoneName, ownerName: CKCurrentUserDefaultName)

    private override init() {
        super.init()
    }

    // MARK: - Enable / disable

    /// Starts the sync engine. On the very first enable on this device (no previously-persisted
    /// engine state), walks the local library and pushes it all up as pending changes — see
    /// Yomi/CLOUDKIT_SYNC_DESIGN.md's "Bootstrap flow" section for why this needs no special-cased
    /// merge logic against whatever's already in CloudKit.
    func enable() async {
        guard cloudSyncEngine == nil, !isEnabling else { return }
        #if YOMI_PERSONAL
        // Personal build (Config/Personal.xcconfig): signed by a free Personal Team, which cannot carry the
        // iCloud/CloudKit entitlement — touching CKContainer would fail. Report sync as unavailable instead.
        isAccountAvailable = false
        status = .unavailable
        return
        #else
        isEnabling = true
        defer { isEnabling = false }

        let accountStatus = (try? await container.accountStatus()) ?? .couldNotDetermine
        guard accountStatus == .available else {
            isAccountAvailable = false
            status = .unavailable
            return
        }
        isAccountAvailable = true

        let isFirstEnable = !FileManager.default.fileExists(atPath: Self.stateFileURL.path)
        let serialization = Self.loadStateSerialization()

        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: serialization,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        cloudSyncEngine = engine
        cloudSyncZoneID = zoneID

        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])

        // Replay any dirty/delete marks that landed while no engine existed yet — the async window
        // between this function starting and `cloudSyncEngine` being assigned above (finding #43).
        await Self.drainPendingMarks(engine: engine, zoneID: zoneID)

        if isFirstEnable {
            await bootstrapPushAllLocalData()
            UserDefaults.standard.set(true, forKey: Self.novelPathResendKey)
        } else if !UserDefaults.standard.bool(forKey: Self.novelPathResendKey) {
            await resendNovelChapterStates(engine: engine)
            UserDefaults.standard.set(true, forKey: Self.novelPathResendKey)
        }

        await syncNow()
        #endif
    }

    /// App back in the foreground: sync, or start sync if it never started — a single "no account" answer at launch
    /// (iCloud still signing in, no network yet) used to leave sync off until the next launch (S189 audit #6).
    func resume() async {
        if cloudSyncEngine == nil { await enable() } else { await syncNow() }
    }

    /// Stops the sync engine. Local data is untouched — disabling sync just stops pushing/pulling,
    /// same as the existing iCloud *backup* toggle already behaves.
    func disable() {
        cloudSyncEngine = nil
        status = .idle
    }

    // MARK: - Manual triggers

    /// Explicit fetch+send, called on app foreground/background (see YomiApp.swift) rather than
    /// relying on real-time push — see Yomi/CLOUDKIT_SYNC_DESIGN.md's "sync latency" decision.
    func syncNow(retryFailed: Bool = false) async {
        guard let engine = cloudSyncEngine else { return }
        status = .syncing
        if retryFailed, !failedChanges.isEmpty {
            // Failures come back through `handleEvent` and land in `failedChanges` again.
            let retries: [CKSyncEngine.PendingRecordZoneChange] = failedChanges.map { recordName, failure in
                let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
                return failure.isDelete ? .deleteRecord(recordID) : .saveRecord(recordID)
            }
            failedChanges = [:]
            engine.state.add(pendingRecordZoneChanges: retries)
        }
        do {
            try await engine.sendChanges()
            try await engine.fetchChanges()
            let now = Date()
            lastSyncDate = now
            UserDefaults.standard.set(now, forKey: "lastCloudSyncDate")
            status = .success
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    /// Passthrough from AppDelegate's didReceiveRemoteNotification. CKSyncEngine's own
    /// CKDatabaseSubscription mechanism drives most of this automatically once the app is registered
    /// for remote notifications — this just makes sure a foregrounded sync happens promptly on
    /// receipt rather than waiting for the next scenePhase change.
    func handleRemoteNotification() async {
        guard cloudSyncEngine != nil else { return }
        await syncNow()
    }

    /// Drains `cloud_sync_map.pendingChange` rows (marks made while no engine was running) into a
    /// freshly-created engine's own persisted state. See `markCloudDirty`/`markCloudDeleted` above.
    private static func drainPendingMarks(engine: CKSyncEngine, zoneID: CKRecordZone.ID) async {
        let rows: [(recordName: String, change: String)] = await Task.detached(priority: .utility) {
            let fetched: [Row] = (try? appDatabase.read { db in
                try Row.fetchAll(db, sql: "SELECT recordName, pendingChange FROM cloud_sync_map WHERE pendingChange IS NOT NULL")
            }) ?? []
            return fetched.map { ($0["recordName"] as String, $0["pendingChange"] as String) }
        }.value

        guard !rows.isEmpty else { return }

        let changes: [CKSyncEngine.PendingRecordZoneChange] = rows.map { row in
            let recordID = CKRecord.ID(recordName: row.recordName, zoneID: zoneID)
            return row.change == "delete" ? .deleteRecord(recordID) : .saveRecord(recordID)
        }
        engine.state.add(pendingRecordZoneChanges: changes)

        await Task.detached(priority: .utility) {
            _ = try? appDatabase.write { db in
                try db.execute(sql: "UPDATE cloud_sync_map SET pendingChange = NULL WHERE pendingChange IS NOT NULL")
            }
        }.value
    }

    // MARK: - Bootstrap

    private static let novelPathResendKey = "cloudSyncNovelPathResent"

    /// Once per device after S191: sends every novel chapter state again so the records already in iCloud gain the
    /// chapter's path (#4) — until then another device can only match them by id.
    private func resendNovelChapterStates(engine: CKSyncEngine) async {
        let zoneID = self.zoneID
        let keys: [String] = await Task.detached(priority: .utility) {
            let rows = (try? appDatabase.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT id, novelId FROM novel_chapter
                    WHERE isRead = 1 OR readingSeconds > 0 OR lastScrollPercent > 0
                    """)
            }) ?? []
            return rows.map { "\($0["novelId"] as String)|\($0["id"] as String)" }
        }.value
        guard !keys.isEmpty else { return }
        await Task.detached(priority: .utility) {
            let names = keys.map { CloudSyncManager.recordID(type: .novelChapterState, key: $0, zoneID: zoneID).recordName }
            CloudSyncManager.rememberMappingBatch(recordNames: names, type: .novelChapterState, keys: keys)
        }.value
        engine.state.add(pendingRecordZoneChanges: keys.map {
            .saveRecord(Self.recordID(type: .novelChapterState, key: $0, zoneID: zoneID))
        })
    }

    private func bootstrapPushAllLocalData(engine: CKSyncEngine? = nil) async {
        guard let engine = engine ?? cloudSyncEngine else { return }
        let zoneID = self.zoneID

        let changes: [CKSyncEngine.PendingRecordZoneChange] = await Task.detached(priority: .utility) {
            var result: [CKSyncEngine.PendingRecordZoneChange] = []

            func add(_ type: CloudRecordType, _ key: String) {
                let recordID = CloudSyncManager.recordID(type: type, key: key, zoneID: zoneID)
                CloudSyncManager.rememberMapping(recordName: recordID.recordName, type: type, key: key)
                result.append(.saveRecord(recordID))
            }

            for manga in (try? MangaQueries.fetchLibrary()) ?? [] {
                add(.manga, manga.id)
            }
            for novel in (try? NovelQueries.fetchLibrary()) ?? [] {
                add(.novel, novel.id)
            }
            for category in (try? CategoryQueries.fetchAll()) ?? [] {
                add(.category, category.id)
            }

            if let rows = try? appDatabase.read({ db in
                try Row.fetchAll(db, sql: """
                    SELECT id, mangaId FROM chapter
                    WHERE isRead = 1 OR progress > 0 OR lastPageRead > 0 OR readingSeconds > 0
                    """)
            }) {
                for row in rows {
                    let mangaId: String = row["mangaId"]
                    let chapterId: String = row["id"]
                    add(.mangaChapterState, "\(mangaId)|\(chapterId)")
                }
            }

            if let rows = try? appDatabase.read({ db in
                try Row.fetchAll(db, sql: """
                    SELECT id, novelId FROM novel_chapter
                    WHERE isRead = 1 OR readingSeconds > 0 OR lastScrollPercent > 0
                    """)
            }) {
                for row in rows {
                    let novelId: String = row["novelId"]
                    let chapterId: String = row["id"]
                    add(.novelChapterState, "\(novelId)|\(chapterId)")
                }
            }

            if let rows = try? appDatabase.read({ db in
                try Row.fetchAll(db, sql: "SELECT mangaId, categoryId FROM manga_category")
            }) {
                for row in rows {
                    let mangaId: String = row["mangaId"]
                    let categoryId: String = row["categoryId"]
                    add(.mangaCategoryLink, "\(mangaId)|\(categoryId)")
                }
            }

            if let rows = try? appDatabase.read({ db in
                try Row.fetchAll(db, sql: "SELECT novelId, categoryId FROM novel_category")
            }) {
                for row in rows {
                    let novelId: String = row["novelId"]
                    let categoryId: String = row["categoryId"]
                    add(.novelCategoryLink, "\(novelId)|\(categoryId)")
                }
            }

            return result
        }.value

        engine.state.add(pendingRecordZoneChanges: changes)
    }

    // MARK: - State serialization persistence

    fileprivate static func loadStateSerialization() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateFileURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    fileprivate static func saveStateSerialization(_ serialization: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(serialization) else { return }
        try? data.write(to: stateFileURL, options: .atomic)
    }

    // MARK: - recordName scheme + reverse-lookup map (cloud_sync_map table)

    /// recordName is a SHA256 hash of the local key rather than the raw key — local keys are often
    /// full source URLs (chapter paths), which can exceed CloudKit's recordName limits or contain
    /// characters worth not relying on. The unhashed `key`/`recordType` pair is preserved in
    /// `cloud_sync_map` (and, redundantly, as plain fields on the record itself) purely for lookups.
    nonisolated static func recordID(type: CloudRecordType, key: String, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return CKRecord.ID(recordName: "\(type.recordNamePrefix)_\(hex)", zoneID: zoneID)
    }

    nonisolated static func rememberMapping(recordName: String, type: CloudRecordType, key: String) {
        _ = try? appDatabase.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO cloud_sync_map (recordName, recordType, key, recordData) VALUES (?, ?, ?, COALESCE((SELECT recordData FROM cloud_sync_map WHERE recordName = ?), NULL))",
                arguments: [recordName, type.rawValue, key, recordName]
            )
        }
    }

    /// Durably stashes a dirty/delete mark for a record when no `CKSyncEngine` is running yet — see
    /// `markCloudDirty`/`markCloudDeleted` above. `rememberMapping` must already have been called for
    /// this `recordName` (it always is, by both call sites) so the row exists to update.
    nonisolated static func markPending(recordName: String, change: String) {
        _ = try? appDatabase.write { db in
            try db.execute(
                sql: "UPDATE cloud_sync_map SET pendingChange = ? WHERE recordName = ?",
                arguments: [change, recordName]
            )
        }
    }

    /// Batched form of `rememberMapping` — one transaction for the whole list. See finding #74.
    nonisolated static func rememberMappingBatch(recordNames: [String], type: CloudRecordType, keys: [String]) {
        _ = try? appDatabase.write { db in
            for (recordName, key) in zip(recordNames, keys) {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO cloud_sync_map (recordName, recordType, key, recordData) VALUES (?, ?, ?, COALESCE((SELECT recordData FROM cloud_sync_map WHERE recordName = ?), NULL))",
                    arguments: [recordName, type.rawValue, key, recordName]
                )
            }
        }
    }

    /// Batched form of `markPending` — one transaction for the whole list. See finding #74.
    nonisolated static func markPendingBatch(recordNames: [String], change: String) {
        _ = try? appDatabase.write { db in
            for recordName in recordNames {
                try db.execute(
                    sql: "UPDATE cloud_sync_map SET pendingChange = ? WHERE recordName = ?",
                    arguments: [change, recordName]
                )
            }
        }
    }

    /// `rememberMapping` inside a caller's transaction (the batched apply, #5).
    nonisolated static func rememberMapping(recordName: String, type: CloudRecordType, key: String, db: Database) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO cloud_sync_map (recordName, recordType, key, recordData) VALUES (?, ?, ?, COALESCE((SELECT recordData FROM cloud_sync_map WHERE recordName = ?), NULL))",
            arguments: [recordName, type.rawValue, key, recordName]
        )
    }

    nonisolated static func mapping(for recordName: String, db: Database) throws -> (type: CloudRecordType, key: String)? {
        guard let row = try Row.fetchOne(db, sql: "SELECT recordType, key FROM cloud_sync_map WHERE recordName = ?",
                                         arguments: [recordName]),
              let type = CloudRecordType(rawValue: row["recordType"] as String) else { return nil }
        return (type, row["key"] as String)
    }

    nonisolated static func cacheRecord(_ record: CKRecord, db: Database) throws {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true) else { return }
        try db.execute(sql: "UPDATE cloud_sync_map SET recordData = ? WHERE recordName = ?",
                       arguments: [data, record.recordID.recordName])
    }

    private nonisolated static func mapping(for recordName: String) -> (type: CloudRecordType, key: String)? {
        let row: Row? = (try? appDatabase.read { db in
            try Row.fetchOne(db, sql: "SELECT recordType, key FROM cloud_sync_map WHERE recordName = ?", arguments: [recordName])
        }) ?? nil
        guard let row else { return nil }
        guard let type = CloudRecordType(rawValue: row["recordType"] as String) else { return nil }
        return (type, row["key"] as String)
    }

    private nonisolated static func cachedRecordData(for recordName: String) -> Data? {
        try? appDatabase.read { db in
            try Data.fetchOne(db, sql: "SELECT recordData FROM cloud_sync_map WHERE recordName = ?", arguments: [recordName])
        } ?? nil
    }

    private nonisolated static func clearCachedRecord(recordName: String) {
        _ = try? appDatabase.write { db in
            try db.execute(sql: "UPDATE cloud_sync_map SET recordData = NULL WHERE recordName = ?", arguments: [recordName])
        }
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudSyncManager: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            Self.saveStateSerialization(update.stateSerialization)

        case .accountChange(let change):
            switch change.changeType {
            case .signIn, .switchAccounts:
                // The engine starts over for the new account, and that account may hold none of this library — send
                // all of it again (S189 audit #6). Nothing local is deleted: the library belongs to this phone first.
                // Cached change tags stay: back on the SAME account they keep edits made while signed out from
                // losing to the server copy; on another account a tag that names nothing comes back `.unknownItem`,
                // which is sent again as new (below).
                isAccountAvailable = true
                await bootstrapPushAllLocalData(engine: syncEngine)
            case .signOut:
                isAccountAvailable = false
                status = .unavailable
            @unknown default:
                break
            }

        case .fetchedRecordZoneChanges(let event):
            await Self.applyRemoteBatch(records: event.modifications.map(\.record),
                                        deletions: event.deletions.map(\.recordID))

        case .sentRecordZoneChanges(let event):
            for saved in event.savedRecords { failedChanges[saved.recordID.recordName] = nil }
            // One write for the whole batch, off the main actor (#5).
            let saved = UncheckedRecords(records: event.savedRecords, deletions: [])
            await Task.detached(priority: .utility) {
                _ = try? appDatabase.write { db in for record in saved.records { try Self.cacheRecord(record, db: db) } }
            }.value
            for deleted in event.deletedRecordIDs {
                failedChanges[deleted.recordName] = nil
            }
            for (recordID, error) in event.failedRecordDeletes {
                noteFailedChange(recordID: recordID, isDelete: true, error: error)
            }
            var serverWins: [CKRecord] = []
            for failedSave in event.failedRecordSaves {
                let recordID = failedSave.record.recordID
                switch failedSave.error.code {
                case .serverRecordChanged:
                    // v1 conflict policy: last write wins, server's committed value is authoritative —
                    // no custom per-field merge. See Yomi/CLOUDKIT_SYNC_DESIGN.md's conflict-policy note.
                    if let serverRecord = failedSave.error.serverRecord { serverWins.append(serverRecord) }
                case .zoneNotFound:
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
                case .unknownItem:
                    // Gone from the server, so the cached copy's change tag points at nothing — send it as new.
                    Self.clearCachedRecord(recordName: recordID.recordName)
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
                default:
                    noteFailedChange(recordID: recordID, isDelete: false, error: failedSave.error)
                }
            }
            if !serverWins.isEmpty { await Self.applyRemoteBatch(records: serverWins, deletions: []) }

        default:
            break
        }
    }

    /// The engine retries these itself and keeps the change pending — same list as Apple's CKSyncEngine sample.
    private static let selfRetriedErrors: Set<CKError.Code> = [
        .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated, .operationCancelled
    ]

    private func noteFailedChange(recordID: CKRecord.ID, isDelete: Bool, error: CKError) {
        guard !Self.selfRetriedErrors.contains(error.code) else { return }
        NSLog("CloudSync: %@ of %@ rejected: %@", isDelete ? "delete" : "save", recordID.recordName, "\(error)")
        // The server's own sentence when there is one — `localizedDescription` is mostly the record ID.
        let reason = error.userInfo["ServerErrorDescription"] as? String ?? error.localizedDescription
        failedChanges[recordID.recordName] = FailedChange(isDelete: isDelete, reason: reason)
        Self.markPending(recordName: recordID.recordName, change: isDelete ? "delete" : "save")
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scopedChanges = syncEngine.state.pendingRecordZoneChanges.filter {
            context.options.scope.contains($0)
        }
        guard !scopedChanges.isEmpty else { return nil }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: scopedChanges) { recordID in
            CloudSyncManager.buildRecord(for: recordID)
        }
    }
}

// MARK: - Record building (local -> CKRecord, for sends)

private extension CloudSyncManager {

    nonisolated static func buildRecord(for recordID: CKRecord.ID) -> CKRecord? {
        guard let mapping = mapping(for: recordID.recordName) else { return nil }

        let base: CKRecord
        if let data = cachedRecordData(for: recordID.recordName),
           let cached = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: data) {
            base = cached
        } else {
            base = CKRecord(recordType: mapping.type.ckRecordType, recordID: recordID)
        }

        switch mapping.type {
        case .manga:
            guard let manga = try? MangaQueries.fetchOne(id: mapping.key) else { return nil }
            populate(base, from: manga)
            // Hidden scanlation groups (v28). Sorted so the record doesn't change when the set doesn't; nil when
            // empty — CloudKit can't start a new field with an empty list (S152).
            let excluded = ((try? ChapterQueries.excludedScanlators(mangaId: manga.id)) ?? []).sorted()
            base["excludedScanlators"] = excluded.isEmpty ? nil : excluded
        case .novel:
            guard let novel = try? NovelQueries.fetchOne(id: mapping.key) else { return nil }
            populate(base, from: novel)
        case .category:
            guard let category = try? appDatabase.read({ db in try Category.fetchOne(db, key: mapping.key) }) else { return nil }
            populate(base, from: category)
        case .mangaChapterState:
            let parts = mapping.key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let chapter = try? ChapterQueries.fetchOne(id: parts[1]) else { return nil }
            populate(base, mangaId: parts[0], from: chapter)
        case .novelChapterState:
            let parts = mapping.key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            guard let chapter = try? appDatabase.read({ db in try NovelChapter.fetchOne(db, key: parts[1]) }) else { return nil }
            // A record that came from another device names a chapter by THAT device's id, which can be a different
            // chapter here (position ids, #4) — never send this chapter's state under it.
            if let syncedPath = base["path"] as? String, syncedPath != chapter.path { return nil }
            populate(base, novelId: parts[0], from: chapter)
        case .mangaCategoryLink:
            let parts = mapping.key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            base["mangaId"] = parts[0]
            base["categoryId"] = parts[1]
        case .novelCategoryLink:
            let parts = mapping.key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            base["novelId"] = parts[0]
            base["categoryId"] = parts[1]
        }
        return base
    }

    nonisolated static func populate(_ record: CKRecord, from manga: Manga) {
        record["localId"]       = manga.id
        record["path"]          = manga.path
        record["sourceId"]      = manga.sourceId
        record["title"]         = manga.title
        record["coverURL"]      = manga.coverURL?.absoluteString
        record["summary"]       = manga.summary
        record["author"]        = manga.author
        record["artist"]        = manga.artist
        record["status"]        = manga.status.rawValue
        // CloudKit rejects an empty list on a field it has not seen yet ("cannot use an empty list to initialize a
        // new field", S152) and the failed record is then dropped — send nothing instead.
        record["genres"]        = manga.genres.isEmpty ? nil : manga.genres
        #if DEBUG
        // `-yomiSyncRejectManga`: a wrong-typed field, so the server rejects every Manga save (#204 check).
        if ProcessInfo.processInfo.arguments.contains("-yomiSyncRejectManga") { record["status"] = 1 }
        #endif
        record["inLibrary"]     = manga.inLibrary
        record["lastReadAt"]    = manga.lastReadAt
        record["lastUpdatedAt"] = manga.lastUpdatedAt
        record["readingSeconds"] = Int64(manga.readingSeconds)
        record["readingStatus"] = manga.readingStatus.rawValue
        record["notes"]         = manga.notes
    }

    nonisolated static func populate(_ record: CKRecord, from novel: Novel) {
        record["localId"]       = novel.id
        record["path"]          = novel.path
        record["sourceId"]      = novel.sourceId
        record["title"]         = novel.title
        record["coverURL"]      = novel.coverURL?.absoluteString
        record["summary"]       = novel.summary
        record["author"]        = novel.author
        record["status"]        = novel.status
        // CloudKit rejects an empty list on a field it has not seen yet ("cannot use an empty list to initialize a
        // new field", S152) and the failed record is then dropped — send nothing instead.
        record["genres"]        = novel.genres.isEmpty ? nil : novel.genres
        record["inLibrary"]     = novel.inLibrary
        record["lastReadAt"]    = novel.lastReadAt
        record["lastUpdatedAt"] = novel.lastUpdatedAt
        record["readingSeconds"] = Int64(novel.readingSeconds)
        record["readingStatus"] = novel.readingStatus.rawValue
        record["notes"]         = novel.notes
    }

    nonisolated static func populate(_ record: CKRecord, from category: Category) {
        record["localId"] = category.id
        record["name"]    = category.name
        record["sort"]    = Int64(category.sort)
    }

    nonisolated static func populate(_ record: CKRecord, mangaId: String, from chapter: Chapter) {
        record["mangaId"]        = mangaId
        record["chapterId"]      = chapter.id
        record["isRead"]         = chapter.isRead
        record["progress"]       = chapter.progress
        record["lastPageRead"]   = Int64(chapter.lastPageRead)
        record["readAt"]         = chapter.readAt
        record["readingSeconds"] = Int64(chapter.readingSeconds)
        record["isBookmarked"]   = chapter.isBookmarked
    }

    nonisolated static func populate(_ record: CKRecord, novelId: String, from chapter: NovelChapter) {
        record["novelId"]           = novelId
        record["chapterId"]         = chapter.id
        // What another device matches on (S191, #4): ids are list positions and differ between devices.
        record["path"]              = chapter.path
        record["isRead"]            = chapter.isRead
        record["readAt"]            = chapter.readAt
        record["readingSeconds"]    = Int64(chapter.readingSeconds)
        record["lastScrollPercent"] = chapter.lastScrollPercent
        record["isBookmarked"]      = chapter.isBookmarked
    }
}

// MARK: - Applying remote records (CKRecord -> local, for fetches + conflict resolution)

extension CloudSyncManager {

    /// Writes a fetched batch off the main thread in ONE transaction (S189 audit #5: each record used to take ~3 write
    /// transactions on the main actor, so a first sync of a big library froze the UI). Each record runs in its own
    /// savepoint, so one record that fails to apply never takes the rest of the batch with it.
    nonisolated static func applyRemoteBatch(records: [CKRecord], deletions: [CKRecord.ID]) async {
        guard !records.isEmpty || !deletions.isEmpty else { return }
        let box = UncheckedRecords(records: records, deletions: deletions)
        await Task.detached(priority: .utility) {
            _ = try? appDatabase.write { db in
                for record in box.records {
                    do {
                        try db.inSavepoint { try applyRemote(record: record, db: db); return .commit }
                    } catch {
                        NSLog("CloudSync: could not apply %@: %@", record.recordID.recordName, "\(error)")
                    }
                }
                for recordID in box.deletions {
                    try? db.inSavepoint { try applyRemoteDeletion(recordID: recordID, db: db); return .commit }
                }
            }
        }.value
    }

    /// CKRecord isn't Sendable; the batch is handed to one detached task and never touched by the caller again.
    struct UncheckedRecords: @unchecked Sendable {
        let records: [CKRecord]
        let deletions: [CKRecord.ID]
    }

    nonisolated static func applyRemote(record: CKRecord, db: Database) throws {
        guard let type = CloudRecordType(ckRecordType: record.recordType) else { return }
        try rememberMapping(recordName: record.recordID.recordName, type: type, key: mapKey(for: type, record: record), db: db)
        // Keep the server's change tag: a later local edit sent without it comes back as a conflict, and the
        // server copy then overwrites the edit (#205).
        try cacheRecord(record, db: db)

        switch type {
        case .manga:
            guard let id = record["localId"] as? String else { return }
            var manga = try Manga.fetchOne(db, key: id) ?? Manga(
                id: id,
                path: record["path"] as? String ?? "",
                sourceId: record["sourceId"] as? String ?? "",
                title: record["title"] as? String ?? "",
                coverURL: nil, summary: nil, author: nil, artist: nil,
                status: .unknown, genres: [], inLibrary: false, isLocal: false,
                lastReadAt: nil, lastUpdatedAt: nil, readingSeconds: 0
            )
            manga.title          = record["title"] as? String ?? manga.title
            manga.coverURL       = (record["coverURL"] as? String).flatMap { URL(string: $0) } ?? manga.coverURL
            manga.summary        = record["summary"] as? String
            manga.author         = record["author"] as? String
            manga.artist         = record["artist"] as? String
            manga.status         = MangaStatus(rawValue: record["status"] as? String ?? "") ?? manga.status
            manga.genres         = record["genres"] as? [String] ?? manga.genres
            manga.inLibrary      = record["inLibrary"] as? Bool ?? manga.inLibrary
            manga.lastReadAt     = record["lastReadAt"] as? Date
            manga.lastUpdatedAt  = record["lastUpdatedAt"] as? Date
            manga.readingSeconds = Int(record["readingSeconds"] as? Int64 ?? 0)
            manga.readingStatus  = ReadingStatus(rawValue: record["readingStatus"] as? String ?? "none") ?? .none
            manga.notes          = record["notes"] as? String
            try manga.save(db)
            try ChapterQueries.replaceExcludedScanlators(Set(record["excludedScanlators"] as? [String] ?? []),
                                                         mangaId: id, db: db)

        case .novel:
            guard let id = record["localId"] as? String else { return }
            var novel = try Novel.fetchOne(db, key: id) ?? Novel(
                id: id,
                path: record["path"] as? String ?? "",
                sourceId: record["sourceId"] as? String ?? "",
                title: record["title"] as? String ?? "",
                coverURL: nil, summary: nil, author: nil,
                status: "", genres: [], inLibrary: false,
                lastReadAt: nil, lastUpdatedAt: nil, readingSeconds: 0,
                readingStatus: .none, notes: nil
            )
            novel.title          = record["title"] as? String ?? novel.title
            novel.coverURL       = (record["coverURL"] as? String).flatMap { URL(string: $0) } ?? novel.coverURL
            novel.summary        = record["summary"] as? String
            novel.author         = record["author"] as? String
            novel.status         = record["status"] as? String ?? novel.status
            novel.genres         = record["genres"] as? [String] ?? novel.genres
            novel.inLibrary      = record["inLibrary"] as? Bool ?? novel.inLibrary
            novel.lastReadAt     = record["lastReadAt"] as? Date
            novel.lastUpdatedAt  = record["lastUpdatedAt"] as? Date
            novel.readingSeconds = Int(record["readingSeconds"] as? Int64 ?? 0)
            novel.readingStatus  = ReadingStatus(rawValue: record["readingStatus"] as? String ?? "none") ?? .none
            novel.notes          = record["notes"] as? String
            try novel.save(db)

        case .category:
            guard let id = record["localId"] as? String,
                  let name = record["name"] as? String else { return }
            let sort = Int(record["sort"] as? Int64 ?? 0)
            try db.execute(
                sql: "INSERT INTO category (id, name, sort) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name, sort = excluded.sort",
                arguments: [id, name, sort]
            )

        case .mangaChapterState:
            guard let mangaId = record["mangaId"] as? String,
                  let chapterId = record["chapterId"] as? String else { return }
            let isRead = record["isRead"] as? Bool ?? false
            let progress = record["progress"] as? Double ?? 0
            let lastPageRead = Int(record["lastPageRead"] as? Int64 ?? 0)
            let readAt = record["readAt"] as? Date
            let readingSeconds = Int(record["readingSeconds"] as? Int64 ?? 0)
            let isBookmarked = record["isBookmarked"] as? Bool ?? false
            try db.execute(
                sql: """
                    UPDATE chapter SET isRead = ?, progress = ?, lastPageRead = ?, readAt = ?, readingSeconds = ?,
                        isBookmarked = ?
                    WHERE id = ? AND mangaId = ?
                    """,
                arguments: [isRead, progress, lastPageRead, readAt, readingSeconds, isBookmarked, chapterId, mangaId]
            )
            if db.changesCount == 0 {
                // The chapter isn't locally cached yet (its detail page has never been opened on
                // this device) — a real upsert isn't possible, the sync payload has no title/url/
                // chapterNumber to construct a valid chapter row with. CKSyncEngine won't redeliver
                // this change once acknowledged, so stash it and replay once the chapter row
                // actually gets inserted (see ChapterQueries.insertAllIgnoringConflicts /
                // insertMangaAndChapters). Fixes code-review finding #41.
                try db.execute(
                    sql: """
                        INSERT INTO pending_chapter_state (mangaId, chapterId, isRead, progress, lastPageRead, readAt, readingSeconds, isBookmarked)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(mangaId, chapterId) DO UPDATE SET
                            isRead = excluded.isRead, progress = excluded.progress, lastPageRead = excluded.lastPageRead,
                            readAt = excluded.readAt, readingSeconds = excluded.readingSeconds, isBookmarked = excluded.isBookmarked
                        """,
                    arguments: [mangaId, chapterId, isRead, progress, lastPageRead, readAt, readingSeconds, isBookmarked]
                )
            } else if isRead {
                try bumpLastRead(table: "manga", id: mangaId, readAt: readAt, db: db)
            }

        case .novelChapterState:
            guard let novelId = record["novelId"] as? String,
                  let chapterId = record["chapterId"] as? String else { return }
            let isRead = record["isRead"] as? Bool ?? false
            let readAt = record["readAt"] as? Date
            let readingSeconds = Int(record["readingSeconds"] as? Int64 ?? 0)
            let lastScrollPercent = record["lastScrollPercent"] as? Double
            let isBookmarked = record["isBookmarked"] as? Bool ?? false
            // Matched by PATH when the record has one (S191, #4): the sender's id is a list position on ITS device
            // and can name a different chapter here. Records from before S191 have no path — by id, as before.
            let path = record["path"] as? String
            let target = path.map { ("novelId = ? AND path = ?", StatementArguments([novelId, $0])) }
                ?? ("novelId = ? AND id = ?", StatementArguments([novelId, chapterId]))
            try db.execute(
                sql: "UPDATE novel_chapter SET isRead = ?, readAt = ?, readingSeconds = ?, lastScrollPercent = ?, isBookmarked = ? WHERE \(target.0)",
                arguments: [isRead, readAt, readingSeconds, lastScrollPercent, isBookmarked] + target.1
            )
            if db.changesCount == 0 {
                // Same reasoning as .mangaChapterState above — stash and replay once
                // NovelQueries.insertAllIgnoringConflicts brings the chapter row in (by path when known).
                try db.execute(
                    sql: """
                        INSERT INTO pending_novel_chapter_state (novelId, chapterId, path, isRead, readAt, readingSeconds, lastScrollPercent, isBookmarked)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(novelId, chapterId) DO UPDATE SET
                            path = excluded.path, isRead = excluded.isRead, readAt = excluded.readAt,
                            readingSeconds = excluded.readingSeconds, lastScrollPercent = excluded.lastScrollPercent,
                            isBookmarked = excluded.isBookmarked
                        """,
                    arguments: [novelId, chapterId, path, isRead, readAt, readingSeconds, lastScrollPercent, isBookmarked]
                )
            } else if isRead {
                try bumpLastRead(table: "novel", id: novelId, readAt: readAt, db: db)
            }

        case .mangaCategoryLink:
            guard let mangaId = record["mangaId"] as? String,
                  let categoryId = record["categoryId"] as? String else { return }
            try db.execute(sql: "INSERT OR IGNORE INTO manga_category (mangaId, categoryId) VALUES (?, ?)",
                           arguments: [mangaId, categoryId])

        case .novelCategoryLink:
            guard let novelId = record["novelId"] as? String,
                  let categoryId = record["categoryId"] as? String else { return }
            try db.execute(sql: "INSERT OR IGNORE INTO novel_category (novelId, categoryId) VALUES (?, ?)",
                           arguments: [novelId, categoryId])
        }
    }

    nonisolated static func applyRemoteDeletion(recordID: CKRecord.ID, db: Database) throws {
        guard let mapping = try mapping(for: recordID.recordName, db: db) else { return }
        switch mapping.type {
        case .category:
            _ = try Category.deleteOne(db, key: mapping.key)
        case .mangaCategoryLink:
            let parts = mapping.key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            try db.execute(sql: "DELETE FROM manga_category WHERE mangaId = ? AND categoryId = ?", arguments: [parts[0], parts[1]])
        case .novelCategoryLink:
            let parts = mapping.key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            try db.execute(sql: "DELETE FROM novel_category WHERE novelId = ? AND categoryId = ?", arguments: [parts[0], parts[1]])
        default:
            break
        }
    }

    nonisolated static func mapKey(for type: CloudRecordType, record: CKRecord) -> String {
        switch type {
        case .manga, .novel, .category:
            return (record["localId"] as? String) ?? record.recordID.recordName
        case .mangaChapterState:
            return "\(record["mangaId"] as? String ?? "")|\(record["chapterId"] as? String ?? "")"
        case .novelChapterState:
            return "\(record["novelId"] as? String ?? "")|\(record["chapterId"] as? String ?? "")"
        case .mangaCategoryLink:
            return "\(record["mangaId"] as? String ?? "")|\(record["categoryId"] as? String ?? "")"
        case .novelCategoryLink:
            return "\(record["novelId"] as? String ?? "")|\(record["categoryId"] as? String ?? "")"
        }
    }
}

// MARK: - Replaying stashed chapter-state changes (finding #41)
//
// Called from ChapterQueries.insertAllIgnoringConflicts/insertMangaAndChapters and
// NovelQueries.insertAllIgnoringConflicts, inside the same write transaction that just inserted the
// chapter rows — so a remote read-state that arrived before the chapter existed locally gets applied
// the moment it can be, rather than waiting for the next full sync.

extension CloudSyncManager {

    /// A read chapter arrived from another device: move the title's `lastReadAt` up to WHEN it was read there, never
    /// back and never to "now" — stamping now put every synced title at the top of History/Continue (S189 audit #7).
    nonisolated static func bumpLastRead(table: String, id: String, readAt: Date?, db: Database) throws {
        guard let readAt else { return }
        try db.execute(sql: "UPDATE \(table) SET lastReadAt = ? WHERE id = ? AND (lastReadAt IS NULL OR lastReadAt < ?)",
                       arguments: [readAt, id, readAt])
    }

    nonisolated static func applyPendingChapterStates(_ chapters: [Chapter], db: Database) throws {
        for chapter in chapters {
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT isRead, progress, lastPageRead, readAt, readingSeconds, isBookmarked FROM pending_chapter_state WHERE mangaId = ? AND chapterId = ?",
                arguments: [chapter.mangaId, chapter.id]
            ) else { continue }

            let isRead = row["isRead"] as Bool
            try db.execute(
                sql: "UPDATE chapter SET isRead = ?, progress = ?, lastPageRead = ?, readAt = ?, readingSeconds = ?, isBookmarked = ? WHERE id = ?",
                arguments: [
                    isRead, row["progress"] as Double, row["lastPageRead"] as Int,
                    row["readAt"] as Date?, row["readingSeconds"] as Int, row["isBookmarked"] as Bool, chapter.id
                ]
            )
            try db.execute(
                sql: "DELETE FROM pending_chapter_state WHERE mangaId = ? AND chapterId = ?",
                arguments: [chapter.mangaId, chapter.id]
            )
            if isRead {
                try bumpLastRead(table: "manga", id: chapter.mangaId, readAt: row["readAt"] as Date?, db: db)
            }
        }
    }

    nonisolated static func applyPendingNovelChapterStates(_ chapters: [NovelChapter], db: Database) throws {
        for chapter in chapters {
            // A stash with a path is matched by it (S191, #4) — the sender's id may be another chapter here.
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT chapterId, isRead, readAt, readingSeconds, lastScrollPercent, isBookmarked
                    FROM pending_novel_chapter_state
                    WHERE novelId = ? AND (path = ? OR (path IS NULL AND chapterId = ?))
                    ORDER BY path IS NULL LIMIT 1
                    """,
                arguments: [chapter.novelId, chapter.path, chapter.id]
            ) else { continue }

            let isRead = row["isRead"] as Bool
            try db.execute(
                sql: "UPDATE novel_chapter SET isRead = ?, readAt = ?, readingSeconds = ?, lastScrollPercent = ?, isBookmarked = ? WHERE id = ?",
                arguments: [
                    isRead, row["readAt"] as Date?, row["readingSeconds"] as Int,
                    row["lastScrollPercent"] as Double?, row["isBookmarked"] as Bool, chapter.id
                ]
            )
            try db.execute(
                sql: "DELETE FROM pending_novel_chapter_state WHERE novelId = ? AND chapterId = ?",
                arguments: [chapter.novelId, row["chapterId"] as String]
            )
            if isRead {
                try bumpLastRead(table: "novel", id: chapter.novelId, readAt: row["readAt"] as Date?, db: db)
            }
        }
    }
}
