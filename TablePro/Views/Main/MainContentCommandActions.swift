//
//  MainContentCommandActions.swift
//  TablePro
//
//  Provides command actions for MainContentView, accessible via @FocusedObject.
//  Menu commands and toolbar buttons call methods directly instead of posting notifications.
//  Retains NotificationCenter subscribers only for legitimate multi-listener broadcasts.
//

import AppKit
import Combine
import Foundation
import os
import SwiftUI
import UniformTypeIdentifiers

/// Provides command actions for MainContentView, accessible via @FocusedObject
@MainActor
final class MainContentCommandActions: ObservableObject {
    nonisolated private static let logger = Logger(subsystem: "com.TablePro", category: "MainContentCommandActions")

    // MARK: - Dependencies

    private weak var coordinator: MainContentCoordinator?
    private let filterStateManager: FilterStateManager
    private let connection: DatabaseConnection

    // MARK: - Bindings

    private let selectedRowIndices: Binding<Set<Int>>
    private let selectedTables: Binding<Set<TableInfo>>
    private let pendingTruncates: Binding<Set<String>>
    private let pendingDeletes: Binding<Set<String>>
    private let tableOperationOptions: Binding<[String: TableOperationOptions]>
    private let rightPanelState: RightPanelState
    private let editingCell: Binding<CellPosition?>

