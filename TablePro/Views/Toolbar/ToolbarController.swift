//
//  ToolbarController.swift
//  TablePro
//
//  Controller managing NSToolbar lifecycle and delegation.
//  Observes ConnectionToolbarState and updates toolbar items accordingly.
//

import AppKit
import Combine

/// Manages the window's NSToolbar
@MainActor
final class ToolbarController: NSObject, NSToolbarDelegate {
    // MARK: - Properties

    private let toolbar: NSToolbar
    private let factory: ToolbarItemFactory
    private let state: ConnectionToolbarState
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        identifier: NSToolbar.Identifier,
        factory: ToolbarItemFactory,
        state: ConnectionToolbarState
    ) {
        self.toolbar = NSToolbar(identifier: identifier)
        self.factory = factory
        self.state = state

        super.init()

        configureToolbar()
        observeState()
    }

    // MARK: - Configuration

    private func configureToolbar() {
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
    }

    /// Attach toolbar to window
    func attach(to window: NSWindow) {
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    // MARK: - State Observation

    private func observeState() {
        // Observe connection state changes
        state.$connectionState
            .sink { [weak self] _ in
                self?.updateToolbarItems()
            }
            .store(in: &cancellables)

        // Observe database type changes (affects database switcher availability)
        state.$databaseType
            .sink { [weak self] _ in
                self?.updateToolbarItems()
            }
            .store(in: &cancellables)

        // Observe execution state changes
        state.$isExecuting
            .sink { [weak self] _ in
                self?.updateToolbarItems()
            }
            .store(in: &cancellables)
    }

    private func updateToolbarItems() {
        // Force toolbar to re-validate items (updates enabled state)
        toolbar.validateVisibleItems()
    }

    // MARK: - NSToolbarDelegate

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        // Map NSToolbarItem.Identifier to our type-safe enum
        guard let identifier = ToolbarItemIdentifier(rawValue: itemIdentifier.rawValue) else {
            return nil
        }

        return factory.makeToolbarItem(identifier: identifier, state: state)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            ToolbarItemIdentifier.databaseSwitcher.nsIdentifier,
            ToolbarItemIdentifier.newQueryTab.nsIdentifier,
            ToolbarItemIdentifier.refresh.nsIdentifier,
            .flexibleSpace,
            ToolbarItemIdentifier.connectionStatus.nsIdentifier,
            .flexibleSpace,
            ToolbarItemIdentifier.filterToggle.nsIdentifier,
            ToolbarItemIdentifier.historyToggle.nsIdentifier,
            .space,
            ToolbarItemIdentifier.export.nsIdentifier,
            ToolbarItemIdentifier.import.nsIdentifier,
            .space,
            ToolbarItemIdentifier.inspector.nsIdentifier
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // All our custom items plus standard system items
        ToolbarItemIdentifier.allCases.map(\.nsIdentifier) + [
            .space,
            .flexibleSpace,
            .print
        ]
    }

    func toolbarWillAddItem(_ notification: Notification) {
        // Optional: Track when items are added
    }

    func toolbarDidRemoveItem(_ notification: Notification) {
        // Optional: Track when items are removed
    }

    // MARK: - Validation

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        // Determine enabled state based on toolbar item identifier
        guard let identifier = ToolbarItemIdentifier(rawValue: item.itemIdentifier.rawValue) else {
            return true
        }

        switch identifier {
        case .connectionSwitcher:
            // Always enabled (can switch even when disconnected)
            return true

        case .databaseSwitcher:
            // Only enabled when connected and not SQLite
            return state.connectionState == .connected && state.databaseType != .sqlite

        case .newQueryTab:
            // Always enabled
            return true

        case .refresh:
            // Only enabled when connected
            return state.connectionState == .connected

        case .connectionStatus:
            // Always visible (shows status even when disconnected)
            return true

        case .filterToggle, .historyToggle:
            // Always enabled (can toggle panels anytime)
            return true

        case .export, .import:
            // Only enabled when connected
            return state.connectionState == .connected

        case .inspector:
            // Always enabled
            return true
        }
    }
}
