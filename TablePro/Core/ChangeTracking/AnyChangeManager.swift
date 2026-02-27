//
//  AnyChangeManager.swift
//  TablePro
//
//  Type-erased wrapper for change managers (data and structure).
//  Allows DataGridView to work with both DataChangeManager and StructureChangeManager.
//

import Combine
import Foundation

/// Type-erased change manager wrapper
@MainActor
final class AnyChangeManager: ObservableObject {
    @Published var hasChanges: Bool = false
    @Published var reloadVersion: Int = 0

    private var cancellables: Set<AnyCancellable> = []
    private let _isRowDeleted: (Int) -> Bool
    private let _getChanges: () -> [Any]
    private let _canRedo: () -> Bool
    private let _recordCellChange: ((Int, Int, String, String?, String?, [String?]) -> Void)?
    private let _undoRowDeletion: ((Int) -> Void)?
    private let _undoRowInsertion: ((Int) -> Void)?
    private let _consumeChangedRowIndices: (() -> Set<Int>)?

    // MARK: - Initializers

    /// Wrap a DataChangeManager
    init(dataManager: DataChangeManager) {
        self._isRowDeleted = { rowIndex in
            dataManager.isRowDeleted(rowIndex)
        }
        self._getChanges = {
            dataManager.changes
        }
        self._canRedo = {
            dataManager.canRedo
        }
        self._recordCellChange = { rowIndex, columnIndex, columnName, oldValue, newValue, originalRow in
            dataManager.recordCellChange(
                rowIndex: rowIndex,
                columnIndex: columnIndex,
                columnName: columnName,
                oldValue: oldValue,
                newValue: newValue,
                originalRow: originalRow
            )
        }
        self._undoRowDeletion = { rowIndex in
            dataManager.undoRowDeletion(rowIndex: rowIndex)
        }
        self._undoRowInsertion = { rowIndex in
            dataManager.undoRowInsertion(rowIndex: rowIndex)
        }
        self._consumeChangedRowIndices = {
            dataManager.consumeChangedRowIndices()
        }

        // Sync published properties — use .sink with [weak self] instead of .assign(to:on:)
        // because .assign retains the target, creating a cycle: self -> cancellables -> subscription -> self
        dataManager.$hasChanges
            .sink { [weak self] in self?.hasChanges = $0 }
            .store(in: &cancellables)
        dataManager.$reloadVersion
            .sink { [weak self] in self?.reloadVersion = $0 }
            .store(in: &cancellables)
    }

    /// Wrap a StructureChangeManager
    init(structureManager: StructureChangeManager) {
        self._isRowDeleted = { _ in false } // Structure doesn't track row deletions
        self._getChanges = {
            Array(structureManager.pendingChanges.values)
        }
        self._canRedo = {
            structureManager.canRedo
        }
        self._recordCellChange = nil // Structure uses custom editing logic
        self._undoRowDeletion = nil
        self._undoRowInsertion = nil
        self._consumeChangedRowIndices = {
            structureManager.consumeChangedRowIndices()
        }

        // Sync published properties — use .sink with [weak self] to avoid retain cycle
        structureManager.$hasChanges
            .sink { [weak self] in self?.hasChanges = $0 }
            .store(in: &cancellables)
        structureManager.$reloadVersion
            .sink { [weak self] in self?.reloadVersion = $0 }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    var canRedo: Bool {
        _canRedo()
    }

    func isRowDeleted(_ rowIndex: Int) -> Bool {
        _isRowDeleted(rowIndex)
    }

    var changes: [Any] {
        _getChanges()
    }

    func recordCellChange(
        rowIndex: Int,
        columnIndex: Int,
        columnName: String,
        oldValue: String?,
        newValue: String?,
        originalRow: [String?]
    ) {
        _recordCellChange?(rowIndex, columnIndex, columnName, oldValue, newValue, originalRow)
    }

    func undoRowDeletion(rowIndex: Int) {
        _undoRowDeletion?(rowIndex)
    }

    func undoRowInsertion(rowIndex: Int) {
        _undoRowInsertion?(rowIndex)
    }

    func consumeChangedRowIndices() -> Set<Int> {
        _consumeChangedRowIndices?() ?? []
    }
}
