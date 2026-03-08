//
//  ClickHouseDriver.swift
//  TablePro
//
//  ClickHouse driver using HTTP interface via ClickHouseConnection
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.TablePro", category: "ClickHouseDriver")

/// ClickHouse database driver using the HTTP interface
final class ClickHouseDriver: DatabaseDriver {
    let connection: DatabaseConnection
    private(set) var status: ConnectionStatus = .disconnected

    private var chConn: ClickHouseConnection?

    var serverVersion: String? {
        _serverVersion
    }
    private var _serverVersion: String?

    var progressHandler: ((ClickHouseQueryProgress) -> Void)?
    private var currentQueryId: String?
    private var progressPollingTask: Task<Void, Never>?

    init(connection: DatabaseConnection) {
        self.connection = connection
    }

    // MARK: - Connection

    func connect() async throws {
        status = .connecting
        let useTLS = connection.sslConfig.isEnabled
        let skipVerification = connection.sslConfig.mode == .required
        let conn = ClickHouseConnection(
            host: connection.host,
            port: connection.port,
            user: connection.username,
            password: ConnectionStorage.shared.loadPassword(for: connection.id) ?? "",
            database: connection.database,
            useTLS: useTLS,
            skipTLSVerification: skipVerification
        )
        do {
            try await conn.connect()
            self.chConn = conn
            status = .connected
            if let result = try? await conn.executeQuery("SELECT version()"),
               let versionStr = result.rows.first?.first ?? nil {
                _serverVersion = versionStr
            }
        } catch {
            status = .error(error.localizedDescription)
            throw error
        }
    }

    func disconnect() {
        chConn?.disconnect()
        chConn = nil
        status = .disconnected
    }

    // MARK: - Query Execution

    func execute(query: String) async throws -> QueryResult {
        guard let conn = chConn else {
            throw DatabaseError.connectionFailed("Not connected to ClickHouse")
        }
        let queryId = UUID().uuidString
        currentQueryId = queryId

        // Only poll progress for user-initiated queries (when a handler is set by the coordinator)
        let shouldPoll = progressHandler != nil
        if shouldPoll {
            startProgressPolling(queryId: queryId)
        }

        let startTime = Date()
        do {
            let result = try await conn.executeQuery(query, queryId: queryId)
            if shouldPoll { stopProgressPolling() }

            let queryResult = mapToQueryResult(result, executionTime: Date().timeIntervalSince(startTime))

            if let summary = result.summary {
                let progress = ClickHouseQueryProgress(
                    rowsRead: summary.rowsRead,
                    bytesRead: summary.bytesRead,
                    totalRowsToRead: summary.totalRowsToRead,
                    elapsedSeconds: Date().timeIntervalSince(startTime)
                )
                progressHandler?(progress)
            }

            return queryResult
        } catch {
            if shouldPoll { stopProgressPolling() }
            throw error
        }
    }

    func executeParameterized(query: String, parameters: [Any?]) async throws -> QueryResult {
        let statement = ParameterizedStatement(sql: query, parameters: parameters)
        let built = SQLParameterInliner.inline(statement, databaseType: .clickhouse)
        return try await execute(query: built)
    }

    func fetchRowCount(query: String) async throws -> Int {
        let countQuery = "SELECT count() FROM (\(query)) AS __cnt"
        let result = try await execute(query: countQuery)
        guard let row = result.rows.first,
              let cell = row.first,
              let str = cell,
              let count = Int(str) else {
            return 0
        }
        return count
    }

