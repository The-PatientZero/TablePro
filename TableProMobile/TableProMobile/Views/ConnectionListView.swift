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

    private var groupedConnections: [(String, [DatabaseConnection])] {
        let grouped = Dictionary(grouping: appState.connections) { $0.type.rawValue.capitalized }
        return grouped.sorted { $0.key < $1.key }
    }

    private var isSyncing: Bool {
        appState.syncCoordinator.status == .syncing
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationTitle("Connections")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingAddConnection = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button {
                                Task {
                                    await appState.syncCoordinator.sync(
                                        localConnections: appState.connections)
                                }
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath.icloud")
                            }
                        }
                    }
                }
        } detail: {
            NavigationStack {
                if let connection = selectedConnection {
                    ConnectedView(connection: connection)
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
            List(selection: $selectedConnection) {
                ForEach(groupedConnections, id: \.0) { sectionTitle, connections in
                    Section(sectionTitle) {
                        ForEach(connections) { connection in
                            ConnectionRow(connection: connection)
                                .tag(connection)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
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
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await appState.syncCoordinator.sync(localConnections: appState.connections)
            }
        }
    }
}

private struct ConnectionRow: View {
    let connection: DatabaseConnection

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
                    Text("\(connection.host):\(connection.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(connection.database.components(separatedBy: "/").last ?? "database")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
