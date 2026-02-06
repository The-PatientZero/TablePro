//
//  QueryHistoryManager.swift
//  TablePro
//
//  Thread-safe coordinator for query history
//  Communicates via NotificationCenter (NOT ObservableObject)
//

import Combine
import Foundation

/// Notification names for query history updates
extension Notification.Name {
    static let queryHistoryDidUpdate = Notification.Name("queryHistoryDidUpdate")
    static let loadQueryIntoEditor = Notification.Name("loadQueryIntoEditor")
}

/// Thread-safe manager for query history
/// NOT an ObservableObject - uses NotificationCenter for UI communication
final class QueryHistoryManager {
    static let shared = QueryHistoryManager()

    private let storage = QueryHistoryStorage.shared

    // Settings observer for immediate cleanup when settings change
    private var settingsObserver: AnyCancellable?

    private init() {
        // Note: Cleanup is now triggered from app startup with settings check
        // See TableProApp.swift for startup cleanup logic

        // Subscribe to history settings changes for immediate cleanup
        settingsObserver = NotificationCenter.default.publisher(for: .historySettingsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }

                // Update settings cache
                self.storage.updateSettingsCache()

                // Perform cleanup if auto-cleanup is enabled
                if AppSettingsManager.shared.history.autoCleanup {
                    self.storage.cleanup()
                }
            }
    }

    /// Perform cleanup if auto-cleanup is enabled in settings
    /// Should be called from app startup (MainActor context)
    @MainActor
    func performStartupCleanup() {
        // Check if auto cleanup is enabled
        guard AppSettingsManager.shared.history.autoCleanup else { return }

        // Update the settings cache before cleanup
        storage.updateSettingsCache()

        // Perform cleanup
        storage.cleanup()
    }

    // MARK: - History Capture

    /// Record a query execution (non-blocking background write)
    func recordQuery(
        query: String,
        connectionId: UUID,
        databaseName: String,
        executionTime: TimeInterval,
        rowCount: Int,
        wasSuccessful: Bool,
        errorMessage: String? = nil
    ) {
        let entry = QueryHistoryEntry(
            query: query,
            connectionId: connectionId,
            databaseName: databaseName,
            executionTime: executionTime,
            rowCount: rowCount,
            wasSuccessful: wasSuccessful,
            errorMessage: errorMessage
        )

        // Background write (non-blocking)
        storage.addHistory(entry) { success in
            if success {
                // Notify UI to refresh on main thread
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .queryHistoryDidUpdate,
                        object: nil
                    )
                }
            }
        }
    }

    // MARK: - History Retrieval

    /// Fetch history entries (synchronous - for compatibility)
    func fetchHistory(
        limit: Int = 100,
        offset: Int = 0,
        connectionId: UUID? = nil,
        searchText: String? = nil,
        dateFilter: DateFilter = .all
    ) -> [QueryHistoryEntry] {
        storage.fetchHistory(
            limit: limit,
            offset: offset,
            connectionId: connectionId,
            searchText: searchText,
            dateFilter: dateFilter
        )
    }

    /// Fetch history entries asynchronously (non-blocking - preferred)
    func fetchHistoryAsync(
        limit: Int = 100,
        offset: Int = 0,
        connectionId: UUID? = nil,
        searchText: String? = nil,
        dateFilter: DateFilter = .all,
        completion: @escaping ([QueryHistoryEntry]) -> Void
    ) {
        storage.fetchHistoryAsync(
            limit: limit,
            offset: offset,
            connectionId: connectionId,
            searchText: searchText,
            dateFilter: dateFilter,
            completion: completion
        )
    }

    /// Search queries using FTS5 full-text search
    func searchQueries(_ text: String) -> [QueryHistoryEntry] {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            return fetchHistory()
        }
        return storage.fetchHistory(searchText: text)
    }

    /// Delete a history entry
    func deleteHistory(id: UUID) -> Bool {
        let success = storage.deleteHistory(id: id)
        if success {
            NotificationCenter.default.post(name: .queryHistoryDidUpdate, object: nil)
        }
        return success
    }

    /// Get total history count
    func getHistoryCount() -> Int {
        storage.getHistoryCount()
    }

    /// Clear all history entries
    func clearAllHistory() -> Bool {
        let success = storage.clearAllHistory()
        if success {
            NotificationCenter.default.post(name: .queryHistoryDidUpdate, object: nil)
        }
        return success
    }

    // MARK: - Cleanup

    /// Manually trigger cleanup (normally runs automatically)
    /// Must be called from MainActor context
    @MainActor
    func cleanup() {
        // Update settings cache before cleanup
        storage.updateSettingsCache()
        storage.cleanup()
    }
}