    func fetchRows(query: String, offset: Int, limit: Int) async throws -> QueryResult {
        var base = query.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix(";") {
            base = String(base.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        base = stripLimitOffset(from: base)
        let paginated = "\(base) LIMIT \(limit) OFFSET \(offset)"
        return try await execute(query: paginated)
    }

    // MARK: - Schema Operations

    func fetchTables() async throws -> [TableInfo] {
        let sql = """
            SELECT name, engine FROM system.tables
            WHERE database = currentDatabase() AND name NOT LIKE '.%'
            ORDER BY name
            """
        let result = try await execute(query: sql)
        return result.rows.compactMap { row -> TableInfo? in
            guard let name = row[safe: 0] ?? nil else { return nil }
            let engine = row[safe: 1] ?? nil
            let tableType: TableInfo.TableType = (engine?.contains("View") == true) ? .view : .table
            return TableInfo(name: name, type: tableType, rowCount: nil)
        }
    }

    func fetchColumns(table: String) async throws -> [ColumnInfo] {
        let escapedTable = table.replacingOccurrences(of: "'", with: "''")

        // Fetch primary key columns from system.tables (falls back to sorting_key if primary_key is empty)
        let pkSql = """
            SELECT primary_key, sorting_key FROM system.tables
            WHERE database = currentDatabase() AND name = '\(escapedTable)'
            """
        let pkResult = try await execute(query: pkSql)
        let primaryKey = pkResult.rows.first.flatMap { $0[safe: 0] ?? nil } ?? ""
        let sortingKey = pkResult.rows.first.flatMap { $0[safe: 1] ?? nil } ?? ""
        let keyString = primaryKey.isEmpty ? sortingKey : primaryKey
        let pkColumns = Set(keyString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })

        let sql = """
            SELECT name, type, default_kind, default_expression, comment
            FROM system.columns
            WHERE database = currentDatabase() AND table = '\(escapedTable)'
            ORDER BY position
            """
        let result = try await execute(query: sql)
        return result.rows.compactMap { row -> ColumnInfo? in
            guard let name = row[safe: 0] ?? nil else { return nil }
            let dataType = (row[safe: 1] ?? nil) ?? "String"
            let defaultKind = row[safe: 2] ?? nil
            let defaultExpr = row[safe: 3] ?? nil
            let comment = row[safe: 4] ?? nil

            let isNullable = dataType.hasPrefix("Nullable(")

            var defaultValue: String?
            if let kind = defaultKind, !kind.isEmpty, let expr = defaultExpr, !expr.isEmpty {
                defaultValue = expr
            }

            var extra: String?
            if let kind = defaultKind, !kind.isEmpty, kind != "DEFAULT" {
                extra = kind
            }

            return ColumnInfo(
                name: name,
                dataType: dataType,
                isNullable: isNullable,
                isPrimaryKey: pkColumns.contains(name),
                defaultValue: defaultValue,
                extra: extra,
                charset: nil,
                collation: nil,
                comment: (comment?.isEmpty == false) ? comment : nil
            )
        }
    }

    func fetchAllColumns() async throws -> [String: [ColumnInfo]] {
        let sql = """
            SELECT table, name, type, default_kind, default_expression, comment
            FROM system.columns
            WHERE database = currentDatabase()
            ORDER BY table, position
            """
        let result = try await execute(query: sql)
        var columnsByTable: [String: [ColumnInfo]] = [:]
        for row in result.rows {
            guard let tableName = row[safe: 0] ?? nil,
                  let colName = row[safe: 1] ?? nil else { continue }
            let dataType = (row[safe: 2] ?? nil) ?? "String"
            let defaultKind = row[safe: 3] ?? nil
            let defaultExpr = row[safe: 4] ?? nil
            let comment = row[safe: 5] ?? nil

            let isNullable = dataType.hasPrefix("Nullable(")

            var defaultValue: String?
            if let kind = defaultKind, !kind.isEmpty, let expr = defaultExpr, !expr.isEmpty {
                defaultValue = expr
            }

            var extra: String?
            if let kind = defaultKind, !kind.isEmpty, kind != "DEFAULT" {
                extra = kind
            }

            let colInfo = ColumnInfo(
                name: colName,
                dataType: dataType,
                isNullable: isNullable,
                isPrimaryKey: false,
                defaultValue: defaultValue,
                extra: extra,
                charset: nil,
                collation: nil,
                comment: (comment?.isEmpty == false) ? comment : nil
            )
            columnsByTable[tableName, default: []].append(colInfo)
        }
        return columnsByTable
    }

    func fetchIndexes(table: String) async throws -> [IndexInfo] {
        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        var indexes: [IndexInfo] = []

        // Fetch sorting key (acts as primary index in ClickHouse)
        let sortingKeySql = """
            SELECT sorting_key FROM system.tables
            WHERE database = currentDatabase() AND name = '\(escapedTable)'
            """
        let sortingResult = try await execute(query: sortingKeySql)
        if let row = sortingResult.rows.first,
           let sortingKey = row[safe: 0] ?? nil, !sortingKey.isEmpty {
            let columns = sortingKey.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            indexes.append(IndexInfo(
                name: "PRIMARY (sorting key)",
                columns: columns,
                isUnique: false,
                isPrimary: true,
                type: "SORTING KEY"
            ))
        }

        // Fetch data skipping indices
        let skippingSql = """
            SELECT name, expr FROM system.data_skipping_indices
            WHERE database = currentDatabase() AND table = '\(escapedTable)'
            """
        let skippingResult = try await execute(query: skippingSql)
        for row in skippingResult.rows {
            guard let idxName = row[safe: 0] ?? nil else { continue }
            let expr = (row[safe: 1] ?? nil) ?? ""
            let columns = expr.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            indexes.append(IndexInfo(
                name: idxName,
                columns: columns,
                isUnique: false,
                isPrimary: false,
                type: "DATA_SKIPPING"
            ))
        }

        return indexes
    }

    func fetchForeignKeys(table: String) async throws -> [ForeignKeyInfo] {
        // ClickHouse does not support foreign keys
        []
    }

    func fetchApproximateRowCount(table: String) async throws -> Int? {
        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        let sql = """
            SELECT sum(rows) FROM system.parts
            WHERE database = currentDatabase() AND table = '\(escapedTable)' AND active = 1
            """
        let result = try await execute(query: sql)
        if let row = result.rows.first, let cell = row.first, let str = cell {
            return Int(str)
        }
        return nil
    }

    func fetchTableDDL(table: String) async throws -> String {
        let escapedTable = table.replacingOccurrences(of: "`", with: "``")
        let sql = "SHOW CREATE TABLE `\(escapedTable)`"
        let result = try await execute(query: sql)
        return result.rows.first?.first?.flatMap { $0 } ?? ""
    }

    func fetchViewDefinition(view: String) async throws -> String {
        let escapedView = view.replacingOccurrences(of: "'", with: "''")
        let sql = """
            SELECT as_select FROM system.tables
            WHERE database = currentDatabase() AND name = '\(escapedView)'
            """
        let result = try await execute(query: sql)
        return result.rows.first?.first?.flatMap { $0 } ?? ""
    }

    func fetchTableMetadata(tableName: String) async throws -> TableMetadata {
        let escapedTable = tableName.replacingOccurrences(of: "'", with: "''")

        // Fetch engine from system.tables
        let engineSql = """
            SELECT engine, comment FROM system.tables
            WHERE database = currentDatabase() AND name = '\(escapedTable)'
            """
        let engineResult = try await execute(query: engineSql)
        let engine = engineResult.rows.first.flatMap { $0[safe: 0] ?? nil }
        let tableComment = engineResult.rows.first.flatMap { $0[safe: 1] ?? nil }

        // Fetch row count and size from system.parts
        let partsSql = """
            SELECT sum(rows), sum(bytes_on_disk)
            FROM system.parts
            WHERE database = currentDatabase() AND table = '\(escapedTable)' AND active = 1
            """
        let partsResult = try await execute(query: partsSql)
        if let row = partsResult.rows.first {
            let rowCount = (row[safe: 0] ?? nil).flatMap { Int64($0) }
            let sizeBytes = (row[safe: 1] ?? nil).flatMap { Int64($0) } ?? 0
            return TableMetadata(
                tableName: tableName,
                dataSize: sizeBytes,
                indexSize: nil,
                totalSize: sizeBytes,
                avgRowLength: nil,
                rowCount: rowCount,
                comment: (tableComment?.isEmpty == false) ? tableComment : nil,
                engine: engine,
                collation: nil,
                createTime: nil,
                updateTime: nil
            )
        }

        return TableMetadata(
            tableName: tableName,
            dataSize: nil,
            indexSize: nil,
            totalSize: nil,
            avgRowLength: nil,
            rowCount: nil,
            comment: nil,
            engine: engine,
            collation: nil,
            createTime: nil,
            updateTime: nil
        )
    }

    func fetchDatabases() async throws -> [String] {
        let result = try await execute(query: "SHOW DATABASES")
        return result.rows.compactMap { $0.first ?? nil }
    }

    func fetchSchemas() async throws -> [String] {
        // ClickHouse does not have schemas
        []
    }

    func fetchDatabaseMetadata(_ database: String) async throws -> DatabaseMetadata {
        let escapedDb = database.replacingOccurrences(of: "'", with: "''")
        let sql = """
            SELECT count() AS table_count, sum(total_bytes) AS size_bytes
            FROM system.tables WHERE database = '\(escapedDb)'
            """
        let result = try await execute(query: sql)
        if let row = result.rows.first {
            let tableCount = (row[safe: 0] ?? nil).flatMap { Int($0) } ?? 0
            let sizeBytes = (row[safe: 1] ?? nil).flatMap { Int64($0) }
            return DatabaseMetadata(
                id: database,
                name: database,
                tableCount: tableCount,
                sizeBytes: sizeBytes,
                lastAccessed: nil,
                isSystemDatabase: false,
                icon: "cylinder.fill"
            )
        }
        return DatabaseMetadata.minimal(name: database)
    }

    func createDatabase(name: String, charset: String, collation: String?) async throws {
        let escapedName = name.replacingOccurrences(of: "`", with: "``")
        _ = try await execute(query: "CREATE DATABASE `\(escapedName)`")
    }

    func cancelQuery() throws {
        let queryId = currentQueryId
        chConn?.cancel()
        stopProgressPolling()
        if let queryId, let conn = chConn {
            Task.detached {
                conn.killQuery(queryId: queryId)
            }
        }
    }

    // MARK: - Transactions

    func beginTransaction() async throws {
        logger.warning("ClickHouse does not support transactions; BEGIN is a no-op")
    }

    func commitTransaction() async throws {
        // No-op: ClickHouse does not support transactions
    }

    func rollbackTransaction() async throws {
        // No-op: ClickHouse does not support transactions
    }

    // MARK: - Database Switching

    func switchDatabase(to database: String) async throws {
        guard let conn = chConn else {
            throw DatabaseError.connectionFailed("Not connected to ClickHouse")
        }
        try await conn.switchDatabase(database)
    }

    // MARK: - Progress Polling

    private func startProgressPolling(queryId: String) {
        guard progressHandler != nil else { return }

        progressPollingTask = Task { [weak self] in
            // Reuse a single connection for all polls
            guard let self else { return }
            let pollConn = ClickHouseConnection(
                host: self.connection.host,
                port: self.connection.port,
                user: self.connection.username,
                password: ConnectionStorage.shared.loadPassword(for: self.connection.id) ?? "",
                database: "",
                useTLS: self.connection.sslConfig.isEnabled,
                skipTLSVerification: self.connection.sslConfig.mode == .required
            )

            do {
                try await pollConn.connect()
            } catch {
                return
            }

            defer { pollConn.disconnect() }

            let escapedId = queryId.replacingOccurrences(of: "'", with: "\\'")
            let pollQuery = """
                SELECT read_rows, read_bytes, total_rows_approx, elapsed
                FROM system.processes
                WHERE query_id = '\(escapedId)'
                """

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { break }

                do {
                    let result = try await pollConn.executeQuery(pollQuery)
                    if let row = result.rows.first {
                        let rowsRead = (row[safe: 0] ?? nil).flatMap { UInt64($0) } ?? 0
                        let bytesRead = (row[safe: 1] ?? nil).flatMap { UInt64($0) } ?? 0
                        let totalRows = (row[safe: 2] ?? nil).flatMap { UInt64($0) } ?? 0
                        let elapsed = (row[safe: 3] ?? nil).flatMap { Double($0) } ?? 0

                        let progress = ClickHouseQueryProgress(
                            rowsRead: rowsRead,
                            bytesRead: bytesRead,
                            totalRowsToRead: totalRows,
                            elapsedSeconds: elapsed
                        )
                        await MainActor.run {
                            self.progressHandler?(progress)
                        }
                    }
                } catch {
                    // Polling failure is non-fatal — query continues
                }
            }
        }
    }

