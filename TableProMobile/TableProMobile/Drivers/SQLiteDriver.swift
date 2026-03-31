//
//  SQLiteDriver.swift
//  TableProMobile
//
//  SQLite driver conforming to DatabaseDriver directly (no plugin layer).
//

import Foundation
import SQLite3
import TableProDatabase
import TableProModels

final class SQLiteDriver: DatabaseDriver, @unchecked Sendable {
    private let dbPath: String
    private let actor = SQLiteActor()

    var supportsSchemas: Bool { false }
    var currentSchema: String? { nil }
    var supportsTransactions: Bool { true }
    var serverVersion: String? { String(cString: sqlite3_libversion()) }

    init(path: String) {
        self.dbPath = path
    }

    // MARK: - Connection

    func connect() async throws {
        let expanded = (dbPath as NSString).expandingTildeInPath

        if !FileManager.default.fileExists(atPath: expanded) {
            let dir = (expanded as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        try await actor.open(path: expanded)
    }

    func disconnect() async throws {
        await actor.close()
    }

    func ping() async throws -> Bool {
        _ = try await actor.execute("SELECT 1")
        return true
    }

    // MARK: - Query Execution

    func execute(query: String) async throws -> QueryResult {
        let raw = try await actor.execute(query)
        return QueryResult(
            columns: raw.columns.enumerated().map { i, name in
                ColumnInfo(
                    name: name,
                    typeName: i < raw.columnTypes.count ? raw.columnTypes[i] : "",
                    isPrimaryKey: false,
                    isNullable: true,
                    defaultValue: nil,
                    comment: nil,
                    characterMaxLength: nil,
                    ordinalPosition: i
                )
            },
            rows: raw.rows,
            rowsAffected: raw.rowsAffected,
            executionTime: raw.executionTime,
            isTruncated: raw.isTruncated,
            statusMessage: nil
        )
    }

    func cancelCurrentQuery() async throws {
        await actor.interrupt()
    }

    // MARK: - Schema

    func fetchTables(schema: String?) async throws -> [TableInfo] {
        let raw = try await actor.execute("""
            SELECT name, type FROM sqlite_master
            WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%'
            ORDER BY name
            """)

        return raw.rows.compactMap { row in
            guard row.count > 0, let name = row[0] else { return nil }
            let kind: TableInfo.TableKind = (row.count > 1 ? row[1] : nil)?.lowercased() == "view" ? .view : .table
            return TableInfo(name: name, type: kind, rowCount: nil, dataSize: nil, comment: nil)
        }
    }

    func fetchColumns(table: String, schema: String?) async throws -> [ColumnInfo] {
        let safe = table.replacingOccurrences(of: "'", with: "''")
        let raw = try await actor.execute("PRAGMA table_info('\(safe)')")

        return raw.rows.enumerated().compactMap { index, row in
            guard row.count >= 6, let name = row[1], let dataType = row[2] else { return nil }
            return ColumnInfo(
                name: name,
                typeName: dataType,
                isPrimaryKey: row[5] == "1",
                isNullable: row[3] == "0",
                defaultValue: row[4],
                comment: nil,
                characterMaxLength: nil,
                ordinalPosition: index
            )
        }
    }

    func fetchIndexes(table: String, schema: String?) async throws -> [IndexInfo] {
        let safe = table.replacingOccurrences(of: "'", with: "''")
        let raw = try await actor.execute("""
            SELECT il.name, il."unique", il.origin, ii.name AS col_name
            FROM pragma_index_list('\(safe)') il
            LEFT JOIN pragma_index_info(il.name) ii ON 1=1
            ORDER BY il.seq, ii.seqno
            """)

        var indexMap: [String: (isUnique: Bool, isPrimary: Bool, columns: [String])] = [:]
        var order: [String] = []

        for row in raw.rows {
            guard row.count >= 4, let indexName = row[0] else { continue }
            if indexMap[indexName] == nil {
                indexMap[indexName] = (
                    isUnique: row[1] == "1",
                    isPrimary: (row[2] ?? "c") == "pk",
                    columns: []
                )
                order.append(indexName)
            }
            if let col = row[3] {
                indexMap[indexName]?.columns.append(col)
            }
        }

        return order.compactMap { name in
            guard let entry = indexMap[name] else { return nil }
            return IndexInfo(
                name: name,
                columns: entry.columns,
                isUnique: entry.isUnique,
                isPrimary: entry.isPrimary,
                type: "BTREE"
            )
        }
    }

    func fetchForeignKeys(table: String, schema: String?) async throws -> [ForeignKeyInfo] {
        let safe = table.replacingOccurrences(of: "'", with: "''")
        let raw = try await actor.execute("PRAGMA foreign_key_list('\(safe)')")

        return raw.rows.compactMap { row in
            guard row.count >= 5,
                  let refTable = row[2],
                  let fromCol = row[3],
                  let toCol = row[4] else { return nil }

            return ForeignKeyInfo(
                name: "fk_\(table)_\(row[0] ?? "0")",
                column: fromCol,
                referencedTable: refTable,
                referencedColumn: toCol,
                onDelete: row.count >= 7 ? (row[6] ?? "NO ACTION") : "NO ACTION",
                onUpdate: row.count >= 6 ? (row[5] ?? "NO ACTION") : "NO ACTION"
            )
        }
    }

    func fetchDatabases() async throws -> [String] { [] }

    func switchDatabase(to name: String) async throws {
        throw SQLiteError.unsupported("SQLite does not support database switching")
    }

    func switchSchema(to name: String) async throws {
        throw SQLiteError.unsupported("SQLite does not support schemas")
    }

    func beginTransaction() async throws {
        _ = try await actor.execute("BEGIN TRANSACTION")
    }

    func commitTransaction() async throws {
        _ = try await actor.execute("COMMIT")
    }

    func rollbackTransaction() async throws {
        _ = try await actor.execute("ROLLBACK")
    }
}

// MARK: - SQLite Actor (thread-safe C API access)

private actor SQLiteActor {
    private var db: OpaquePointer?

    func open(path: String) throws {
        if sqlite3_open(path, &db) != SQLITE_OK {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw SQLiteError.connectionFailed(msg)
        }
        sqlite3_busy_timeout(db, 5000)
    }

    func close() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    func interrupt() {
        if let db { sqlite3_interrupt(db) }
    }

    func execute(_ query: String) throws -> RawResult {
        guard let db else { throw SQLiteError.notConnected }

        let start = Date()
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let colCount = sqlite3_column_count(stmt)
        var columns: [String] = []
        var columnTypes: [String] = []

        for i in 0..<colCount {
            columns.append(sqlite3_column_name(stmt, i).map { String(cString: $0) } ?? "col_\(i)")
            columnTypes.append(sqlite3_column_decltype(stmt, i).map { String(cString: $0) } ?? "")
        }

        var rows: [[String?]] = []
        let maxRows = 100_000

        while sqlite3_step(stmt) == SQLITE_ROW {
            if rows.count >= maxRows {
                return RawResult(columns: columns, columnTypes: columnTypes, rows: rows,
                                 rowsAffected: 0, executionTime: Date().timeIntervalSince(start), isTruncated: true)
            }

            var row: [String?] = []
            for i in 0..<colCount {
                if sqlite3_column_type(stmt, i) == SQLITE_NULL {
                    row.append(nil)
                } else if sqlite3_column_type(stmt, i) == SQLITE_BLOB {
                    let bytes = Int(sqlite3_column_bytes(stmt, i))
                    if bytes > 0, let ptr = sqlite3_column_blob(stmt, i) {
                        row.append(Data(bytes: ptr, count: bytes).base64EncodedString())
                    } else {
                        row.append("")
                    }
                } else if let text = sqlite3_column_text(stmt, i) {
                    row.append(String(cString: text))
                } else {
                    row.append(nil)
                }
            }
            rows.append(row)
        }

        let affected = columns.isEmpty ? Int(sqlite3_changes(db)) : 0
        return RawResult(columns: columns, columnTypes: columnTypes, rows: rows,
                         rowsAffected: affected, executionTime: Date().timeIntervalSince(start), isTruncated: false)
    }
}

private struct RawResult: Sendable {
    let columns: [String]
    let columnTypes: [String]
    let rows: [[String?]]
    let rowsAffected: Int
    let executionTime: TimeInterval
    let isTruncated: Bool
}

// MARK: - Errors

enum SQLiteError: Error, LocalizedError {
    case connectionFailed(String)
    case notConnected
    case queryFailed(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "SQLite connection failed: \(msg)"
        case .notConnected: return "Not connected to SQLite database"
        case .queryFailed(let msg): return "SQLite query failed: \(msg)"
        case .unsupported(let msg): return msg
        }
    }
}
