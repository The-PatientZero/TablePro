//
//  SchemaPreviewSheet.swift
//  TablePro
//
//  SwiftUI sheet showing SQL preview before executing schema changes
//

import SwiftUI

/// Sheet for previewing ALTER TABLE statements before execution
struct SchemaPreviewSheet: View {
    let statements: [String]
    let onApply: () -> Void
    let onCancel: () -> Void

    @AppStorage("skipSchemaPreview") private var skipPreview = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Preview Schema Changes")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // SQL Statements
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if statements.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(statements.enumerated()), id: \.offset) { index, sql in
                            sqlStatement(sql: sql, index: index + 1)
                        }
                    }
                }
                .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            // Footer
            HStack {
                Toggle("Don't show this again", isOn: $skipPreview)
                    .help("You can re-enable this in Settings")

                Spacer()

                Button("Cancel") {
                    dismiss()
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Apply Changes") {
                    dismiss()
                    onApply()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 700, height: 500)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.plaintext")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No changes to preview")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sqlStatement(sql: String, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Statement \(index)")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                copyButton(sql: sql)
            }

            // SQL text with monospaced font
            Text(sql)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }

    private func copyButton(sql: String) -> some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(sql, forType: .string)
        }) {
            Label("Copy", systemImage: "doc.on.doc")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .help("Copy this statement to clipboard")
    }
}

#Preview {
    SchemaPreviewSheet(
        statements: [
            "ALTER TABLE users ADD COLUMN email VARCHAR(255) NOT NULL",
            "ALTER TABLE users MODIFY COLUMN name VARCHAR(100) NOT NULL",
            "CREATE INDEX idx_email ON users(email)"
        ],
        onApply: {},
        onCancel: {}
    )
}