    private func stopProgressPolling() {
        progressPollingTask?.cancel()
        progressPollingTask = nil
        currentQueryId = nil
    }

    // MARK: - ClickHouse-Specific

    func fetchClickHouseParts(table: String) async throws -> [ClickHousePartInfo] {
        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        let sql = """
            SELECT partition, name, rows, bytes_on_disk,
                   toString(modification_time) AS mod_time, active
            FROM system.parts
            WHERE database = currentDatabase() AND table = '\(escapedTable)'
            ORDER BY partition, name
            """
        let result = try await execute(query: sql)
        return result.rows.compactMap { row -> ClickHousePartInfo? in
            guard let name = row[safe: 1] ?? nil else { return nil }
            let partition = (row[safe: 0] ?? nil) ?? ""
            let rows = (row[safe: 2] ?? nil).flatMap { UInt64($0) } ?? 0
            let bytesOnDisk = (row[safe: 3] ?? nil).flatMap { UInt64($0) } ?? 0
            let modTime = (row[safe: 4] ?? nil) ?? ""
            let active = (row[safe: 5] ?? nil) == "1"
            return ClickHousePartInfo(
                partition: partition,
                name: name,
                rows: rows,
                bytesOnDisk: bytesOnDisk,
                modificationTime: modTime,
                active: active
            )
        }
    }

