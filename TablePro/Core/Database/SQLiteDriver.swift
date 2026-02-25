//
//  SQLiteDriver.swift
//  TablePro
//
//  Created by Ngo Quoc Dat on 16/12/25.
//

import Foundation
import OSLog
import SQLite3

// MARK: - SQLite Connection Actor

/// Actor that owns and serializes all access to the sqlite3 handle,
/// eliminating TOCTOU race conditions from concurrent task access.
private actor SQLiteConnectionActor {
    private static let logger = Logger(subsystem: "com.TablePro", category: "SQLiteConnectionActor")

    private var db: OpaquePointer?

    var isConnected: Bool { db != nil }

    func open(path: String) throws {
        let result = sqlite3_open(path, &db)

        if result != SQLITE_OK {
            let errorMessage = db.map { String(cString: sqlite3_errmsg($0)) }
                ?? "Unknown SQLite error"
            throw DatabaseError.connectionFailed(errorMessage)
        }
    }

    func close() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    func applyBusyTimeout(_ milliseconds: Int32) {
        guard let db else { return }
        sqlite3_busy_timeout(db, milliseconds)
    }

    /// Get the raw db handle for interrupt purposes.
    /// sqlite3_interrupt() is one of the few sqlite3 APIs that is safe to call
    /// from a different thread than the one running the query.
    var dbHandleForInterrupt: OpaquePointer? { db }

    /// Execute a SQL query and return the raw result
    func executeQuery(_ query: String) throws -> SQLiteRawResult {
        guard let db else {
            throw DatabaseError.notConnected
        }

        let startTime = Date()
        var statement: OpaquePointer?

        let prepareResult = sqlite3_prepare_v2(db, query, -1, &statement, nil)

        if prepareResult != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.queryFailed(errorMessage)
        }

        defer {
            sqlite3_finalize(statement)
        }

        // Get column info
        let columnCount = sqlite3_column_count(statement)
        var columns: [String] = []
        var columnTypes: [ColumnType] = []

        for i in 0..<columnCount {
            if let name = sqlite3_column_name(statement, i) {
                columns.append(String(cString: name))
            } else {
                columns.append("column_\(i)")
            }

            let declaredType: String? = {
                if let typePtr = sqlite3_column_decltype(statement, i) {
                    return String(cString: typePtr)
                }
                return nil
            }()

            columnTypes.append(ColumnType(fromSQLiteType: declaredType))
        }

        // Execute and fetch rows
        var rows: [[String?]] = []
        var rowsAffected = 0
        var truncated = false

        while sqlite3_step(statement) == SQLITE_ROW {
            if rows.count >= DriverRowLimits.defaultMax {
                truncated = true
                break
            }

            var row: [String?] = []

            for i in 0..<columnCount {
                if sqlite3_column_type(statement, i) == SQLITE_NULL {
                    row.append(nil)
                } else if let text = sqlite3_column_text(statement, i) {
                    row.append(String(cString: text))
                } else {
                    row.append(nil)
                }
            }

            rows.append(row)
        }

        if columns.isEmpty {
            rowsAffected = Int(sqlite3_changes(db))
        }

        let executionTime = Date().timeIntervalSince(startTime)

        return SQLiteRawResult(
            columns: columns,
            columnTypes: columnTypes,
            rows: rows,
            rowsAffected: rowsAffected,
            executionTime: executionTime,
            isTruncated: truncated
        )
    }

    /// Execute a parameterized SQL query and return the raw result
    func executeParameterizedQuery(_ query: String, stringParams: [String?]) throws -> SQLiteRawResult {
        guard let db else {
            throw DatabaseError.notConnected
        }

        let startTime = Date()
        var statement: OpaquePointer?

        let prepareResult = sqlite3_prepare_v2(db, query, -1, &statement, nil)

        if prepareResult != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.queryFailed(errorMessage)
        }

        defer {
            sqlite3_finalize(statement)
        }

        // Bind parameters (SQLite uses 1-based indexing)
        for (index, param) in stringParams.enumerated() {
            let bindIndex = Int32(index + 1)

            if let stringValue = param {
                let bindResult = sqlite3_bind_text(statement, bindIndex, stringValue, -1, nil)
                if bindResult != SQLITE_OK {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    throw DatabaseError.queryFailed(
                        "Failed to bind parameter \(index): \(errorMessage)"
                    )
                }
            } else {
                let bindResult = sqlite3_bind_null(statement, bindIndex)
                if bindResult != SQLITE_OK {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    throw DatabaseError.queryFailed(
                        "Failed to bind NULL parameter \(index): \(errorMessage)"
                    )
                }
            }
        }

        // Get column info
        let columnCount = sqlite3_column_count(statement)
        var columns: [String] = []
        var columnTypes: [ColumnType] = []

        for i in 0..<columnCount {
            if let name = sqlite3_column_name(statement, i) {
                columns.append(String(cString: name))
            } else {
                columns.append("column_\(i)")
            }

            let declaredType: String? = {
                if let typePtr = sqlite3_column_decltype(statement, i) {
                    return String(cString: typePtr)
                }
                return nil
            }()

            columnTypes.append(ColumnType(fromSQLiteType: declaredType))
        }

        // Execute and fetch rows
        var rows: [[String?]] = []
        var rowsAffected = 0
        var truncated = false

        while sqlite3_step(statement) == SQLITE_ROW {
            if rows.count >= DriverRowLimits.defaultMax {
                truncated = true
                break
            }

            var row: [String?] = []

            for i in 0..<columnCount {
                if sqlite3_column_type(statement, i) == SQLITE_NULL {
                    row.append(nil)
                } else if let text = sqlite3_column_text(statement, i) {
                    row.append(String(cString: text))
                } else {
                    row.append(nil)
                }
            }

            rows.append(row)
        }

        if columns.isEmpty {
            rowsAffected = Int(sqlite3_changes(db))
        }

        let executionTime = Date().timeIntervalSince(startTime)

        return SQLiteRawResult(
            columns: columns,
            columnTypes: columnTypes,
            rows: rows,
            rowsAffected: rowsAffected,
            executionTime: executionTime,
            isTruncated: truncated
        )
    }
}

