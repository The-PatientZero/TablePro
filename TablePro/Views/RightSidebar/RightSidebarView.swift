//
//  RightSidebarView.swift
//  TablePro
//
//  Professional macOS inspector-style right sidebar
//

import SwiftUI

/// Right sidebar that shows table metadata or selected row details
struct RightSidebarView: View {
    let tableName: String?
    let tableMetadata: TableMetadata?
    let selectedRowData: [(column: String, value: String?, type: String)]?
    let isEditable: Bool
    let isRowDeleted: Bool
    let onSave: () -> Void

    @ObservedObject var editState: MultiRowEditState

    @State private var searchText: String = ""

    private var mode: String {
        if selectedRowData != nil {
            return isEditable ? "Edit Row" : "Row Details"
        }
        return "Table Info"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Search (only for row details)
            if selectedRowData != nil {
                searchField

                Divider()
            }

            // Content
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let rowData = selectedRowData {
                        rowDetailContent(rowData)
                    } else if let metadata = tableMetadata {
                        tableInfoContent(metadata)
                    } else {
                        emptyState
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(mode)
                    .font(.system(size: DesignConstants.FontSize.small, weight: .semibold))
                if let name = tableName {
                    Text(name)
                        .font(.system(size: DesignConstants.FontSize.caption))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.system(size: DesignConstants.FontSize.caption))

            TextField("Filter", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: DesignConstants.FontSize.small))

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: DesignConstants.FontSize.caption))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, DesignConstants.Spacing.xs)
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sidebar.right")
                .font(.system(size: DesignConstants.IconSize.extraLarge))
                .foregroundStyle(.quaternary)
            Text("No Selection")
                .font(.system(size: DesignConstants.FontSize.small))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Table Info Content

    @ViewBuilder
    private func tableInfoContent(_ metadata: TableMetadata) -> some View {
        sectionHeader("SIZE")
        propertyRow("Data Size", TableMetadata.formatSize(metadata.dataSize))
        propertyRow("Index Size", TableMetadata.formatSize(metadata.indexSize))
        propertyRow("Total Size", TableMetadata.formatSize(metadata.totalSize))

        sectionHeader("STATISTICS")
        if let rows = metadata.rowCount {
            propertyRow("Rows", "\(rows)")
        }
        if let avgLen = metadata.avgRowLength {
            propertyRow("Avg Row", "\(avgLen) B")
        }

        if metadata.engine != nil || metadata.collation != nil {
            sectionHeader("METADATA")
            if let engine = metadata.engine {
                propertyRow("Engine", engine)
            }
            if let collation = metadata.collation {
                propertyRow("Collation", collation)
            }
        }

        if metadata.createTime != nil || metadata.updateTime != nil {
            sectionHeader("TIMESTAMPS")
            if let create = metadata.createTime {
                propertyRow("Created", formatDate(create))
            }
            if let update = metadata.updateTime {
                propertyRow("Updated", formatDate(update))
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private func formatDate(_ date: Date) -> String {
        RightSidebarView.dateFormatter.string(from: date)
    }

    // MARK: - Row Detail Content

    @ViewBuilder
    private func rowDetailContent(_ rowData: [(column: String, value: String?, type: String)]) -> some View {
        let filtered = searchText.isEmpty ? editState.fields : editState.fields.filter {
            $0.columnName.localizedCaseInsensitiveContains(searchText) ||
                ($0.originalValue?.localizedCaseInsensitiveContains(searchText) ?? false)
        }

        sectionHeader("FIELDS (\(filtered.count))")

        ForEach(filtered, id: \.columnName) { field in
            if isEditable && !isRowDeleted {
                editableFieldRow(field, at: field.columnIndex)
            } else {
                readonlyFieldRow(field)
            }
        }

        if isEditable && !isRowDeleted && editState.hasEdits {
            saveButton
        }
    }

    private var saveButton: some View {
        VStack(spacing: 0) {
            Divider()

            Button(action: onSave) {
                Text("Save Changes")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("s", modifiers: .command)
            .padding(12)
        }
    }

    @ViewBuilder
    private func editableFieldRow(_ field: FieldEditState, at index: Int) -> some View {
        EditableFieldView(
            columnName: field.columnName,
            columnType: field.columnType,
            isLongText: field.isLongText,
            value: Binding(
                get: { field.pendingValue ?? field.originalValue ?? "" },
                set: { editState.updateField(at: index, value: $0) }
            ),
            originalValue: field.originalValue,
            hasMultipleValues: field.hasMultipleValues,
            isPendingNull: field.isPendingNull,
            isPendingDefault: field.isPendingDefault,
            onSetNull: { editState.setFieldToNull(at: index) },
            onSetDefault: { editState.setFieldToDefault(at: index) },
            onSetFunction: { editState.setFieldToFunction(at: index, function: $0) }
        )
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func readonlyFieldRow(_ field: FieldEditState) -> some View {
        ReadOnlyFieldView(
            columnName: field.columnName,
            columnType: field.columnType,
            isLongText: field.isLongText,
            value: field.originalValue
        )
        .padding(.horizontal, 12)
    }

    // MARK: - UI Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: DesignConstants.FontSize.caption, weight: .medium))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func propertyRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: DesignConstants.FontSize.small))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: DesignConstants.FontSize.small))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @StateObject var editState = MultiRowEditState()
    return RightSidebarView(
        tableName: "users",
        tableMetadata: TableMetadata(
            tableName: "users",
            dataSize: 16_384,
            indexSize: 8_192,
            totalSize: 24_576,
            avgRowLength: 128,
            rowCount: 1_250,
            comment: "User accounts",
            engine: "InnoDB",
            collation: "utf8mb4_unicode_ci",
            createTime: Date(),
            updateTime: nil
        ),
        selectedRowData: nil,
        isEditable: false,
        isRowDeleted: false,
        onSave: {},
        editState: editState
    )
    .frame(width: 280, height: 400)
}
