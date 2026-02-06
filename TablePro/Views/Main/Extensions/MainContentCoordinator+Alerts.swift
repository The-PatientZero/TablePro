//
//  MainContentCoordinator+Alerts.swift
//  TablePro
//
//  Alert handling methods for MainContentCoordinator
//  Centralizes all NSAlert logic for main content operations
//

import AppKit
import Foundation

extension MainContentCoordinator {
    // MARK: - Dangerous Query Confirmation

    /// Check if query needs confirmation and show alert if needed
    /// - Parameter sql: SQL query to check
    /// - Returns: true if safe to execute, false if user cancelled
    func confirmDangerousQueryIfNeeded(_ sql: String) async -> Bool {
        guard isDangerousQuery(sql) else { return true }

        let message = dangerousQueryMessage(for: sql)
        return await AlertHelper.confirmCritical(
            title: "Potentially Dangerous Query",
            message: message,
            confirmButton: "Execute",
            cancelButton: "Cancel"
        )
    }

    /// Generate appropriate message for dangerous query type
    private func dangerousQueryMessage(for sql: String) -> String {
        let uppercased = sql.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if uppercased.hasPrefix("DROP ") {
            return "This DROP query will permanently remove database objects. This action cannot be undone."
        } else if uppercased.hasPrefix("TRUNCATE ") {
            return "This TRUNCATE query will permanently delete all rows in the table. This action cannot be undone."
        } else if uppercased.hasPrefix("DELETE ") {
            return "This DELETE query has no WHERE clause and will delete ALL rows in the table. This action cannot be undone."
        }

        return "This query may permanently modify or delete data."
    }

    // MARK: - Discard Changes Confirmation

    /// Confirm discarding unsaved changes
    /// - Parameter action: The action that requires discarding changes
    /// - Returns: true if user confirmed, false if cancelled
    func confirmDiscardChanges(action: DiscardAction) async -> Bool {
        let message = discardMessage(for: action)
        return await AlertHelper.confirmDestructive(
            title: "Discard Unsaved Changes?",
            message: message,
            confirmButton: "Discard",
            cancelButton: "Cancel"
        )
    }

    /// Generate appropriate message for discard action type
    private func discardMessage(for action: DiscardAction) -> String {
        switch action {
        case .refresh, .refreshAll:
            return "Refreshing will discard all unsaved changes."
        case .closeTab:
            return "Closing this tab will discard all unsaved changes."
        }
    }

    // MARK: - Error Alerts

    /// Show query execution error as a sheet
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - window: Parent window (optional)
    func showQueryError(_ error: Error, window: NSWindow?) {
        AlertHelper.showErrorSheet(
            title: "Query Execution Failed",
            message: error.localizedDescription,
            window: window
        )
    }

    /// Show save changes error as a sheet
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - window: Parent window (optional)
    func showSaveError(_ error: Error, window: NSWindow?) {
        AlertHelper.showErrorSheet(
            title: "Failed to Save Changes",
            message: error.localizedDescription,
            window: window
        )
    }
}