/// Internal result type for passing data out of the actor
private struct SQLiteRawResult: Sendable {
    let columns: [String]
    let columnTypes: [ColumnType]
    let rows: [[String?]]
    let rowsAffected: Int
    let executionTime: TimeInterval
    let isTruncated: Bool
}

// MARK: - SQLite Driver

/// Native SQLite database driver using libsqlite3
final class SQLiteDriver: DatabaseDriver {
    let connection: DatabaseConnection
    private(set) var status: ConnectionStatus = .disconnected

    // MARK: - Cached Regex

    private static let limitRegex = try? NSRegularExpression(pattern: "(?i)\\s+LIMIT\\s+\\d+")

    private static let offsetRegex = try? NSRegularExpression(pattern: "(?i)\\s+OFFSET\\s+\\d+")

    /// Actor-isolated connection state — serializes all sqlite3 access
    private let connectionActor = SQLiteConnectionActor()

    /// Lock protecting `_dbHandleForInterrupt` against concurrent disconnect/interrupt access
    private let interruptLock = NSLock()

    /// Raw db handle kept outside the actor for thread-safe sqlite3_interrupt() calls.
    /// Protected by `interruptLock` for concurrent access between disconnect() and cancelQuery().
    /// sqlite3_interrupt() is documented as safe to call from any thread.
    nonisolated(unsafe) private var _dbHandleForInterrupt: OpaquePointer?

    /// Server version string (SQLite library version, e.g., "3.43.2")
    var serverVersion: String? {
        String(cString: sqlite3_libversion())
    }

    init(connection: DatabaseConnection) {
        self.connection = connection
    }

    deinit {
        disconnect()
    }

    // MARK: - Connection

