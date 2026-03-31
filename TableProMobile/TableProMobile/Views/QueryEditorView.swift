//
//  QueryEditorView.swift
//  TableProMobile
//

import SwiftUI
import TableProDatabase
import TableProModels

struct QueryEditorView: View {
    let session: ConnectionSession?
    var tables: [TableInfo] = []
    var initialQuery: String = ""

    @State private var query = ""
    @State private var result: QueryResult?
    @State private var errorMessage: String?
    @State private var isExecuting = false
    @State private var executionTime: TimeInterval?
    @State private var queryHistory: [String] = []
    @State private var showHistory = false
    @State private var showTemplates = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            editorArea
            if editorFocused {
                keywordAccessory
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider()
            resultArea
        }
        .navigationTitle("Query")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await executeQuery() }
                } label: {
                    Image(systemName: isExecuting ? "stop.fill" : "play.fill")
                        .foregroundStyle(isExecuting ? .red : .green)
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExecuting)
            }

            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button {
                        showHistory = true
                    } label: {
                        Label("History", systemImage: "clock")
                    }
                    .disabled(queryHistory.isEmpty)

                    if !tables.isEmpty {
                        Menu {
                            ForEach(tables) { table in
                                Button(table.name) {
                                    query = "SELECT * FROM \(table.name) LIMIT 100"
                                }
                            }
                        } label: {
                            Label("SELECT * FROM ...", systemImage: "text.badge.star")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        query = ""
                        result = nil
                        errorMessage = nil
                        executionTime = nil
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            if !initialQuery.isEmpty {
                query = initialQuery
            }
        }
        .sheet(isPresented: $showHistory) {
            historySheet
        }
    }

    // MARK: - Editor

    private var editorArea: some View {
        VStack(spacing: 0) {
            TextEditor(text: $query)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100, maxHeight: result != nil || errorMessage != nil ? 150 : 300)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .focused($editorFocused)

            if executionTime != nil || result != nil {
                HStack {
                    if let time = executionTime {
                        Label(
                            String(format: "%.1fms", time * 1000),
                            systemImage: "clock"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let result, !result.rows.isEmpty {
                        Text("\(result.rows.count) rows")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - SQL Keyword Accessory

    private var keywordAccessory: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(keywords, id: \.self) { keyword in
                    Button { insertKeyword(keyword) } label: {
                        Text(keyword)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .fontDesign(.monospaced)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.fill.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    private let keywords = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "JOIN",
        "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
        "CREATE", "TABLE", "DROP", "ALTER",
        "LIMIT", "ORDER BY", "GROUP BY", "HAVING", "AS", "IN",
        "NOT", "NULL", "LIKE", "BETWEEN", "COUNT", "DISTINCT"
    ]

    private func insertKeyword(_ keyword: String) {
        let needsLeadingSpace = !query.isEmpty && !query.hasSuffix(" ") && !query.hasSuffix("\n")
        query += (needsLeadingSpace ? " " : "") + keyword + " "
        editorFocused = true
    }

    // MARK: - Results

    private var resultArea: some View {
        Group {
            if isExecuting {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Executing...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ScrollView {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let result {
                if result.columns.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                        Text("\(result.rowsAffected) row(s) affected")
                            .font(.body)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if result.rows.isEmpty {
                    ContentUnavailableView("No Results", systemImage: "tray")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    resultTable(result)
                }
            } else {
                ContentUnavailableView {
                    Label("Run a Query", systemImage: "terminal")
                } description: {
                    Text("Write SQL and tap the play button.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func resultTable(_ result: QueryResult) -> some View {
        ScrollView(.horizontal) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                Section {
                    ForEach(Array(result.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 0) {
                            ForEach(Array(result.columns.enumerated()), id: \.offset) { colIndex, column in
                                let value = colIndex < row.count ? row[colIndex] : nil
                                Text(value ?? "NULL")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(value == nil ? .secondary : .primary)
                                    .lineLimit(1)
                                    .frame(width: columnWidth(for: colIndex, column: column, rows: result.rows), alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                    .contextMenu {
                                        Button {
                                            UIPasteboard.general.string = value ?? ""
                                        } label: {
                                            Label("Copy", systemImage: "doc.on.doc")
                                        }
                                    }
                            }
                        }
                        Divider()
                    }
                } header: {
                    HStack(spacing: 0) {
                        ForEach(Array(result.columns.enumerated()), id: \.offset) { colIndex, col in
                            Text(col.name)
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.semibold)
                                .frame(width: columnWidth(for: colIndex, column: col, rows: result.rows), alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                        }
                    }
                    .background(.bar)
                    Divider()
                }
            }
        }
    }

    private func columnWidth(for columnIndex: Int, column: ColumnInfo, rows: [[String?]]) -> CGFloat {
        let headerWidth = CGFloat(column.name.count) * 8 + 16
        let maxDataWidth = rows.prefix(20).compactMap { row -> CGFloat? in
            guard columnIndex < row.count, let value = row[columnIndex] else { return nil }
            return min(CGFloat(value.count) * 7.5, 200) + 16
        }.max() ?? 60
        return max(max(headerWidth, maxDataWidth), 60)
    }

    // MARK: - History

    private var historySheet: some View {
        NavigationStack {
            List {
                ForEach(queryHistory.reversed(), id: \.self) { historyQuery in
                    Button {
                        query = historyQuery
                        showHistory = false
                    } label: {
                        Text(historyQuery)
                            .font(.system(.footnote, design: .monospaced))
                            .lineLimit(3)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Query History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showHistory = false }
                }
            }
            .overlay {
                if queryHistory.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock",
                        description: Text("Executed queries will appear here.")
                    )
                }
            }
        }
    }

    // MARK: - Execution

    private func executeQuery() async {
        guard let session else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isExecuting = true
        errorMessage = nil
        result = nil

        do {
            let queryResult = try await session.driver.execute(query: trimmed)
            self.result = queryResult
            self.executionTime = queryResult.executionTime

            if !queryHistory.contains(trimmed) {
                queryHistory.append(trimmed)
                if queryHistory.count > 50 {
                    queryHistory.removeFirst()
                }
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }

        isExecuting = false
    }
}
