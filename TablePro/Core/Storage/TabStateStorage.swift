//
//  TabStateStorage.swift
//  TablePro
//
//  File-based persistence for tab state per connection.
//  Migrated from UserDefaults to Application Support directory
//  to avoid bloating the plist loaded at app launch.
//

import Foundation
import os

/// Represents persisted tab state for a connection
struct TabState: Codable {
    let tabs: [PersistedTab]
    let selectedTabId: UUID?
}

/// Service for persisting tab state per connection using file-based storage.
///
/// Data is stored as individual JSON files per connection in:
///   `~/Library/Application Support/TablePro/TabState/`
///
/// Last-query strings are stored in a sibling directory:
///   `~/Library/Application Support/TablePro/LastQuery/`
final class TabStateStorage {
    static let shared = TabStateStorage()

    private static let logger = Logger(subsystem: "com.TablePro", category: "TabStateStorage")

    // MARK: - Legacy UserDefaults Keys (for migration)

    private static let legacyTabStateKeyPrefix = "com.TablePro.tabs."
    private static let legacyLastQueryKeyPrefix = "com.TablePro.lastquery."
    private static let migrationCompleteKey = "com.TablePro.tabStateMigrationComplete"

    // MARK: - File Storage

    private let tabStateDirectory: URL
    private let lastQueryDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Maximum query size to persist (500KB). Larger queries (e.g., imported SQL dumps)
    /// would cause excessive file I/O.
    private static let maxPersistableQuerySize = 500_000

    private init() {
        let appSupport: URL
        if let resolved = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            appSupport = resolved
        } else {
            Self.logger.error("Application Support directory unavailable, falling back to temporary directory")
            appSupport = FileManager.default.temporaryDirectory
        }

        let baseDirectory = appSupport.appendingPathComponent("TablePro", isDirectory: true)
        tabStateDirectory = baseDirectory.appendingPathComponent("TabState", isDirectory: true)
        lastQueryDirectory = baseDirectory.appendingPathComponent("LastQuery", isDirectory: true)

        encoder = JSONEncoder()
        decoder = JSONDecoder()

