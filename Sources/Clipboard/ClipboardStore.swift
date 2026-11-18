import Foundation
import SQLite3
import CryptoKit

/// 剪贴板历史的 SQLite 存储（系统自带 libsqlite3，无第三方依赖）。
final class ClipboardStore {
    enum Kind: String {
        case text, image, files
    }

    struct Item: Identifiable, Hashable {
        let id: Int64
        let kind: Kind
        let text: String?
        let preview: String
        let thumbData: Data?
        let createdAt: Date
        let sourceApp: String?
        let pinned: Bool
    }

    static let shared = ClipboardStore()
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()

    private init() {
        let fileManager = FileManager.default
        let folder: URL
        if let override = ProcessInfo.processInfo.environment["CLIPSTATS_DATA_DIR"], !override.isEmpty {
            folder = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            folder = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/ClipStats", isDirectory: true)
        }
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("clipboard.db").path

        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            NSLog("ClipStats: cannot open clipboard db: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        execute("PRAGMA journal_mode=WAL;")
        execute("""
        CREATE TABLE IF NOT EXISTS items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            text TEXT,
            data BLOB,
            thumb BLOB,
            hash TEXT NOT NULL,
            source_app TEXT,
            created_at REAL NOT NULL,
            pinned INTEGER NOT NULL DEFAULT 0
        );
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_items_hash ON items(hash);")
        execute("CREATE INDEX IF NOT EXISTS idx_items_created ON items(created_at DESC);")
    }

    // MARK: - 基础

    @discardableResult
    private func execute(_ sql: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &error)
        if result != SQLITE_OK {
            if let error {
                NSLog("ClipStats: sqlite error: \(String(cString: error))")
                sqlite3_free(error)
            }
            return false
        }
        return true
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            NSLog("ClipStats: prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        return statement
    }

    private static func hash(kind: Kind, text: String?, data: Data?) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        if let text { hasher.update(data: Data(text.utf8)) }
        if let data { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 写入

    @discardableResult
    func insert(kind: Kind, text: String?, data: Data?, thumb: Data?, sourceApp: String?) -> Item? {
        let hash = Self.hash(kind: kind, text: text, data: data)
        lock.lock()
        defer { lock.unlock() }

        if let existingID = existingID(hash: hash) {
            var statement = prepare("UPDATE items SET created_at = ? WHERE id = ?")
            if let statement {
                sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
                sqlite3_bind_int64(statement, 2, existingID)
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
            return item(id: existingID)
        }

        var statement = prepare("""
        INSERT INTO items (kind, text, data, thumb, hash, source_app, created_at, pinned)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0)
        """)
        guard let statement else { return nil }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, kind.rawValue, -1, Self.transient)
        if let text {
            sqlite3_bind_text(statement, 2, text, -1, Self.transient)
        } else {
            sqlite3_bind_null(statement, 2)
        }
        if let data, !data.isEmpty {
            _ = data.withUnsafeBytes { raw in
                sqlite3_bind_blob(statement, 3, raw.baseAddress, Int32(data.count), Self.transient)
            }
        } else {
            sqlite3_bind_null(statement, 3)
        }
        if let thumb, !thumb.isEmpty {
            _ = thumb.withUnsafeBytes { raw in
                sqlite3_bind_blob(statement, 4, raw.baseAddress, Int32(thumb.count), Self.transient)
            }
        } else {
            sqlite3_bind_null(statement, 4)
        }
        sqlite3_bind_text(statement, 5, hash, -1, Self.transient)
        if let sourceApp {
            sqlite3_bind_text(statement, 6, sourceApp, -1, Self.transient)
        } else {
            sqlite3_bind_null(statement, 6)
        }
        sqlite3_bind_double(statement, 7, Date().timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else { return nil }
        let id = sqlite3_last_insert_rowid(db)
        return item(id: id)
    }

    private func existingID(hash: String) -> Int64? {
        var statement = prepare("SELECT id FROM items WHERE hash = ? LIMIT 1")
        guard let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, hash, -1, Self.transient)
        if sqlite3_step(statement) == SQLITE_ROW {
            return sqlite3_column_int64(statement, 0)
        }
        return nil
    }

    // MARK: - 查询

    func items(search: String = "", limit: Int = 500) -> [Item] {
        lock.lock()
        defer { lock.unlock() }

        var sql = "SELECT id, kind, text, thumb, created_at, source_app, pinned FROM items"
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            sql += " WHERE text LIKE ?"
        }
        sql += " ORDER BY pinned DESC, created_at DESC LIMIT ?"

        guard let statement = prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }

        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            let pattern = "%\(search)%"
            sqlite3_bind_text(statement, 1, pattern, -1, Self.transient)
            sqlite3_bind_int(statement, 2, Int32(limit))
        } else {
            sqlite3_bind_int(statement, 1, Int32(limit))
        }

        var result: [Item] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let item = decodeRow(statement) {
                result.append(item)
            }
        }
        return result
    }

    func item(id: Int64) -> Item? {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("""
        SELECT id, kind, text, thumb, created_at, source_app, pinned FROM items WHERE id = ?
        """) else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        if sqlite3_step(statement) == SQLITE_ROW {
            return decodeRow(statement)
        }
        return nil
    }

    private func decodeRow(_ statement: OpaquePointer) -> Item? {
        guard let kindText = sqlite3_column_text(statement, 1).map({ String(cString: $0) }),
              let kind = Kind(rawValue: kindText) else { return nil }
        let id = sqlite3_column_int64(statement, 0)
        let text = sqlite3_column_text(statement, 2).map { String(cString: $0) }

        var thumb: Data?
        if let bytes = sqlite3_column_blob(statement, 3) {
            let count = Int(sqlite3_column_bytes(statement, 3))
            if count > 0 { thumb = Data(bytes: bytes, count: count) }
        }
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
        let sourceApp = sqlite3_column_text(statement, 5).map { String(cString: $0) }
        let pinned = sqlite3_column_int(statement, 6) != 0

        return Item(
            id: id,
            kind: kind,
            text: text,
            preview: Self.preview(kind: kind, text: text),
            thumbData: thumb,
            createdAt: createdAt,
            sourceApp: sourceApp,
            pinned: pinned
        )
    }

    private static func preview(kind: Kind, text: String?) -> String {
        switch kind {
        case .image:
            return "图片"
        case .files:
            guard let text else { return "文件" }
            let names = text.split(separator: "\n").prefix(2).map {
                URL(fileURLWithPath: String($0)).lastPathComponent
            }
            let extra = text.split(separator: "\n").count - 2
            return names.joined(separator: "、") + (extra > 0 ? " 等 \(extra + 2) 项" : "")
        case .text:
            guard let text else { return "" }
            let collapsed = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return String(collapsed.prefix(2000))
        }
    }

    func payload(id: Int64) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("SELECT data FROM items WHERE id = ?") else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count > 0 else { return nil }
        return Data(bytes: bytes, count: count)
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("SELECT COUNT(*) FROM items") else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    // MARK: - 修改

    func touch(id: Int64) {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("UPDATE items SET created_at = ? WHERE id = ?") else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
        sqlite3_bind_int64(statement, 2, id)
        sqlite3_step(statement)
    }

    func delete(id: Int64) {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("DELETE FROM items WHERE id = ?") else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        sqlite3_step(statement)
    }

    func clear() {
        execute("DELETE FROM items;")
    }

    func trim(maxItems: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = prepare("""
        DELETE FROM items WHERE pinned = 0 AND id NOT IN (
            SELECT id FROM items ORDER BY pinned DESC, created_at DESC LIMIT ?
        )
        """) else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(max(maxItems, 1)))
        sqlite3_step(statement)
    }
}
