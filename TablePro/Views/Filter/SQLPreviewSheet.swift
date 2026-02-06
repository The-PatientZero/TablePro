//
//  SQLPreviewSheet.swift
//  TablePro
//
//  Modal sheet to display generated SQL from filters.
//  Extracted from FilterPanelView for better maintainability.
//

import SwiftUI

/// Modal sheet to display generated SQL
struct SQLPreviewSheet: View {
    let sql: String
    let tableName: String
    let databaseType: DatabaseType
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Generated WHERE Clause")
                    .font(.system(size: DesignConstants.FontSize.body, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: DesignConstants.IconSize.default))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }

            ScrollView {
                Text(sql.isEmpty ? "(no conditions)" : sql)
                    .font(.system(size: DesignConstants.FontSize.medium, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 180)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )

            HStack {
                Button(action: copyToClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: DesignConstants.FontSize.small))
                        Text(copied ? "Copied!" : "Copy")
                            .font(.system(size: DesignConstants.FontSize.medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(sql.isEmpty)

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 480, height: 300)
        .onExitCommand {
            dismiss()
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sql, forType: .string)
        copied = true

        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}
