//
//  ToolbarItemFactory.swift
//  TablePro
//
//  Factory for creating NSToolbarItem instances.
//  Implements protocol-oriented design for testability and flexibility.
//

import AppKit

/// Protocol for creating toolbar items
@MainActor
protocol ToolbarItemFactory {
    /// Create a toolbar item for the given identifier
    func makeToolbarItem(
        identifier: ToolbarItemIdentifier,
        state: ConnectionToolbarState
    ) -> NSToolbarItem?
}

/// Default implementation of toolbar item factory
@MainActor
final class DefaultToolbarItemFactory: ToolbarItemFactory {
    // MARK: - Properties

    /// Hold references to hosted SwiftUI views to prevent deallocation
    private var hostedViews: [NSToolbarItem.Identifier: Any] = [:]

    // MARK: - Helper Methods

    /// Creates an NSImage from a system symbol name with a fallback
    private func systemImage(named symbolName: String, description: String) -> NSImage {
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description) {
            return image
        }
        // Fallback to a generic symbol if the requested one doesn't exist
        return NSImage(systemSymbolName: "square.dashed", accessibilityDescription: description)
            ?? NSImage()
    }

    // MARK: - ToolbarItemFactory

    func makeToolbarItem(
        identifier: ToolbarItemIdentifier,
        state: ConnectionToolbarState
    ) -> NSToolbarItem? {
        switch identifier {
        case .connectionSwitcher:
            return makeConnectionSwitcherItem(state: state)
        case .databaseSwitcher:
            return makeDatabaseSwitcherItem(state: state)
        case .newQueryTab:
            return makeNewQueryTabItem()
        case .refresh:
            return makeRefreshItem(state: state)
        case .connectionStatus:
            return makeConnectionStatusItem(state: state)
        case .filterToggle:
            return makeFilterToggleItem()
        case .historyToggle:
            return makeHistoryToggleItem()
        case .export:
            return makeExportItem(state: state)
        case .import:
            return makeImportItem(state: state)
        case .inspector:
            return makeInspectorItem()
        }
    }

    // MARK: - Factory Methods

    private func makeConnectionSwitcherItem(state: ConnectionToolbarState) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarItemIdentifier.connectionSwitcher.nsIdentifier)
        item.label = ToolbarItemIdentifier.connectionSwitcher.label
        item.paletteLabel = ToolbarItemIdentifier.connectionSwitcher.paletteLabel
        item.toolTip = ToolbarItemIdentifier.connectionSwitcher.toolTip

        let button = NSButton(
            image: systemImage(named: ToolbarItemIdentifier.connectionSwitcher.iconName, description: "Connection"),
            target: ToolbarActionProxy.shared,
            action: #selector(ToolbarActionProxy.connectionSwitcherAction)
        )
        button.bezelStyle = .texturedRounded
        button.isBordered = true

        item.view = button
        item.isEnabled = true  // Always enabled (can switch even when disconnected)

        return item
    }

    private func makeDatabaseSwitcherItem(state: ConnectionToolbarState) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarItemIdentifier.databaseSwitcher.nsIdentifier)
        item.label = ToolbarItemIdentifier.databaseSwitcher.label
        item.paletteLabel = ToolbarItemIdentifier.databaseSwitcher.paletteLabel
        item.toolTip = ToolbarItemIdentifier.databaseSwitcher.toolTip

        let button = NSButton(
            image: systemImage(named: ToolbarItemIdentifier.databaseSwitcher.iconName, description: "Database"),
            target: ToolbarActionProxy.shared,
            action: #selector(ToolbarActionProxy.databaseSwitcherAction)
        )
        button.bezelStyle = .texturedRounded
        button.isBordered = true

        item.view = button

        // Bind enabled state to connection status and database type
        item.isEnabled = (state.connectionState == .connected && state.databaseType != .sqlite)

        return item
    }

    private func makeNewQueryTabItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarItemIdentifier.newQueryTab.nsIdentifier)
        item.label = ToolbarItemIdentifier.newQueryTab.label
        item.paletteLabel = ToolbarItemIdentifier.newQueryTab.paletteLabel
        item.toolTip = ToolbarItemIdentifier.newQueryTab.toolTip

        let button = NSButton(
            title: "SQL",
            target: ToolbarActionProxy.shared,
            action: #selector(ToolbarActionProxy.newQueryTabAction)
        )
        button.bezelStyle = .texturedRounded
        button.isBordered = true

        item.view = button
        item.isEnabled = true  // Always enabled

        return item
    }

    private func makeRefreshItem(state: ConnectionToolbarState) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarItemIdentifier.refresh.nsIdentifier)
        item.label = ToolbarItemIdentifier.refresh.label
        item.paletteLabel = ToolbarItemIdentifier.refresh.paletteLabel
        item.toolTip = ToolbarItemIdentifier.refresh.toolTip

        let button = NSButton(
            image: systemImage(named: ToolbarItemIdentifier.refresh.iconName, description: "Refresh"),
            target: ToolbarActionProxy.shared,
            action: #selector(ToolbarActionProxy.refreshAction)
        )
        button.bezelStyle = .texturedRounded
        button.isBordered = true

        item.view = button
        item.isEnabled = (state.connectionState == .connected)

        return item
    }

    private func makeConnectionStatusItem(state: ConnectionToolbarState) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarItemIdentifier.connectionStatus.nsIdentifier)
        item.label = "" // Don't show label (connection name already in window title)
        item.paletteLabel = ToolbarItemIdentifier.connectionStatus.paletteLabel
        item.toolTip = ToolbarItemIdentifier.connectionStatus.toolTip

        // Host SwiftUI view
        let hostingView = ToolbarPrincipalContentHostingView(state: state)
        item.view = hostingView

        // Store reference to prevent deallocation
        hostedViews[item.itemIdentifier] = hostingView

        return item
    }

    private func makeFilterToggleItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarItemIdentifier.filterToggle.nsIdentifier)
        item.label = ToolbarItemIdentifier.filterToggle.label
        item.paletteLabel = ToolbarItemIdentifier.filterToggle.paletteLabel
        item.toolTip = ToolbarItemIdentifier.filterToggle.toolTip

        let button = NSButton(
            image: systemImage(named: ToolbarItemIdentifier.filterToggle.iconName, description: "Filters"),
            target: ToolbarActionProxy.shared,
            action: #selector(ToolbarActionProxy.filterToggleAction)
        )
        button.bezelStyle = .texturedRounded
        button.isBordered = true

        item.view = button
        item.isEnabled = true

        return item
    }

    private func makeHistoryToggleItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarItemIdentifier.historyToggle.nsIdentifier)
        item.label = ToolbarItemIdentifier.historyToggle.label
        item.paletteLabel = ToolbarItemIdentifier.historyToggle.paletteLabel
        item.toolTip = ToolbarItemIdentifier.historyToggle.toolTip

        let button = NSButton(
            image: systemImage(named: ToolbarItemIdentifier.historyToggle.iconName, description: "History"),
            target: ToolbarActionProxy.shared,
            action: #selector(ToolbarActionProxy.historyToggleAction)
        )
        button.bezelStyle = .texturedRounded
        button.isBordered = true

        item.view = button
        item.isEnabled = true

        return item
    }

    private func makeExportItem(state: ConnectionToolbarState) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarItemIdentifier.export.nsIdentifier)
        item.label = ToolbarItemIdentifier.export.label
        item.paletteLabel = ToolbarItemIdentifier.export.paletteLabel
        item.toolTip = ToolbarItemIdentifier.export.toolTip

        let button = NSButton(
            image: systemImage(named: ToolbarItemIdentifier.export.iconName, description: "Export"),
            target: ToolbarActionProxy.shared,
            action: #selector(ToolbarActionProxy.exportAction)
        )
        button.bezelStyle = .texturedRounded
        button.isBordered = true

        item.view = button
        item.isEnabled = (state.connectionState == .connected)

        return item
    }

    private func makeImportItem(state: ConnectionToolbarState) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarItemIdentifier.import.nsIdentifier)
        item.label = ToolbarItemIdentifier.import.label
        item.paletteLabel = ToolbarItemIdentifier.import.paletteLabel
        item.toolTip = ToolbarItemIdentifier.import.toolTip

        let button = NSButton(
            image: systemImage(named: ToolbarItemIdentifier.import.iconName, description: "Import"),
            target: ToolbarActionProxy.shared,
            action: #selector(ToolbarActionProxy.importAction)
        )
        button.bezelStyle = .texturedRounded
        button.isBordered = true

        item.view = button
        item.isEnabled = (state.connectionState == .connected)

        return item
    }

    private func makeInspectorItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarItemIdentifier.inspector.nsIdentifier)
        item.label = ToolbarItemIdentifier.inspector.label
        item.paletteLabel = ToolbarItemIdentifier.inspector.paletteLabel
        item.toolTip = ToolbarItemIdentifier.inspector.toolTip

        let button = NSButton(
            image: systemImage(named: ToolbarItemIdentifier.inspector.iconName, description: "Inspector"),
            target: ToolbarActionProxy.shared,
            action: #selector(ToolbarActionProxy.inspectorAction)
        )
        button.bezelStyle = .texturedRounded
        button.isBordered = true

        item.view = button
        item.isEnabled = true

        return item
    }
}

