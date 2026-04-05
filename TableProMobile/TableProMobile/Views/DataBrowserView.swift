//
//  DataBrowserView.swift
//  TableProMobile
//

import os
import SwiftUI
import TableProDatabase
import TableProModels

struct DataBrowserView: View {
    let connection: DatabaseConnection
    let table: TableInfo
    let session: ConnectionSession?

    private static let logger = Logger(subsystem: "com.TablePro", category: "DataBrowserView")

    @State private var columns: [ColumnInfo] = []
    @State private var columnDetails: [ColumnInfo] = []
    @State private var rows: [[String?]] = []
    @State private var isLoading = true
    @State private var appError: AppError?
    @State private var pagination = PaginationState(pageSize: 100, currentPage: 0)
    @State private var showInsertSheet = false
    @State private var deleteTarget: [(column: String, value: String)]?
    @State private var showDeleteConfirmation = false
    @State private var operationError: AppError?
    @State private var showOperationError = false

    private var isView: Bool {
        table.type == .view || table.type == .materializedView
    }

    private var hasPrimaryKeys: Bool {
        columnDetails.contains(where: \.isPrimaryKey)
    }

    private var paginationLabel: String {
        guard !rows.isEmpty else { return "" }
        let start = pagination.currentOffset + 1
        let end = pagination.currentOffset + rows.count
        if let total = pagination.totalRows {
            return "\(start)–\(end) of \(total)"
        }
        return "\(start)–\(end)"
    }

