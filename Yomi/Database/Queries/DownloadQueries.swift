import Foundation
import GRDB

/// Operaciones de descarga para la tabla chapter
enum DownloadQueries {

    /// Marca un capítulo como descargado con isDownloaded=true y downloadedAt=ahora
    nonisolated static func markDownloaded(chapterId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET isDownloaded = 1, downloadedAt = ? WHERE id = ?",
                arguments: [Date(), chapterId]
            )
        }
    }

    /// Marca un capítulo como no descargado con isDownloaded=false y downloadedAt=nil
    nonisolated static func markNotDownloaded(chapterId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET isDownloaded = 0, downloadedAt = NULL WHERE id = ?",
                arguments: [chapterId]
            )
        }
    }

    /// Devuelve los capítulos descargados de un manga, ordenados por chapterNumber ASC NULLS LAST
    nonisolated static func fetchDownloaded(mangaId: String) throws -> [Chapter] {
        try appDatabase.read { db in
            try Chapter
                .filter(Column("mangaId") == mangaId)
                .filter(Column("isDownloaded") == true)
                .order(Column("chapterNumber").ascNullsLast)
                .fetchAll(db)
        }
    }

    /// Devuelve todos los capítulos descargados de cualquier manga
    nonisolated static func fetchAllDownloaded() throws -> [Chapter] {
        try appDatabase.read { db in
            try Chapter
                .filter(Column("isDownloaded") == true)
                .fetchAll(db)
        }
    }

    /// Resetea isDownloaded=false y downloadedAt=nil para el capítulo indicado.
    /// No borra el archivo local — la eliminación del archivo es responsabilidad del caller.
    nonisolated static func deleteDownloadRecord(chapterId: String) throws {
        _ = try appDatabase.write { db in
            try db.execute(
                sql: "UPDATE chapter SET isDownloaded = 0, downloadedAt = NULL WHERE id = ?",
                arguments: [chapterId]
            )
        }
    }
}
