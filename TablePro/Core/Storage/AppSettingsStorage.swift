//
//  AppSettingsStorage.swift
//  TablePro
//
//  Persistent storage for application settings using UserDefaults.
//  Follows FilterSettingsStorage pattern - singleton with JSON encoding.
//

import Foundation

/// Persistent storage for app settings
final class AppSettingsStorage {
    static let shared = AppSettingsStorage()

    private let defaults = UserDefaults.standard

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let general = "com.TablePro.settings.general"
        static let appearance = "com.TablePro.settings.appearance"
        static let editor = "com.TablePro.settings.editor"
        static let dataGrid = "com.TablePro.settings.dataGrid"
        static let history = "com.TablePro.settings.history"
        static let lastConnectionId = "com.TablePro.settings.lastConnectionId"
    }

    private init() {}

    // MARK: - General Settings

    func loadGeneral() -> GeneralSettings {
        load(key: Keys.general, default: .default)
    }

    func saveGeneral(_ settings: GeneralSettings) {
        save(settings, key: Keys.general)
    }

    // MARK: - Appearance Settings

    func loadAppearance() -> AppearanceSettings {
        load(key: Keys.appearance, default: .default)
    }

    func saveAppearance(_ settings: AppearanceSettings) {
        save(settings, key: Keys.appearance)
    }

    // MARK: - Editor Settings

    func loadEditor() -> EditorSettings {
        load(key: Keys.editor, default: .default)
    }

    func saveEditor(_ settings: EditorSettings) {
        save(settings, key: Keys.editor)
    }

    // MARK: - Data Grid Settings

    func loadDataGrid() -> DataGridSettings {
        load(key: Keys.dataGrid, default: .default)
    }

    func saveDataGrid(_ settings: DataGridSettings) {
        save(settings, key: Keys.dataGrid)
    }

    // MARK: - History Settings

    func loadHistory() -> HistorySettings {
        load(key: Keys.history, default: .default)
    }

    func saveHistory(_ settings: HistorySettings) {
        save(settings, key: Keys.history)
    }

    // MARK: - Last Connection (for Reopen Last Session)

    /// Load the last used connection ID
    func loadLastConnectionId() -> UUID? {
        guard let uuidString = defaults.string(forKey: Keys.lastConnectionId) else {
            return nil
        }
        return UUID(uuidString: uuidString)
    }

    /// Save the last used connection ID
    func saveLastConnectionId(_ connectionId: UUID?) {
        if let connectionId = connectionId {
            defaults.set(connectionId.uuidString, forKey: Keys.lastConnectionId)
        } else {
            defaults.removeObject(forKey: Keys.lastConnectionId)
        }
    }

    // MARK: - Reset

    /// Reset all settings to defaults
    func resetToDefaults() {
        saveGeneral(.default)
        saveAppearance(.default)
        saveEditor(.default)
        saveDataGrid(.default)
        saveHistory(.default)
    }

    // MARK: - Helpers

    private func load<T: Codable>(key: String, default defaultValue: T) -> T {
        guard let data = defaults.data(forKey: key) else {
            return defaultValue
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("Failed to decode settings for \(key): \(error)")
            return defaultValue
        }
    }

    private func save<T: Codable>(_ value: T, key: String) {
        do {
            let data = try JSONEncoder().encode(value)
            defaults.set(data, forKey: key)
        } catch {
            print("Failed to encode settings for \(key): \(error)")
        }
    }
}