    // MARK: - Private Helpers

    private func mapToQueryResult(_ chResult: ClickHouseQueryResult, executionTime: TimeInterval) -> QueryResult {
        let columnTypes = chResult.columnTypeNames.map { rawType in
            ColumnType(fromClickHouseType: rawType)
        }
        return QueryResult(
            columns: chResult.columns,
            columnTypes: columnTypes,
            rows: chResult.rows,
            rowsAffected: chResult.affectedRows,
            executionTime: executionTime,
            error: nil
        )
    }

    /// Strip trailing LIMIT/OFFSET clauses so fetchRows can re-apply pagination.
    private func stripLimitOffset(from query: String) -> String {
        let ns = query as NSString
        let len = ns.length
        guard len > 0 else { return query }

        // Case-insensitive search for the last top-level LIMIT clause
        let upper = query.uppercased() as NSString
        var depth = 0
        var i = len - 1

        while i >= 4 {
            let ch = upper.character(at: i)
            if ch == 0x29 { depth += 1 }       // ')'
            else if ch == 0x28 { depth -= 1 }  // '('
            else if depth == 0 && ch == 0x54 { // 'T' — end of "LIMIT"
                let start = i - 4
                if start >= 0 {
                    let candidate = upper.substring(with: NSRange(location: start, length: 5))
                    if candidate == "LIMIT" {
                        // Verify it's a word boundary (preceded by whitespace or start of string)
                        if start == 0 || CharacterSet.whitespacesAndNewlines
                            .contains(UnicodeScalar(upper.character(at: start - 1)) ?? UnicodeScalar(0)) {
                            return ns.substring(to: start)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
            }
            i -= 1
        }
        return query
    }
}
