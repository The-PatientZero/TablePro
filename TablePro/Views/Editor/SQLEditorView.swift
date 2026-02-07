//
//  SQLEditorView.swift
//  TablePro
//
//  Production-quality SQL editor using AppKit NSTextView
//  Fully rewritten with clean architecture
//

import AppKit
import SwiftUI

// MARK: - SQLEditorView

/// SwiftUI wrapper for the SQL editor
struct SQLEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorPosition: Int
    var onExecute: (() -> Void)?
    var schemaProvider: SQLSchemaProvider?

    func makeNSView(context: Context) -> NSView {
        // Create container view to hold line numbers and scroll view
        let containerView = NSView()

        // Create scroll view
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = SQLEditorTheme.background

        // Create text storage, layout manager, and text container
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        // Allow non-contiguous layout: lets the layout manager skip laying out offscreen
        // regions. This is the single most important setting for large-document performance.
        layoutManager.allowsNonContiguousLayout = true
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))

        // Word wrap configuration based on settings
        let wordWrap = SQLEditorTheme.wordWrap
        if wordWrap {
            textContainer.widthTracksTextView = true
        } else {
            textContainer.widthTracksTextView = false
            textContainer.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }

        textContainer.lineFragmentPadding = SQLEditorTheme.lineFragmentPadding
        layoutManager.addTextContainer(textContainer)

        // Create text view using EditorTextView with the text container
        let textView = EditorTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = !wordWrap
        textView.autoresizingMask = .width

        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = SQLEditorTheme.font
        textView.textColor = SQLEditorTheme.text
        textView.backgroundColor = SQLEditorTheme.background
        textView.drawsBackground = true
        textView.insertionPointColor = SQLEditorTheme.insertionPoint
        textView.textContainerInset = SQLEditorTheme.textContainerInset

        // Disable all automatic text features for SQL syntax integrity and performance
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.usesFontPanel = false
        textView.usesFindBar = true

        // Set initial text
        textView.string = text

        // MUST set documentView BEFORE coordinator setup so that
        // textView.enclosingScrollView is non-nil when SyntaxHighlighter
        // attaches its scroll observer for viewport-based highlighting.
        scrollView.documentView = textView

        // Set up coordinator (textStorage is now guaranteed to exist)
        context.coordinator.setup(textView: textView, textStorage: textStorage)

        // Create custom line number view (positioned left of scroll view)
        let lineNumberView = LineNumberView(textView: textView, scrollView: scrollView)

        // Add both views to container
        containerView.addSubview(lineNumberView)
        containerView.addSubview(scrollView)

        // Disable autoresizing masks (use Auto Layout)
        lineNumberView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Store reference to line number view for visibility control
        context.coordinator.lineNumberView = lineNumberView

        // Apply initial line number visibility from settings
        let showLineNumbers = SQLEditorTheme.showLineNumbers
        lineNumberView.isHidden = !showLineNumbers

        // Set up layout constraints
        // Use width constraint for line number view that can be toggled
        let lineNumberWidthConstraint = lineNumberView.widthAnchor.constraint(equalToConstant: showLineNumbers ? lineNumberView.intrinsicContentSize.width : 0)
        lineNumberWidthConstraint.priority = .defaultHigh
        context.coordinator.lineNumberWidthConstraint = lineNumberWidthConstraint

        NSLayoutConstraint.activate([
            // Line number view: left side, full height
            lineNumberView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            lineNumberView.topAnchor.constraint(equalTo: containerView.topAnchor),
            lineNumberView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            // Scroll view: right side, full height
            scrollView.leadingAnchor.constraint(equalTo: lineNumberView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Extract scroll view from container view and update text if changed from SwiftUI side
        if nsView.subviews.first(where: { $0 is NSScrollView }) is NSScrollView {
            context.coordinator.updateTextViewIfNeeded(with: text)
        }

        // Update line number visibility based on settings
        let showLineNumbers = SQLEditorTheme.showLineNumbers
        if let lineNumberView = context.coordinator.lineNumberView {
            lineNumberView.isHidden = !showLineNumbers
        }
    }

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(
            text: $text,
            cursorPosition: $cursorPosition,
            onExecute: onExecute,
            schemaProvider: schemaProvider
        )
    }
}

// MARK: - Preview

#Preview {
    SQLEditorView(
        text: .constant("SELECT * FROM users\nWHERE active = true;"),
        cursorPosition: .constant(0)
    )
    .frame(width: 500, height: 200)
}
