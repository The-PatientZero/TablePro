//
//  QueryEditorView.swift
//  TableProMobile
//

import os
import SwiftUI
import TableProDatabase
import TableProModels

struct QueryEditorView: View {
    let session: ConnectionSession?
    var tables: [TableInfo] = []
    var initialQuery: String = ""

    private static let logger = Logger(subsystem: "com.TablePro", category: "QueryEditorView")

    @State private var query = ""
    @State private var result: QueryResult?
    @State private var appError: AppError?
    @State private var isExecuting = false
    @State private var executionTime: TimeInterval?
    @State private var executeTask: Task<Void, Never>?
    @Binding var queryHistory: [String]
    @State private var showHistory = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            editorSection
            Divider()
            resultSection
        }
        .toolbar { toolbarContent }
        .onAppear {
            if !initialQuery.isEmpty { query = initialQuery }
        }
        .sheet(isPresented: $showHistory) { historySheet }
    }

    // MARK: - Editor

    private var editorSection: some View {
        VStack(spacing: 0) {
            TextEditor(text: $query)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80, maxHeight: result != nil || appError != nil ? 120 : 250)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .focused($editorFocused)

            if executionTime != nil || result != nil {
                HStack {
                    if let time = executionTime {
                        Label(String(format: "%.1fms", time * 1000), systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let result, !result.rows.isEmpty {
                        Text(verbatim: "\(result.rows.count) rows")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Results

    private var resultSection: some View {
        Group {
            if isExecuting {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Executing...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let appError {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(verbatim: appError.message)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                        if let recovery = appError.recovery {
                            Text(verbatim: recovery)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 28)
                        }
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
                        Text(verbatim: "\(result.rowsAffected) row(s) affected")
                            .font(.body)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if result.rows.isEmpty {
                    ContentUnavailableView("No Results", systemImage: "tray")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    resultList(result)
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

    // Native iOS pattern: List with rows, each row shows column:value pairs
    private func resultList(_ result: QueryResult) -> some View {
        List {
            ForEach(Array(result.rows.enumerated()), id: \.offset) { rowIndex, row in
                Section {
                    ForEach(Array(result.columns.enumerated()), id: \.offset) { colIndex, col in
                        let value = colIndex < row.count ? row[colIndex] : nil
                        HStack(alignment: .top) {
                            Text(verbatim: col.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .leading)
                            Text(verbatim: value ?? "NULL")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(value == nil ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                        .contextMenu {
                            if let value {
                                Button {
                                    UIPasteboard.general.string = value
                                } label: {
                                    Label("Copy Value", systemImage: "doc.on.doc")
                                }
                            }
                            Button {
                                UIPasteboard.general.string = col.name
                            } label: {
                                Label("Copy Column Name", systemImage: "textformat")
                            }
                        }
                    }
                } header: {
                    Text(verbatim: "Row \(rowIndex + 1)")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                if isExecuting {
                    executeTask?.cancel()
                    Task { try? await session?.driver.cancelCurrentQuery() }
                } else {
                    executeTask = Task { await executeQuery() }
                }
            } label: {
                Image(systemName: isExecuting ? "stop.fill" : "play.fill")
            }
            .disabled(!isExecuting && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        ToolbarItem(placement: .topBarTrailing) {
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
                    appError = nil
                    executionTime = nil
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
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
                        Text(verbatim: historyQuery)
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

        editorFocused = false
        isExecuting = true
        appError = nil
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
            let context = ErrorContext(operation: "executeQuery")
            self.appError = ErrorClassifier.classify(error, context: context)
        }

        isExecuting = false
    }
}
