//
//  TableProToolbarView.swift
//  TablePro
//
//  Main toolbar composition view combining all toolbar components.
//  This is a pure presentation view - all state is injected via bindings.
//
//  Layout:
//  - Left (.navigation): Reserved for future navigation controls
//  - Center (.principal): Environment badge + Connection status
//  - Right (.primaryAction): Execution indicator
//

import SwiftUI

/// Content for the principal (center) toolbar area
/// Displays environment badge, connection status, and execution indicator in a unified card
struct ToolbarPrincipalContent: View {
    @ObservedObject var state: ConnectionToolbarState

    var body: some View {
        HStack(spacing: ToolbarDesignTokens.Spacing.betweenSections) {
            // Tag badge (if tag is assigned)
            if let tagId = state.tagId,
               let tag = TagStorage.shared.tag(for: tagId)
            {
                TagBadgeView(tag: tag)

                Divider()
                    .frame(height: ToolbarDesignTokens.Spacing.dividerHeight)
            }

            // Main connection status display
            ConnectionStatusView(
                databaseType: state.databaseType,
                databaseVersion: state.databaseVersion,
                databaseName: state.databaseName,
                connectionName: state.connectionName,
                connectionState: state.connectionState,
                displayColor: state.displayColor,
                tagName: state.tagId.flatMap { TagStorage.shared.tag(for: $0)?.name }
            )

            Divider()
                .frame(height: ToolbarDesignTokens.Spacing.dividerHeight)

            // Execution indicator (spinner or duration)
            ExecutionIndicatorView(
                isExecuting: state.isExecuting,
                lastDuration: state.lastQueryDuration
            )
        }
        .animation(
            .spring(
                response: ToolbarDesignTokens.Animation.springResponse,
                dampingFraction: ToolbarDesignTokens.Animation.springDamping), value: state.tagId
        )
        .animation(.easeInOut, value: state.connectionState)
    }
}

/// Toolbar modifier that composes all toolbar items
/// Apply this to a view to add the production toolbar
struct TableProToolbar: ViewModifier {
    @ObservedObject var state: ConnectionToolbarState

    func body(content: Content) -> some View {
        content
            .toolbar {
                // MARK: - Navigation (Left)
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 8) {
                        // Connection switcher button (opens welcome window to select different connection)
                        Button {
                            NotificationCenter.default.post(name: .openWelcomeWindow, object: nil)
                        } label: {
                            Image(systemName: "network")
                        }
                        .help("Switch Connection")

                        Divider()
                            .frame(height: 20)

                        // Database switcher button
                        Button {
                            NotificationCenter.default.post(
                                name: .openDatabaseSwitcher, object: nil)
                        } label: {
                            Image(systemName: "cylinder")
                        }
                        .help("Open Database (⌘K)")
                        .disabled(
                            state.connectionState != .connected || state.databaseType == .sqlite)

                        // SQL query tab button
                        Button("SQL") {
                            NotificationCenter.default.post(name: .newTab, object: nil)
                        }
                        .help("New Query Tab (⌘T)")

                        // Refresh button
                        Button {
                            NotificationCenter.default.post(name: .refreshData, object: nil)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Refresh (⌘R)")
                        .disabled(state.connectionState != .connected)
                    }
                }

                // MARK: - Principal (Center)
                // Main connection information display with execution indicator
                ToolbarItem(placement: .principal) {
                    ToolbarPrincipalContent(state: state)
                }

                // MARK: - Primary Action (Right)
                // Action buttons
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 8) {
                        // Filter toggle
                        Button {
                            NotificationCenter.default.post(name: .toggleFilterPanel, object: nil)
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        .help("Toggle Filters (⌘F)")

                        // History toggle
                        Button {
                            NotificationCenter.default.post(name: .toggleHistoryPanel, object: nil)
                        } label: {
                            Image(systemName: "clock")
                        }
                        .help("Toggle Query History (⌘⇧H)")

                        Divider()
                            .frame(height: 20)

                        // Export
                        Button {
                            NotificationCenter.default.post(name: .exportTables, object: nil)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .help("Export Data (⌘⇧E)")
                        .disabled(state.connectionState != .connected)

                        // Import
                        Button {
                            NotificationCenter.default.post(name: .importTables, object: nil)
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .help("Import Data (⌘⇧I)")
                        .disabled(state.connectionState != .connected)

                        Divider()
                            .frame(height: 20)

                        // Inspector toggle
                        Button {
                            NotificationCenter.default.post(name: .toggleRightSidebar, object: nil)
                        } label: {
                            Image(systemName: "sidebar.trailing")
                        }
                        .help("Toggle Inspector (⌘⌥B)")
                    }
                }
            }
    }
}

// MARK: - View Extension

extension View {
    /// Apply the TablePro toolbar to this view
    /// - Parameter state: The toolbar state to display
    /// - Returns: View with toolbar applied
    func openTableToolbar(state: ConnectionToolbarState) -> some View {
        modifier(TableProToolbar(state: state))
    }
}

// MARK: - Preview

#Preview("With Production Tag") {
    let state = ConnectionToolbarState()
    state.tagId = ConnectionTag.presets.first { $0.name == "production" }?.id
    state.databaseType = .mariadb
    state.databaseVersion = "11.1.2"
    state.connectionName = "Production Database"
    state.connectionState = .connected
    state.displayColor = .red

    return NavigationStack {
        Text("Content")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
    }
    .openTableToolbar(state: state)
    .frame(width: 900, height: 400)
}

#Preview("Executing Query") {
    let state = ConnectionToolbarState()
    state.tagId = ConnectionTag.presets.first { $0.name == "local" }?.id
    state.databaseType = .mysql
    state.databaseVersion = "8.0.35"
    state.connectionName = "Development"
    state.connectionState = .executing
    state.isExecuting = true
    state.displayColor = .orange

    return NavigationStack {
        Text("Content")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
    }
    .openTableToolbar(state: state)
    .frame(width: 900, height: 400)
}

#Preview("No Tag") {
    let state = ConnectionToolbarState()
    state.tagId = nil
    state.databaseType = .postgresql
    state.databaseVersion = "16.1"
    state.connectionName = "Analytics"
    state.connectionState = .connected
    state.displayColor = .blue

    return NavigationStack {
        Text("Content")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
    }
    .openTableToolbar(state: state)
    .frame(width: 900, height: 400)
    .preferredColorScheme(.dark)
}
