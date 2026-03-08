//
//  MainContentCoordinator+Discard.swift
//  TablePro
//
//  Sidebar transaction execution and discard handling.
//

import Foundation

extension MainContentCoordinator {
    // MARK: - Table Creation

    /// Execute sidebar changes immediately (single transaction)
    func executeSidebarChanges(statements: [ParameterizedStatement]) async throws {
        guard let driver = DatabaseManager.shared.driver(for: connectionId) else {
            throw DatabaseError.notConnected
        }

        let dbType = connection.type
        let supportsTransactions = dbType != .redis && dbType != .mongodb && dbType != .clickhouse
        var allStatements: [ParameterizedStatement] = []

        if supportsTransactions {
            allStatements.append(ParameterizedStatement(sql: dbType.beginTransactionSQL, parameters: []))
        }

        allStatements.append(contentsOf: statements)

        if supportsTransactions {
            allStatements.append(ParameterizedStatement(sql: "COMMIT", parameters: []))
        }

        do {
            for stmt in allStatements {
                if stmt.parameters.isEmpty {
                    _ = try await driver.execute(query: stmt.sql)
                } else {
                    _ = try await driver.executeParameterized(query: stmt.sql, parameters: stmt.parameters)
                }
            }
        } catch {
            if supportsTransactions {
                _ = try? await driver.execute(query: "ROLLBACK")
            }
            throw error
        }
    }

    // MARK: - Discard Handling

    func handleDiscard(
        pendingTruncates: inout Set<String>,
        pendingDeletes: inout Set<String>
    ) {
        let originalValues = changeManager.getOriginalValues()
        if let index = tabManager.selectedTabIndex {
            for (rowIndex, columnIndex, originalValue) in originalValues {
                if rowIndex < tabManager.tabs[index].resultRows.count {
                    tabManager.tabs[index].resultRows[rowIndex].values[columnIndex] = originalValue
                }
            }

            let insertedIndices = changeManager.insertedRowIndices.sorted(by: >)
            for rowIndex in insertedIndices {
                if rowIndex < tabManager.tabs[index].resultRows.count {
                    tabManager.tabs[index].resultRows.remove(at: rowIndex)
                }
            }
        }

        pendingTruncates.removeAll()
        pendingDeletes.removeAll()
        changeManager.clearChanges()

        if let index = tabManager.selectedTabIndex {
            tabManager.tabs[index].pendingChanges = TabPendingChanges()
        }

        NotificationCenter.default.post(name: .databaseDidConnect, object: nil)
    }
}
