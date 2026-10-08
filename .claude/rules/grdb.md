---
paths:
  - "Yomi/Database/**"
  - "Yomi/Sync/**"
  - "Yomi/Models/**"
---

# GRDB / database rules

- Next migration prefix: `v25_` (`v24_` = chapter numbers from names, S144). Migrations are keyed by full
  string name; keep the numeric prefix unique and ascending (#55 is the one historical duplicate).
- Every `*Queries` static method is `nonisolated`. Use `_ = try appDatabase.write { … }` to silence the
  unused result. `appDatabase.read` from MainActor needs `try await`.
- Chapter-list persistence uses INSERT OR IGNORE: `try ch.insert(db, onConflict: .ignore)` /
  `insertAllIgnoringConflicts` — never `save(db)` (INSERT OR REPLACE wipes read/download state).
- Every new `WHERE column = ?` on a large table needs an index (existing: `idx_chapter_mangaid`,
  `idx_chapter_unread`, `idx_novel_chapter_novelid`, `idx_manga_sourceid`, `idx_novel_sourceid`,
  `idx_novel_chapter_unread`).
- Writes to synced fields call `markCloudDirty` (batch: `markCloudDirtyBatch`) — one transaction for bulk
  operations, never one per row (#74, #138, #141).
- Update only the columns you change (`addReadingSeconds`, `updateSourceMetadata`, …); whole-row `update`
  caused a lost-update race on reader close (S124).
- Ids are content-derived (chapter path, plugin list id) — the same title gets the same id on every device.