// MARK: - Action Proxy

/// Action proxy for toolbar buttons (follows target-action pattern)
/// Singleton that routes toolbar actions to NotificationCenter
@MainActor
@objc final class ToolbarActionProxy: NSObject {
    static let shared = ToolbarActionProxy()

    override private init() {
        super.init()
    }

    @objc func connectionSwitcherAction() {
        // TODO: Implement connection switcher UI
        // For now, just show welcome window
        NotificationCenter.default.post(name: .openWelcomeWindow, object: nil)
    }

    @objc func databaseSwitcherAction() {
        NotificationCenter.default.post(name: .openDatabaseSwitcher, object: nil)
    }

    @objc func newQueryTabAction() {
        NotificationCenter.default.post(name: .newTab, object: nil)
    }

    @objc func refreshAction() {
        NotificationCenter.default.post(name: .refreshData, object: nil)
    }

    @objc func filterToggleAction() {
        NotificationCenter.default.post(name: .toggleFilterPanel, object: nil)
    }

    @objc func historyToggleAction() {
        NotificationCenter.default.post(name: .toggleHistoryPanel, object: nil)
    }

    @objc func exportAction() {
        NotificationCenter.default.post(name: .exportTables, object: nil)
    }

    @objc func importAction() {
        NotificationCenter.default.post(name: .importTables, object: nil)
    }

    @objc func inspectorAction() {
        NotificationCenter.default.post(name: .toggleRightSidebar, object: nil)
    }
}
