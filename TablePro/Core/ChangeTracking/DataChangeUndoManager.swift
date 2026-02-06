//
//  DataChangeUndoManager.swift
//  TablePro
//
//  Manages undo/redo stacks for data changes.
//  Extracted from DataChangeManager to improve separation of concerns.
//

import Foundation

/// Manages undo/redo stacks for data changes
final class DataChangeUndoManager {
    /// Undo stack for reversing changes (LIFO)
    private var undoStack: [UndoAction] = []

    /// Redo stack for re-applying undone changes (LIFO)
    private var redoStack: [UndoAction] = []

    // MARK: - Public API

    /// Check if there are any undo actions available
    var canUndo: Bool {
        !undoStack.isEmpty
    }

    /// Check if there are any redo actions available
    var canRedo: Bool {
        !redoStack.isEmpty
    }

    /// Push an undo action onto the stack
    /// Clears the redo stack since new changes invalidate redo history
    func push(_ action: UndoAction) {
        undoStack.append(action)
        // Don't clear redo here - let caller decide when to clear
    }

    /// Pop the last undo action from the stack
    func popUndo() -> UndoAction? {
        undoStack.popLast()
    }

    /// Pop the last redo action from the stack
    func popRedo() -> UndoAction? {
        redoStack.popLast()
    }

    /// Move an action from undo to redo stack
    func moveToRedo(_ action: UndoAction) {
        redoStack.append(action)
    }

    /// Move an action from redo to undo stack
    func moveToUndo(_ action: UndoAction) {
        undoStack.append(action)
    }

    /// Clear the undo stack
    func clearUndo() {
        undoStack.removeAll()
    }

    /// Clear the redo stack (called when new changes are made)
    func clearRedo() {
        redoStack.removeAll()
    }

    /// Clear both stacks
    func clearAll() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    /// Get the count of undo actions
    var undoCount: Int {
        undoStack.count
    }

    /// Get the count of redo actions
    var redoCount: Int {
        redoStack.count
    }
}
