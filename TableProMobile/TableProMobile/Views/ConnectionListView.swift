//
//  ConnectionListView.swift
//  TableProMobile
//

import SwiftUI
import TableProModels

struct ConnectionListView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddConnection = false
    @State private var editingConnection: DatabaseConnection?

    private var groupedConnections: [(String, [DatabaseConnection])] {
        let grouped = Dictionary(grouping: appState.connections) { $0.type.rawValue.capitalized }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            Group {
                if appState.connections.isEmpty {
                    emptyState
                } else {
                    connectionList
                }
            }
            .navigationTitle("Connections")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddConnection = true
                    } label: {
                        Image(systemName: "plus")
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
                    appState.removeConnection(connection)
                    appState.addConnection(updated)
                    editingConnection = nil
                }
            }
            .navigationDestination(for: DatabaseConnection.self) { connection in
                ConnectedView(connection: connection)
            }
        }
    }

    private var emptyState: some View {
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
    }

    private var connectionList: some View {
        List {
            ForEach(groupedConnections, id: \.0) { sectionTitle, connections in
                Section(sectionTitle) {
                    ForEach(connections) { connection in
                        NavigationLink(value: connection) {
                            ConnectionRow(connection: connection)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
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

                HStack(spacing: 4) {
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
            }

            Spacer()

            Circle()
                .fill(.green.opacity(0.8))
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 4)
    }

    private func iconName(for type: DatabaseType) -> String {
        switch type {
        case .mysql, .mariadb: return "cylinder"
        case .postgresql, .redshift: return "elephant"
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