    func connect() async throws {
        guard status != .connected else { return }

        status = .connecting

        let path = expandPath(connection.database)

        // Check if file exists (for existing databases)
        if !FileManager.default.fileExists(atPath: path) {
            // Create new database file
            let directory = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }

        do {
            try await connectionActor.open(path: path)
            interruptLock.lock()
            _dbHandleForInterrupt = await connectionActor.dbHandleForInterrupt
            interruptLock.unlock()
            status = .connected
        } catch {
            let message = (error as? DatabaseError).flatMap { err -> String? in
                if case .connectionFailed(let msg) = err { return msg }
                return nil
            } ?? error.localizedDescription
            status = .error(message)
            throw error
        }
    }

    func applyQueryTimeout(_ seconds: Int) async throws {
        guard seconds > 0 else { return }
        await connectionActor.applyBusyTimeout(Int32(seconds * 1_000))
    }

    func disconnect() {
        interruptLock.lock()
        _dbHandleForInterrupt = nil
        interruptLock.unlock()
        // Fire-and-forget close on the actor
        let actor = connectionActor
        Task { await actor.close() }
        status = .disconnected
    }

    // MARK: - Query Execution

    func execute(query: String) async throws -> QueryResult {
        guard status == .connected else {
            throw DatabaseError.notConnected
        }

        let rawResult = try await connectionActor.executeQuery(query)

        return QueryResult(
            columns: rawResult.columns,
            columnTypes: rawResult.columnTypes,
            rows: rawResult.rows,
            rowsAffected: rawResult.rowsAffected,
            executionTime: rawResult.executionTime,
            error: nil,
            isTruncated: rawResult.isTruncated
        )
    }

    func executeParameterized(query: String, parameters: [Any?]) async throws -> QueryResult {
        guard status == .connected else {
            throw DatabaseError.notConnected
        }

        // Snapshot parameters to strings before dispatching (Any? isn't Sendable)
        let stringParams: [String?] = parameters.map { param in
            guard let param else { return nil }
            if let str = param as? String { return str }
            return "\(param)"
        }

        let rawResult = try await connectionActor.executeParameterizedQuery(query, stringParams: stringParams)

        return QueryResult(
            columns: rawResult.columns,
            columnTypes: rawResult.columnTypes,
            rows: rawResult.rows,
            rowsAffected: rawResult.rowsAffected,
            executionTime: rawResult.executionTime,
            error: nil,
            isTruncated: rawResult.isTruncated
        )
    }

    // MARK: - Cancellation

    func cancelQuery() throws {
        interruptLock.lock()
        let db = _dbHandleForInterrupt
        interruptLock.unlock()
        guard let db else { return }
        sqlite3_interrupt(db)
    }

    // MARK: - Schema

    func fetchTables() async throws -> [TableInfo] {
        guard status == .connected else {
            throw DatabaseError.notConnected
        }

        let query = """
            SELECT name, type FROM sqlite_master
            WHERE type IN ('table', 'view')
            AND name NOT LIKE 'sqlite_%'
            ORDER BY name
        """

        let result = try await execute(query: query)

        return result.rows.compactMap { row in
            guard let name = row[0] else { return nil }
            let typeString = row[1] ?? "table"
            let type: TableInfo.TableType = typeString.lowercased() == "view" ? .view : .table

            return TableInfo(name: name, type: type, rowCount: nil)
        }
    }

    func fetchColumns(table: String) async throws -> [ColumnInfo] {
        guard status == .connected else {
            throw DatabaseError.notConnected
        }

        let query = "PRAGMA table_info('\(SQLEscaping.escapeStringLiteral(table))')"
        let result = try await execute(query: query)

        return result.rows.compactMap { row in
            guard row.count >= 6,
                  let name = row[1],
                  let dataType = row[2] else {
                return nil
            }

            let isNullable = row[3] == "0"
            let isPrimaryKey = row[5] == "1"
            let defaultValue = row[4]

            return ColumnInfo(
                name: name,
                dataType: dataType,
                isNullable: isNullable,
                isPrimaryKey: isPrimaryKey,
                defaultValue: defaultValue,
                extra: nil,
                charset: nil,        // SQLite doesn't have charset
                collation: nil,      // SQLite uses database collation
                comment: nil         // SQLite doesn't support column comments
            )
        }
    }

