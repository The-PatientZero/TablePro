//
//  MySQLDriver.swift
//  TablePro
//
//  MySQL/MariaDB database driver using libmariadb (MariaDB Connector/C)
//

import Foundation
import os

/// MySQL/MariaDB database driver using libmariadb
/// Supports MySQL 5.7+, MySQL 8.x (all auth methods), and MariaDB
final class MySQLDriver: DatabaseDriver {
    let connection: DatabaseConnection
    private(set) var status: ConnectionStatus = .disconnected

    /// The underlying MariaDB connection
    private var mariadbConnection: MariaDBConnection?

    /// Static date formatter for parsing MySQL dates (performance optimization)
    private static let mysqlDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// Cached regex for extracting table name from SELECT queries
    private static let tableNameRegex = try? NSRegularExpression(pattern: "(?i)\\bFROM\\s+[`\"']?([\\w]+)[`\"']?")

    /// Cached regex for stripping LIMIT clause (handles LIMIT n or LIMIT n, m)
    private static let limitRegex = try? NSRegularExpression(pattern: "(?i)\\s+LIMIT\\s+\\d+(\\s*,\\s*\\d+)?")

    /// Cached regex for stripping OFFSET clause
    private static let offsetRegex = try? NSRegularExpression(pattern: "(?i)\\s+OFFSET\\s+\\d+")

    init(connection: DatabaseConnection) {
        self.connection = connection
    }

    // MARK: - Server Version

    /// Server version string from the connected database
    var serverVersion: String? {
        mariadbConnection?.serverVersion()
    }

    /// The actual server type detected from the version string after connecting.
    /// Falls back to `connection.type` if detection hasn't occurred.
    private(set) var detectedServerType: DatabaseType?

    // MARK: - Connection

    func connect() async throws {
        status = .connecting

        // Get password from Keychain
        let password = ConnectionStorage.shared.loadPassword(for: connection.id)

        // Create connection
        let conn = MariaDBConnection(
            host: connection.host,
            port: connection.port,
            user: connection.username,
            password: password,
            database: connection.database,
            sslConfig: connection.sslConfig
        )

        do {
            try await conn.connect()
            mariadbConnection = conn
            status = .connected

            // Auto-detect actual server type from version string
            // MariaDB includes "MariaDB" in its version (e.g., "10.5.20-MariaDB")
            if let version = conn.serverVersion() {
                detectedServerType = version.lowercased().contains("mariadb") ? .mariadb : .mysql
            }
        } catch let error as MariaDBError {
            status = .error(error.message)
            throw DatabaseError.connectionFailed(error.localizedDescription)
        } catch {
            status = .error(error.localizedDescription)
            throw DatabaseError.connectionFailed(error.localizedDescription)
        }
    }

    func disconnect() {
        mariadbConnection?.disconnect()
        mariadbConnection = nil
        detectedServerType = nil
        status = .disconnected
    }

    func testConnection() async throws -> Bool {
        try await connect()
        let isConnected = status == .connected
        disconnect()
        return isConnected
    }

    // MARK: - Query Execution

    func execute(query: String) async throws -> QueryResult {
        try await executeWithReconnect(query: query, isRetry: false)
    }

