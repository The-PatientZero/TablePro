//
//  AppNotifications.swift
//  TablePro
//
//  Centralized notification names used across the app.
//  Domain-specific collections remain in TableProApp.swift
//  and SettingsNotifications.swift.
//

import Foundation

extension Notification.Name {
    // MARK: - Query Editor

    static let aiFixError = Notification.Name("aiFixError")
    static let aiExplainSelection = Notification.Name("aiExplainSelection")
    static let aiOptimizeSelection = Notification.Name("aiOptimizeSelection")

    // MARK: - Query History

    static let queryHistoryDidUpdate = Notification.Name("queryHistoryDidUpdate")
    static let loadQueryIntoEditor = Notification.Name("loadQueryIntoEditor")
    static let insertQueryFromAI = Notification.Name("insertQueryFromAI")

    // MARK: - Connections

    static let connectionUpdated = Notification.Name("connectionUpdated")
    static let databaseDidConnect = Notification.Name("databaseDidConnect")

    // MARK: - SSH

    static let sshTunnelDied = Notification.Name("sshTunnelDied")
    static let lastWindowDidClose = Notification.Name("lastWindowDidClose")
}
