import Foundation
import SQLite3

/// One page the person has visited, as the command bar shows it.
struct HistoryEntry {
    var url: URL
    var title: String
    var host: String
    var count: Int
}

/// A small SQLite store of visited pages, one row per url per profile. The command bar queries it
/// as you type, ranked by how often and how recently a page was visited. Everything runs on the
/// main actor against a single connection, which is plenty for a local, indexed store.
@MainActor
final class History {
    private var db: OpaquePointer?

    /// ~/Library/Application Support/Cove/history.sqlite, or COVE_HISTORY_FILE for tests.
    private static var fileURL: URL {
        if let path = ProcessInfo.processInfo.environment["COVE_HISTORY_FILE"] {
            return URL(fileURLWithPath: path)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Cove/history.sqlite")
    }

    init(open: Bool = true) {
        guard open else { return }
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if sqlite3_open(url.path, &db) == SQLITE_OK {
            exec("""
                CREATE TABLE IF NOT EXISTS visits (
                    url TEXT NOT NULL, profile TEXT NOT NULL, title TEXT, host TEXT,
                    count INTEGER DEFAULT 1, last REAL,
                    PRIMARY KEY (url, profile)
                );
                CREATE INDEX IF NOT EXISTS visits_profile ON visits(profile);
                """)
        }
    }

    deinit { if let db { sqlite3_close(db) } }

    private func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Records one visit. Only http and https pages, and never a blank title.
    func record(url: URL, title: String, host: String, profile: UUID) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        let sql = """
            INSERT INTO visits (url, profile, title, host, count, last)
            VALUES (?, ?, ?, ?, 1, ?)
            ON CONFLICT(url, profile) DO UPDATE SET
                count = count + 1,
                title = CASE WHEN excluded.title <> '' THEN excluded.title ELSE title END,
                last = excluded.last;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, url.absoluteString, -1, Self.transient)
        sqlite3_bind_text(stmt, 2, profile.uuidString, -1, Self.transient)
        sqlite3_bind_text(stmt, 3, title, -1, Self.transient)
        sqlite3_bind_text(stmt, 4, host, -1, Self.transient)
        sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    /// Bulk insert for the Arc import. Existing rows keep the larger visit count.
    func importEntries(_ entries: [(url: URL, title: String, host: String, count: Int, last: Double)], profile: UUID) {
        exec("BEGIN")
        let sql = """
            INSERT INTO visits (url, profile, title, host, count, last)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(url, profile) DO UPDATE SET
                count = max(count, excluded.count),
                last = max(last, excluded.last);
            """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            for e in entries {
                sqlite3_reset(stmt)
                sqlite3_bind_text(stmt, 1, e.url.absoluteString, -1, Self.transient)
                sqlite3_bind_text(stmt, 2, profile.uuidString, -1, Self.transient)
                sqlite3_bind_text(stmt, 3, e.title, -1, Self.transient)
                sqlite3_bind_text(stmt, 4, e.host, -1, Self.transient)
                sqlite3_bind_int(stmt, 5, Int32(e.count))
                sqlite3_bind_double(stmt, 6, e.last)
                sqlite3_step(stmt)
            }
        }
        sqlite3_finalize(stmt)
        exec("COMMIT")
    }

    /// Pages matching the text, best first. Matches the url or the title.
    func matches(_ text: String, profile: UUID, limit: Int = 5) -> [HistoryEntry] {
        let needle = "%" + text.replacingOccurrences(of: "%", with: "") + "%"
        let sql = """
            SELECT url, title, host, count FROM visits
            WHERE profile = ? AND (url LIKE ? OR title LIKE ?)
            ORDER BY count DESC, last DESC LIMIT ?;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, profile.uuidString, -1, Self.transient)
        sqlite3_bind_text(stmt, 2, needle, -1, Self.transient)
        sqlite3_bind_text(stmt, 3, needle, -1, Self.transient)
        sqlite3_bind_int(stmt, 4, Int32(limit))

        var out: [HistoryEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let c0 = sqlite3_column_text(stmt, 0), let url = URL(string: String(cString: c0)) else { continue }
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let host = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? (url.host ?? "")
            let count = Int(sqlite3_column_int(stmt, 3))
            out.append(HistoryEntry(url: url, title: title.isEmpty ? host : title, host: host, count: count))
        }
        return out
    }
}
