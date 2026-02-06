//
//  StructureRowProvider.swift
//  TablePro
//
//  Adapts structure entities (columns/indexes/FKs) to InMemoryRowProvider interface
//  Converts entity-based data to row-based format for DataGridView
//

import Foundation

/// Provides structure entities as rows for DataGridView
final class StructureRowProvider {
    private let changeManager: StructureChangeManager
    private let tab: StructureTab

    // Computed properties that match InMemoryRowProvider interface
    var rows: [QueryResultRow] {
        switch tab {
        case .columns:
            return changeManager.workingColumns.map { column in
                QueryResultRow(values: [
                    column.name,
                    column.dataType,
                    column.isNullable ? "YES" : "NO",
                    column.defaultValue ?? "",
                    column.autoIncrement ? "YES" : "NO",
                    column.comment ?? ""
                ])
            }
        case .indexes:
            return changeManager.workingIndexes.map { index in
                QueryResultRow(values: [
                    index.name,
                    index.columns.joined(separator: ", "),
                    index.type.rawValue,
                    index.isUnique ? "YES" : "NO"
                ])
            }
        case .foreignKeys:
            return changeManager.workingForeignKeys.map { fk in
                QueryResultRow(values: [
                    fk.name,
                    fk.columns.joined(separator: ", "),
                    fk.referencedTable,
                    fk.referencedColumns.joined(separator: ", "),
                    fk.onDelete.rawValue,
                    fk.onUpdate.rawValue
                ])
            }
        case .ddl:
            return []
        }
    }

    var columns: [String] {
        switch tab {
        case .columns:
            return ["Name", "Type", "Nullable", "Default", "Auto Inc", "Comment"]
        case .indexes:
            return ["Name", "Columns", "Type", "Unique"]
        case .foreignKeys:
            return ["Name", "Columns", "Ref Table", "Ref Columns", "On Delete", "On Update"]
        case .ddl:
            return []
        }
    }

    var columnTypes: [ColumnType] {
        // All columns are text for structure editing
        Array(repeating: .text(rawType: nil), count: columns.count)
    }

    /// Column indices that should use YES/NO dropdowns instead of text fields
    var dropdownColumns: Set<Int> {
        switch tab {
        case .columns:
            return [2, 4] // Nullable (index 2), Auto Inc (index 4)
        case .indexes:
            return [3] // Unique (index 3)
        case .foreignKeys:
            return [] // On Delete/Update use text for now (could add dropdown for CASCADE/SET NULL/etc later)
        case .ddl:
            return []
        }
    }

    var totalRowCount: Int {
        rows.count
    }

    init(changeManager: StructureChangeManager, tab: StructureTab) {
        self.changeManager = changeManager
        self.tab = tab
    }

    // MARK: - InMemoryRowProvider-compatible methods

    func row(at index: Int) -> QueryResultRow? {
        guard index < rows.count else { return nil }
        return rows[index]
    }

    func updateValue(_ newValue: String?, at rowIndex: Int, columnIndex: Int) {
        // Updates are handled by StructureTableCoordinator
        // This method is called by DataGridView but we intercept edits earlier
    }

    func appendRow(_ row: [String?]) {
        // Handled by changeManager.addNewColumn/Index/ForeignKey
    }

    func removeRow(at index: Int) {
        // Handled by changeManager.deleteColumn/Index/ForeignKey
    }
}

// MARK: - Helper to create InMemoryRowProvider

extension StructureRowProvider {
    /// Creates an InMemoryRowProvider from structure data
    func asInMemoryProvider() -> InMemoryRowProvider {
        InMemoryRowProvider(
            rows: rows,
            columns: columns,
            columnTypes: columnTypes
        )
    }
}
