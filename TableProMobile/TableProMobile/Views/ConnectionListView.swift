//
//  ConnectionListView.swift
//  TableProMobile
//

import SwiftUI
import TableProModels
import TableProSync

struct ConnectionListView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddConnection = false
    @State private var editingConnection: DatabaseConnection?
    @State private var selectedConnection: DatabaseConnection?
    @State private var viewMode: ViewMode = .all
    @State private var selectedTagIds: Set<UUID> = []
    @State private var showingGroupManagement = false
    @State private var showingTagManagement = false

    private enum ViewMode: String, CaseIterable {
        case all = "All"
        case groups = "Groups"
    }

    private var filteredConnections: [DatabaseConnection] {
        if selectedTagIds.isEmpty {
            return appState.connections
        }
        return appState.connections.filter { conn in
            guard let tagId = conn.tagId else { return false }
            return selectedTagIds.contains(tagId)
        }
    }

    private var isSyncing: Bool {
        appState.syncCoordinator.status == .syncing
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationTitle("Connections")
                .navigationDestination(for: DatabaseConnection.self) { connection in
                    ConnectedView(connection: connection)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingAddConnection = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button {
                                showingGroupManagement = true
                            } label: {
                                Label("Manage Groups", systemImage: "folder")
                            }
                            Button {
                                showingTagManagement = true
                            } label: {
                                Label("Manage Tags", systemImage: "tag")
                            }
                            Divider()
                            Button {
                                Task {
                                    await appState.syncCoordinator.sync(
                                        localConnections: appState.connections,
                                        localGroups: appState.groups,
                                        localTags: appState.tags
                                    )
                                }
                            } label: {
                                if isSyncing {
                                    Label("Syncing...", systemImage: "arrow.triangle.2.circlepath.icloud")
                                } else {
                                    Label("Sync", systemImage: "arrow.triangle.2.circlepath.icloud")
                                }
                            }
                            .disabled(isSyncing)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
        } detail: {
            NavigationStack {
                if let connection = selectedConnection {
                    ConnectedView(connection: connection)
                        .id(connection.id)
                } else {
                    ContentUnavailableView(
                        "Select a Connection",
                        systemImage: "server.rack",
                        description: Text("Choose a connection from the sidebar.")
                    )
                }
            }
        }
        .sheet(isPresented: $showingAddConnection) {
            ConnectionFormView { connection in
                appState.addConnection(connection)
                showingAddConnection = false
            }
        }
        .sheet(item: $editingConnection) { connection in
            ConnectionFormView(editing: connection) { updated in
                appState.updateConnection(updated)
                editingConnection = nil
            }
        }
        .sheet(isPresented: $showingGroupManagement) {
            GroupManagementView()
        }
        .sheet(isPresented: $showingTagManagement) {
            TagManagementView()
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        if appState.connections.isEmpty && !isSyncing {
            ContentUnavailableView {
                Label("No Connections", systemImage: "server.rack")
            } description: {
                Text("Add a database connection to get started.")
            } actions: {
                Button("Add Connection") {
                    showingAddConnection = true
                }
                .buttonStyle(.borderedProminent)
            }
        } else if appState.connections.isEmpty && isSyncing {
            ProgressView("Syncing from iCloud...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                viewModeAndFilters
                connectionList
            }
        }
    }

    private var viewModeAndFilters: some View {
        VStack(spacing: 8) {
            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if !appState.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(appState.tags) { tag in
                            let isSelected = selectedTagIds.contains(tag.id)
                            Button {
                                if isSelected {
                                    selectedTagIds.remove(tag.id)
                                } else {
                                    selectedTagIds.insert(tag.id)
                                }
                            } label: {
                                Text(tag.name)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule()
                                            .fill(isSelected
                                                ? ConnectionColorPicker.swiftUIColor(for: tag.color)
                                                : ConnectionColorPicker.swiftUIColor(for: tag.color).opacity(0.15))
                                    )
                                    .foregroundStyle(isSelected ? .white : .primary)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var connectionList: some View {
        List {
            switch viewMode {
            case .all:
                allConnectionsList
            case .groups:
                groupedConnectionsList
            }
        }
        .listStyle(.sidebar)
        .refreshable {
            await appState.syncCoordinator.sync(
                localConnections: appState.connections,
                localGroups: appState.groups,
                localTags: appState.tags
            )
        }
    }

    @ViewBuilder
    private var allConnectionsList: some View {
        let sorted = filteredConnections.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        ForEach(sorted) { connection in
            connectionRow(connection)
        }
    }

    @ViewBuilder
    private var groupedConnectionsList: some View {
        let sortedGroups = appState.groups.sorted { $0.sortOrder < $1.sortOrder }

        ForEach(sortedGroups) { group in
            let groupConnections = filteredConnections
                .filter { $0.groupId == group.id }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            if !groupConnections.isEmpty {
                Section {
                    ForEach(groupConnections) { connection in
                        connectionRow(connection)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ConnectionColorPicker.swiftUIColor(for: group.color))
                            .frame(width: 8, height: 8)
                        Text(group.name)
                    }
                }
            }
        }

        let ungrouped = filteredConnections
            .filter { $0.groupId == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if !ungrouped.isEmpty {
            Section("Ungrouped") {
                ForEach(ungrouped) { connection in
                    connectionRow(connection)
                }
            }
        }
    }

    private func connectionRow(_ connection: DatabaseConnection) -> some View {
        NavigationLink(value: connection) {
            ConnectionRow(connection: connection, tag: appState.tag(for: connection.tagId))
        }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    if selectedConnection?.id == connection.id {
                        selectedConnection = nil
                    }
                    appState.removeConnection(connection)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .contextMenu {
                Button {
                    editingConnection = connection
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button {
                    var duplicate = connection
                    duplicate.id = UUID()
                    duplicate.name = "\(connection.name) Copy"
                    appState.addConnection(duplicate)
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                Divider()
                Button(role: .destructive) {
                    if selectedConnection?.id == connection.id {
                        selectedConnection = nil
                    }
                    appState.removeConnection(connection)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}

private struct ConnectionRow: View {
    let connection: DatabaseConnection
    let tag: ConnectionTag?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: connection.type))
                .font(.title2)
                .foregroundStyle(iconColor(for: connection.type))
                .frame(width: 36, height: 36)
                .background(iconColor(for: connection.type).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name.isEmpty ? connection.host : connection.name)
                    .font(.body)
                    .fontWeight(.medium)

                if connection.type != .sqlite {
                    Text(verbatim: "\(connection.host):\(connection.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(connection.database.components(separatedBy: "/").last ?? "database")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let tag {
                    Text(tag.name)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(ConnectionColorPicker.swiftUIColor(for: tag.color).opacity(0.2))
                        )
                        .foregroundStyle(ConnectionColorPicker.swiftUIColor(for: tag.color))
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func iconName(for type: DatabaseType) -> String {
        switch type {
        case .mysql, .mariadb: return "cylinder"
        case .postgresql, .redshift: return "cylinder.split.1x2"
        case .sqlite: return "doc"
        case .redis: return "key"
        case .mongodb: return "leaf"
        case .clickhouse: return "bolt"
        case .mssql: return "server.rack"
        default: return "externaldrive"
        }
    }

    private func iconColor(for type: DatabaseType) -> Color {
        switch type {
        case .mysql, .mariadb: return .orange
        case .postgresql, .redshift: return .blue
        case .sqlite: return .green
        case .redis: return .red
        case .mongodb: return .green
        case .clickhouse: return .yellow
        case .mssql: return .indigo
        default: return .gray
        }
    }
}
