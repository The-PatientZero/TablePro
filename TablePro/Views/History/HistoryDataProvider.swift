//
//  HistoryDataProvider.swift
//  TablePro
//
//  Data provider for query history entries.
//  Extracted from HistoryListViewController for better separation of concerns.
//

import Foundation

/// Data provider for query history entries
final class HistoryDataProvider {
    // MARK: - Properties

    private(set) var historyEntries: [QueryHistoryEntry] = []

    var dateFilter: UIDateFilter = .all
    var searchText: String = ""

    private var searchTask: DispatchWorkItem?
    private let searchDebounceInterval: TimeInterval = 0.15

    /// Callback when data changes
    var onDataChanged: (() -> Void)?

    // MARK: - Computed Properties

    var count: Int {
        historyEntries.count
    }

    var isEmpty: Bool {
        historyEntries.isEmpty
    }

    // MARK: - Data Loading

    /// Load data synchronously (for compatibility with existing code)
    func loadData() {
        loadHistory()
    }

    /// Load data asynchronously to avoid blocking main thread
    func loadDataAsync(completion: @escaping () -> Void) {
        QueryHistoryManager.shared.fetchHistoryAsync(
            limit: 500,
            offset: 0,
            connectionId: nil,
            searchText: searchText.isEmpty ? nil : searchText,
            dateFilter: dateFilter.toDateFilter
        ) { [weak self] entries in
            self?.historyEntries = entries
            completion()
        }
    }

    private func loadHistory() {
        historyEntries = QueryHistoryManager.shared.fetchHistory(
            limit: 500,
            offset: 0,
            connectionId: nil,
            searchText: searchText.isEmpty ? nil : searchText,
            dateFilter: dateFilter.toDateFilter
        )
    }

    // MARK: - Search

    func scheduleSearch(completion: @escaping () -> Void) {
        searchTask?.cancel()

        let task = DispatchWorkItem { [weak self] in
            self?.loadData()
            completion()
        }
        searchTask = task

        DispatchQueue.main.asyncAfter(deadline: .now() + searchDebounceInterval, execute: task)
    }

    // MARK: - Item Access

    func historyEntry(at index: Int) -> QueryHistoryEntry? {
        guard index >= 0 && index < historyEntries.count else { return nil }
        return historyEntries[index]
    }

    func query(at index: Int) -> String? {
        historyEntry(at: index)?.query
    }

    // MARK: - Deletion

    func deleteItem(at index: Int) -> Bool {
        guard let entry = historyEntry(at: index) else { return false }
        _ = QueryHistoryManager.shared.deleteHistory(id: entry.id)
        return true
    }

    func clearAll() -> Bool {
        QueryHistoryManager.shared.clearAllHistory()
    }
}
