//
//  HistoryTableView.swift
//  TablePro
//
//  Custom NSTableView with keyboard handling for history panel.
//  Extracted from HistoryListViewController for better maintainability.
//

import AppKit

/// Protocol for keyboard event delegation
protocol HistoryTableViewKeyboardDelegate: AnyObject {
    func handleDeleteKey()
    func handleReturnKey()
    func handleSpaceKey()
    func deleteSelectedRow()
    func copy(_ sender: Any?)
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool

    /// Handle ESC key - clear search or selection
    /// Note: This is called from cancelOperation(_:) responder method
    func cancelOperation(_ sender: Any?)
}

/// Custom table view for keyboard delegation in history panel
final class HistoryTableView: NSTableView, NSMenuItemValidation {
    weak var keyboardDelegate: HistoryTableViewKeyboardDelegate?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // Ensure we become first responder for keyboard shortcuts
        window?.makeFirstResponder(self)
    }

    // MARK: - Standard Responder Actions

    @objc func delete(_ sender: Any?) {
        keyboardDelegate?.deleteSelectedRow()
    }

    @objc func copy(_ sender: Any?) {
        keyboardDelegate?.copy(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(delete(_:)) {
            return keyboardDelegate?.validateMenuItem(menuItem) ?? false
        }
        if menuItem.action == #selector(copy(_:)) {
            return selectedRow >= 0
        }
        return false
    }

    // MARK: - Keyboard Event Handling

    override func keyDown(with event: NSEvent) {
        guard let key = KeyCode(rawValue: event.keyCode) else {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Return/Enter key - open in new tab
        if (key == .return || key == .enter) && modifiers.isEmpty {
            if selectedRow >= 0 {
                keyboardDelegate?.handleReturnKey()
                return
            }
        }

        // Space key - toggle preview
        if key == .space && modifiers.isEmpty {
            if selectedRow >= 0 {
                keyboardDelegate?.handleSpaceKey()
                return
            }
        }

        // Escape key - delegated to cancelOperation(_:) responder method
        if key == .escape && modifiers.isEmpty {
            cancelOperation(nil)
            return
        }

        // Delete key (bare, not Cmd+Delete which goes through menu)
        if key == .delete && modifiers.isEmpty {
            if selectedRow >= 0 {
                keyboardDelegate?.handleDeleteKey()
                return
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - Standard Responder Actions

    /// Handle ESC key - delegate to owner for clear search/selection logic
    @objc override func cancelOperation(_ sender: Any?) {
        keyboardDelegate?.cancelOperation(sender)
    }
}
