//
//  ToolbarItemIdentifier.swift
//  TablePro
//
//  Type-safe toolbar item identifiers for NSToolbar customization.
//  Provides compile-time safety and centralized toolbar item metadata.
//

import AppKit

/// Type-safe toolbar item identifiers
enum ToolbarItemIdentifier: String, CaseIterable {
    // MARK: - Left Section (Navigation)

    /// Connection switcher (dropdown to switch between saved connections)
    case connectionSwitcher = "com.TablePro.toolbar.connectionSwitcher"

    /// Database switcher (switch to different database within current connection)
    case databaseSwitcher = "com.TablePro.toolbar.databaseSwitcher"

    /// New query tab
    case newQueryTab = "com.TablePro.toolbar.newQueryTab"

    /// Refresh current view/query
    case refresh = "com.TablePro.toolbar.refresh"

    // MARK: - Center Section (Principal)

    /// Connection status display (tag + connection info + execution indicator)
    case connectionStatus = "com.TablePro.toolbar.connectionStatus"

    // MARK: - Right Section (Actions)

    /// Toggle filter panel
    case filterToggle = "com.TablePro.toolbar.filterToggle"

    /// Toggle query history panel
    case historyToggle = "com.TablePro.toolbar.historyToggle"

    /// Export data
    case export = "com.TablePro.toolbar.export"

    /// Import data
    case `import` = "com.TablePro.toolbar.import"

    /// Toggle right sidebar (inspector)
    case inspector = "com.TablePro.toolbar.inspector"

    // MARK: - Conversion

    /// Convert to NSToolbarItem.Identifier
    var nsIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(rawValue)
    }

    // MARK: - Metadata

    /// Human-readable label for toolbar item
    /// Note: connectionStatus label is set dynamically based on connection name
    var label: String {
        switch self {
        case .connectionSwitcher: return "Connection"
        case .databaseSwitcher: return "Database"
        case .newQueryTab: return "SQL"
        case .refresh: return "Refresh"
        case .connectionStatus: return "" // Set dynamically in ToolbarItemFactory
        case .filterToggle: return "Filters"
        case .historyToggle: return "History"
        case .export: return "Export"
        case .import: return "Import"
        case .inspector: return "Inspector"
        }
    }

    /// Label shown in customization palette
    var paletteLabel: String {
        switch self {
        case .connectionSwitcher: return "Connection Switcher"
        case .databaseSwitcher: return "Database Switcher"
        case .newQueryTab: return "New Query Tab"
        case .refresh: return "Refresh"
        case .connectionStatus: return "Connection Status"
        case .filterToggle: return "Toggle Filters"
        case .historyToggle: return "Toggle History"
        case .export: return "Export Data"
        case .import: return "Import Data"
        case .inspector: return "Toggle Inspector"
        }
    }

    /// Tooltip text with keyboard shortcut (if applicable)
    var toolTip: String {
        switch self {
        case .connectionSwitcher:
            return "Switch Connection"
        case .databaseSwitcher:
            return "Switch Database (⌘K)"
        case .newQueryTab:
            return "New Query Tab (⌘T)"
        case .refresh:
            return "Refresh (⌘R)"
        case .connectionStatus:
            return "Connection Status"
        case .filterToggle:
            return "Toggle Filters (⌘F)"
        case .historyToggle:
            return "Toggle Query History (⌘⇧H)"
        case .export:
            return "Export Data (⌘⇧E)"
        case .import:
            return "Import Data (⌘⇧I)"
        case .inspector:
            return "Toggle Inspector (⌘⌥B)"
        }
    }

    /// SF Symbol name for the toolbar item icon
    var iconName: String {
        switch self {
        case .connectionSwitcher:
            return "network"
        case .databaseSwitcher:
            return "cylinder"
        case .newQueryTab:
            return "doc.text"
        case .refresh:
            return "arrow.clockwise"
        case .connectionStatus:
            return "info.circle"  // Not used (custom view)
        case .filterToggle:
            return "line.3.horizontal.decrease.circle"
        case .historyToggle:
            return "clock"
        case .export:
            return "square.and.arrow.up"
        case .import:
            return "square.and.arrow.down"
        case .inspector:
            return "sidebar.trailing"
        }
    }
}
