//
//  EditableFieldView.swift
//  TablePro
//
//  Compact, type-aware field editor for right sidebar.
//  Two-line layout: field name + type badge, then native editor + menu.
//

import SwiftUI

/// Compact editable field view using native macOS components
struct EditableFieldView: View {
    let columnName: String
    let columnTypeEnum: ColumnType
    let isLongText: Bool
    @Binding var value: String
    let originalValue: String?
    let hasMultipleValues: Bool
    let isPendingNull: Bool
    let isPendingDefault: Bool
    let isModified: Bool

    let onSetNull: () -> Void
    let onSetDefault: () -> Void
    let onSetEmpty: () -> Void
    let onSetFunction: (String) -> Void

    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    private var placeholderText: String {
        if hasMultipleValues {
            return String(localized: "Multiple values")
        } else if let original = originalValue {
            return original
        } else {
            return "NULL"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Line 1: modified indicator + field name + type badge
            HStack(spacing: 4) {
                if isModified {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }

                Text(columnName)
                    .font(.system(size: DesignConstants.FontSize.small))
                    .lineLimit(1)

                Spacer()

                Text(columnTypeEnum.badgeLabel)
                    .font(.system(size: DesignConstants.FontSize.tiny, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }

            // Line 2: full-width editor with inline menu overlay
            typeAwareEditor
                .overlay(alignment: .topTrailing) {
                    fieldMenu
                        .opacity(isHovered ? 1 : 0)
                        .padding(.trailing, 4)
                }
        }
        .onHover { isHovered = $0 }
    }

    // MARK: - Type-Aware Editor

    @ViewBuilder
    private var typeAwareEditor: some View {
        if isPendingNull || isPendingDefault {
            TextField(isPendingNull ? "NULL" : "DEFAULT", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: DesignConstants.FontSize.small))
                .disabled(true)
        } else if columnTypeEnum.isBooleanType {
            booleanPicker
        } else if (columnTypeEnum.isEnumType || columnTypeEnum.isSetType),
                  let values = columnTypeEnum.enumValues, !values.isEmpty {
            enumPicker(values: values)
        } else if isLongText || columnTypeEnum.isJsonType {
            multiLineEditor
        } else {
            singleLineEditor
        }
    }

    private var booleanPicker: some View {
        Picker("", selection: Binding(
            get: { normalizeBooleanValue(value) },
            set: { value = $0 }
        )) {
            Text("true").tag("1")
            Text("false").tag("0")
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }

    private func enumPicker(values: [String]) -> some View {
        Picker("", selection: Binding(
            get: { value },
            set: { value = $0 }
        )) {
            ForEach(values, id: \.self) { val in
                Text(val).tag(val)
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }

    private var multiLineEditor: some View {
        TextField(placeholderText, text: $value, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: DesignConstants.FontSize.small))
            .lineLimit(3...6)
            .focused($isFocused)
    }

    private var singleLineEditor: some View {
        TextField(placeholderText, text: $value)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: DesignConstants.FontSize.small))
            .focused($isFocused)
    }

    // MARK: - Field Menu

    private var fieldMenu: some View {
        Menu {
            Button("Set NULL") {
                onSetNull()
            }

            Button("Set DEFAULT") {
                onSetDefault()
            }

            Button("Set EMPTY") {
                onSetEmpty()
            }

            Divider()

            if columnTypeEnum.isJsonType {
                Button("Pretty Print") {
                    if let formatted = value.prettyPrintedAsJson() {
                        value = formatted
                    }
                }
            }

            Button("Copy Value") {
                ClipboardService.shared.writeText(value)
            }

            Divider()

            Menu("SQL Functions") {
                Button("NOW()") { onSetFunction("NOW()") }
                Button("CURRENT_TIMESTAMP()") { onSetFunction("CURRENT_TIMESTAMP()") }
                Button("CURDATE()") { onSetFunction("CURDATE()") }
                Button("CURTIME()") { onSetFunction("CURTIME()") }
                Button("UTC_TIMESTAMP()") { onSetFunction("UTC_TIMESTAMP()") }
            }

            if isPendingNull || isPendingDefault {
                Divider()
                Button("Clear") {
                    value = originalValue ?? ""
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Helpers

    private func normalizeBooleanValue(_ val: String) -> String {
        let lower = val.lowercased()
        if lower == "true" || lower == "1" || lower == "t" || lower == "yes" {
            return "1"
        }
        return "0"
    }
}

/// Read-only field view using native macOS components
struct ReadOnlyFieldView: View {
    let columnName: String
    let columnTypeEnum: ColumnType
    let isLongText: Bool
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Line 1: field name + type badge
            HStack(spacing: 4) {
                Text(columnName)
                    .font(.system(size: DesignConstants.FontSize.small))
                    .lineLimit(1)

                Spacer()

                Text(columnTypeEnum.badgeLabel)
                    .font(.system(size: DesignConstants.FontSize.tiny, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }

            // Line 2: value in disabled native text field
            if let value {
                if isLongText {
                    Text(value)
                        .font(.system(size: DesignConstants.FontSize.small, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, maxHeight: 80, alignment: .topLeading)
                } else {
                    TextField("", text: .constant(value))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: DesignConstants.FontSize.small))
                        .disabled(true)
                }
            } else {
                TextField("NULL", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: DesignConstants.FontSize.small))
                    .disabled(true)
            }
        }
        .contextMenu {
            if let value {
                Button("Copy Value") {
                    ClipboardService.shared.writeText(value)
                }
            }
        }
    }
}
