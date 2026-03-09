import Foundation

public protocol PluginDatabaseDriver: AnyObject, Sendable {
    // Connection
    func connect() async throws
    func disconnect()
    func ping() async throws

    // Queries
    func execute(query: String) async throws -> PluginQueryResult
    func fetchRowCount(query: String) async throws -> Int
    func fetchRows(query: String, offset: Int, limit: Int) async throws -> PluginQueryResult

    // Schema
    func fetchTables(schema: String?) async throws -> [PluginTableInfo]
    func fetchColumns(table: String, schema: String?) async throws -> [PluginColumnInfo]
    func fetchIndexes(table: String, schema: String?) async throws -> [PluginIndexInfo]
    func fetchForeignKeys(table: String, schema: String?) async throws -> [PluginForeignKeyInfo]
    func fetchTableDDL(table: String, schema: String?) async throws -> String
    func fetchViewDefinition(view: String, schema: String?) async throws -> String
    func fetchTableMetadata(table: String, schema: String?) async throws -> PluginTableMetadata
    func fetchDatabases() async throws -> [String]
    func fetchDatabaseMetadata(_ database: String) async throws -> PluginDatabaseMetadata

    // Schema navigation
    var supportsSchemas: Bool { get }
    func fetchSchemas() async throws -> [String]
    func switchSchema(to schema: String) async throws
    var currentSchema: String? { get }

    // Transactions
    var supportsTransactions: Bool { get }
    func beginTransaction() async throws
    func commitTransaction() async throws
    func rollbackTransaction() async throws

    // Execution control
    func cancelQuery() throws
    func applyQueryTimeout(_ seconds: Int) async throws
    var serverVersion: String? { get }

    // Batch operations
    func fetchApproximateRowCount(table: String, schema: String?) async throws -> Int?
    func fetchAllColumns(schema: String?) async throws -> [String: [PluginColumnInfo]]
    func fetchAllForeignKeys(schema: String?) async throws -> [String: [PluginForeignKeyInfo]]
    func fetchAllDatabaseMetadata() async throws -> [PluginDatabaseMetadata]
    func fetchDependentTypes(table: String, schema: String?) async throws -> [(name: String, labels: [String])]
    func fetchDependentSequences(table: String, schema: String?) async throws -> [(name: String, ddl: String)]
    func createDatabase(name: String, charset: String, collation: String?) async throws
    func executeParameterized(query: String, parameters: [String?]) async throws -> PluginQueryResult

    // Database switching (SQL Server USE, ClickHouse database switch, etc.)
    func switchDatabase(to database: String) async throws
}

public extension PluginDatabaseDriver {
    var supportsSchemas: Bool { false }

    func fetchSchemas() async throws -> [String] { [] }

    func switchSchema(to schema: String) async throws {}

    var currentSchema: String? { nil }

    var supportsTransactions: Bool { true }

    func beginTransaction() async throws {
        _ = try await execute(query: "BEGIN")
    }

    func commitTransaction() async throws {
        _ = try await execute(query: "COMMIT")
    }

    func rollbackTransaction() async throws {
        _ = try await execute(query: "ROLLBACK")
    }

    func cancelQuery() throws {}

    func applyQueryTimeout(_ seconds: Int) async throws {}

    func ping() async throws {
        _ = try await execute(query: "SELECT 1")
    }

    var serverVersion: String? { nil }

    func fetchApproximateRowCount(table: String, schema: String?) async throws -> Int? { nil }

    func fetchAllColumns(schema: String?) async throws -> [String: [PluginColumnInfo]] {
        let tables = try await fetchTables(schema: schema)
        var result: [String: [PluginColumnInfo]] = [:]
        for table in tables {
            result[table.name] = try await fetchColumns(table: table.name, schema: schema)
        }
        return result
    }

    func fetchAllForeignKeys(schema: String?) async throws -> [String: [PluginForeignKeyInfo]] {
        let tables = try await fetchTables(schema: schema)
        var result: [String: [PluginForeignKeyInfo]] = [:]
        for table in tables {
            let fks = try await fetchForeignKeys(table: table.name, schema: schema)
            if !fks.isEmpty { result[table.name] = fks }
        }
        return result
    }

    func fetchAllDatabaseMetadata() async throws -> [PluginDatabaseMetadata] {
        let dbs = try await fetchDatabases()
        var result: [PluginDatabaseMetadata] = []
        for db in dbs {
            do {
                result.append(try await fetchDatabaseMetadata(db))
            } catch {
                result.append(PluginDatabaseMetadata(name: db))
            }
        }
        return result
    }

    func fetchDependentTypes(table: String, schema: String?) async throws -> [(name: String, labels: [String])] { [] }
    func fetchDependentSequences(table: String, schema: String?) async throws -> [(name: String, ddl: String)] { [] }

    func createDatabase(name: String, charset: String, collation: String?) async throws {
        throw NSError(domain: "PluginDatabaseDriver", code: -1, userInfo: [NSLocalizedDescriptionKey: "createDatabase not supported"])
    }

    func switchDatabase(to database: String) async throws {
        throw NSError(
            domain: "TableProPluginKit",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "This driver does not support database switching"]
        )
    }

    func executeParameterized(query: String, parameters: [String?]) async throws -> PluginQueryResult {
        var sql = ""
        var paramIndex = 0
        var inSingleQuote = false
        var inDoubleQuote = false
        var isEscaped = false

        for char in query {
            if isEscaped {
                isEscaped = false
                sql.append(char)
                continue
            }

            if char == "\\" && (inSingleQuote || inDoubleQuote) {
                isEscaped = true
                sql.append(char)
                continue
            }

            if char == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
            } else if char == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
            }

            if char == "?" && !inSingleQuote && !inDoubleQuote && paramIndex < parameters.count {
                if let value = parameters[paramIndex] {
                    let escaped = value
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "'", with: "''")
                    sql.append("'\(escaped)'")
                } else {
                    sql.append("NULL")
                }
                paramIndex += 1
            } else {
                sql.append(char)
            }
        }

        return try await execute(query: sql)
    }

    func fetchRowCount(query: String) async throws -> Int {
        let result = try await execute(query: "SELECT COUNT(*) FROM (\(query)) _t")
        guard let firstRow = result.rows.first, let value = firstRow.first, let countStr = value else {
            return 0
        }
        return Int(countStr) ?? 0
    }

    func fetchRows(query: String, offset: Int, limit: Int) async throws -> PluginQueryResult {
        try await execute(query: "\(query) LIMIT \(limit) OFFSET \(offset)")
    }
}
