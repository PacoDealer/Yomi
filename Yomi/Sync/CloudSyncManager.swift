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

    private let container = CKContainer(identifier: CloudSyncManager.containerIdentifier)
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
        }

        await syncNow()
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
    func syncNow() async {
        guard let engine = cloudSyncEngine else { return }
        status = .syncing
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

    private func bootstrapPushAllLocalData() async {
        guard let engine = cloudSyncEngine else { return }
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

    private nonisolated static func cacheRecord(_ record: CKRecord) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true) else { return }
        _ = try? appDatabase.write { db in
            try db.execute(
                sql: "UPDATE cloud_sync_map SET recordData = ? WHERE recordName = ?",
                arguments: [data, record.recordID.recordName]
            )
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
                isAccountAvailable = true
            case .signOut:
                isAccountAvailable = false
                status = .unavailable
            @unknown default:
                break
            }

        case .fetchedRecordZoneChanges(let event):
            for modification in event.modifications {
                applyRemote(record: modification.record)
            }
            for deletion in event.deletions {
                applyRemoteDeletion(recordID: deletion.recordID)
            }

        case .sentRecordZoneChanges(let event):
            for saved in event.savedRecords {
                Self.cacheRecord(saved)
            }
            for failedSave in event.failedRecordSaves {
                switch failedSave.error.code {
                case .serverRecordChanged:
                    // v1 conflict policy: last write wins, server's committed value is authoritative —
                    // no custom per-field merge. See Yomi/CLOUDKIT_SYNC_DESIGN.md's conflict-policy note.
                    if let serverRecord = failedSave.error.serverRecord {
                        applyRemote(record: serverRecord)
                        Self.cacheRecord(serverRecord)
                    }
                case .zoneNotFound:
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failedSave.record.recordID)])
                default:
                    break
                }
            }

        default:
            break
        }
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
        record["genres"]        = manga.genres
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
        record["genres"]        = novel.genres
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
    }

    nonisolated static func populate(_ record: CKRecord, novelId: String, from chapter: NovelChapter) {
        record["novelId"]           = novelId
        record["chapterId"]         = chapter.id
        record["isRead"]            = chapter.isRead
        record["readAt"]            = chapter.readAt
        record["readingSeconds"]    = Int64(chapter.readingSeconds)
        record["lastScrollPercent"] = chapter.lastScrollPercent
    }
}

// MARK: - Applying remote records (CKRecord -> local, for fetches + conflict resolution)

private extension CloudSyncManager {