    var body: some View {
        content
            .navigationTitle(table.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { topToolbar }
            .toolbar(rows.isEmpty ? .hidden : .visible, for: .bottomBar)
            .toolbar { paginationToolbar }
            .task { await loadData(isInitial: true) }
            .sheet(isPresented: $showInsertSheet) { insertSheet }
            .confirmationDialog("Delete Row", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let pkValues = deleteTarget {
                        Task { await deleteRow(withPKs: pkValues) }
                    }
                }
            } message: {
                Text("Are you sure you want to delete this row? This action cannot be undone.")
            }
            .alert(operationError?.title ?? "Error", isPresented: $showOperationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(operationError?.message ?? "")
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let appError {
            ErrorView(error: appError) { await loadData() }
        } else if rows.isEmpty {
            ContentUnavailableView {
                Label("No Data", systemImage: "tray")
            } description: {
                Text("This table is empty.")
            } actions: {
                if !isView {
                    Button("Insert Row") { showInsertSheet = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            rowList
        }
    }

    private var rowList: some View {
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
                        databaseType: connection.type,
                        onSaved: { Task { await loadData() } }
                    )
                } label: {
                    RowCard(
                        columns: columns,
                        columnDetails: columnDetails,
                        row: row
                    )
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !isView && hasPrimaryKeys {
                        Button(role: .destructive) {
                            deleteTarget = primaryKeyValues(for: rows[index])
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadData() }
    }

    // MARK: - Toolbars

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                StructureView(table: table, session: session, databaseType: connection.type)
            } label: {
                Image(systemName: "info.circle")
            }
        }
        if !isView {
            ToolbarItem(placement: .primaryAction) {
                Button { showInsertSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var paginationToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button { Task { await goToPreviousPage() } } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(pagination.currentPage == 0 || isLoading)

            Spacer()

            Menu {
                ForEach([50, 100, 200, 500], id: \.self) { size in
                    Button {
                        changePageSize(size)
                    } label: {
                        HStack {
                            Text("\(size) rows")
                            if pagination.pageSize == size {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(paginationLabel)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            Spacer()

            Button { Task { await goToNextPage() } } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!pagination.hasNextPage || isLoading)
        }
    }

    private var insertSheet: some View {
        InsertRowView(
            table: table,
            columnDetails: columnDetails,
            session: session,
            databaseType: connection.type,
            onInserted: { Task { await loadData() } }
        )
    }

    // MARK: - Data Loading

    private func loadData(isInitial: Bool = false) async {
        guard let session else {
            appError = AppError(
                category: .config,
                title: String(localized: "Not Connected"),
                message: String(localized: "No active database session."),
                recovery: String(localized: "Go back and reconnect to the database."),
                underlying: nil
            )
            isLoading = false
            return
        }

        if isInitial || rows.isEmpty { isLoading = true }
        appError = nil

        do {
            let query = SQLBuilder.buildSelect(
                table: table.name, type: connection.type,
                limit: pagination.pageSize, offset: pagination.currentOffset
            )
            let result = try await session.driver.execute(query: query)
            columns = result.columns
            rows = result.rows
            columnDetails = try await session.driver.fetchColumns(table: table.name, schema: nil)
            if pagination.totalRows == nil {
                await fetchTotalRows(session: session)
            }
            isLoading = false
        } catch {
            appError = ErrorClassifier.classify(
                error,
                context: ErrorContext(operation: "loadData", databaseType: connection.type, host: connection.host)
            )
            isLoading = false
        }
    }

    private func fetchTotalRows(session: ConnectionSession) async {
        do {
            let countQuery = SQLBuilder.buildCount(table: table.name, type: connection.type)
            let countResult = try await session.driver.execute(query: countQuery)
            if let firstRow = countResult.rows.first, let firstCol = firstRow.first {
                pagination.totalRows = Int(firstCol ?? "0")
            }
        } catch {
            Self.logger.warning("Failed to fetch row count: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func changePageSize(_ newSize: Int) {
        pagination.pageSize = newSize
        pagination.currentPage = 0
        pagination.totalRows = nil
        Task { await loadData() }
    }

    private func goToNextPage() async {
        pagination.currentPage += 1
        await loadData()
    }

    private func goToPreviousPage() async {
        guard pagination.currentPage > 0 else { return }
        pagination.currentPage -= 1
        await loadData()
    }

    // MARK: - Row Operations

    private func deleteRow(withPKs pkValues: [(column: String, value: String)]) async {
        guard let session, !pkValues.isEmpty else { return }
        do {
            _ = try await session.driver.execute(
                query: SQLBuilder.buildDelete(table: table.name, type: connection.type, primaryKeys: pkValues)
            )
            await loadData()
        } catch {
            operationError = ErrorClassifier.classify(
                error,
                context: ErrorContext(operation: "deleteRow", databaseType: connection.type, host: connection.host)
            )
            showOperationError = true
        }
    }

    private func primaryKeyValues(for row: [String?]) -> [(column: String, value: String)] {
        columnDetails.compactMap { col in
            guard col.isPrimaryKey,
                  let colIndex = columns.firstIndex(where: { $0.name == col.name }),
                  colIndex < row.count,
                  let value = row[colIndex] else { return nil }
            return (column: col.name, value: value)
        }
    }
}

// MARK: - Row Card

private struct RowCard: View {
    let columns: [ColumnInfo]
    let columnDetails: [ColumnInfo]
    let row: [String?]

    private static let maxPreview = 4

    private var pkNames: Set<String> {
        Set(columnDetails.filter(\.isPrimaryKey).map(\.name))
    }

    private var titlePair: (name: String, value: String)? {
        let pks = pkNames
        for (col, val) in zip(columns, row) where pks.contains(col.name) {
            return (col.name, val ?? "NULL")
        }
        guard let first = columns.first else { return nil }
        return (first.name, row.first.flatMap { $0 } ?? "NULL")
    }

    private var detailPairs: [(name: String, value: String)] {
        let pks = pkNames
        let title = titlePair?.name
        return zip(columns, row)
            .filter { !pks.contains($0.0.name) && $0.0.name != title }
            .prefix(Self.maxPreview - 1)
            .map { ($0.0.name, $0.1 ?? "NULL") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = titlePair {
                HStack(spacing: 6) {
                    Text(title.name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(verbatim: title.value)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
            }

            ForEach(Array(detailPairs.enumerated()), id: \.offset) { _, pair in
                HStack(spacing: 6) {
                    Text(pair.name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(verbatim: pair.value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if columns.count > Self.maxPreview {
                Text("+\(columns.count - Self.maxPreview) more columns")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 2)
    }
}
