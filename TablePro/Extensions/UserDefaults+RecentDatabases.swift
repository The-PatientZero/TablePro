//
//  UserDefaults+RecentDatabases.swift
//  TablePro
//
//  UserDefaults extension for tracking recently accessed databases per connection.
//

import Foundation

extension UserDefaults {
    private static let recentDatabasesKey = "recentDatabases"
    private static let maxRecentCount = 5

    /// Get recent databases for a specific connection
    /// - Parameter connectionId: The connection UUID
    /// - Returns: Array of recently accessed database names (max 5, ordered by recency)
    func recentDatabases(for connectionId: UUID) -> [String] {
        guard let dict = dictionary(forKey: Self.recentDatabasesKey) as? [String: [String]] else {
            return []
        }
        return dict[connectionId.uuidString] ?? []
    }

    /// Track database access for a connection
    /// - Parameters:
    ///   - database: Database name to track
    ///   - connectionId: The connection UUID
    func trackDatabaseAccess(_ database: String, for connectionId: UUID) {
        var dict = (dictionary(forKey: Self.recentDatabasesKey) as? [String: [String]]) ?? [:]
        var recent = dict[connectionId.uuidString] ?? []

        // Remove if already exists (will be added to front)
        recent.removeAll { $0 == database }

        // Add to front
        recent.insert(database, at: 0)

        // Keep only max count
        if recent.count > Self.maxRecentCount {
            recent = Array(recent.prefix(Self.maxRecentCount))
        }

        dict[connectionId.uuidString] = recent
        set(dict, forKey: Self.recentDatabasesKey)
    }

    /// Clear recent databases for a connection
    /// - Parameter connectionId: The connection UUID
    func clearRecentDatabases(for connectionId: UUID) {
        var dict = (dictionary(forKey: Self.recentDatabasesKey) as? [String: [String]]) ?? [:]
        dict.removeValue(forKey: connectionId.uuidString)
        set(dict, forKey: Self.recentDatabasesKey)
    }
}
