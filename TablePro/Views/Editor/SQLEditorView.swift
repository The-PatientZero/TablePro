//
//  SQLEditorView.swift
//  TablePro
//
//  SwiftUI wrapper for CodeEditSourceEditor-based SQL editor
//

import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import SwiftUI

// MARK: - SQLEditorView

/// SwiftUI SQL editor powered by CodeEditSourceEditor
struct SQLEditorView: View {
    @Binding var text: String
    @Binding var cursorPositions: [CursorPosition]
    var schemaProvider: SQLSchemaProvider?

    @State private var editorState = SourceEditorState()
    @State private var completionAdapter: SQLCompletionAdapter?
    @State private var coordinator = SQLEditorCoordinator()
    @State private var editorConfiguration = makeConfiguration()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SourceEditor(
            $text,
            language: .sql,
            configuration: editorConfiguration,
            state: $editorState,
            coordinators: [coordinator],
            completionDelegate: completionAdapter
        )
        .onChange(of: editorState.cursorPositions) { newValue in
            guard let positions = newValue else { return }
            // Skip cursor propagation when the editor doesn't have focus
            // (e.g., find panel match highlighting). Propagating triggers
            // a SwiftUI re-render that disrupts the find panel's focus.
            guard coordinator.isEditorFirstResponder else { return }
            // Guard against stale propagation during tab switch (.id() recreation):
            // verify the editor's text still matches the binding before propagating.
            if let controller = coordinator.controller,
               controller.textView.string != text {
                return
            }
            cursorPositions = positions
        }
        // SourceEditor doesn't re-read the text binding in updateNSViewController,
        // so programmatic changes on the SAME tab (clear, format) won't appear
        // without this. Tab switches don't need it — .id(tab.id) recreates the
        // entire SourceEditor with the correct text.
        .onChange(of: text) { newValue in
            if let controller = coordinator.controller,
               controller.textView.string != newValue {
                let fullRange = NSRange(location: 0, length: (controller.textView.string as NSString).length)
                controller.textView.replaceCharacters(in: fullRange, with: newValue)
            }
        }
        .onChange(of: colorScheme) { _ in
            editorConfiguration = Self.makeConfiguration()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorSettingsDidChange)) { _ in
            editorConfiguration = Self.makeConfiguration()
        }
        .onAppear {
            if completionAdapter == nil {
                completionAdapter = SQLCompletionAdapter(schemaProvider: schemaProvider)
            }
        }
    }

    // MARK: - Configuration

    private static func makeConfiguration() -> SourceEditorConfiguration {
        SourceEditorConfiguration(
            appearance: .init(
                theme: TableProEditorTheme.make(),
                font: SQLEditorTheme.font,
                wrapLines: SQLEditorTheme.wordWrap,
                tabWidth: SQLEditorTheme.tabWidth
            ),
            behavior: .init(
                indentOption: .spaces(count: SQLEditorTheme.tabWidth)
            ),
            layout: .init(
                contentInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            ),
            peripherals: .init(
                showGutter: SQLEditorTheme.showLineNumbers,
                showMinimap: false,
                showFoldingRibbon: false
            )
        )
    }
}

// MARK: - Preview

#Preview {
    SQLEditorView(
        text: .constant("SELECT * FROM users\nWHERE active = true;"),
        cursorPositions: .constant([])
    )
    .frame(width: 500, height: 200)
}
