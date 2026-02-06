//
//  StructureUndoManager.swift
//  TablePro
//
//  Undo/redo stack for schema changes - mirrors DataChangeUndoManager pattern
//

import Foundation

/// Represents an action that can be undone in schema editing
enum SchemaUndoAction {
    case columnEdit(id: UUID, old: EditableColumnDefinition, new: EditableColumnDefinition)
    case columnAdd(column: EditableColumnDefinition)
    case columnDelete(column: EditableColumnDefinition)
    case indexEdit(id: UUID, old: EditableIndexDefinition, new: EditableIndexDefinition)
    case indexAdd(index: EditableIndexDefinition)
    case indexDelete(index: EditableIndexDefinition)
    case foreignKeyEdit(id: UUID, old: EditableForeignKeyDefinition, new: EditableForeignKeyDefinition)
    case foreignKeyAdd(fk: EditableForeignKeyDefinition)
    case foreignKeyDelete(fk: EditableForeignKeyDefinition)
    case primaryKeyChange(old: [String], new: [String])
}

/// Manages undo/redo stack for schema changes
final class StructureUndoManager {
    private var undoStack: [SchemaUndoAction] = []
    private var redoStack: [SchemaUndoAction] = []

    private let maxStackSize = 100

    // MARK: - Public API

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    /// Push a new action onto the undo stack
    func push(_ action: SchemaUndoAction) {
        undoStack.append(action)

        // Limit stack size
        if undoStack.count > maxStackSize {
            undoStack.removeFirst()
        }

        // Clear redo stack when new action is performed
        redoStack.removeAll()
    }

    /// Pop the last action from undo stack
    func undo() -> SchemaUndoAction? {
        guard let action = undoStack.popLast() else {
            return nil
        }

        redoStack.append(action)
        return action
    }

    /// Pop the last action from redo stack
    func redo() -> SchemaUndoAction? {
        guard let action = redoStack.popLast() else {
            return nil
        }

        undoStack.append(action)
        return action
    }

    /// Clear all stacks
    func clearAll() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
