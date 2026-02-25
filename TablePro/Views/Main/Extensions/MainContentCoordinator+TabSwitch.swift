//
//  MainContentCoordinator+TabSwitch.swift
//  TablePro
//
//  Tab switching logic extracted from MainContentCoordinator
//  to keep the main class body within SwiftLint limits.
//

import Foundation

extension MainContentCoordinator {
    /// Performs a direct tab switch bypassing SwiftUI .onChange scheduling delay.
    /// Called from tab bar clicks and keyboard shortcuts.
    func performDirectTabSwitch(to tab: QueryTab, selectedRowIndices: inout Set<Int>) {
        guard tabManager.selectedTabId != tab.id else { return }

        let oldTabId = tabManager.selectedTabId
        skipNextTabChangeOnChange = true
        tabManager.selectedTabId = tab.id

        handleTabChange(from: oldTabId, to: tab.id,
                        selectedRowIndices: &selectedRowIndices, tabs: tabManager.tabs)

        NotificationCenter.default.post(name: NSNotification.Name("QueryTabDidChange"), object: nil)

        guard !tabPersistence.isRestoringTabs, !tabPersistence.isDismissing,
              let sessionId = DatabaseManager.shared.currentSessionId else { return }
        DatabaseManager.shared.updateSession(sessionId) { session in
            session.selectedTabId = tab.id
        }
        tabPersistence.saveTabsAsync(tabs: tabManager.tabs, selectedTabId: tab.id)
    }

    func handleTabChange(
        from oldTabId: UUID?,
        to newTabId: UUID?,
        selectedRowIndices: inout Set<Int>,
        tabs: [QueryTab]
    ) {
        isHandlingTabSwitch = true
        defer { isHandlingTabSwitch = false }

        // Debounce flush: skip if less than 100ms since last save to avoid
        // redundant synchronous work during rapid tab switching.
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastFlushTime >= 0.1 {
            tabPersistence.flushPendingSave(tabs: tabs, selectedTabId: tabManager.selectedTabId)
            lastFlushTime = now
        }

        if let oldId = oldTabId,
           let oldIndex = tabManager.tabs.firstIndex(where: { $0.id == oldId }) {
            // Save change state to separate dictionary to avoid CoW on QueryTab struct
            if changeManager.hasChanges {
                tabPendingChanges[oldId] = changeManager.saveState()
            } else {
                tabPendingChanges.removeValue(forKey: oldId)
            }
            tabSelectionCache[oldId] = selectedRowIndices
        }

        if let newId = newTabId,
           let newIndex = tabManager.tabs.firstIndex(where: { $0.id == newId }) {
            let newTab = tabManager.tabs[newIndex]

            selectedRowIndices = tabSelectionCache[newId] ?? newTab.selectedRowIndices
            AppState.shared.isCurrentTabEditable = newTab.isEditable && !newTab.isView && newTab.tableName != nil
            toolbarState.isTableTab = newTab.tabType == .table

            // Configure change manager without triggering reload yet — we'll fire a single
            // reloadVersion bump below after everything is set up.
            // Check separate dictionary first, then fall back to tab's pendingChanges for backward compat
            let pendingState = tabPendingChanges[newId] ?? newTab.pendingChanges
            if pendingState.hasChanges {
                changeManager.restoreState(from: pendingState, tableName: newTab.tableName ?? "")
            } else {
                changeManager.configureForTable(
                    tableName: newTab.tableName ?? "",
                    columns: newTab.resultColumns,
                    primaryKeyColumn: newTab.primaryKeyColumn ?? newTab.resultColumns.first,
                    databaseType: connection.type,
                    triggerReload: false
                )
            }

            // Defer reloadVersion bump — only needed when we won't run a query.
            // When a query runs, executeQueryInternal Phase 1 sets new result data
            // that triggers its own SwiftUI update; bumping beforehand causes a
            // redundant re-evaluation that blocks the Task executor (15-40ms).

            // Defer async operations (database switch, lazy load) to avoid blocking
            let shouldSkipLazyLoad = tabPersistence.justRestoredTab
            tabPersistence.clearJustRestoredFlag()

            if !newTab.databaseName.isEmpty {
                let currentDatabase: String
                if let sessionId = DatabaseManager.shared.currentSessionId,
                   let session = DatabaseManager.shared.activeSessions[sessionId] {
                    currentDatabase = session.connection.database
                } else {
                    currentDatabase = connection.database
                }

                if newTab.databaseName != currentDatabase {
                    changeManager.reloadVersion += 1
                    Task { @MainActor in
                        await switchDatabase(to: newTab.databaseName)
                    }
                    return  // switchDatabase will re-execute the query
                }
            }

            // If the tab shows isExecuting but has no results, the previous query was
            // likely cancelled when the user rapidly switched away. Force-clear the stale
            // flag so the lazy-load check below can re-execute the query.
            if newTab.isExecuting && newTab.resultRows.isEmpty && newTab.lastExecutedAt == nil {
                let tabId = newId
                Task { @MainActor [weak self] in
                    guard let self,
                          let idx = self.tabManager.tabs.firstIndex(where: { $0.id == tabId }),
                          self.tabManager.tabs[idx].isExecuting else { return }
                    self.tabManager.tabs[idx].isExecuting = false
                }
            }

            let needsLazyQuery = !shouldSkipLazyLoad
                && newTab.tabType == .table
                && newTab.resultRows.isEmpty
                && newTab.lastExecutedAt == nil
                && !newTab.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if needsLazyQuery {
                if let session = DatabaseManager.shared.currentSession, session.isConnected {
                    executeTableTabQueryDirectly()
                } else {
                    changeManager.reloadVersion += 1
                    needsLazyLoad = true
                }
            } else {
                // Data already cached or not a table tab — bump reload and finish
                changeManager.reloadVersion += 1
            }
        } else {
            AppState.shared.isCurrentTabEditable = false
            toolbarState.isTableTab = false
        }
    }
}
