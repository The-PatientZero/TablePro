//
//  QueryExecutionService.swift
//  TablePro
//
//  Service responsible for query execution, parsing, and SQL statement extraction.
//  Extracted from MainContentView for better separation of concerns.
//

import Combine
import Foundation

/// Service for executing database queries and parsing SQL
@MainActor
final class QueryExecutionService: ObservableObject {
    // MARK: - Published State

    @Published var isExecuting: Bool = false
    @Published var executionTime: TimeInterval?
    @Published var errorMessage: String?

    // MARK: - Private State

    private var currentTask: Task<Void, Never>?
    private var queryGeneration: Int = 0

    // MARK: - Query Execution

    /// Execute a query and return results via callbacks
    /// - Parameters:
    ///   - sql: The SQL query to execute
    ///   - connection: Database connection configuration
    ///   - tableName: Optional table name for editable queries
    ///   - onSuccess: Callback with query result
    ///   - onError: Callback with error
    func execute(
        sql: String,
        connection: DatabaseConnection,
        tableName: String?,
        onSuccess: @escaping (QueryExecutionResult) async -> Void,
        onError: @escaping (Error) async -> Void
    ) {
        // Don't execute empty queries
        guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isExecuting = false
            return
        }

        // Cancel any previous running query
        currentTask?.cancel()

        // Increment generation for race condition prevention
        queryGeneration += 1
        let capturedGeneration = queryGeneration

        isExecuting = true
        executionTime = nil
        errorMessage = nil

        let isEditable = tableName != nil

        currentTask = Task {
            do {
                let result = try await DatabaseManager.shared.execute(query: sql)

                // Fetch column defaults and total row count if editable table
                var columnDefaults: [String: String?] = [:]
                var totalRowCount: Int?

                if isEditable, let tableName = tableName {
                    if let driver = DatabaseManager.shared.activeDriver {
                        // Execute both queries in parallel for better performance
                        async let columnInfoTask = driver.fetchColumns(table: tableName)
                        let quotedTable = connection.type.quoteIdentifier(tableName)
                        async let countTask: QueryResult = try await DatabaseManager.shared.execute(query: "SELECT COUNT(*) FROM \(quotedTable)")

                        let (columnInfo, countResult) = try await (columnInfoTask, countTask)

                        for col in columnInfo {
                            columnDefaults[col.name] = col.defaultValue
                        }

                        if let firstRow = countResult.rows.first,
                           let countStr = firstRow.first as? String,
                           let count = Int(countStr) {
                            totalRowCount = count
                        }
                    }
                }

                // No need for deep copy - database drivers already return Swift-owned strings
                // MariaDBConnection performs deep copying at the C library level (see lines 461-475)
                // PostgreSQL and SQLite also return properly owned String objects
                let rows = result.rows.map { QueryResultRow(values: $0) }

                let executionResult = QueryExecutionResult(
                    columns: result.columns,
                    rows: rows,
                    executionTime: result.executionTime,
                    columnDefaults: columnDefaults,
                    totalRowCount: totalRowCount,
                    tableName: tableName,
                    isEditable: isEditable
                )

                // Check for cancellation
                guard !Task.isCancelled else {
                    await MainActor.run {
                        isExecuting = false
                        executionTime = executionResult.executionTime
                    }
                    return
                }

                // Check generation for race conditions
                guard capturedGeneration == queryGeneration else {
                    return
                }

                await MainActor.run {
                    isExecuting = false
                    executionTime = executionResult.executionTime
                }

                await onSuccess(executionResult)
            } catch {
                guard capturedGeneration == queryGeneration else { return }

                await MainActor.run {
                    isExecuting = false
                    errorMessage = error.localizedDescription
                }

                await onError(error)
            }
        }
    }

    /// Cancel any running query
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isExecuting = false
    }

    // MARK: - SQL Parsing

    /// Extract the SQL statement at the cursor position (semicolon-delimited)
    /// Enables TablePlus-like behavior: execute only the current query
    func extractQueryAtCursor(from fullQuery: String, at position: Int) -> String {
        let nsQuery = fullQuery as NSString
        let length = nsQuery.length
        guard length > 0 else { return "" }

        // Fast check: if no semicolons, return the full query trimmed.
        // Uses NSString range search (C-level speed) instead of Swift String.contains.
        guard nsQuery.range(of: ";").location != NSNotFound else {
            return fullQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let singleQuote = UInt16(UnicodeScalar("'").value)
        let doubleQuote = UInt16(UnicodeScalar("\"").value)
        let semicolonChar = UInt16(UnicodeScalar(";").value)

        let safePosition = min(max(0, position), length)
        var currentStart = 0
        var inString = false
        var stringCharVal: UInt16 = 0

        // Scan through characters, stopping as soon as we find the statement
        // containing the cursor. Avoids scanning the entire file.
        for i in 0..<length {
            let ch = nsQuery.character(at: i)

            // Track string literals to avoid splitting on semicolons inside strings
            if ch == singleQuote || ch == doubleQuote {
                if !inString {
                    inString = true
                    stringCharVal = ch
                } else if ch == stringCharVal {
                    inString = false
                }
            }

            // Found a statement delimiter
            if ch == semicolonChar && !inString {
                let stmtEnd = i + 1
                // Check if cursor is within this statement
                if safePosition >= currentStart && safePosition <= stmtEnd {
                    let stmtRange = NSRange(location: currentStart, length: i - currentStart)
                    return nsQuery.substring(with: stmtRange)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                currentStart = stmtEnd
            }
        }

        // Cursor is in the last statement (no trailing semicolon)
        if currentStart < length {
            let stmtRange = NSRange(location: currentStart, length: length - currentStart)
            return nsQuery.substring(with: stmtRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return fullQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract table name from a simple SELECT query
    func extractTableName(from sql: String) -> String? {
        let pattern = #"(?i)^\s*SELECT\s+.+?\s+FROM\s+[`"]?(\w+)[`"]?\s*(?:WHERE|ORDER|LIMIT|GROUP|HAVING|$|;)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: sql, options: [], range: NSRange(sql.startIndex..., in: sql)),
              let range = Range(match.range(at: 1), in: sql)
        else {
            return nil
        }

        return String(sql[range])
    }
}

// MARK: - Query Execution Result

/// Result of a query execution with all necessary data
struct QueryExecutionResult {
    let columns: [String]
    let rows: [QueryResultRow]
    let executionTime: TimeInterval
    let columnDefaults: [String: String?]
    let totalRowCount: Int?
    let tableName: String?
    let isEditable: Bool
}
