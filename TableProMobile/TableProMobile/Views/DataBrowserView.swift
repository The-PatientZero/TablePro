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
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var pagination = PaginationState(pageSize: 100, currentPage: 0)
    @State private var showInsertSheet = false
    @State private var deleteTarget: [(column: String, value: String)]?
    @State private var showDeleteConfirmation = false
    @State private var operationError: AppError?
    @State private var showOperationError = false

    private let maxPreviewColumns = 4

    private var isView: Bool {
        table.type == .view || table.type == .materializedView
    }

    private var hasPrimaryKeys: Bool {
        columnDetails.contains { $0.isPrimaryKey }
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
        Group {
            if isLoading {
                ProgressView("Loading data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let appError {
                ErrorView(error: appError) {
                    await loadData()
                }
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
                cardList
            }
        }
        .navigationTitle(table.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    StructureView(
                        table: table,
                        session: session,
                        databaseType: connection.type
                    )
                } label: {
                    Image(systemName: "info.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if !isView {
                    Button {
                        showInsertSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !rows.isEmpty {
                HStack {
                    Button {
                        Task { await goToPreviousPage() }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(pagination.currentPage == 0 || isLoading)

                    Spacer()

                    Text(paginationLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        Task { await goToNextPage() }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!pagination.hasNextPage || isLoading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
        }
        .task { await loadData(isInitial: true) }
        .sheet(isPresented: $showInsertSheet) {
            InsertRowView(
                table: table,
                columnDetails: columnDetails,
                session: session,
                databaseType: connection.type,
                onInserted: {
                    Task { await loadData() }
                }
            )
        }
        .alert("Delete Row", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let pkValues = deleteTarget {
                    Task { await deleteRow(withPKs: pkValues) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this row? This action cannot be undone.")
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                ErrorToast(message: toastMessage)
                    .onAppear {
                        toastTask?.cancel()
                        toastTask = Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            withAnimation { self.toastMessage = nil }
                        }
                    }
                    .onDisappear {
                        toastTask?.cancel()
                        toastTask = nil
                    }
            }
        }
        .animation(.default, value: toastMessage)
        .alert(operationError?.title ?? "Error", isPresented: $showOperationError) {
            Button("OK", role: .cancel) {}
        } message: {
            VStack {
                Text(operationError?.message ?? "An unknown error occurred.")
                if let recovery = operationError?.recovery {
                    Text(verbatim: recovery)
                }
            }
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
                        databaseType: connection.type,
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

    private func loadData(isInitial: Bool = false) async {
        guard let session else {
            appError = AppError(
                category: .config,
                title: "Not Connected",
                message: "No active database session.",
                recovery: "Go back and reconnect to the database.",
                underlying: nil
            )
            isLoading = false
            return
        }

        if isInitial || rows.isEmpty {
            isLoading = true
        }
        appError = nil

        do {
            let query = SQLBuilder.buildSelect(
                table: table.name, type: connection.type,
                limit: pagination.pageSize, offset: pagination.currentOffset
            )
            let result = try await session.driver.execute(query: query)
            self.columns = result.columns
            self.rows = result.rows

            // columnDetails (from fetchColumns) provides PK info for edit/delete.
            // columns (from query result) only have name/type, no PK metadata.
            self.columnDetails = try await session.driver.fetchColumns(table: table.name, schema: nil)

            await fetchTotalRows(session: session)

            isLoading = false
        } catch {
            let context = ErrorContext(
                operation: "loadData",
                databaseType: connection.type,
                host: connection.host
            )
            appError = ErrorClassifier.classify(error, context: context)
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

    private func goToNextPage() async {
        pagination.currentPage += 1
        await loadData()
    }

    private func goToPreviousPage() async {
        guard pagination.currentPage > 0 else { return }
        pagination.currentPage -= 1
        await loadData()
    }

    private func deleteRow(withPKs pkValues: [(column: String, value: String)]) async {
        guard let session, !pkValues.isEmpty else { return }

        let sql = SQLBuilder.buildDelete(table: table.name, type: connection.type, primaryKeys: pkValues)

        do {
            _ = try await session.driver.execute(query: sql)
            await loadData()
        } catch {
            let context = ErrorContext(
                operation: "deleteRow",
                databaseType: connection.type,
                host: connection.host
            )
            operationError = ErrorClassifier.classify(error, context: context)
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

    private var pkPair: (name: String, value: String)? {
        for (col, val) in zip(columns, row) where col.isPrimaryKey {
            return (col.name, val ?? "NULL")
        }
        if let first = columns.first {
            return (first.name, row.first.flatMap { $0 } ?? "NULL")
        }
        return nil
    }

    private var previewPairs: [(name: String, value: String)] {
        let paired = zip(columns, row)
        return paired
            .filter { !$0.0.isPrimaryKey }
            .prefix(maxPreviewColumns - 1)
            .map { ($0.0.name, $0.1 ?? "NULL") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let pk = pkPair {
                HStack(spacing: 6) {
                    Text(pk.name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(verbatim: pk.value)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
            }

            ForEach(Array(previewPairs.enumerated()), id: \.offset) { _, pair in
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

            if columns.count > maxPreviewColumns {
                Text("+\(columns.count - maxPreviewColumns) more columns")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 2)
    }
}