    /// Fetch columns for all tables in a single query using table-valued pragma functions.
    /// Avoids the N+1 per-table PRAGMA calls from the default protocol implementation.
    /// Requires SQLite 3.16.0+ (macOS 10.13+).
    func fetchAllColumns() async throws -> [String: [ColumnInfo]] {
        guard status == .connected else {
            throw DatabaseError.notConnected
        }

        let query = """
            SELECT m.name AS tbl, p.cid, p.name, p.type, p."notnull", p.dflt_value, p.pk
            FROM sqlite_master m, pragma_table_info(m.name) p
            WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite_%'
            ORDER BY m.name, p.cid
            """
        let result = try await execute(query: query)

        var allColumns: [String: [ColumnInfo]] = [:]

        for row in result.rows {
            guard row.count >= 7,
                  let tableName = row[0],
                  let columnName = row[2],
                  let dataType = row[3] else {
                continue
            }

            let isNullable = row[4] == "0"   // notnull=0 means nullable
            let defaultValue = row[5]
            let isPrimaryKey = row[6] == "1"

            let column = ColumnInfo(
                name: columnName,
                dataType: dataType,
                isNullable: isNullable,
                isPrimaryKey: isPrimaryKey,
                defaultValue: defaultValue,
                extra: nil,
                charset: nil,
                collation: nil,
                comment: nil
            )

            allColumns[tableName, default: []].append(column)
        }

        return allColumns
    }

    func fetchIndexes(table: String) async throws -> [IndexInfo] {
        guard status == .connected else {
            throw DatabaseError.notConnected
        }

        // Use table-valued pragma functions to fetch all index info in a single query
        // instead of N+1 separate PRAGMA calls. Requires SQLite 3.16.0+ (macOS 10.13+).
        let safeTable = SQLEscaping.escapeStringLiteral(table)
        let query = """
            SELECT il.name, il."unique", il.origin, ii.name AS col_name
            FROM pragma_index_list('\(safeTable)') il
            LEFT JOIN pragma_index_info(il.name) ii ON 1=1
            ORDER BY il.seq, ii.seqno
            """
        let result = try await execute(query: query)

        // Group columns by index name, preserving order
        var indexMap: [(name: String, isUnique: Bool, isPrimary: Bool, columns: [String])] = []
        var indexLookup: [String: Int] = [:]

        for row in result.rows {
            guard row.count >= 4,
                  let indexName = row[0] else { continue }

            let isUnique = row[1] == "1"
            let origin = row[2] ?? "c"

            if let idx = indexLookup[indexName] {
                // Append column to existing index
                if let colName = row[3] {
                    indexMap[idx].columns.append(colName)
                }
            } else {
                // New index entry
                let columns: [String] = row[3].map { [$0] } ?? []
                indexLookup[indexName] = indexMap.count
                indexMap.append((
                    name: indexName,
                    isUnique: isUnique,
                    isPrimary: origin == "pk",
                    columns: columns
                ))
            }
        }

        let indexes = indexMap.map { entry in
            IndexInfo(
                name: entry.name,
                columns: entry.columns,
                isUnique: entry.isUnique,
                isPrimary: entry.isPrimary,
                type: "BTREE"
            )
        }

        return indexes.sorted { $0.isPrimary && !$1.isPrimary }
    }

    func fetchForeignKeys(table: String) async throws -> [ForeignKeyInfo] {
        guard status == .connected else {
            throw DatabaseError.notConnected
        }

        let query = "PRAGMA foreign_key_list('\(SQLEscaping.escapeStringLiteral(table))')"
        let result = try await execute(query: query)

        return result.rows.compactMap { row in
            guard row.count >= 5,
                  let refTable = row[2],
                  let fromCol = row[3],
                  let toCol = row[4] else {
                return nil
            }

            let id = row[0] ?? "0"
            let onUpdate = row.count >= 6 ? (row[5] ?? "NO ACTION") : "NO ACTION"
            let onDelete = row.count >= 7 ? (row[6] ?? "NO ACTION") : "NO ACTION"

            return ForeignKeyInfo(
                name: "fk_\(table)_\(id)",
                column: fromCol,
                referencedTable: refTable,
                referencedColumn: toCol,
                onDelete: onDelete,
                onUpdate: onUpdate
            )
        }
    }

