//
//  DataBrowserView.swift
//  TableProMobile
//

import SwiftUI
import TableProDatabase
import TableProModels

struct DataBrowserView: View {
    let connection: DatabaseConnection
    let table: TableInfo
    let session: ConnectionSession?

    @State private var columns: [ColumnInfo] = []
    @State private var columnDetails: [ColumnInfo] = []
    @State private var rows: [[String?]] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var pagination = PaginationState(pageSize: 100, currentPage: 0)
    @State private var hasMore = true
    @State private var showInsertSheet = false
    @State private var deleteTarget: Int?
    @State private var showDeleteConfirmation = false
    @State private var operationError: String?
    @State private var showOperationError = false

    private let maxPreviewColumns = 4

    private var isView: Bool {
        table.type == .view || table.type == .materializedView
    }

    private var hasPrimaryKeys: Bool {
        columnDetails.contains { $0.isPrimaryKey }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Query Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") {
                        Task { await loadData() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if rows.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "tray",
                    description: Text("This table is empty.")
                )
            } else {
                cardList
            }
        }
        .navigationTitle(table.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Text("\(rows.count) rows")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !isView {
                        Button {
                            showInsertSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .task { await loadData() }
        .sheet(isPresented: $showInsertSheet) {
            InsertRowView(
                table: table,
                columnDetails: columnDetails,
                session: session,
                onInserted: {
                    Task { await loadData() }
                }
            )
        }
        .alert("Delete Row", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let index = deleteTarget {
                    Task { await deleteRow(at: index) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this row? This action cannot be undone.")
        }
        .alert("Error", isPresented: $showOperationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(operationError ?? "An unknown error occurred.")
        }
    }

    private var cardList: some View {
        List {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                NavigationLink {
                    RowDetailView(
                        columns: columns,
                        rows: rows,
                        initialIndex: index,
                        table: table,
                        session: session,
                        columnDetails: columnDetails,
                        onSaved: {
                            Task { await loadData() }
                        }
                    )
                } label: {
                    RowCard(
                        columns: columns,
                        row: row,
                        maxPreviewColumns: maxPreviewColumns
                    )
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !isView && hasPrimaryKeys {
                        Button(role: .destructive) {
                            deleteTarget = index
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            if hasMore {
                Section {
                    Button {
                        Task { await loadNextPage() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading...")
                            } else {
                                Label("Load More", systemImage: "arrow.down.circle")
                            }
                            Spacer()
                        }
                        .foregroundStyle(.blue)
                    }
                    .disabled(isLoadingMore)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await loadData() }
    }

    private func loadData() async {
        guard let session else {
            errorMessage = "Not connected"
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        pagination.reset()

        do {
            let query = "SELECT * FROM `\(table.name)` LIMIT \(pagination.pageSize) OFFSET \(pagination.currentOffset)"
            let result = try await session.driver.execute(query: query)
            self.columns = result.columns
            self.rows = result.rows
            self.hasMore = result.rows.count >= pagination.pageSize

            if columnDetails.isEmpty {
                self.columnDetails = try await session.driver.fetchColumns(table: table.name, schema: nil)
            }

            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func loadNextPage() async {
        guard let session else { return }

        isLoadingMore = true
        pagination.currentPage += 1

        do {
            let query = "SELECT * FROM `\(table.name)` LIMIT \(pagination.pageSize) OFFSET \(pagination.currentOffset)"
            let result = try await session.driver.execute(query: query)
            rows.append(contentsOf: result.rows)
            hasMore = result.rows.count >= pagination.pageSize
        } catch {
            pagination.currentPage -= 1
        }

        isLoadingMore = false
    }

    private func deleteRow(at index: Int) async {
        guard let session, index < rows.count else { return }

        let row = rows[index]
        let pkValues = primaryKeyValues(for: row)

        guard !pkValues.isEmpty else {
            operationError = "Cannot delete: no primary key columns found."
            showOperationError = true
            return
        }

        let sql = SQLHelper.buildDelete(table: table.name, primaryKeys: pkValues)

        do {
            _ = try await session.driver.execute(query: sql)
            await loadData()
        } catch {
            operationError = error.localizedDescription
            showOperationError = true
        }
    }

    private func primaryKeyValues(for row: [String?]) -> [(column: String, value: String)] {
        columnDetails.enumerated().compactMap { index, col in
            guard col.isPrimaryKey else { return nil }
            let colIndex = columns.firstIndex(where: { $0.name == col.name })
            guard let colIndex, colIndex < row.count, let value = row[colIndex] else { return nil }
            return (column: col.name, value: value)
        }
    }
}

private struct RowCard: View {
    let columns: [ColumnInfo]
    let row: [String?]
    let maxPreviewColumns: Int

    private var sortedPairs: [(column: ColumnInfo, value: String?)] {
        let paired = zip(columns, row).map { ($0, $1) }
        let pkPairs = paired.filter { $0.0.isPrimaryKey }
        let nonPkPairs = paired.filter { !$0.0.isPrimaryKey }
        return (pkPairs + nonPkPairs).prefix(maxPreviewColumns).map { ($0.0, $0.1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(sortedPairs.enumerated()), id: \.offset) { _, pair in
                HStack(spacing: 8) {
                    Text(pair.column.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 60, alignment: .leading)

                    if let value = pair.value {
                        Text(value)
                            .font(.subheadline)
                            .fontWeight(pair.column.isPrimaryKey ? .semibold : .regular)
                            .lineLimit(1)
                    } else {
                        Text("NULL")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
            }

            if columns.count > maxPreviewColumns {
                Text("+\(columns.count - maxPreviewColumns) more columns")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
