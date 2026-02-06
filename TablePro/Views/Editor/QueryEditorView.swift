//
//  QueryEditorView.swift
//  TablePro
//
//  SQL query editor wrapper with toolbar
//

import SwiftUI

extension Notification.Name {
    static let formatQueryRequested = Notification.Name("formatQueryRequested")
}

/// SQL query editor view with execute button
struct QueryEditorView: View {
    @Binding var queryText: String
    @Binding var cursorPosition: Int  // Track cursor for query-at-cursor execution
    var onExecute: () -> Void
    var schemaProvider: SQLSchemaProvider?  // Optional for autocomplete

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Editor header with toolbar (above editor, higher z-index)
            editorToolbar
                .zIndex(1)

            Divider()

            // SQL Editor (AppKit-based with syntax highlighting and built-in line numbers)
            SQLEditorView(text: $queryText, cursorPosition: $cursorPosition, onExecute: onExecute, schemaProvider: schemaProvider)
                .frame(minHeight: 100)
                .clipped()
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .formatQueryRequested)) { _ in
            formatQuery()
        }
    }

    // MARK: - Toolbar

    private var editorToolbar: some View {
        HStack {
            Text("Query")
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()

            // Clear button
            Button(action: { queryText = "" }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Clear Query (⌘+Delete)")
            .keyboardShortcut(.delete, modifiers: .command)

            // Format button
            Button(action: formatQuery) {
                Image(systemName: "text.alignleft")
            }
            .buttonStyle(.borderless)
            .help("Format Query (⌥⌘F)")
            .keyboardShortcut("f", modifiers: [.option, .command])

            Divider()
                .frame(height: 16)

            // Execute button
            Button(action: onExecute) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                    Text("Execute")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helpers

    private func formatQuery() {
        // Get current database type from active session
        let dbType = DatabaseManager.shared.currentSession?.connection.type ?? .mysql

        // Create formatter service
        let formatter = SQLFormatterService()
        let options = SQLFormatterOptions.default

        do {
            // Format SQL with cursor preservation
            let result = try formatter.format(
                queryText,
                dialect: dbType,
                cursorOffset: cursorPosition,
                options: options
            )

            // Update text and cursor position
            queryText = result.formattedSQL
            if let newCursor = result.cursorOffset {
                cursorPosition = newCursor
            }
        } catch {
            // Show error to user (could enhance with an alert later)
            print("SQL Formatting error: \(error.localizedDescription)")
        }
    }
}

#Preview {
    QueryEditorView(
        queryText: .constant("SELECT * FROM users\nWHERE active = true\nORDER BY created_at DESC;"),
        cursorPosition: .constant(0)
    )        {}
    .frame(width: 600, height: 200)
}
