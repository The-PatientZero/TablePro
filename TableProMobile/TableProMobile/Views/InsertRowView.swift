//
//  InsertRowView.swift
//  TableProMobile
//

import SwiftUI
import TableProDatabase
import TableProModels

struct InsertRowView: View {
    let table: TableInfo
    let columnDetails: [ColumnInfo]
    let session: ConnectionSession?
    var onInserted: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String] = []
    @State private var isNullFlags: [Bool] = []
    @State private var isSaving = false
    @State private var operationError: String?
    @State private var showOperationError = false

    var body: some View {
        NavigationStack {
            Form {
                ForEach(Array(columnDetails.enumerated()), id: \.offset) { index, column in
                    Section {
                        HStack {
                            if isNullFlags[safe: index] == true {
                                Text("NULL")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .italic()
                            } else {
                                TextField(placeholder(for: column), text: binding(for: index))
                                    .font(.body)
                                    .keyboardType(keyboardType(for: column))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }

                            Spacer()

                            Button {
                                guard index < isNullFlags.count else { return }
                                isNullFlags[index].toggle()
                                if isNullFlags[index], index < values.count {
                                    values[index] = ""
                                }
                            } label: {
                                Text("NULL")
                                    .font(.caption2)
                                    .foregroundStyle(isNullFlags[safe: index] == true ? .white : .secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(isNullFlags[safe: index] == true ? Color.accentColor : Color(.systemFill))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            if column.isPrimaryKey {
                                Image(systemName: "key.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            Text(column.name)

                            if column.isPrimaryKey {
                                Text(isAutoIncrement(column) ? "auto-increment" : "primary key")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(column.typeName)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.fill.tertiary)
                                .clipShape(Capsule())
                        }
                    } footer: {
                        if let defaultValue = column.defaultValue {
                            Text("Default: \(defaultValue)")
                                .font(.caption2)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Insert Row")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await insertRow() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                values = Array(repeating: "", count: columnDetails.count)
                isNullFlags = columnDetails.map { col in
                    col.isPrimaryKey
                }
            }
            .alert("Error", isPresented: $showOperationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(operationError ?? "An unknown error occurred.")
            }
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding<String>(
            get: { values[safe: index] ?? "" },
            set: { newValue in
                guard index < values.count else { return }
                values[index] = newValue
            }
        )
    }

    private func placeholder(for column: ColumnInfo) -> String {
        if column.isPrimaryKey { return "Auto" }
        if let defaultValue = column.defaultValue { return "Default: \(defaultValue)" }
        return column.typeName
    }

    private func isAutoIncrement(_ column: ColumnInfo) -> Bool {
        column.isPrimaryKey && column.typeName.uppercased().contains("INT")
    }

    private func keyboardType(for column: ColumnInfo) -> UIKeyboardType {
        let type = column.typeName.uppercased()
        if type.contains("INT") || type.contains("REAL") || type.contains("FLOAT")
            || type.contains("DOUBLE") || type.contains("NUMERIC") || type.contains("DECIMAL")
        {
            return .decimalPad
        }
        return .default
    }

    private func insertRow() async {
        guard let session else { return }

        isSaving = true
        defer { isSaving = false }

        var insertColumns: [String] = []
        var insertValues: [String?] = []

        for (index, column) in columnDetails.enumerated() {
            let isNull = isNullFlags[safe: index] == true
            let text = values[safe: index] ?? ""

            if column.isPrimaryKey && (isNull || text.isEmpty) {
                continue
            }

            insertColumns.append(column.name)
            if isNull {
                insertValues.append(nil)
            } else {
                insertValues.append(text)
            }
        }

        let sql = SQLHelper.buildInsert(
            table: table.name,
            columns: insertColumns,
            values: insertValues
        )

        do {
            _ = try await session.driver.execute(query: sql)
            onInserted?()
            dismiss()
        } catch {
            operationError = error.localizedDescription
            showOperationError = true
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
