//
//  SchemaChange+Undo.swift
//  TablePro
//
//  Extension to SchemaChange for undo/redo support
//

import Foundation

extension SchemaChange {
    /// Returns the inverse of this change for undo operations
    var inverse: SchemaChange? {
        switch self {
        // Column operations
        case .addColumn(let column):
            return .deleteColumn(column)
        case .modifyColumn(let old, let new):
            return .modifyColumn(old: new, new: old)
        case .deleteColumn(let column):
            return .addColumn(column)

        // Index operations
        case .addIndex(let index):
            return .deleteIndex(index)
        case .modifyIndex(let old, let new):
            return .modifyIndex(old: new, new: old)
        case .deleteIndex(let index):
            return .addIndex(index)

        // Foreign key operations
        case .addForeignKey(let fk):
            return .deleteForeignKey(fk)
        case .modifyForeignKey(let old, let new):
            return .modifyForeignKey(old: new, new: old)
        case .deleteForeignKey(let fk):
            return .addForeignKey(fk)

        // Primary key operations
        case .modifyPrimaryKey(let old, let new):
            return .modifyPrimaryKey(old: new, new: old)
        }
    }
}
