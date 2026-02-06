//
//  TableRowViewWithMenu.swift
//  TablePro
//
//  Custom row view with context menu support.
//  Extracted from DataGridView for better maintainability.
//

import AppKit

/// Custom row view that provides context menu for row operations
final class TableRowViewWithMenu: NSTableRowView {
    weak var coordinator: TableViewCoordinator?
    var rowIndex: Int = 0

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let coordinator = coordinator,
              let tableView = coordinator.tableView else { return nil }

        // Determine which column was clicked
        let locationInRow = convert(event.locationInWindow, from: nil)
        let locationInTable = tableView.convert(locationInRow, from: self)
        let clickedColumn = tableView.column(at: locationInTable)

        // Adjust for row number column (index 0)
        let dataColumnIndex = clickedColumn > 0 ? clickedColumn - 1 : -1

        let menu = NSMenu()

        if coordinator.changeManager.isRowDeleted(rowIndex) {
            menu.addItem(
                withTitle: "Undo Delete", action: #selector(undoDeleteRow), keyEquivalent: ""
            ).target = self
        }

        // Normal row menu (or additional items for inserted rows)
        if !coordinator.changeManager.isRowDeleted(rowIndex) {
            // Edit actions (if editable)
            if coordinator.isEditable && dataColumnIndex >= 0 {
                let setValueMenu = NSMenu()

                let emptyItem = NSMenuItem(
                    title: "Empty", action: #selector(setEmptyValue(_:)), keyEquivalent: "")
                emptyItem.representedObject = dataColumnIndex
                emptyItem.target = self
                setValueMenu.addItem(emptyItem)

                let nullItem = NSMenuItem(
                    title: "NULL", action: #selector(setNullValue(_:)), keyEquivalent: "")
                nullItem.representedObject = dataColumnIndex
                nullItem.target = self
                setValueMenu.addItem(nullItem)

                let defaultItem = NSMenuItem(
                    title: "Default", action: #selector(setDefaultValue(_:)), keyEquivalent: "")
                defaultItem.representedObject = dataColumnIndex
                defaultItem.target = self
                setValueMenu.addItem(defaultItem)

                let setValueItem = NSMenuItem(title: "Set Value", action: nil, keyEquivalent: "")
                setValueItem.submenu = setValueMenu
                menu.addItem(setValueItem)

                menu.addItem(NSMenuItem.separator())
            }

            // Copy actions
            if dataColumnIndex >= 0 {
                let copyCellItem = NSMenuItem(
                    title: "Copy Cell Value", action: #selector(copyCellValue(_:)),
                    keyEquivalent: "")
                copyCellItem.representedObject = dataColumnIndex
                copyCellItem.target = self
                menu.addItem(copyCellItem)
            }

            let copyItem = NSMenuItem(
                title: "Copy", action: #selector(copySelectedOrCurrentRow), keyEquivalent: "c")
            copyItem.keyEquivalentModifierMask = .command
            copyItem.target = self
            menu.addItem(copyItem)

            let pasteItem = NSMenuItem(
                title: "Paste", action: #selector(pasteRows), keyEquivalent: "v")
            pasteItem.keyEquivalentModifierMask = .command
            pasteItem.target = self
            menu.addItem(pasteItem)

            if coordinator.isEditable {
                menu.addItem(NSMenuItem.separator())

                let duplicateItem = NSMenuItem(
                    title: "Duplicate", action: #selector(duplicateRow), keyEquivalent: "d")
                duplicateItem.keyEquivalentModifierMask = .command
                duplicateItem.target = self
                menu.addItem(duplicateItem)

                let deleteItem = NSMenuItem(
                    title: "Delete",
                    action: #selector(deleteRow),
                    keyEquivalent: String(UnicodeScalar(NSBackspaceCharacter).map { Character($0) } ?? "\u{8}")
                )
                deleteItem.keyEquivalentModifierMask = []
                deleteItem.target = self
                menu.addItem(deleteItem)
            }
        }

        return menu
    }

    @objc private func deleteRow() {
        NotificationCenter.default.post(name: .deleteSelectedRows, object: nil)
    }

    @objc private func duplicateRow() {
        NotificationCenter.default.post(name: .duplicateRow, object: nil)
    }

    @objc private func undoDeleteRow() {
        coordinator?.undoDeleteRow(at: rowIndex)
    }

    @objc private func undoInsertRow() {
        coordinator?.undoInsertRow(at: rowIndex)
    }

    @objc private func copyRow() {
        coordinator?.copyRows(at: [rowIndex])
    }

    @objc private func copySelectedRows() {
        guard let selectedIndices = coordinator?.selectedRowIndices else { return }
        coordinator?.copyRows(at: selectedIndices)
    }

    @objc private func copySelectedOrCurrentRow() {
        guard let coordinator = coordinator else { return }
        let indices: Set<Int> = !coordinator.selectedRowIndices.isEmpty
            ? coordinator.selectedRowIndices
            : [rowIndex]
        if let callback = coordinator.onCopyRows {
            callback(indices)
        } else {
            coordinator.copyRows(at: indices)
        }
    }

    @objc private func pasteRows() {
        NotificationCenter.default.post(name: .pasteRows, object: nil)
    }

    @objc private func copyCellValue(_ sender: NSMenuItem) {
        guard let columnIndex = sender.representedObject as? Int else { return }
        coordinator?.copyCellValue(at: rowIndex, columnIndex: columnIndex)
    }

    @objc private func setNullValue(_ sender: NSMenuItem) {
        guard let columnIndex = sender.representedObject as? Int else { return }
        coordinator?.setCellValueAtColumn(nil, at: rowIndex, columnIndex: columnIndex)
    }

    @objc private func setEmptyValue(_ sender: NSMenuItem) {
        guard let columnIndex = sender.representedObject as? Int else { return }
        coordinator?.setCellValueAtColumn("", at: rowIndex, columnIndex: columnIndex)
    }

    @objc private func setDefaultValue(_ sender: NSMenuItem) {
        guard let columnIndex = sender.representedObject as? Int else { return }
        coordinator?.setCellValueAtColumn("__DEFAULT__", at: rowIndex, columnIndex: columnIndex)
    }
}