    nonisolated func applyRemote(record: CKRecord) {
        guard let type = CloudRecordType(ckRecordType: record.recordType) else { return }
        Self.rememberMapping(recordName: record.recordID.recordName, type: type, key: mapKey(for: type, record: record))

        switch type {
        case .manga:
            guard let id = record["localId"] as? String else { return }
            var manga = (try? MangaQueries.fetchOne(id: id)) ?? Manga(
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
            _ = try? appDatabase.write { db in try manga.save(db) }

        case .novel:
            guard let id = record["localId"] as? String else { return }
            var novel = (try? NovelQueries.fetchOne(id: id)) ?? Novel(
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
            _ = try? appDatabase.write { db in try novel.save(db) }

        case .category:
            guard let id = record["localId"] as? String,
                  let name = record["name"] as? String else { return }
            let sort = Int(record["sort"] as? Int64 ?? 0)
            _ = try? appDatabase.write { db in
                try db.execute(
                    sql: "INSERT INTO category (id, name, sort) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name, sort = excluded.sort",
                    arguments: [id, name, sort]
                )
            }

        case .mangaChapterState:
            guard let mangaId = record["mangaId"] as? String,
                  let chapterId = record["chapterId"] as? String else { return }
            let isRead = record["isRead"] as? Bool ?? false
            let progress = record["progress"] as? Double ?? 0
            let lastPageRead = Int(record["lastPageRead"] as? Int64 ?? 0)
            let readAt = record["readAt"] as? Date
            let readingSeconds = Int(record["readingSeconds"] as? Int64 ?? 0)
            _ = try? appDatabase.write { db in
                try db.execute(
                    sql: """
                        UPDATE chapter SET isRead = ?, progress = ?, lastPageRead = ?, readAt = ?, readingSeconds = ?
                        WHERE id = ? AND mangaId = ?
                        """,
                    arguments: [isRead, progress, lastPageRead, readAt, readingSeconds, chapterId, mangaId]
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
                            INSERT INTO pending_chapter_state (mangaId, chapterId, isRead, progress, lastPageRead, readAt, readingSeconds)
                            VALUES (?, ?, ?, ?, ?, ?, ?)
                            ON CONFLICT(mangaId, chapterId) DO UPDATE SET
                                isRead = excluded.isRead, progress = excluded.progress, lastPageRead = excluded.lastPageRead,
                                readAt = excluded.readAt, readingSeconds = excluded.readingSeconds
                            """,
                        arguments: [mangaId, chapterId, isRead, progress, lastPageRead, readAt, readingSeconds]
                    )
                } else if isRead {
                    try Manga.filter(Column("id") == mangaId).updateAll(db, [Column("lastReadAt").set(to: Date())])
                }
            }

        case .novelChapterState:
            guard let novelId = record["novelId"] as? String,
                  let chapterId = record["chapterId"] as? String else { return }
            let isRead = record["isRead"] as? Bool ?? false
            let readAt = record["readAt"] as? Date
            let readingSeconds = Int(record["readingSeconds"] as? Int64 ?? 0)
            let lastScrollPercent = record["lastScrollPercent"] as? Double
            _ = try? appDatabase.write { db in
                try db.execute(
                    sql: """
                        UPDATE novel_chapter SET isRead = ?, readAt = ?, readingSeconds = ?, lastScrollPercent = ?
                        WHERE id = ? AND novelId = ?
                        """,
                    arguments: [isRead, readAt, readingSeconds, lastScrollPercent, chapterId, novelId]
                )
                if db.changesCount == 0 {
                    // Same reasoning as .mangaChapterState above — stash and replay once
                    // NovelQueries.insertAllIgnoringConflicts brings the chapter row in.
                    try db.execute(
                        sql: """
                            INSERT INTO pending_novel_chapter_state (novelId, chapterId, isRead, readAt, readingSeconds, lastScrollPercent)
                            VALUES (?, ?, ?, ?, ?, ?)
                            ON CONFLICT(novelId, chapterId) DO UPDATE SET
                                isRead = excluded.isRead, readAt = excluded.readAt,
                                readingSeconds = excluded.readingSeconds, lastScrollPercent = excluded.lastScrollPercent
                            """,
                        arguments: [novelId, chapterId, isRead, readAt, readingSeconds, lastScrollPercent]
                    )
                } else if isRead {
                    try Novel.filter(Column("id") == novelId).updateAll(db, [Column("lastReadAt").set(to: Date())])
                }
            }

        case .mangaCategoryLink:
            guard let mangaId = record["mangaId"] as? String,
                  let categoryId = record["categoryId"] as? String else { return }
            _ = try? appDatabase.write { db in
                try db.execute(
                    sql: "INSERT OR IGNORE INTO manga_category (mangaId, categoryId) VALUES (?, ?)",
                    arguments: [mangaId, categoryId]
                )
            }

        case .novelCategoryLink:
            guard let novelId = record["novelId"] as? String,
                  let categoryId = record["categoryId"] as? String else { return }
            _ = try? appDatabase.write { db in
                try db.execute(
                    sql: "INSERT OR IGNORE INTO novel_category (novelId, categoryId) VALUES (?, ?)",
                    arguments: [novelId, categoryId]
                )
            }
        }
    }

    nonisolated func applyRemoteDeletion(recordID: CKRecord.ID) {
        guard let mapping = CloudSyncManager.mapping(for: recordID.recordName) else { return }
        switch mapping.type {
        case .category:
            _ = try? appDatabase.write { db in _ = try Category.deleteOne(db, key: mapping.key) }
        case .mangaCategoryLink:
            let parts = mapping.key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            _ = try? appDatabase.write { db in
                try db.execute(sql: "DELETE FROM manga_category WHERE mangaId = ? AND categoryId = ?", arguments: [parts[0], parts[1]])
            }
        case .novelCategoryLink:
            let parts = mapping.key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            _ = try? appDatabase.write { db in
                try db.execute(sql: "DELETE FROM novel_category WHERE novelId = ? AND categoryId = ?", arguments: [parts[0], parts[1]])
            }
        default:
            break
        }
    }

    nonisolated func mapKey(for type: CloudRecordType, record: CKRecord) -> String {
        switch type {
        case .manga, .novel, .category:
            return (record["localId"] as? String) ?? record.recordID.recordName
        case .mangaChapterState:
            let mangaId = record["mangaId"] as? String ?? ""
            let chapterId = record["chapterId"] as? String ?? ""
            return "\(mangaId)|\(chapterId)"
        case .novelChapterState:
            let novelId = record["novelId"] as? String ?? ""
            let chapterId = record["chapterId"] as? String ?? ""
            return "\(novelId)|\(chapterId)"
        case .mangaCategoryLink:
            let mangaId = record["mangaId"] as? String ?? ""
            let categoryId = record["categoryId"] as? String ?? ""
            return "\(mangaId)|\(categoryId)"
        case .novelCategoryLink:
            let novelId = record["novelId"] as? String ?? ""
            let categoryId = record["categoryId"] as? String ?? ""
            return "\(novelId)|\(categoryId)"
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

    nonisolated static func applyPendingChapterStates(_ chapters: [Chapter], db: Database) throws {
        for chapter in chapters {
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT isRead, progress, lastPageRead, readAt, readingSeconds FROM pending_chapter_state WHERE mangaId = ? AND chapterId = ?",
                arguments: [chapter.mangaId, chapter.id]
            ) else { continue }

            let isRead = row["isRead"] as Bool
            try db.execute(
                sql: "UPDATE chapter SET isRead = ?, progress = ?, lastPageRead = ?, readAt = ?, readingSeconds = ? WHERE id = ?",
                arguments: [
                    isRead, row["progress"] as Double, row["lastPageRead"] as Int,
                    row["readAt"] as Date?, row["readingSeconds"] as Int, chapter.id
                ]
            )
            try db.execute(
                sql: "DELETE FROM pending_chapter_state WHERE mangaId = ? AND chapterId = ?",
                arguments: [chapter.mangaId, chapter.id]
            )
            if isRead {
                try Manga.filter(Column("id") == chapter.mangaId).updateAll(db, [Column("lastReadAt").set(to: Date())])
            }
        }
    }

    nonisolated static func applyPendingNovelChapterStates(_ chapters: [NovelChapter], db: Database) throws {
        for chapter in chapters {
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT isRead, readAt, readingSeconds, lastScrollPercent FROM pending_novel_chapter_state WHERE novelId = ? AND chapterId = ?",
                arguments: [chapter.novelId, chapter.id]
            ) else { continue }

            let isRead = row["isRead"] as Bool
            try db.execute(
                sql: "UPDATE novel_chapter SET isRead = ?, readAt = ?, readingSeconds = ?, lastScrollPercent = ? WHERE id = ?",
                arguments: [
                    isRead, row["readAt"] as Date?, row["readingSeconds"] as Int,
                    row["lastScrollPercent"] as Double?, chapter.id
                ]
            )
            try db.execute(
                sql: "DELETE FROM pending_novel_chapter_state WHERE novelId = ? AND chapterId = ?",
                arguments: [chapter.novelId, chapter.id]
            )
            if isRead {
                try Novel.filter(Column("id") == chapter.novelId).updateAll(db, [Column("lastReadAt").set(to: Date())])
            }
        }
    }
}
