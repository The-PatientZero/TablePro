//
//  DatabaseSwitcherViewModel.swift
//  TablePro
//
//  ViewModel for DatabaseSwitcherSheet.
//  Handles database fetching, metadata loading, recent tracking, and switching logic.
//

import Combine
import Foundation
import SwiftUI

@MainActor
class DatabaseSwitcherViewModel: ObservableObject {
    // MARK: - Published State

    @Published var databases: [DatabaseMetadata] = []
    @Published var recentDatabases: [String] = []
    @Published var searchText = ""
    @Published var selectedDatabase: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showPreview = false

    // MARK: - Dependencies

    private let connectionId: UUID
    private let currentDatabase: String?
    private let databaseType: DatabaseType

    // MARK: - Computed Properties

    var filteredDatabases: [DatabaseMetadata] {
        if searchText.isEmpty {
            return databases
        }
        return databases.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var recentDatabaseMetadata: [DatabaseMetadata] {
        recentDatabases.compactMap { dbName in
            databases.first { $0.name == dbName }
        }
    }

    var allDatabases: [DatabaseMetadata] {
        // Filter out recent databases from "all" list
        filteredDatabases.filter { db in
            !recentDatabases.contains(db.name)
        }
    }

    // MARK: - Initialization

    init(connectionId: UUID, currentDatabase: String?, databaseType: DatabaseType) {
        self.connectionId = connectionId
        self.currentDatabase = currentDatabase
        self.databaseType = databaseType
        self.recentDatabases = UserDefaults.standard.recentDatabases(for: connectionId)
    }

    // MARK: - Public Methods

    /// Fetch databases and their metadata
    func fetchDatabases() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let driver = DatabaseManager.shared.activeDriver else {
                errorMessage = "No active connection"
                isLoading = false
                return
            }

            // Fetch database names
            let dbNames = try await driver.fetchDatabases()

            // Fetch metadata for each database (in parallel for performance)
            let metadataList = await withTaskGroup(of: DatabaseMetadata?.self) { group in
                for dbName in dbNames {
                    group.addTask {
                        await self.fetchMetadata(for: dbName, driver: driver)
                    }
                }

                var results: [DatabaseMetadata] = []
                for await metadata in group {
                    if let metadata = metadata {
                        results.append(metadata)
                    }
                }
                return results
            }

            // Update state
            databases = metadataList.sorted { $0.name < $1.name }
            isLoading = false

            // Pre-select current database or first database
            if let current = currentDatabase, databases.contains(where: { $0.name == current }) {
                selectedDatabase = current
            } else {
                selectedDatabase = databases.first?.name
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    /// Refresh database list
    func refreshDatabases() async {
        await fetchDatabases()
    }

    /// Create a new database
    func createDatabase(name: String, charset: String, collation: String?) async throws {
        guard let driver = DatabaseManager.shared.activeDriver else {
            throw DatabaseError.notConnected
        }

        try await driver.createDatabase(name: name, charset: charset, collation: collation)
    }

    /// Track database access
    func trackAccess(database: String) {
        UserDefaults.standard.trackDatabaseAccess(database, for: connectionId)
        recentDatabases = UserDefaults.standard.recentDatabases(for: connectionId)
    }

    // MARK: - Private Methods

    /// Fetch metadata for a single database
    private func fetchMetadata(for database: String, driver: DatabaseDriver) async
    -> DatabaseMetadata?
    {
        do {
            return try await driver.fetchDatabaseMetadata(database)
        } catch {
            // If metadata fetch fails, return minimal metadata
            print("Failed to fetch metadata for \(database): \(error)")
            return DatabaseMetadata.minimal(name: database, isSystem: isSystemDatabase(database))
        }
    }

    /// Determine if a database is a system database
    private func isSystemDatabase(_ database: String) -> Bool {
        switch databaseType {
        case .mysql, .mariadb:
            return ["information_schema", "mysql", "performance_schema", "sys"].contains(database)
        case .postgresql:
            return ["postgres", "template0", "template1"].contains(database)
        case .sqlite:
            return false
        }
    }
}
