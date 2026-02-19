//
//  MainContentNotificationHandler.swift
//  TablePro
//
//  Consolidates all notification handlers for MainContentView.
//  Uses Combine for cleaner subscription management.
//

import AppKit
import Combine
import Foundation
import os
import SwiftUI
import UniformTypeIdentifiers

/// Handles all NotificationCenter subscriptions for MainContentView
@MainActor
final class MainContentNotificationHandler: ObservableObject {
    nonisolated private static let logger = Logger(subsystem: "com.TablePro", category: "MainContentNotificationHandler")

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
        setupRowOperationObservers()
        setupTabOperationObservers()
        setupTabNavigationObservers()
        setupFilterOperationObservers()
        setupDataOperationObservers()
        setupUIOperationObservers()
        setupDatabaseOperationObservers()
        setupUndoRedoObservers()
        setupWindowObservers()
        setupFileOpenObservers()
        setupReconnectObservers()
    }

    // MARK: - Row Operations

    private func setupRowOperationObservers() {
        NotificationCenter.default.publisher(for: .addNewRow)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleAddNewRow()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .deleteSelectedRows)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleDeleteSelectedRows(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .duplicateRow)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleDuplicateRow()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .copySelectedRows)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleCopySelectedRows()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .copySelectedRowsWithHeaders)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleCopySelectedRowsWithHeaders()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pasteRows)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handlePasteRows()
            }
            .store(in: &cancellables)
    }

    private func handleAddNewRow() {
        var indices = selectedRowIndices.wrappedValue
        var cell = editingCell.wrappedValue
        coordinator?.addNewRow(selectedRowIndices: &indices, editingCell: &cell)
        selectedRowIndices.wrappedValue = indices
        editingCell.wrappedValue = cell
    }

    private func handleDeleteSelectedRows(_ notification: Notification) {
        // Check if the notification carries row indices directly (from data grid)
        // This avoids relying on SwiftUI binding sync timing
        let directIndices = notification.userInfo?["rowIndices"] as? Set<Int>
        let fromDataGrid = directIndices != nil

        let indices = directIndices ?? selectedRowIndices.wrappedValue
        if !indices.isEmpty {
            var mutableIndices = indices
            coordinator?.deleteSelectedRows(indices: indices, selectedRowIndices: &mutableIndices)
            selectedRowIndices.wrappedValue = mutableIndices
        } else if !fromDataGrid, !selectedTables.wrappedValue.isEmpty {
            // Only toggle table deletion when the notification did NOT originate from
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

    private func handleDuplicateRow() {
        let indices = selectedRowIndices.wrappedValue
        guard let selectedIndex = indices.first, indices.count == 1 else { return }

        var mutableIndices = indices
        var cell = editingCell.wrappedValue
        coordinator?.duplicateSelectedRow(index: selectedIndex, selectedRowIndices: &mutableIndices, editingCell: &cell)
        selectedRowIndices.wrappedValue = mutableIndices
        editingCell.wrappedValue = cell
    }

    private func handleCopySelectedRows() {
        let indices = selectedRowIndices.wrappedValue
        coordinator?.copySelectedRowsToClipboard(indices: indices)
    }

    private func handleCopySelectedRowsWithHeaders() {
        let indices = selectedRowIndices.wrappedValue
        coordinator?.copySelectedRowsWithHeaders(indices: indices)
    }

    private func handlePasteRows() {
        var indices = selectedRowIndices.wrappedValue
        var cell = editingCell.wrappedValue
        coordinator?.pasteRows(selectedRowIndices: &indices, editingCell: &cell)
        selectedRowIndices.wrappedValue = indices
        editingCell.wrappedValue = cell
    }

    // MARK: - Tab Operations

    private func setupTabOperationObservers() {
        NotificationCenter.default.publisher(for: .newTab)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleNewTab()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .closeCurrentTab)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.coordinator?.handleCloseAction()
            }
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

        NotificationCenter.default.publisher(for: .createTable)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleCreateTable()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .createView)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleCreateView()
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

    private func handleNewTab() {
        guard let coordinator = coordinator else { return }
        let lastQuery = coordinator.tabPersistence.loadLastQuery()
        coordinator.tabManager.addTab(initialQuery: lastQuery)
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
            NotificationCenter.default.post(name: .newTab, object: nil)
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

    private func handleCreateTable() {
        guard !connection.isReadOnly, let coordinator = coordinator else { return }

        // Get current database name from the connection
        let currentDatabase = connection.database

        coordinator.tabManager.addCreateTableTab(
            databaseName: currentDatabase,
            databaseType: connection.type
        )
    }

    private func handleCreateView() {
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

    private func handleEditViewDefinition(_ viewName: String) {
        guard let coordinator = coordinator else { return }

        Task {
            do {
                guard let driver = DatabaseManager.shared.activeDriver else { return }
                let definition = try await driver.fetchViewDefinition(view: viewName)

                await MainActor.run {
                    coordinator.tabManager.addTab(
                        initialQuery: definition,
                        title: "View: \(viewName)"
                    )
                }
            } catch {
                await MainActor.run {
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
    }

    // MARK: - Tab Navigation

    private func setupTabNavigationObservers() {
        // Cmd+1-9: Select tab by number
        NotificationCenter.default.publisher(for: .selectTabByNumber)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let number = notification.object as? Int,
                      let tabManager = self?.coordinator?.tabManager else { return }
                let index = number - 1
                if index >= 0, index < tabManager.tabs.count {
                    tabManager.selectTab(tabManager.tabs[index])
                }
            }
            .store(in: &cancellables)

        // Cmd+Shift+[ or Cmd+Option+Left: Previous tab
        NotificationCenter.default.publisher(for: .previousTab)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let tabManager = self?.coordinator?.tabManager,
                      let current = tabManager.selectedTabIndex,
                      current > 0 else { return }
                tabManager.selectTab(tabManager.tabs[current - 1])
            }
            .store(in: &cancellables)

        // Cmd+Shift+] or Cmd+Option+Right: Next tab
        NotificationCenter.default.publisher(for: .nextTab)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let tabManager = self?.coordinator?.tabManager,
                      let current = tabManager.selectedTabIndex,
                      current + 1 < tabManager.tabs.count else { return }
                tabManager.selectTab(tabManager.tabs[current + 1])
            }
            .store(in: &cancellables)
    }

    // MARK: - Filter Operations

    private func setupFilterOperationObservers() {
        NotificationCenter.default.publisher(for: .toggleFilterPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let coordinator = self?.coordinator,
                      coordinator.tabManager.selectedTab?.tabType == .table else { return }
                self?.filterStateManager.toggle()
            }
            .store(in: &cancellables)

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

    // MARK: - Data Operations

    private func setupDataOperationObservers() {
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

        NotificationCenter.default.publisher(for: .saveChanges)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSaveChanges()
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

        NotificationCenter.default.publisher(for: .explainQuery)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.coordinator?.runExplainQuery()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .exportTables)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleExportTables()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .importTables)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleImportTables()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .previewSQL)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handlePreviewSQL()
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

    private func handlePreviewSQL() {
        coordinator?.handlePreviewSQL(
            pendingTruncates: pendingTruncates.wrappedValue,
            pendingDeletes: pendingDeletes.wrappedValue,
            tableOperationOptions: tableOperationOptions.wrappedValue
        )
    }

    private func handleSaveChanges() {
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

    private func handleExportTables() {
        coordinator?.showExportDialog = true
    }

    private func handleImportTables() {
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

    // MARK: - UI Operations

    private func setupUIOperationObservers() {
        NotificationCenter.default.publisher(for: .clearSelection)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleClearSelection()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .toggleHistoryPanel)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                AppState.shared.isHistoryPanelVisible.toggle()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .toggleRightSidebar)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleToggleRightSidebar()
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

    private func handleToggleRightSidebar() {
        rightPanelState.isPresented.toggle()
    }

    // MARK: - Database Operations

    private func setupDatabaseOperationObservers() {
        NotificationCenter.default.publisher(for: .databaseDidConnect)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleDatabaseDidConnect()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .openDatabaseSwitcher)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.coordinator?.showDatabaseSwitcher = true
            }
            .store(in: &cancellables)
    }

    private func handleDatabaseDidConnect() {
        Task {
            await coordinator?.loadSchema()
            if let driver = DatabaseManager.shared.activeDriver {
                coordinator?.toolbarState.databaseVersion = driver.serverVersion
            }
        }
    }

    // MARK: - Undo/Redo

    private func setupUndoRedoObservers() {
        NotificationCenter.default.publisher(for: .undoChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                var indices = self?.selectedRowIndices.wrappedValue ?? []
                self?.coordinator?.undoLastChange(selectedRowIndices: &indices)
                self?.selectedRowIndices.wrappedValue = indices
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .redoChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.coordinator?.redoLastChange()
            }
            .store(in: &cancellables)
    }

    // MARK: - File Open Operations

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

        Task {
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

    // MARK: - Window Operations

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

    // MARK: - Reconnect Operations

    private func setupReconnectObservers() {
        NotificationCenter.default.publisher(for: .reconnectDatabase)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleReconnect()
            }
            .store(in: &cancellables)
    }

    private func handleReconnect() {
        Task {
            await DatabaseManager.shared.reconnectCurrentSession()
        }
    }
}