    // MARK: - State

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        coordinator: MainContentCoordinator,
        filterStateManager: FilterStateManager,
        connection: DatabaseConnection,
        selectedRowIndices: Binding<Set<Int>>,
        selectedTables: Binding<Set<TableInfo>>,
        pendingTruncates: Binding<Set<String>>,
        pendingDeletes: Binding<Set<String>>,
        tableOperationOptions: Binding<[String: TableOperationOptions]>,
        rightPanelState: RightPanelState,
        editingCell: Binding<CellPosition?>
    ) {
        self.coordinator = coordinator
        self.filterStateManager = filterStateManager
        self.connection = connection
        self.selectedRowIndices = selectedRowIndices
        self.selectedTables = selectedTables
        self.pendingTruncates = pendingTruncates
        self.pendingDeletes = pendingDeletes
        self.tableOperationOptions = tableOperationOptions
        self.rightPanelState = rightPanelState
        self.editingCell = editingCell

        setupSaveAction()
        setupObservers()
    }

    // MARK: - Save Action

    private func setupSaveAction() {
        rightPanelState.onSave = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                do {
                    try await self.coordinator?.saveSidebarEdits(
                        selectedRowIndices: self.selectedRowIndices.wrappedValue,
                        editState: self.rightPanelState.editState
                    )
                } catch {
                    AlertHelper.showErrorSheet(
                        title: String(localized: "Failed to Save Changes"),
                        message: error.localizedDescription,
                        window: nil
                    )
                }
            }
        }
    }

    // MARK: - Observer Setup

    private func setupObservers() {
        setupNonMenuNotificationObservers()
        setupFilterBroadcastObservers()
        setupDataBroadcastObservers()
        setupTabBroadcastObservers()
        setupDatabaseBroadcastObservers()
        setupUIBroadcastObservers()
        setupWindowObservers()
        setupFileOpenObservers()
        setupReconnectObservers()
    }

    /// Subscribers for notifications still posted by non-menu views (DataGrid, SidebarView,
    /// context menus, QueryEditorView, ConnectionStatusView). These bridge AppKit/non-menu
    /// notification posts to the same command action methods used by @FocusedObject callers.
    private func setupNonMenuNotificationObservers() {
        NotificationCenter.default.publisher(for: .addNewRow)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.addNewRow() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .deleteSelectedRows)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let directIndices = notification.userInfo?["rowIndices"] as? Set<Int>
                self?.deleteSelectedRows(rowIndices: directIndices)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .duplicateRow)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.duplicateRow() }
            .store(in: &cancellables)

        // Note: .copySelectedRows and .pasteRows subscribers call the data-grid
        // path directly (not the public methods) to avoid an infinite loop —
        // the public methods re-post these notifications for structure view.
        NotificationCenter.default.publisher(for: .copySelectedRows)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let indices = self.selectedRowIndices.wrappedValue
                self.coordinator?.copySelectedRowsToClipboard(indices: indices)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pasteRows)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                var indices = self.selectedRowIndices.wrappedValue
                var cell = self.editingCell.wrappedValue
                self.coordinator?.pasteRows(selectedRowIndices: &indices, editingCell: &cell)
                self.selectedRowIndices.wrappedValue = indices
                self.editingCell.wrappedValue = cell
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .createTable)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.createTable() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .createView)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.createView() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .exportTables)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.exportTables() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .importTables)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.importTables() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .explainQuery)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.explainQuery() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .openDatabaseSwitcher)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.openDatabaseSwitcher() }
            .store(in: &cancellables)
    }

    // MARK: - Row Operations (Group A — Called Directly)

    func addNewRow() {
        var indices = selectedRowIndices.wrappedValue
        var cell = editingCell.wrappedValue
        coordinator?.addNewRow(selectedRowIndices: &indices, editingCell: &cell)
        selectedRowIndices.wrappedValue = indices
        editingCell.wrappedValue = cell
    }

    func deleteSelectedRows(rowIndices: Set<Int>? = nil) {
        // When rowIndices is provided (from data grid), use them directly
        // This avoids relying on SwiftUI binding sync timing
        let fromDataGrid = rowIndices != nil

        let indices = rowIndices ?? selectedRowIndices.wrappedValue
        if !indices.isEmpty {
            var mutableIndices = indices
            coordinator?.deleteSelectedRows(indices: indices, selectedRowIndices: &mutableIndices)
            selectedRowIndices.wrappedValue = mutableIndices
        } else if !fromDataGrid, !selectedTables.wrappedValue.isEmpty {
            // Only toggle table deletion when the call did NOT originate from
            // the data grid (e.g., from the app menu Cmd+Delete with no rows selected)
            var updatedDeletes = pendingDeletes.wrappedValue
            var updatedTruncates = pendingTruncates.wrappedValue

            for table in selectedTables.wrappedValue {
                updatedTruncates.remove(table.name)
                if updatedDeletes.contains(table.name) {
                    updatedDeletes.remove(table.name)
                } else {
                    updatedDeletes.insert(table.name)
                }
            }

            pendingTruncates.wrappedValue = updatedTruncates
            pendingDeletes.wrappedValue = updatedDeletes
        }
    }

    func duplicateRow() {
        let indices = selectedRowIndices.wrappedValue
        guard let selectedIndex = indices.first, indices.count == 1 else { return }

        var mutableIndices = indices
        var cell = editingCell.wrappedValue
        coordinator?.duplicateSelectedRow(index: selectedIndex, selectedRowIndices: &mutableIndices, editingCell: &cell)
        selectedRowIndices.wrappedValue = mutableIndices
        editingCell.wrappedValue = cell
    }

    func copySelectedRows() {
        if coordinator?.tabManager.selectedTab?.showStructure == true {
            NotificationCenter.default.post(name: .copySelectedRows, object: nil)
        } else {
            let indices = selectedRowIndices.wrappedValue
            coordinator?.copySelectedRowsToClipboard(indices: indices)
        }
    }

    func copySelectedRowsWithHeaders() {
        let indices = selectedRowIndices.wrappedValue
        coordinator?.copySelectedRowsWithHeaders(indices: indices)
    }

    func pasteRows() {
        if coordinator?.tabManager.selectedTab?.showStructure == true {
            NotificationCenter.default.post(name: .pasteRows, object: nil)
        } else {
            var indices = selectedRowIndices.wrappedValue
            var cell = editingCell.wrappedValue
            coordinator?.pasteRows(selectedRowIndices: &indices, editingCell: &cell)
            selectedRowIndices.wrappedValue = indices
            editingCell.wrappedValue = cell
        }
    }

    // MARK: - Tab Operations (Group A — Called Directly)

    func newTab() {
        guard let coordinator = coordinator else { return }
        let lastQuery = coordinator.tabPersistence.loadLastQuery()
        coordinator.tabManager.addTab(initialQuery: lastQuery)
    }

    func closeCurrentTab() {
        coordinator?.handleCloseAction()
    }

    func createTable() {
        guard !connection.isReadOnly, let coordinator = coordinator else { return }

        // Get current database name from the connection
        let currentDatabase = connection.database

        coordinator.tabManager.addCreateTableTab(
            databaseName: currentDatabase,
            databaseType: connection.type
        )
    }

    func createView() {
        guard !connection.isReadOnly, let coordinator = coordinator else { return }

        let template: String
        switch connection.type {
        case .postgresql:
            template = "CREATE OR REPLACE VIEW view_name AS\nSELECT column1, column2\nFROM table_name\nWHERE condition;"
        case .mysql, .mariadb:
            template = "CREATE VIEW view_name AS\nSELECT column1, column2\nFROM table_name\nWHERE condition;"
        case .sqlite:
            template = "CREATE VIEW IF NOT EXISTS view_name AS\nSELECT column1, column2\nFROM table_name\nWHERE condition;"
        }

        coordinator.tabManager.addTab(
            initialQuery: template,
            title: "New View"
        )
    }

    // MARK: - Tab Navigation (Group A — Called Directly)

    func selectTab(number: Int) {
        guard let tabManager = coordinator?.tabManager else { return }
        let index = number - 1
        if index >= 0, index < tabManager.tabs.count {
            performDirectTabSwitch(to: tabManager.tabs[index])
        }
    }

    func previousTab() {
        guard let tabManager = coordinator?.tabManager,
              let current = tabManager.selectedTabIndex,
              current > 0 else { return }
        let target = tabManager.tabs[current - 1]
        TabOpenTimingLogger.shared.markTrigger(
            source: "keyboard:prevTab→\(target.tableName ?? target.title)"
        )
        performDirectTabSwitch(to: target)
    }

    func nextTab() {
        guard let tabManager = coordinator?.tabManager,
              let current = tabManager.selectedTabIndex,
              current + 1 < tabManager.tabs.count else { return }
        let target = tabManager.tabs[current + 1]
        TabOpenTimingLogger.shared.markTrigger(
            source: "keyboard:nextTab→\(target.tableName ?? target.title)"
        )
        performDirectTabSwitch(to: target)
    }

    /// Perform a direct tab switch bypassing the SwiftUI .onChange delay.
    /// Calls handleTabChange synchronously, then sets selectedTabId for UI update.
    private func performDirectTabSwitch(to target: QueryTab) {
        guard let coordinator = coordinator else { return }
        let tabManager = coordinator.tabManager

        // Skip if already on this tab
        guard tabManager.selectedTabId != target.id else { return }

        let oldTabId = tabManager.selectedTabId

        // Set selectedTabId FIRST so that selectedTabIndex is correct inside
        // handleTabChange (executeTableTabQueryDirectly uses selectedTabIndex).
        // Set skip flag before selectedTabId to prevent .onChange from re-doing the work.
        coordinator.skipNextTabChangeOnChange = true
        tabManager.selectedTabId = target.id

        // Call handleTabChange directly (synchronous — no SwiftUI scheduling delay)
        var selectedRowIndices = selectedRowIndices.wrappedValue
        coordinator.handleTabChange(
            from: oldTabId,
            to: target.id,
            selectedRowIndices: &selectedRowIndices,
            tabs: tabManager.tabs
        )
        self.selectedRowIndices.wrappedValue = selectedRowIndices

        // Dismiss autocomplete windows
        NotificationCenter.default.post(name: NSNotification.Name("QueryTabDidChange"), object: nil)

        // Persist tab selection
        if !coordinator.tabPersistence.isRestoringTabs,
           !coordinator.tabPersistence.isDismissing {
            if let sessionId = DatabaseManager.shared.currentSessionId {
                DatabaseManager.shared.updateSession(sessionId) { session in
                    session.selectedTabId = target.id
                }
                coordinator.tabPersistence.saveTabsAsync(
                    tabs: tabManager.tabs,
                    selectedTabId: target.id
                )
            }
        }
    }

    // MARK: - Filter Operations (Group A — Called Directly)

    func toggleFilterPanel() {
        guard let coordinator = coordinator,
              coordinator.tabManager.selectedTab?.tabType == .table else { return }
        filterStateManager.toggle()
    }

    // MARK: - Data Operations (Group A — Called Directly)

    func saveChanges() {
        // Check if we're in structure view mode
        if coordinator?.tabManager.selectedTab?.showStructure == true {
            // Post notification for structure view to handle
            NotificationCenter.default.post(name: .saveStructureChanges, object: nil)
        } else {
            // Handle data grid changes
            var truncates = pendingTruncates.wrappedValue
            var deletes = pendingDeletes.wrappedValue
            var options = tableOperationOptions.wrappedValue
            coordinator?.saveChanges(
                pendingTruncates: &truncates,
                pendingDeletes: &deletes,
                tableOperationOptions: &options
            )
            pendingTruncates.wrappedValue = truncates
            pendingDeletes.wrappedValue = deletes
            tableOperationOptions.wrappedValue = options
        }
    }

    func explainQuery() {
        coordinator?.runExplainQuery()
    }

    func exportTables() {
        coordinator?.showExportDialog = true
    }

    func importTables() {
        guard !connection.isReadOnly else { return }
        // Open file picker first, then show dialog with selected file
        let panel = NSOpenPanel()
        var contentTypes: [UTType] = []
        if let sqlType = UTType(filenameExtension: "sql") {
            contentTypes.append(sqlType)
        }
        if let gzType = UTType(filenameExtension: "gz") {
            contentTypes.append(gzType)
        }
        if !contentTypes.isEmpty {
            panel.allowedContentTypes = contentTypes
        }
        panel.allowsMultipleSelection = false
        panel.message = "Select SQL file to import"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }

            // Store the selected file URL and show dialog
            self?.coordinator?.importFileURL = url
            self?.coordinator?.showImportDialog = true
        }
    }

    func previewSQL() {
        coordinator?.handlePreviewSQL(
            pendingTruncates: pendingTruncates.wrappedValue,
            pendingDeletes: pendingDeletes.wrappedValue,
            tableOperationOptions: tableOperationOptions.wrappedValue
        )
    }

    // MARK: - UI Operations (Group A — Called Directly)

    func toggleHistoryPanel() {
        AppState.shared.isHistoryPanelVisible.toggle()
    }

    func toggleRightSidebar() {
        rightPanelState.isPresented.toggle()
    }

    // MARK: - Database Operations (Group A — Called Directly)

    func openDatabaseSwitcher() {
        coordinator?.showDatabaseSwitcher = true
    }

    // MARK: - Undo/Redo (Group A — Called Directly)

    func undoChange() {
        if coordinator?.tabManager.selectedTab?.showStructure == true {
            NotificationCenter.default.post(name: .undoChange, object: nil)
        } else {
            var indices = selectedRowIndices.wrappedValue
            coordinator?.undoLastChange(selectedRowIndices: &indices)
            selectedRowIndices.wrappedValue = indices
        }
    }

    func redoChange() {
        if coordinator?.tabManager.selectedTab?.showStructure == true {
            NotificationCenter.default.post(name: .redoChange, object: nil)
        } else {
            coordinator?.redoLastChange()
        }
    }

    // MARK: - Group B Broadcast Subscribers

    // MARK: Filter Broadcasts

    private func setupFilterBroadcastObservers() {
        NotificationCenter.default.publisher(for: .applyAllFilters)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleApplyAllFilters()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .duplicateFilter)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleDuplicateFilter()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .removeFilter)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleRemoveFilter()
            }
            .store(in: &cancellables)
    }

    private func handleApplyAllFilters() {
        if filterStateManager.hasSelectedFilters {
            filterStateManager.applySelectedFilters()
            coordinator?.applyFilters(filterStateManager.appliedFilters)
        }
    }

    private func handleDuplicateFilter() {
        if filterStateManager.isVisible, let focusedFilter = filterStateManager.focusedFilter {
            filterStateManager.duplicateFilter(focusedFilter)
        }
    }

    private func handleRemoveFilter() {
        if filterStateManager.isVisible, let focusedFilter = filterStateManager.focusedFilter {
            filterStateManager.removeFilter(focusedFilter)
        }
    }

    // MARK: Data Broadcasts

    private func setupDataBroadcastObservers() {
        NotificationCenter.default.publisher(for: .refreshData)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleRefreshData()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .refreshAll)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleRefreshAll()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .showTableStructure)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let tableName = notification.object as? String {
                    self?.coordinator?.openTableTab(tableName, showStructure: true)
                }
            }
            .store(in: &cancellables)
    }

    private func handleRefreshData() {
        let hasPendingTableOps = !pendingTruncates.wrappedValue.isEmpty || !pendingDeletes.wrappedValue.isEmpty
        coordinator?.handleRefresh(
            hasPendingTableOps: hasPendingTableOps,
            onDiscard: { [weak self] in
                self?.pendingTruncates.wrappedValue.removeAll()
                self?.pendingDeletes.wrappedValue.removeAll()
            }
        )
    }

    private func handleRefreshAll() {
        let hasPendingTableOps = !pendingTruncates.wrappedValue.isEmpty || !pendingDeletes.wrappedValue.isEmpty
        coordinator?.handleRefreshAll(
            hasPendingTableOps: hasPendingTableOps,
            onDiscard: { [weak self] in
                self?.pendingTruncates.wrappedValue.removeAll()
                self?.pendingDeletes.wrappedValue.removeAll()
            }
        )
    }

    // MARK: Tab Broadcasts

    private func setupTabBroadcastObservers() {
        NotificationCenter.default.publisher(for: .newQueryTab)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.newTab() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .loadQueryIntoEditor)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleLoadQueryIntoEditor(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .insertQueryFromAI)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleInsertQueryFromAI(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .tableTabClosed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleTableTabClosed(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .showAllTables)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.coordinator?.showAllTablesMetadata()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .editViewDefinition)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let viewName = notification.object as? String {
                    self?.handleEditViewDefinition(viewName)
                }
            }
            .store(in: &cancellables)
    }

    private func handleLoadQueryIntoEditor(_ notification: Notification) {
        guard let query = notification.object as? String,
              let coordinator = coordinator else { return }

        // Check if current tab is a query tab
        if let tabIndex = coordinator.tabManager.selectedTabIndex,
           tabIndex < coordinator.tabManager.tabs.count,
           coordinator.tabManager.tabs[tabIndex].tabType == .query {
            coordinator.tabManager.tabs[tabIndex].query = query
            coordinator.tabManager.tabs[tabIndex].hasUserInteraction = true
        } else {
            // Create a new query tab and load the query into it
            self.newTab()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let newIndex = coordinator.tabManager.selectedTabIndex,
                   newIndex < coordinator.tabManager.tabs.count {
                    coordinator.tabManager.tabs[newIndex].query = query
                    coordinator.tabManager.tabs[newIndex].hasUserInteraction = true
                }
            }
        }
    }

    private func handleInsertQueryFromAI(_ notification: Notification) {
        guard let query = notification.object as? String,
              let coordinator = coordinator else { return }

        // Find or create a query tab
        if let tabIndex = coordinator.tabManager.selectedTabIndex,
           tabIndex < coordinator.tabManager.tabs.count,
           coordinator.tabManager.tabs[tabIndex].tabType == .query {
            // Append to existing query tab with separator
            let existingQuery = coordinator.tabManager.tabs[tabIndex].query
            if existingQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                coordinator.tabManager.tabs[tabIndex].query = query
            } else {
                coordinator.tabManager.tabs[tabIndex].query = existingQuery + "\n\n" + query
            }
            coordinator.tabManager.tabs[tabIndex].hasUserInteraction = true
        } else {
            // No query tab selected — create a new one
            coordinator.tabManager.addTab(initialQuery: query)
        }
    }

    private func handleTableTabClosed(_ notification: Notification) {
        if let tableName = notification.object as? String {
            selectedTables.wrappedValue = selectedTables.wrappedValue.filter { $0.name != tableName }
        }
    }

    private func handleEditViewDefinition(_ viewName: String) {
        guard let coordinator = coordinator else { return }

        Task { @MainActor in
            do {
                guard let driver = DatabaseManager.shared.activeDriver else { return }
                let definition = try await driver.fetchViewDefinition(view: viewName)

                coordinator.tabManager.addTab(
                    initialQuery: definition,
                    title: "View: \(viewName)"
                )
            } catch {
                // Open tab with a basic ALTER template on failure
                let fallbackSQL: String
                switch connection.type {
                case .postgresql:
                    fallbackSQL = "CREATE OR REPLACE VIEW \(viewName) AS\n-- Could not fetch view definition: \(error.localizedDescription)\nSELECT * FROM table_name;"
                case .mysql, .mariadb:
                    fallbackSQL = "ALTER VIEW \(viewName) AS\n-- Could not fetch view definition: \(error.localizedDescription)\nSELECT * FROM table_name;"
                case .sqlite:
                    fallbackSQL = "-- SQLite does not support ALTER VIEW. Drop and recreate:\nDROP VIEW IF EXISTS \(viewName);\nCREATE VIEW \(viewName) AS\nSELECT * FROM table_name;"
                }

                coordinator.tabManager.addTab(
                    initialQuery: fallbackSQL,
                    title: "View: \(viewName)"
                )
            }
        }
    }

    // MARK: Database Broadcasts

    private func setupDatabaseBroadcastObservers() {
        NotificationCenter.default.publisher(for: .databaseDidConnect)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleDatabaseDidConnect()
            }
            .store(in: &cancellables)
    }

    private func handleDatabaseDidConnect() {
        Task { @MainActor in
            await coordinator?.loadSchema()
            if let driver = DatabaseManager.shared.activeDriver {
                coordinator?.toolbarState.databaseVersion = driver.serverVersion
            }
        }
    }

    // MARK: UI Broadcasts

    private func setupUIBroadcastObservers() {
        NotificationCenter.default.publisher(for: .clearSelection)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleClearSelection()
            }
            .store(in: &cancellables)
    }

    private func handleClearSelection() {
        selectedRowIndices.wrappedValue.removeAll()
        selectedTables.wrappedValue.removeAll()
        if filterStateManager.isVisible {
            filterStateManager.close()
        }
    }

    // MARK: Window Broadcasts

    private func setupWindowObservers() {
        NotificationCenter.default.publisher(for: .mainWindowWillClose)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let coordinator = self?.coordinator else { return }
                coordinator.tabPersistence.handleWindowClose(
                    tabs: coordinator.tabManager.tabs,
                    selectedTabId: coordinator.tabManager.selectedTabId
                )
            }
            .store(in: &cancellables)
    }

    // MARK: File Open Broadcasts

    private func setupFileOpenObservers() {
        NotificationCenter.default.publisher(for: .openSQLFiles)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleOpenSQLFiles(notification)
            }
            .store(in: &cancellables)
    }

    private func handleOpenSQLFiles(_ notification: Notification) {
        guard let urls = notification.object as? [URL],
              let coordinator = coordinator else { return }

        Task { @MainActor in
            for url in urls {
                let content = await Task.detached(priority: .userInitiated) { () -> String? in
                    do {
                        return try String(contentsOf: url, encoding: .utf8)
                    } catch {
                        Self.logger.error("Failed to read \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        return nil
                    }
                }.value

                if let content {
                    coordinator.tabManager.addTab(
                        initialQuery: content,
                        title: url.lastPathComponent
                    )
                }
            }
        }
    }

    // MARK: Reconnect Broadcasts

    private func setupReconnectObservers() {
        NotificationCenter.default.publisher(for: .reconnectDatabase)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleReconnect()
            }
            .store(in: &cancellables)
    }

    private func handleReconnect() {
        Task { @MainActor in
            await DatabaseManager.shared.reconnectCurrentSession()
        }
    }
}
