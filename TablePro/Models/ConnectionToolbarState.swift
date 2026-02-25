//
//  ConnectionToolbarState.swift
//  TablePro
//
//  Observable state container for toolbar connection information.
//  Centralizes all toolbar-related state in a single, composable object.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Connection Environment

/// Represents the connection environment type for visual badges
enum ConnectionEnvironment: String, CaseIterable {
    case local = "LOCAL"
    case ssh = "SSH"
    case production = "PROD"
    case staging = "STAGING"

    /// SF Symbol for this environment type
    var iconName: String {
        switch self {
        case .local: return "house.fill"
        case .ssh: return "lock.fill"
        case .production: return "exclamationmark.triangle.fill"
        case .staging: return "flask.fill"
        }
    }

    /// Badge background color
    var backgroundColor: Color {
        switch self {
        case .local: return Color(nsColor: .systemGray).opacity(0.3)
        case .ssh: return Color(nsColor: .systemOrange).opacity(0.3)
        case .production: return Color(nsColor: .systemRed).opacity(0.3)
        case .staging: return Color(nsColor: .systemBlue).opacity(0.3)
        }
    }

    /// Badge foreground color
    var foregroundColor: Color {
        switch self {
        case .local: return .secondary
        case .ssh: return Color(nsColor: .systemOrange)
        case .production: return Color(nsColor: .systemRed)
        case .staging: return Color(nsColor: .systemBlue)
        }
    }
}

// MARK: - Connection State

/// Represents the current state of the database connection
enum ToolbarConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case executing
    case error(String)

    /// Status indicator color
    var indicatorColor: Color {
        switch self {
        case .disconnected: return Color(nsColor: .systemGray)
        case .connecting: return Color(nsColor: .systemOrange)
        case .connected: return Color(nsColor: .systemGreen)
        case .executing: return Color(nsColor: .systemBlue)
        case .error: return Color(nsColor: .systemRed)
        }
    }

    /// Human-readable description
    var description: String {
        switch self {
        case .disconnected: return String(localized: "Disconnected")
        case .connecting: return String(localized: "Connecting...")
        case .connected: return String(localized: "Connected")
        case .executing: return String(localized: "Executing...")
        case .error(let message): return String(localized: "Error: \(message)")
        }
    }

    /// Short label for toolbar display
    var label: String {
        switch self {
        case .disconnected: return String(localized: "Disconnected")
        case .connecting: return String(localized: "Connecting")
        case .connected: return String(localized: "Connected")
        case .executing: return String(localized: "Executing")
        case .error: return String(localized: "Error")
        }
    }

    /// Whether to show activity indicator
    var isAnimating: Bool {
        switch self {
        case .connecting, .executing: return true
        default: return false
        }
    }
}

// MARK: - Toolbar State

/// Observable state container for the connection toolbar.
/// Uses ObservableObject (could migrate to @Observable since macOS 14 is now the minimum).
/// This is the single source of truth for all toolbar UI state.
@MainActor
final class ConnectionToolbarState: ObservableObject {
    // MARK: - Connection Info

    /// The tag assigned to this connection (optional)
    @Published var tagId: UUID?

    /// Database type (MySQL, MariaDB, PostgreSQL, SQLite)
    @Published var databaseType: DatabaseType = .mysql

    /// Server version string (e.g., "11.1.2")
    @Published var databaseVersion: String?

    /// Connection name for display
    @Published var connectionName: String = ""

    /// Current database name
    @Published var databaseName: String = ""

    /// Custom display color for the connection (uses database type color if not set)
    @Published var displayColor: Color = .init(nsColor: .systemOrange)

    /// Current connection state
    @Published var connectionState: ToolbarConnectionState = .disconnected

    // MARK: - Query Execution

    /// Whether a query is currently executing.
    /// Not @Published — use `setExecuting(_:)` to update, which batches
    /// the connectionState side-effect into a single objectWillChange.
    private(set) var isExecuting: Bool = false

    /// Set execution state and update connectionState in one publish cycle.
    func setExecuting(_ executing: Bool) {
        let newState: ToolbarConnectionState
        if executing && connectionState == .connected {
            newState = .executing
        } else if !executing && connectionState == .executing {
            newState = .connected
        } else {
            newState = connectionState
        }

        // Only fire objectWillChange if something actually changes
        guard executing != isExecuting || newState != connectionState else { return }

        // Set isExecuting first (non-Published, no notification).
        // Then set connectionState — its @Published wrapper fires
        // objectWillChange once, covering both mutations.
        // If connectionState is unchanged, send manually for isExecuting.
        isExecuting = executing
        if newState != connectionState {
            connectionState = newState
        } else {
            objectWillChange.send()
        }
    }

    /// Duration of the last completed query
    @Published var lastQueryDuration: TimeInterval?

    // MARK: - Future Expansion

    /// Whether the connection is read-only
    @Published var isReadOnly: Bool = false

    /// Whether the current tab is a table tab (enables filter/sort actions)
    @Published var isTableTab: Bool = false

    /// Whether there are pending changes to preview
    @Published var hasPendingChanges: Bool = false

    /// Whether the SQL review popover is showing
    @Published var showSQLReviewPopover: Bool = false

    /// SQL statements to display in the review popover
    @Published var previewStatements: [String] = []

    /// Network latency in milliseconds (for SSH connections)
    @Published var latencyMs: Int?

    /// Replication lag in seconds (for replicated databases)
    @Published var replicationLagSeconds: Int?

    // MARK: - Computed Properties

    /// Formatted database version with type
    var formattedDatabaseInfo: String {
        if let version = databaseVersion, !version.isEmpty {
            return "\(databaseType.rawValue) \(version)"
        }
        return databaseType.rawValue
    }

    /// Tooltip text for the status indicator
    var statusTooltip: String {
        var parts: [String] = [connectionState.description]

        if let latency = latencyMs {
            parts.append(String(localized: "Latency: \(latency)ms"))
        }

        if let lag = replicationLagSeconds {
            parts.append(String(localized: "Replication lag: \(lag)s"))
        }

        if isReadOnly {
            parts.append(String(localized: "Read-only"))
        }

        return parts.joined(separator: " • ")
    }

    // MARK: - Initialization

    init() {}

    /// Initialize with a database connection
    init(connection: DatabaseConnection) {
        update(from: connection)
    }

    // MARK: - Update Methods

    /// Update state from a DatabaseConnection model
    func update(from connection: DatabaseConnection) {
        connectionName = connection.name
        if connection.type == .sqlite {
            databaseName = (connection.database as NSString).lastPathComponent
        } else {
            databaseName = connection.database
        }
        databaseType = connection.type
        displayColor = connection.displayColor
        tagId = connection.tagId
        isReadOnly = connection.isReadOnly
    }

    /// Update connection state from ConnectionStatus
    func updateConnectionState(from status: ConnectionStatus) {
        switch status {
        case .disconnected:
            connectionState = .disconnected
        case .connecting:
            connectionState = .connecting
        case .connected:
            connectionState = isExecuting ? .executing : .connected
        case .error(let message):
            connectionState = .error(message)
        }
    }

    /// Reset to default disconnected state
    func reset() {
        tagId = nil
        databaseType = .mysql
        databaseVersion = nil
        connectionName = ""
        databaseName = ""
        displayColor = databaseType.themeColor
        connectionState = .disconnected
        isExecuting = false
        lastQueryDuration = nil
        isReadOnly = false
        isTableTab = false
        latencyMs = nil
        replicationLagSeconds = nil
    }
}
