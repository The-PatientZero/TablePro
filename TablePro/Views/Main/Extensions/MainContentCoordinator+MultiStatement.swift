//
//  MainContentCoordinator+MultiStatement.swift
//  TablePro
//
//  Multi-statement SQL execution support for MainContentCoordinator.
//  Splits SQL text on semicolons (respecting strings/comments) and
//  executes each statement sequentially, stopping on first error.
//

import AppKit
import Foundation

extension MainContentCoordinator {
    // MARK: - Statement Splitting

    /// Split SQL text into individual statements, respecting strings, comments, and backticks.
    /// Uses the same parsing logic as `extractQueryAtCursor` but collects all statements.
    func splitStatements(from sql: String) -> [String] {
        let nsQuery = sql as NSString
        let length = nsQuery.length
        guard length > 0 else { return [] }

        // Fast check: if no semicolons, return the full query trimmed
        guard nsQuery.range(of: ";").location != NSNotFound else {
            let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }

        let singleQuote = UInt16(UnicodeScalar("'").value)
        let doubleQuote = UInt16(UnicodeScalar("\"").value)
        let backtick = UInt16(UnicodeScalar("`").value)
        let semicolonChar = UInt16(UnicodeScalar(";").value)
        let dash = UInt16(UnicodeScalar("-").value)
        let slash = UInt16(UnicodeScalar("/").value)
        let star = UInt16(UnicodeScalar("*").value)
        let newline = UInt16(UnicodeScalar("\n").value)
        let backslash = UInt16(UnicodeScalar("\\").value)

        var statements: [String] = []
        var currentStart = 0
        var inString = false
        var stringCharVal: UInt16 = 0
        var inLineComment = false
        var inBlockComment = false
        var i = 0

        while i < length {
            let ch = nsQuery.character(at: i)

            if inLineComment {
                if ch == newline { inLineComment = false }
                i += 1
                continue
            }

            if inBlockComment {
                if ch == star && i + 1 < length && nsQuery.character(at: i + 1) == slash {
                    inBlockComment = false
                    i += 2
                    continue
                }
                i += 1
                continue
            }

            if !inString && ch == dash && i + 1 < length && nsQuery.character(at: i + 1) == dash {
                inLineComment = true
                i += 2
                continue
            }

            if !inString && ch == slash && i + 1 < length && nsQuery.character(at: i + 1) == star {
                inBlockComment = true
                i += 2
                continue
            }

            // Handle backslash escapes inside strings (e.g., \' \" \\)
            if inString && ch == backslash && i + 1 < length {
                i += 2 // Skip the backslash and the escaped character
                continue
            }

            if ch == singleQuote || ch == doubleQuote || ch == backtick {
                if !inString {
                    inString = true
                    stringCharVal = ch
                } else if ch == stringCharVal {
                    // Handle doubled (escaped) quotes: '' "" ``
                    if i + 1 < length && nsQuery.character(at: i + 1) == stringCharVal {
                        i += 1 // Skip the escaped quote
                    } else {
                        inString = false
                    }
                }
            }

            if ch == semicolonChar && !inString {
                let stmtRange = NSRange(location: currentStart, length: i - currentStart)
                let stmt = nsQuery.substring(with: stmtRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !stmt.isEmpty {
                    statements.append(stmt)
                }
                currentStart = i + 1
            }

            i += 1
        }

        // Last statement (no trailing semicolon)
        if currentStart < length {
            let stmtRange = NSRange(location: currentStart, length: length - currentStart)
            let stmt = nsQuery.substring(with: stmtRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stmt.isEmpty {
                statements.append(stmt)
            }
        }

        return statements
    }

    // MARK: - Multi-Statement Execution

    /// Execute multiple SQL statements sequentially within a transaction,
    /// stopping on first error with automatic rollback.
    /// Displays results from the last SELECT statement (if any).
    func executeMultipleStatements(_ statements: [String]) {
        guard let index = tabManager.selectedTabIndex else { return }
        guard !tabManager.tabs[index].isExecuting else { return }

        currentQueryTask?.cancel()
        queryGeneration += 1
        let capturedGeneration = queryGeneration

        var tab = tabManager.tabs[index]
        tab.isExecuting = true
        tab.executionTime = nil
        tab.errorMessage = nil
        tabManager.tabs[index] = tab
        toolbarState.isExecuting = true

        let conn = connection
        let tabId = tabManager.tabs[index].id
        let totalCount = statements.count
        let dbType = connection.type

        currentQueryTask = Task {
            var cumulativeTime: TimeInterval = 0
            var lastSelectResult: QueryResult?
            var lastSelectSQL: String?
            var totalRowsAffected = 0
            var executedCount = 0
            var failedSQL: String?

            do {
                guard let driver = DatabaseManager.shared.activeDriver else {
                    throw DatabaseError.notConnected
                }

                // Wrap in a transaction for atomicity
                let beginSQL: String
                switch dbType {
                case .mysql, .mariadb:
                    beginSQL = "START TRANSACTION"
                default:
                    beginSQL = "BEGIN"
                }
                _ = try await driver.execute(query: beginSQL)

                for (stmtIndex, sql) in statements.enumerated() {
                    guard !Task.isCancelled else { break }
                    guard capturedGeneration == queryGeneration else {
                        _ = try? await driver.execute(query: "ROLLBACK")
                        return
                    }

                    failedSQL = sql
                    let result = try await driver.execute(query: sql)
                    failedSQL = nil
                    executedCount = stmtIndex + 1
                    cumulativeTime += result.executionTime
                    totalRowsAffected += result.rowsAffected

                    // Keep the last result that has columns (i.e. a SELECT)
                    if !result.columns.isEmpty {
                        lastSelectResult = result
                        lastSelectSQL = sql
                    }

                    // Record each statement individually in query history
                    await MainActor.run {
                        QueryHistoryManager.shared.recordQuery(
                            query: sql,
                            connectionId: conn.id,
                            databaseName: conn.database,
                            executionTime: result.executionTime,
                            rowCount: result.rows.count,
                            wasSuccessful: true,
                            errorMessage: nil
                        )
                    }
                }

                // Commit the transaction
                _ = try await driver.execute(query: "COMMIT")

                // All statements succeeded — update tab with results
                await MainActor.run {
                    currentQueryTask = nil
                    toolbarState.isExecuting = false
                    toolbarState.lastQueryDuration = cumulativeTime

                    guard capturedGeneration == queryGeneration else { return }
                    guard let idx = tabManager.tabs.firstIndex(where: { $0.id == tabId }) else {
                        return
                    }

                    var updatedTab = tabManager.tabs[idx]

                    if let selectResult = lastSelectResult {
                        // Deep copy to prevent C buffer retention issues
                        let safeColumns = selectResult.columns.map { String($0) }
                        let safeColumnTypes = selectResult.columnTypes
                        let safeRows = selectResult.rows.map { row in
                            QueryResultRow(values: row.map { $0.map { String($0) } })
                        }
                        let tableName = lastSelectSQL.flatMap {
                            extractTableName(from: $0)
                        }

                        updatedTab.resultColumns = safeColumns
                        updatedTab.columnTypes = safeColumnTypes
                        updatedTab.resultRows = safeRows
                        updatedTab.tableName = tableName
                        updatedTab.isEditable = tableName != nil && updatedTab.isEditable
                    } else {
                        // No SELECT results — clear grid, show rowsAffected summary
                        updatedTab.resultColumns = []
                        updatedTab.columnTypes = []
                        updatedTab.resultRows = []
                        updatedTab.tableName = nil
                        updatedTab.isEditable = false
                    }

                    updatedTab.resultVersion += 1
                    updatedTab.executionTime = cumulativeTime
                    updatedTab.rowsAffected = totalRowsAffected
                    updatedTab.isExecuting = false
                    updatedTab.lastExecutedAt = Date()
                    updatedTab.errorMessage = nil
                    tabManager.tabs[idx] = updatedTab

                    changeManager.clearChanges()
                    changeManager.reloadVersion += 1
                }
            } catch {
                // Rollback on failure
                if let driver = DatabaseManager.shared.activeDriver {
                    _ = try? await driver.execute(query: "ROLLBACK")
                }

                guard capturedGeneration == queryGeneration else { return }

                let failedStmtIndex = executedCount + 1
                let contextMsg = "Statement \(failedStmtIndex)/\(totalCount) failed: "
                    + error.localizedDescription

                await MainActor.run {
                    currentQueryTask = nil
                    toolbarState.isExecuting = false

                    if let idx = tabManager.tabs.firstIndex(where: { $0.id == tabId }) {
                        var errTab = tabManager.tabs[idx]
                        errTab.errorMessage = contextMsg
                        errTab.isExecuting = false
                        errTab.executionTime = cumulativeTime
                        tabManager.tabs[idx] = errTab
                    }

                    // Record only the failing statement in history
                    let recordSQL = failedSQL ?? statements[min(executedCount, totalCount - 1)]
                    QueryHistoryManager.shared.recordQuery(
                        query: recordSQL,
                        connectionId: conn.id,
                        databaseName: conn.database,
                        executionTime: cumulativeTime,
                        rowCount: 0,
                        wasSuccessful: false,
                        errorMessage: error.localizedDescription
                    )

                    AlertHelper.showErrorSheet(
                        title: String(localized: "Query Execution Failed"),
                        message: contextMsg,
                        window: NSApp.keyWindow
                    )
                }
            }
        }
    }
}