    func executeParameterized(query: String, parameters: [Any?]) async throws -> QueryResult {
        let startTime = Date()

        guard let conn = mariadbConnection else {
            throw DatabaseError.notConnected
        }

        do {
            // MariaDB Connector/C supports prepared statements via mysql_stmt_* API
            // For security, we use the prepared statement API which handles parameter binding safely
            let result = try await conn.executeParameterizedQuery(query, parameters: parameters)

            // Convert MySQL column types to ColumnType enum with raw type names
            let columnTypes = zip(result.columnTypes, result.columnTypeNames).map { mysqlType, rawType in
                ColumnType(fromMySQLType: mysqlType, rawType: rawType)
            }

            return QueryResult(
                columns: result.columns,
                columnTypes: columnTypes,
                rows: result.rows,
                rowsAffected: Int(result.affectedRows),
                executionTime: Date().timeIntervalSince(startTime),
                error: nil,
                isTruncated: result.isTruncated
            )
        } catch let error as MariaDBError {
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    // MARK: - Query Cancellation

    func cancelQuery() throws {
        mariadbConnection?.cancelCurrentQuery()
    }

    /// Execute query with automatic reconnection on connection-lost errors
    private func executeWithReconnect(query: String, isRetry: Bool) async throws -> QueryResult {
        let startTime = Date()

        guard let conn = mariadbConnection else {
            throw DatabaseError.notConnected
        }

        do {
            let result = try await conn.executeQuery(query)

            // Handle empty result for SELECT queries - try to get column names from table.
            // Only issue the extra DESCRIBE round-trip when the MariaDB C API returned no
            // column metadata AND the query is actually a SELECT (non-SELECT queries like
            // INSERT/UPDATE legitimately return empty columns).
            if result.columns.isEmpty && result.rows.isEmpty {
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                let isSelect = trimmed.uppercased().hasPrefix("SELECT")
                if isSelect, let tableName = extractTableName(from: query) {
                    let columns = try await fetchColumnNames(for: tableName)
                    return QueryResult(
                        columns: columns,
                        columnTypes: Array(repeating: .text(rawType: nil), count: columns.count),
                        rows: [],
                        rowsAffected: Int(result.affectedRows),
                        executionTime: Date().timeIntervalSince(startTime),
                        error: nil,
                        isTruncated: result.isTruncated
                    )
                }
            }

            // Convert MySQL column types to ColumnType enum
            let columnTypes = zip(result.columnTypes, result.columnTypeNames).map { mysqlType, rawType in
                ColumnType(fromMySQLType: mysqlType, rawType: rawType)
            }

            return QueryResult(
                columns: result.columns,
                columnTypes: columnTypes,
                rows: result.rows,
                rowsAffected: Int(result.affectedRows),
                executionTime: Date().timeIntervalSince(startTime),
                error: nil,
                isTruncated: result.isTruncated
            )
        } catch let error as MariaDBError where !isRetry && isConnectionLostError(error) {
            // Connection lost - attempt reconnect and retry once
            try await reconnect()
            return try await executeWithReconnect(query: query, isRetry: true)
        } catch let error as MariaDBError {
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    // MARK: - Auto-Reconnect

    /// Check if error indicates a lost connection that can be recovered
    private func isConnectionLostError(_ error: MariaDBError) -> Bool {
        // 2006 = Server has gone away
        // 2013 = Lost connection to MySQL server during query
        // 2055 = Lost connection to MySQL server at reading initial packet
        [2_006, 2_013, 2_055].contains(Int(error.code))
    }

    /// Reconnect to the database
    private func reconnect() async throws {
        // Close existing connection
        mariadbConnection?.disconnect()
        mariadbConnection = nil
        status = .connecting

        // Reconnect using stored connection info
        try await connect()
    }

    // MARK: - Schema

    func fetchTables() async throws -> [TableInfo] {
        let query = "SHOW FULL TABLES"
        let result = try await execute(query: query)

        return result.rows.compactMap { row in
            guard let name = row[0] else { return nil }
            let typeStr = row.count > 1 ? (row[1] ?? "BASE TABLE") : "BASE TABLE"
            let type: TableInfo.TableType = typeStr.contains("VIEW") ? .view : .table

            return TableInfo(name: name, type: type, rowCount: nil)
        }
    }

    func fetchColumns(table: String) async throws -> [ColumnInfo] {
        let safeTable = table.replacingOccurrences(of: "`", with: "``")
        let query = "SHOW FULL COLUMNS FROM `\(safeTable)`"
        let result = try await execute(query: query)

        return result.rows.compactMap { row in
            // SHOW FULL COLUMNS returns:
            // 0: Field, 1: Type, 2: Collation, 3: Null, 4: Key, 5: Default, 6: Extra, 7: Privileges, 8: Comment
            guard row.count >= 7,
                  let name = row[0],
                  let dataType = row[1]
            else {
                return nil
            }

            let collation = row.count > 2 ? row[2] : nil
            let isNullable = row[3] == "YES"
            let isPrimaryKey = row[4] == "PRI"
            let defaultValue = row[5]
            let extra = row[6]
            let comment = row.count > 8 ? row[8] : nil

            // Extract charset from collation (e.g., "utf8mb4_general_ci" -> "utf8mb4")
            let charset: String? = {
                guard let coll = collation, coll != "NULL" else { return nil }
                return coll.components(separatedBy: "_").first
            }()

            // Preserve original casing for ENUM/SET values (e.g., enum('Active','Inactive'))
            let upperType = dataType.uppercased()
            let normalizedType = (upperType.hasPrefix("ENUM(") || upperType.hasPrefix("SET("))
                ? dataType : upperType

            return ColumnInfo(
                name: name,
                dataType: normalizedType,
                isNullable: isNullable,
                isPrimaryKey: isPrimaryKey,
                defaultValue: defaultValue,
                extra: extra,
                charset: charset,
                collation: collation == "NULL" ? nil : collation,
                comment: comment?.isEmpty == false ? comment : nil
            )
        }
    }

    /// Bulk-fetch columns for all tables in the current database using a single
    /// INFORMATION_SCHEMA query (avoids N+1 per-table SHOW FULL COLUMNS calls).
    func fetchAllColumns() async throws -> [String: [ColumnInfo]] {
        let dbName = connection.database
        let query = """
            SELECT
                TABLE_NAME, COLUMN_NAME, COLUMN_TYPE, COLLATION_NAME,
                IS_NULLABLE, COLUMN_KEY, COLUMN_DEFAULT, EXTRA, COLUMN_COMMENT
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = '\(SQLEscaping.escapeStringLiteral(dbName))'
            ORDER BY TABLE_NAME, ORDINAL_POSITION
            """

        let result = try await execute(query: query)

        var allColumns: [String: [ColumnInfo]] = [:]
        for row in result.rows {
            guard row.count >= 8,
                  let tableName = row[0],
                  let name = row[1],
                  let dataType = row[2]
            else {
                continue
            }

            let collation = row[3]
            let isNullable = row[4] == "YES"
            let isPrimaryKey = row[5] == "PRI"
            let defaultValue = row[6]
            let extra = row[7]
            let comment = row.count > 8 ? row[8] : nil

            let charset: String? = {
                guard let coll = collation, coll != "NULL" else { return nil }
                return coll.components(separatedBy: "_").first
            }()

            let upperType = dataType.uppercased()
            let normalizedType = (upperType.hasPrefix("ENUM(") || upperType.hasPrefix("SET("))
                ? dataType : upperType

            let column = ColumnInfo(
                name: name,
                dataType: normalizedType,
                isNullable: isNullable,
                isPrimaryKey: isPrimaryKey,
                defaultValue: defaultValue,
                extra: extra,
                charset: charset,
                collation: collation == "NULL" ? nil : collation,
                comment: comment?.isEmpty == false ? comment : nil
            )

            allColumns[tableName, default: []].append(column)
        }

        return allColumns
    }

    func fetchIndexes(table: String) async throws -> [IndexInfo] {
        let safeTable = table.replacingOccurrences(of: "`", with: "``")
        let query = "SHOW INDEX FROM `\(safeTable)`"
        let result = try await execute(query: query)

        // Group by index name (Key_name is column index 2)
        var indexMap: [String: (columns: [String], isUnique: Bool, type: String)] = [:]

        for row in result.rows {
            guard row.count >= 11,
                  let indexName = row[2],  // Key_name
                  let columnName = row[4]  // Column_name
            else {
                continue
            }

            let nonUnique = row[1] == "1"  // Non_unique: 0 = unique, 1 = not unique
            let indexType = row[10] ?? "BTREE"  // Index_type

            if var existing = indexMap[indexName] {
                existing.columns.append(columnName)
                indexMap[indexName] = existing
            } else {
                indexMap[indexName] = (
                    columns: [columnName],
                    isUnique: !nonUnique,
                    type: indexType
                )
            }
        }

        return indexMap
            .map { name, info in
                IndexInfo(
                    name: name,
                    columns: info.columns,
                    isUnique: info.isUnique,
                    isPrimary: name == "PRIMARY",
                    type: info.type
                )
            }
            .sorted { $0.isPrimary && !$1.isPrimary }  // PRIMARY key first
    }

    func fetchForeignKeys(table: String) async throws -> [ForeignKeyInfo] {
        // Get database name from connection
        let dbName = connection.database

        let query = """
            SELECT
                kcu.CONSTRAINT_NAME,
                kcu.COLUMN_NAME,
                kcu.REFERENCED_TABLE_NAME,
                kcu.REFERENCED_COLUMN_NAME,
                rc.DELETE_RULE,
                rc.UPDATE_RULE
            FROM information_schema.KEY_COLUMN_USAGE kcu
            JOIN information_schema.REFERENTIAL_CONSTRAINTS rc
                ON kcu.CONSTRAINT_NAME = rc.CONSTRAINT_NAME
                AND kcu.CONSTRAINT_SCHEMA = rc.CONSTRAINT_SCHEMA
            WHERE kcu.TABLE_SCHEMA = '\(SQLEscaping.escapeStringLiteral(dbName))'
                AND kcu.TABLE_NAME = '\(SQLEscaping.escapeStringLiteral(table))'
                AND kcu.REFERENCED_TABLE_NAME IS NOT NULL
            ORDER BY kcu.CONSTRAINT_NAME
            """

        let result = try await execute(query: query)

        return result.rows.compactMap { row in
            guard row.count >= 6,
                  let name = row[0],
                  let column = row[1],
                  let refTable = row[2],
                  let refColumn = row[3]
            else {
                return nil
            }

            return ForeignKeyInfo(
                name: name,
                column: column,
                referencedTable: refTable,
                referencedColumn: refColumn,
                onDelete: row[4] ?? "NO ACTION",
                onUpdate: row[5] ?? "NO ACTION"
            )
        }
    }

    func fetchTableDDL(table: String) async throws -> String {
        // The `table` argument must be a valid MySQL/MariaDB table identifier, optionally
        // schema-qualified, and is interpolated verbatim into the query. Examples:
        //   - "users"
        //   - "`mydb`.`users`"
        //   - "`users`"
        //
        // This method does not add any quoting or escaping around `table`. It is the
        // caller's responsibility to provide a correctly formatted and safely quoted
        // identifier when needed.
        let query = "SHOW CREATE TABLE \(table)"
        let result = try await execute(query: query)

        // SHOW CREATE TABLE returns 2 columns: Table name and Create Table statement
        guard let firstRow = result.rows.first,
              firstRow.count >= 2,
              let ddl = firstRow[1]
        else {
            throw DatabaseError.queryFailed("Failed to fetch DDL for table '\(table)'")
        }

        return ddl.hasSuffix(";") ? ddl : ddl + ";"
    }

    func fetchViewDefinition(view: String) async throws -> String {
        let query = "SHOW CREATE VIEW \(view)"
        let result = try await execute(query: query)

        // SHOW CREATE VIEW returns columns: View, Create View, character_set_client, collation_connection
        guard let firstRow = result.rows.first,
              firstRow.count >= 2,
              let ddl = firstRow[1]
        else {
            throw DatabaseError.queryFailed("Failed to fetch definition for view '\(view)'")
        }

        return ddl
    }

    func fetchTableMetadata(tableName: String) async throws -> TableMetadata {
        // NOTE: `SHOW TABLE STATUS LIKE` expects a pattern string literal, not an
        // identifier. For that reason we must use single-quoted string syntax here
        // instead of the backtick identifier quoting used in other schema queries
        // (e.g. `SHOW CREATE TABLE \`table\``). The table name is safely embedded
        // using SQLEscaping.escapeStringLiteral.
        let query = "SHOW TABLE STATUS WHERE Name = '\(SQLEscaping.escapeStringLiteral(tableName))'"
        let result = try await execute(query: query)

        guard let row = result.rows.first else {
            return TableMetadata(
                tableName: tableName,
                dataSize: nil,
                indexSize: nil,
                totalSize: nil,
                avgRowLength: nil,
                rowCount: nil,
                comment: nil,
                engine: nil,
                collation: nil,
                createTime: nil,
                updateTime: nil
            )
        }

        // SHOW TABLE STATUS columns:
        // 0: Name, 1: Engine, 2: Version, 3: Row_format, 4: Rows, 5: Avg_row_length,
        // 6: Data_length, 7: Max_data_length, 8: Index_length, 9: Data_free,
        // 10: Auto_increment, 11: Create_time, 12: Update_time, 13: Check_time,
        // 14: Collation, 15: Checksum, 16: Create_options, 17: Comment

        let engine = row.count > 1 ? row[1] : nil
        let rowCount = row.count > 4 ? Int64(row[4] ?? "0") : nil
        let avgRowLength = row.count > 5 ? Int64(row[5] ?? "0") : nil
        let dataSize = row.count > 6 ? Int64(row[6] ?? "0") : nil
        let indexSize = row.count > 8 ? Int64(row[8] ?? "0") : nil
        let collation = row.count > 14 ? row[14] : nil
        let comment = row.count > 17 ? row[17] : nil

        // Parse dates using static formatter for performance
        let createTime: Date? = {
            guard row.count > 11, let dateStr = row[11] else { return nil }
            return Self.mysqlDateFormatter.date(from: dateStr)
        }()

        let updateTime: Date? = {
            guard row.count > 12, let dateStr = row[12] else { return nil }
            return Self.mysqlDateFormatter.date(from: dateStr)
        }()

        let totalSize: Int64? = {
            guard let data = dataSize, let index = indexSize else { return nil }
            return data + index
        }()

        return TableMetadata(
            tableName: tableName,
            dataSize: dataSize,
            indexSize: indexSize,
            totalSize: totalSize,
            avgRowLength: avgRowLength,
            rowCount: rowCount,
            comment: comment?.isEmpty == true ? nil : comment,
            engine: engine,
            collation: collation,
            createTime: createTime,
            updateTime: updateTime
        )
    }

    // MARK: - Paginated Query Support

    func fetchRowCount(query: String) async throws -> Int {
        // Strip any existing LIMIT/OFFSET from the query
        let baseQuery = stripLimitOffset(from: query)
        let countQuery = "SELECT COUNT(*) AS cnt FROM (\(baseQuery)) AS __count_subquery__"

        let result = try await execute(query: countQuery)

        // Get the count from first row, first column
        guard let firstRow = result.rows.first,
              !firstRow.isEmpty,
              let countStr = firstRow[0],
              let count = Int(countStr)
        else {
            return 0
        }

        return count
    }

    func fetchRows(query: String, offset: Int, limit: Int) async throws -> QueryResult {
        // Strip any existing LIMIT/OFFSET and apply new ones
        let baseQuery = stripLimitOffset(from: query)
        let paginatedQuery = "\(baseQuery) LIMIT \(limit) OFFSET \(offset)"
        return try await execute(query: paginatedQuery)
    }

    // MARK: - Helpers

    /// Extract table name from SELECT query
    private func extractTableName(from query: String) -> String? {
        guard let regex = Self.tableNameRegex,
              let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              let range = Range(match.range(at: 1), in: query)
        else {
            return nil
        }
        return String(query[range])
    }

    /// Fetch column names using DESCRIBE
    private func fetchColumnNames(for tableName: String) async throws -> [String] {
        let safeName = tableName.replacingOccurrences(of: "`", with: "``")
        let result = try await execute(query: "DESCRIBE `\(safeName)`")

        var columns: [String] = []
        for row in result.rows {
            if let columnName = row.first, let unwrappedName = columnName {
                columns.append(unwrappedName)
            }
        }
        return columns
    }

    /// Remove LIMIT and OFFSET clauses from a query
    private func stripLimitOffset(from query: String) -> String {
        var result = query

        // Remove LIMIT clause (handles LIMIT n or LIMIT n, m)
        if let regex = Self.limitRegex {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove OFFSET clause
        if let regex = Self.offsetRegex {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fetch list of all databases on the server
    func fetchDatabases() async throws -> [String] {
        let result = try await execute(query: "SHOW DATABASES")
        return result.rows.compactMap { row in row.first.flatMap { $0 } }
    }

    /// Fetch metadata for a specific database
    func fetchDatabaseMetadata(_ database: String) async throws -> DatabaseMetadata {
        // Escape database name for use as a SQL string literal in information_schema queries
        let escapedDbLiteral = SQLEscaping.escapeStringLiteral(database)

        // Single query for both table count and total size
        let query = """
            SELECT COUNT(*), COALESCE(SUM(DATA_LENGTH + INDEX_LENGTH), 0)
            FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = '\(escapedDbLiteral)'
        """
        let result = try await execute(query: query)
        let row = result.rows.first
        let tableCount = Int(row?[0] ?? "0") ?? 0
        let sizeBytes = Int64(row?[1] ?? "0") ?? 0

        // Determine if system database
        let systemDatabases = ["information_schema", "mysql", "performance_schema", "sys"]
        let isSystem = systemDatabases.contains(database)

        return DatabaseMetadata(
            id: database,
            name: database,
            tableCount: tableCount,
            sizeBytes: sizeBytes,
            lastAccessed: nil,  // Could track separately if needed
            isSystemDatabase: isSystem,
            icon: isSystem ? "gearshape.fill" : "cylinder.fill"
        )
    }

    /// Create a new database
    func createDatabase(name: String, charset: String, collation: String?) async throws {
        // Escape backticks in database name
        let escapedName = name.replacingOccurrences(of: "`", with: "``")

        // Validate charset (basic validation - should be expanded)
        let validCharsets = ["utf8mb4", "utf8", "latin1", "ascii"]
        guard validCharsets.contains(charset) else {
            throw DatabaseError.queryFailed("Invalid character set: \(charset)")
        }

        var query = "CREATE DATABASE `\(escapedName)` CHARACTER SET \(charset)"

        // Validate collation if provided
        if let collation = collation {
            // Collation must match charset prefix and only contain safe identifier characters
            let allowedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
            let isSafe = collation.unicodeScalars.allSatisfy { allowedChars.contains($0) }
            guard collation.hasPrefix(charset), isSafe else {
                throw DatabaseError.queryFailed("Invalid collation for charset")
            }
            query += " COLLATE \(collation)"
        }

        _ = try await execute(query: query)
    }

    // MARK: - Query Timeout

    /// Override to use detected server type instead of connection.type
    func applyQueryTimeout(_ seconds: Int) async throws {
        guard seconds > 0 else { return }
        let effectiveType = detectedServerType ?? connection.type
        do {
            switch effectiveType {
            case .mysql:
                let ms = seconds * 1_000
                _ = try await execute(query: "SET SESSION max_execution_time = \(ms)")
            case .mariadb:
                _ = try await execute(query: "SET SESSION max_statement_time = \(seconds)")
            default:
                break
            }
        } catch {
            Logger(subsystem: "com.TablePro", category: "MySQLDriver")
                .warning("Failed to set query timeout: \(error.localizedDescription)")
        }
    }
}
