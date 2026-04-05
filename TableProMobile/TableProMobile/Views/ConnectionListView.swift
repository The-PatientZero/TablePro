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
    @State private var showingGroupManagement = false
    @State private var showingTagManagement = false
    @State private var filterTagId: UUID?
    @State private var groupByGroup = false

    private var displayedConnections: [DatabaseConnection] {
        var result = appState.connections
        if let filterTagId {
            result = result.filter { $0.tagId == filterTagId }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        filterMenu
                        Button {
                            showingAddConnection = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
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
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath.icloud")
                            }
                        }
                        .disabled(isSyncing)
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
            List {
                if groupByGroup {
                    groupedContent
                } else {
                    ForEach(displayedConnections) { connection in
                        connectionRow(connection)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await appState.syncCoordinator.sync(
                    localConnections: appState.connections,
                    localGroups: appState.groups,
                    localTags: appState.tags
                )
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Section {
                Toggle("Group by Folder", isOn: $groupByGroup)
            }

            if !appState.tags.isEmpty {
                Section("Filter by Tag") {
                    Button {
                        filterTagId = nil
                    } label: {
                        HStack {
                            Text("All")
                            if filterTagId == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    ForEach(appState.tags) { tag in
                        Button {
                            filterTagId = tag.id
                        } label: {
                            HStack {
                                Image(systemName: "circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(ConnectionColorPicker.swiftUIColor(for: tag.color))
                                Text(tag.name)
                                if filterTagId == tag.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            Section {
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
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }

    @ViewBuilder
    private var groupedContent: some View {
        let sortedGroups = appState.groups.sorted { $0.sortOrder < $1.sortOrder }

        ForEach(sortedGroups) { group in
            let groupConnections = displayedConnections.filter { $0.groupId == group.id }

            if !groupConnections.isEmpty {
                Section {
                    ForEach(groupConnections) { connection in
                        connectionRow(connection)
                    }
                } header: {
                    HStack(spacing: 6) {
                        if group.color != .none {
                            Circle()
                                .fill(ConnectionColorPicker.swiftUIColor(for: group.color))
                                .frame(width: 8, height: 8)
                        }
                        Text(group.name)
                    }
                }
            }
        }

        let ungrouped = displayedConnections.filter { conn in
            conn.groupId == nil || !appState.groups.contains { $0.id == conn.groupId }
        }

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
                .font(.title3)
                .foregroundStyle(iconColor(for: connection.type))
                .frame(width: 32, height: 32)
                .background(iconColor(for: connection.type).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name.isEmpty ? connection.host : connection.name)
                    .font(.body)

                if connection.type != .sqlite {
                    Text(verbatim: "\(connection.host):\(connection.port)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(connection.database.components(separatedBy: "/").last ?? "database")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let tag {
                Text(tag.name)
                    .font(.caption)
                    .foregroundStyle(ConnectionColorPicker.swiftUIColor(for: tag.color))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(ConnectionColorPicker.swiftUIColor(for: tag.color).opacity(0.15))
                    )
            }
        }
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
