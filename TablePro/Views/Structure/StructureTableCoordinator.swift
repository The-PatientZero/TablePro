//
//  StructureTableCoordinator.swift
//  TablePro
//
//  Coordinator for structure grid - adapts DataGridView for schema editing
//  Converts entity-based data (columns/indexes/FKs) to row-based format for grid
//

import AppKit
import Foundation

/// Coordinator for structure table editing
final class StructureTableCoordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSTextFieldDelegate {
    // MARK: - Properties

    var structureChangeManager: StructureChangeManager
    var currentTab: StructureTab
    var isEditable: Bool = true

    weak var tableView: NSTableView?
    var onDeleteRows: ((Set<Int>) -> Void)?
    var onAddRow: (() -> Void)?

    private var cachedRowCount: Int = 0
    private var cachedColumnCount: Int = 0
    private var visualStateCache: [Int: RowVisualState] = [:]

    // MARK: - Initialization

    init(changeManager: StructureChangeManager, tab: StructureTab) {
        self.structureChangeManager = changeManager
        self.currentTab = tab
        super.init()
    }

    // MARK: - Data Conversion

    /// Convert columns to row-based format
    private func columnsAsRows() -> [[String?]] {
        structureChangeManager.workingColumns.map { column in
            [
                column.name,
                column.dataType,
                column.isNullable ? "YES" : "NO",
                column.defaultValue ?? "",
                column.autoIncrement ? "YES" : "NO",
                column.comment ?? ""
            ]
        }
    }

    /// Convert indexes to row-based format
    private func indexesAsRows() -> [[String?]] {
        structureChangeManager.workingIndexes.map { index in
            [
                index.name,
                index.columns.joined(separator: ", "),
                index.type.rawValue,
                index.isUnique ? "YES" : "NO"
            ]
        }
    }

    /// Convert foreign keys to row-based format
    private func foreignKeysAsRows() -> [[String?]] {
        structureChangeManager.workingForeignKeys.map { fk in
            [
                fk.name,
                fk.columns.joined(separator: ", "),
                fk.referencedTable,
                fk.referencedColumns.joined(separator: ", "),
                fk.onDelete.rawValue,
                fk.onUpdate.rawValue
            ]
        }
    }

    /// Get column names for current tab
    private func columnNames() -> [String] {
        switch currentTab {
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

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        switch currentTab {
        case .columns:
            return structureChangeManager.workingColumns.count
        case .indexes:
            return structureChangeManager.workingIndexes.count
        case .foreignKeys:
            return structureChangeManager.workingForeignKeys.count
        case .ddl:
            return 0
        }
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let rows: [[String?]]

        switch currentTab {
        case .columns:
            rows = columnsAsRows()
        case .indexes:
            rows = indexesAsRows()
        case .foreignKeys:
            rows = foreignKeysAsRows()
        case .ddl:
            return nil
        }

        guard row < rows.count else { return nil }

        // Extract column index from identifier (format: "col_0", "col_1", etc.)
        guard let identifier = tableColumn?.identifier.rawValue,
              identifier.starts(with: "col_"),
              let colIndex = Int(identifier.dropFirst(4)) else {
            return nil
        }

        guard colIndex < rows[row].count else { return nil }
        return rows[row][colIndex]
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        guard isEditable else { return false }

        // Don't allow editing row number column
        guard tableColumn?.identifier.rawValue != "__rowNumber__" else {
            return false
        }

        return true
    }

    // MARK: - NSTextFieldDelegate

    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        guard let tableView = tableView else { return true }

        let row = tableView.row(for: control)
        let column = tableView.column(for: control)

        guard row >= 0, column >= 0 else { return true }

        let newValue = fieldEditor.string

        // Update the appropriate entity based on tab and column
        updateEntity(row: row, column: column, value: newValue)

        return true
    }

    // MARK: - Entity Updates

    private func updateEntity(row: Int, column: Int, value: String) {
        // Extract column index (accounting for row number column)
        let dataColumnIndex = column - 1
        guard dataColumnIndex >= 0 else { return }

        switch currentTab {
        case .columns:
            updateColumn(row: row, columnIndex: dataColumnIndex, value: value)
        case .indexes:
            updateIndex(row: row, columnIndex: dataColumnIndex, value: value)
        case .foreignKeys:
            updateForeignKey(row: row, columnIndex: dataColumnIndex, value: value)
        case .ddl:
            break
        }
    }

    private func updateColumn(row: Int, columnIndex: Int, value: String) {
        guard row < structureChangeManager.workingColumns.count else { return }
        var column = structureChangeManager.workingColumns[row]

        switch columnIndex {
        case 0: // Name
            column.name = value
        case 1: // Type
            column.dataType = value
        case 2: // Nullable
            column.isNullable = value.uppercased() == "YES" || value == "1"
        case 3: // Default
            column.defaultValue = value.isEmpty ? nil : value
        case 4: // Auto Inc
            column.autoIncrement = value.uppercased() == "YES" || value == "1"
        case 5: // Comment
            column.comment = value.isEmpty ? nil : value
        default:
            break
        }

        structureChangeManager.updateColumn(id: column.id, with: column)
    }

    private func updateIndex(row: Int, columnIndex: Int, value: String) {
        guard row < structureChangeManager.workingIndexes.count else { return }
        var index = structureChangeManager.workingIndexes[row]

        switch columnIndex {
        case 0: // Name
            index.name = value
        case 1: // Columns (comma-separated)
            index.columns = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        case 2: // Type
            if let indexType = EditableIndexDefinition.IndexType(rawValue: value.uppercased()) {
                index.type = indexType
            }
        case 3: // Unique
            index.isUnique = value.uppercased() == "YES" || value == "1"
        default:
            break
        }

        structureChangeManager.updateIndex(id: index.id, with: index)
    }

    private func updateForeignKey(row: Int, columnIndex: Int, value: String) {
        guard row < structureChangeManager.workingForeignKeys.count else { return }
        var fk = structureChangeManager.workingForeignKeys[row]

        switch columnIndex {
        case 0: // Name
            fk.name = value
        case 1: // Columns (comma-separated)
            fk.columns = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        case 2: // Ref Table
            fk.referencedTable = value
        case 3: // Ref Columns (comma-separated)
            fk.referencedColumns = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        case 4: // On Delete
            if let action = EditableForeignKeyDefinition.ReferentialAction(rawValue: value.uppercased()) {
                fk.onDelete = action
            }
        case 5: // On Update
            if let action = EditableForeignKeyDefinition.ReferentialAction(rawValue: value.uppercased()) {
                fk.onUpdate = action
            }
        default:
            break
        }

        structureChangeManager.updateForeignKey(id: fk.id, with: fk)
    }

    // MARK: - Visual State

    func rebuildVisualStateCache() {
        structureChangeManager.rebuildVisualStateCache()
    }

    func getVisualState(for row: Int) -> RowVisualState {
        structureChangeManager.getVisualState(for: row, tab: currentTab)
    }

    // MARK: - Cache Management

    func updateCache() {
        cachedRowCount = numberOfRows(in: tableView ?? NSTableView())
        cachedColumnCount = columnNames().count
    }
}