    /// Fetch enum-like values from CHECK constraints for a table
    func fetchCheckConstraintEnumValues(table: String) async throws -> [String: [String]] {
        guard let createSQL = try await fetchCreateTableSQL(table: table) else {
            return [:]
        }

        // Get column names first
        let columns = try await fetchColumns(table: table)
        var result: [String: [String]] = [:]

        for col in columns {
            if let values = parseCheckConstraintValues(createSQL: createSQL, columnName: col.name) {
                result[col.name] = values
            }
        }

        return result
    }

    /// Fetch the CREATE TABLE SQL from sqlite_master
    private func fetchCreateTableSQL(table: String) async throws -> String? {
        let query = "SELECT sql FROM sqlite_master WHERE type='table' AND name='\(SQLEscaping.escapeStringLiteral(table))'"
        let result = try await execute(query: query)
        return result.rows.first?.first ?? nil
    }

    /// Parse CHECK constraint values for a column from CREATE TABLE SQL
    /// Looks for patterns like: CHECK(column IN ('val1','val2','val3'))
    /// or CHECK("column" IN ('val1','val2','val3'))
    private func parseCheckConstraintValues(createSQL: String, columnName: String) -> [String]? {
        // Build regex pattern: CHECK\s*\(\s*"?columnName"?\s+IN\s*\(([^)]+)\)\s*\)
        let escapedName = NSRegularExpression.escapedPattern(for: columnName)
        let pattern = "CHECK\\s*\\(\\s*\"?\(escapedName)\"?\\s+IN\\s*\\(([^)]+)\\)\\s*\\)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let nsString = createSQL as NSString
        guard let match = regex.firstMatch(
            in: createSQL,
            range: NSRange(location: 0, length: nsString.length)
        ) else {
            return nil
        }

        guard match.numberOfRanges > 1 else { return nil }
        let valuesRange = match.range(at: 1)
        let valuesString = nsString.substring(with: valuesRange)

        // Reuse shared parser by wrapping in ENUM(...) format
        return ColumnType.parseEnumValues(from: "ENUM(\(valuesString))")
    }

    func fetchTableDDL(table: String) async throws -> String {
        guard status == .connected else {
            throw DatabaseError.notConnected
        }

        // SQLite stores the original CREATE TABLE statement in sqlite_master
        let query = """
            SELECT sql FROM sqlite_master
            WHERE type = 'table' AND name = '\(SQLEscaping.escapeStringLiteral(table))'
            """

        let result = try await execute(query: query)

        guard let firstRow = result.rows.first,
              let ddl = firstRow[0]
        else {
            throw DatabaseError.queryFailed("Failed to fetch DDL for table '\(table)'")
        }

        let formatted = formatDDL(ddl)
        return formatted.hasSuffix(";") ? formatted : formatted + ";"
    }

    func fetchViewDefinition(view: String) async throws -> String {
        guard status == .connected else {
            throw DatabaseError.notConnected
        }

        let query = """
            SELECT sql FROM sqlite_master
            WHERE type = 'view' AND name = '\(SQLEscaping.escapeStringLiteral(view))'
            """

        let result = try await execute(query: query)

        guard let firstRow = result.rows.first,
              let ddl = firstRow[0]
        else {
            throw DatabaseError.queryFailed("Failed to fetch definition for view '\(view)'")
        }

        return ddl
    }

    // MARK: - DDL Formatting

