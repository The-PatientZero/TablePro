//
//  SettingsNotifications.swift
//  TablePro
//
//  Notification names and payload structures for settings changes.
//  Follows existing NotificationCenter pattern used throughout the app.
//

import Foundation

// MARK: - Settings Notification Names

extension Notification.Name {
    // MARK: - Domain-Specific Notifications

    /// Posted when data grid settings change (row height, date format, etc.)
    static let dataGridSettingsDidChange = Notification.Name("dataGridSettingsDidChange")

    /// Posted when history settings change (retention, auto-cleanup, etc.)
    static let historySettingsDidChange = Notification.Name("historySettingsDidChange")

    /// Posted when editor settings change (font, line numbers, etc.)
    static let editorSettingsDidChange = Notification.Name("editorSettingsDidChange")

    /// Posted when appearance settings change (theme, accent color)
    static let appearanceSettingsDidChange = Notification.Name("appearanceSettingsDidChange")

    /// Posted when general settings change (startup behavior, confirmations)
    static let generalSettingsDidChange = Notification.Name("generalSettingsDidChange")

    // MARK: - Generic Notification

    /// Posted for any settings change (in addition to domain-specific notification)
    /// Use this to listen for all settings changes regardless of domain
    static let settingsDidChange = Notification.Name("settingsDidChange")
}

// MARK: - Settings Change Info

/// Information about a settings change included in notification userInfo
struct SettingsChangeInfo {
    /// The settings domain that changed (e.g., "general", "dataGrid", "history")
    let domain: String

    /// Optional set of specific keys that changed within the domain
    /// If nil, assume all settings in the domain may have changed
    let changedKeys: Set<String>?

    /// User info dictionary key for accessing SettingsChangeInfo
    static let userInfoKey = "changeInfo"
}

// MARK: - Convenience Extensions

extension Notification {
    /// Extract SettingsChangeInfo from notification's userInfo
    var settingsChangeInfo: SettingsChangeInfo? {
        guard let userInfo = userInfo,
              let changeInfo = userInfo[SettingsChangeInfo.userInfoKey] as? SettingsChangeInfo else {
            return nil
        }
        return changeInfo
    }
}