        createDirectoriesIfNeeded()
        migrateFromUserDefaultsIfNeeded()
    }

    // MARK: - Public API

    /// Save tab state for a connection
    func saveTabState(connectionId: UUID, tabs: [QueryTab], selectedTabId: UUID?) {
        let persistedTabs = tabs.map { $0.toPersistedTab() }
        let tabState = TabState(tabs: persistedTabs, selectedTabId: selectedTabId)

        do {
            let data = try encoder.encode(tabState)
            let fileURL = tabStateFileURL(for: connectionId)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save tab state for \(connectionId): \(error.localizedDescription)")
        }
    }

    /// Load tab state for a connection
    func loadTabState(connectionId: UUID) -> TabState? {
        let fileURL = tabStateFileURL(for: connectionId)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(TabState.self, from: data)
        } catch {
            Self.logger.error("Failed to load tab state for \(connectionId): \(error.localizedDescription)")
            return nil
        }
    }

    /// Clear tab state for a connection
    func clearTabState(connectionId: UUID) {
        let fileURL = tabStateFileURL(for: connectionId)

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            Self.logger.error("Failed to clear tab state for \(connectionId): \(error.localizedDescription)")
        }
    }

    // MARK: - Last Query Memory (TablePlus-style)

    /// Save the last query text for a connection (persists across tab close/open)
    func saveLastQuery(_ query: String, for connectionId: UUID) {
        // Skip persistence for very large queries to avoid excessive file I/O
        guard (query as NSString).length < Self.maxPersistableQuerySize else { return }

        let fileURL = lastQueryFileURL(for: connectionId)

        // Only save non-empty queries (trimmed to avoid saving whitespace-only queries)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Remove file if query is empty
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                } catch {
                    Self.logger.error(
                        "Failed to remove last query for \(connectionId): \(error.localizedDescription)"
                    )
                }
            }
        } else {
            do {
                let data = Data(trimmed.utf8)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                Self.logger.error(
                    "Failed to save last query for \(connectionId): \(error.localizedDescription)"
                )
            }
        }
    }

    /// Load the last query text for a connection
    func loadLastQuery(for connectionId: UUID) -> String? {
        let fileURL = lastQueryFileURL(for: connectionId)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return String(data: data, encoding: .utf8)
        } catch {
            Self.logger.error("Failed to load last query for \(connectionId): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private Helpers

    private func tabStateFileURL(for connectionId: UUID) -> URL {
        tabStateDirectory.appendingPathComponent("\(connectionId.uuidString).json")
    }

    private func lastQueryFileURL(for connectionId: UUID) -> URL {
        lastQueryDirectory.appendingPathComponent("\(connectionId.uuidString).txt")
    }

    private func createDirectoriesIfNeeded() {
        let fm = FileManager.default
        for directory in [tabStateDirectory, lastQueryDirectory] {
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                Self.logger.error("Failed to create directory \(directory.path): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Migration from UserDefaults

    /// One-time migration: reads existing tab state and last-query data from UserDefaults,
    /// writes it to file storage, then clears the old UserDefaults keys.
    ///
    /// SVC-25: This runs synchronously at first launch but is acceptable because:
    ///   1. The `migrationCompleteKey` boolean guard makes subsequent launches O(1).
    ///   2. Migration only processes a handful of small JSON blobs (one per connection).
    ///   3. It runs during `init()` before any UI is displayed, so there is no visible stall.
    /// Making this async would require the entire public API to become async, adding
    /// significant complexity for a one-time operation that completes in milliseconds.
    private func migrateFromUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard

        guard !defaults.bool(forKey: Self.migrationCompleteKey) else { return }

        Self.logger.trace("Starting one-time migration of tab state from UserDefaults to file storage")

        var migratedTabStates = 0
        var migratedLastQueries = 0

        // Migrate tab state entries
        let allKeys = defaults.dictionaryRepresentation().keys
        let tabStateKeys = allKeys.filter { $0.hasPrefix(Self.legacyTabStateKeyPrefix) }
        let lastQueryKeys = allKeys.filter { $0.hasPrefix(Self.legacyLastQueryKeyPrefix) }

        for key in tabStateKeys {
            let uuidString = String(key.dropFirst(Self.legacyTabStateKeyPrefix.count))
            guard let connectionId = UUID(uuidString: uuidString),
                  let data = defaults.data(forKey: key) else { continue }

            // Write directly to file (data is already JSON-encoded TabState)
            let fileURL = tabStateFileURL(for: connectionId)
            do {
                try data.write(to: fileURL, options: .atomic)
                defaults.removeObject(forKey: key)
                migratedTabStates += 1
            } catch {
                Self.logger.error("Failed to migrate tab state for \(uuidString): \(error.localizedDescription)")
            }
        }

        for key in lastQueryKeys {
            let uuidString = String(key.dropFirst(Self.legacyLastQueryKeyPrefix.count))
            guard let connectionId = UUID(uuidString: uuidString),
                  let query = defaults.string(forKey: key) else { continue }

            let fileURL = lastQueryFileURL(for: connectionId)
            do {
                let data = Data(query.utf8)
                try data.write(to: fileURL, options: .atomic)
                defaults.removeObject(forKey: key)
                migratedLastQueries += 1
            } catch {
                Self.logger.error("Failed to migrate last query for \(uuidString): \(error.localizedDescription)")
            }
        }

        defaults.set(true, forKey: Self.migrationCompleteKey)

        if migratedTabStates > 0 || migratedLastQueries > 0 {
            Self.logger.trace(
                "Migration complete: \(migratedTabStates) tab states, \(migratedLastQueries) last queries"
            )
        } else {
            Self.logger.trace("Migration complete: no legacy data found")
        }
    }
}