    private func formatDDL(_ ddl: String) -> String {
        guard ddl.uppercased().hasPrefix("CREATE TABLE") else {
            return ddl // Only format CREATE TABLE statements
        }

        var formatted = ddl

        // Step 1: Find the first opening parenthesis (after table name) and add newline
        if let range = formatted.range(of: "(") {
            let before = String(formatted[..<range.lowerBound])
            let after = String(formatted[range.upperBound...])
            formatted = before + "(\n  " + after.trimmingCharacters(in: .whitespaces)
        }

        // Step 2: Add newline after commas at the top level (column separators)
        // We need to track parenthesis depth to avoid formatting commas inside type definitions
        var result = ""
        var depth = 0
        var i = 0
        let chars = Array(formatted)

        while i < chars.count {
            let char = chars[i]

            if char == "(" {
                depth += 1
                result.append(char)
            } else if char == ")" {
                depth -= 1
                result.append(char)
            } else if char == "," && depth == 1 {
                // This is a comma at column level, add newline
                result.append(",\n  ")
                // Skip any following whitespace
                i += 1
                while i < chars.count && chars[i].isWhitespace {
                    i += 1
                }
                i -= 1 // Will be incremented at end of loop
            } else {
                result.append(char)
            }

            i += 1
        }

        formatted = result

        // Step 3: Add newline before the final closing parenthesis
        if let range = formatted.range(of: ")", options: .backwards) {
            let before = String(formatted[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let after = String(formatted[range.lowerBound...])
            formatted = before + "\n" + after
        }

        return formatted.isEmpty ? ddl : formatted // Fallback to original if empty
    }

    // MARK: - Paginated Query Support

    func fetchRowCount(query: String) async throws -> Int {
        let baseQuery = stripLimitOffset(from: query)
        let countQuery = "SELECT COUNT(*) FROM (\(baseQuery))"

        let result = try await execute(query: countQuery)
        guard let firstRow = result.rows.first, let countStr = firstRow.first else { return 0 }
        return Int(countStr ?? "0") ?? 0
    }

    func fetchRows(query: String, offset: Int, limit: Int) async throws -> QueryResult {
        let baseQuery = stripLimitOffset(from: query)
        let paginatedQuery = "\(baseQuery) LIMIT \(limit) OFFSET \(offset)"
        return try await execute(query: paginatedQuery)
    }

    func fetchTableMetadata(tableName: String) async throws -> TableMetadata {
        guard status == .connected else {
            throw DatabaseError.notConnected
        }

        // Escape table name to prevent SQL injection (escape double quotes for identifier quoting)
        let safeTableName = tableName.replacingOccurrences(of: "\"", with: "\"\"")

        // Get row count — cap scan at 100k rows to avoid full table scan on large tables
        let countQuery = "SELECT COUNT(*) FROM (SELECT 1 FROM \"\(safeTableName)\" LIMIT 100001)"
        let countResult = try await execute(query: countQuery)
        let rowCount: Int64? = {
            guard let row = countResult.rows.first, let countStr = row.first else { return nil }
            return Int64(countStr ?? "0")
        }()

        // SQLite does not expose accurate per-table size information.
        // To avoid reporting misleading values, we leave size-related fields as nil.
        return TableMetadata(
            tableName: tableName,
            dataSize: nil,
            indexSize: nil,
            totalSize: nil,
            avgRowLength: nil,
            rowCount: rowCount,
            comment: nil,
            engine: "SQLite",
            collation: nil,
            createTime: nil,
            updateTime: nil
        )
    }

    private func stripLimitOffset(from query: String) -> String {
        var result = query

        if let limitRegex = Self.limitRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = limitRegex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }

        if let offsetRegex = Self.offsetRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = offsetRegex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    private func expandPath(_ path: String) -> String {
        if path.hasPrefix("~") {
            return NSString(string: path).expandingTildeInPath
        }
        return path
    }

    /// SQLite databases are file-based, so this returns an empty array
    func fetchDatabases() async throws -> [String] {
        // SQLite doesn't have a concept of multiple databases on a server
        // Each SQLite file is a separate database
        []
    }

    /// SQLite is file-based, return minimal metadata
    func fetchDatabaseMetadata(_ database: String) async throws -> DatabaseMetadata {
        DatabaseMetadata(
            id: database,
            name: database,
            tableCount: nil,
            sizeBytes: nil,
            lastAccessed: nil,
            isSystemDatabase: false,
            icon: "doc.fill"
        )
    }

    /// SQLite databases are created as files, not via SQL
    func createDatabase(name: String, charset: String, collation: String?) async throws {
        throw DatabaseError.unsupportedOperation
    }
}
