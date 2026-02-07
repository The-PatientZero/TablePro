//
//  SyntaxHighlighter.swift
//  TablePro
//
//  Incremental syntax highlighter for SQL using NSTextStorageDelegate.
//  Uses viewport-only highlighting for large documents — only the visible
//  range plus a buffer zone is highlighted, with lazy expansion on scroll.
//

import AppKit

/// Incremental syntax highlighter that operates on edited ranges only
final class SyntaxHighlighter: NSObject, NSTextStorageDelegate {
    // MARK: - Properties

    private weak var textStorage: NSTextStorage?
    private weak var scrollView: NSScrollView?
    private weak var textView: NSTextView?

    /// Edits larger than this trigger viewport-only highlighting instead of chunked full-doc
    private static let viewportThreshold = 50_000

    /// Buffer zone (in characters) above and below the viewport to pre-highlight
    private static let viewportBuffer = 10_000

    /// Maximum characters to highlight in a single highlightRange call.
    /// SQL dumps often have mega-lines (millions of chars); running 7 regex
    /// patterns on a 10MB line freezes the main thread for seconds.
    private static let maxHighlightRangeSize = 10_000

    /// Tracks which ranges have already been highlighted (avoids re-work on scroll)
    private var highlightedRanges = IndexSet()

    /// Debounce timer for scroll-based highlighting
    private var scrollDebounceItem: DispatchWorkItem?

    /// Whether the document is large enough to use viewport-only mode
    private var isLargeDocument: Bool = false

    /// Reentrancy guard: prevents didProcessEditing from re-entering
    /// when highlightRange's endEditing triggers another delegate callback
    private var isProcessingEdit: Bool = false

    /// SQL keywords for highlighting (synced with SQLKeywords for consistency)
    private static let keywords: Set<String> = [
        // DQL
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "LIKE", "BETWEEN",
        "AS", "DISTINCT", "ALL", "TOP",

        // Joins
        "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS", "ON", "USING",

        // Ordering & Grouping
        "ORDER", "BY", "ASC", "DESC", "NULLS", "FIRST", "LAST",
        "GROUP", "HAVING",

        // Limiting
        "LIMIT", "OFFSET", "FETCH", "NEXT", "ROWS", "ONLY",

        // Set operations
        "UNION", "INTERSECT", "EXCEPT", "MINUS",

        // Subqueries
        "EXISTS", "ANY", "SOME",

        // DML
        "INSERT", "INTO", "VALUES", "DEFAULT",
        "UPDATE", "SET",
        "DELETE", "TRUNCATE",

        // DDL - Tables
        "CREATE", "ALTER", "DROP", "RENAME", "MODIFY", "CHANGE",
        "TABLE", "VIEW", "INDEX", "DATABASE", "SCHEMA",
        "ADD", "COLUMN", "AFTER", "BEFORE",

        // Constraints
        "CONSTRAINT", "PRIMARY", "FOREIGN", "KEY", "REFERENCES",
        "UNIQUE", "CHECK", "CASCADE", "RESTRICT", "NO", "ACTION",
        "AUTO_INCREMENT", "AUTOINCREMENT", "SERIAL",

        // Data types
        "INT", "INTEGER", "BIGINT", "SMALLINT", "TINYINT",
        "DECIMAL", "NUMERIC", "FLOAT", "DOUBLE", "REAL",
        "VARCHAR", "CHAR", "TEXT", "BLOB", "CLOB",
        "DATE", "TIME", "DATETIME", "TIMESTAMP", "YEAR",
        "BOOLEAN", "BOOL", "BIT", "JSON", "JSONB", "XML",
        "UUID", "BINARY", "VARBINARY", "UNSIGNED", "SIGNED",

        // Conditionals
        "CASE", "WHEN", "THEN", "ELSE", "END", "IF",

        // NULL/Boolean
        "NULL", "IS", "TRUE", "FALSE", "UNKNOWN",

        // Transactions
        "BEGIN", "COMMIT", "ROLLBACK", "SAVEPOINT", "TRANSACTION",

        // Other
        "WITH", "RECURSIVE", "TEMPORARY", "TEMP",
        "EXPLAIN", "ANALYZE", "DESCRIBE", "SHOW",
        "WINDOW", "OVER", "PARTITION", "RANGE",
        "ILIKE", "SIMILAR", "REGEXP", "RLIKE"
    ]

    // MARK: - Compiled Regex Patterns (Thread-Safe, Compiled Once)

    private static let keywordRegex: NSRegularExpression? = {
        let pattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
        return try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()

    private static let stringRegexes: [NSRegularExpression] = {
        ["'[^']*'", "\"[^\"]*\"", "`[^`]*`"].compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    private static let numberRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b")
    }()

    private static let singleLineCommentRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "--[^\\n]*")
    }()

    private static let multiLineCommentRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "/\\*[\\s\\S]*?\\*/")
    }()

    private static let nullBoolRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\b(NULL|TRUE|FALSE)\\b", options: .caseInsensitive)
    }()

    // MARK: - Initialization

    init(textStorage: NSTextStorage) {
        self.textStorage = textStorage
        super.init()
        textStorage.delegate = self
    }

    /// Attach scroll view for viewport-based highlighting on scroll
    func attachScrollView(_ scrollView: NSScrollView, textView: NSTextView) {
        self.scrollView = scrollView
        self.textView = textView

        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - NSTextStorageDelegate

    /// Called after text storage processes an edit
    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // Only process character changes, not attribute-only changes
        guard editedMask.contains(.editedCharacters) else { return }

        // Prevent reentrancy: highlightRange calls endEditing which can
        // fire didProcessEditing again, creating a tight CPU-burning loop.
        guard !isProcessingEdit else { return }
        isProcessingEdit = true
        defer { isProcessingEdit = false }

        let length = textStorage.length
        guard length > 0 else { return }

        isLargeDocument = length > Self.viewportThreshold

        if isLargeDocument {
            // Large edit (file load, paste) — invalidate highlighted ranges that shifted
            if delta != 0 {
                shiftHighlightedRanges(editedLocation: editedRange.location, delta: delta)
            }

            // If the edit covers most of the document (file load, large paste),
            // skip immediate highlighting — let viewport highlighting handle it.
            // Running 7 regex patterns over 40MB freezes the app for seconds.
            if editedRange.length > Self.viewportThreshold {
                scheduleViewportHighlighting()
            } else {
                // Normal edit — highlight just the edited line range.
                // Cap the range to prevent running regex on mega-lines (SQL dumps
                // can have single lines with millions of characters).
                let text = textStorage.string
                var expandedRange = expandToLineRange(editedRange, in: text)
                if expandedRange.length > Self.maxHighlightRangeSize {
                    // Center the capped range around the edit point
                    let editCenter = editedRange.location + editedRange.length / 2
                    let halfCap = Self.maxHighlightRangeSize / 2
                    let capStart = max(expandedRange.location, editCenter - halfCap)
                    let capEnd = min(NSMaxRange(expandedRange), capStart + Self.maxHighlightRangeSize)
                    expandedRange = NSRange(location: capStart, length: capEnd - capStart)
                }
                highlightRange(expandedRange, in: textStorage)
                highlightedRanges.insert(integersIn: expandedRange.location..<NSMaxRange(expandedRange))

                // Also ensure viewport is highlighted
                scheduleViewportHighlighting()
            }
        } else {
            // Small document — highlight edited lines immediately
            let text = textStorage.string
            let expandedRange = expandToLineRange(editedRange, in: text)
            highlightRange(expandedRange, in: textStorage)
        }
    }

    // MARK: - Public API

    /// Manually trigger highlighting (e.g., on initial load)
    func highlightFullDocument() {
        guard let textStorage = textStorage else { return }
        let length = textStorage.length
        guard length > 0 else { return }

        isLargeDocument = length > Self.viewportThreshold
        highlightedRanges = IndexSet()

        if isLargeDocument {
            // Only highlight the viewport — rest is done lazily on scroll
            highlightViewport()
        } else {
            highlightRange(NSRange(location: 0, length: length), in: textStorage)
            highlightedRanges.insert(integersIn: 0..<length)
        }
    }

    /// Cancel any pending deferred highlighting
    func cancelDeferredHighlighting() {
        scrollDebounceItem?.cancel()
        scrollDebounceItem = nil
    }

    // MARK: - Viewport-Based Highlighting

    @objc private func scrollViewDidScroll() {
        guard isLargeDocument else { return }
        scheduleViewportHighlighting()
    }

    private func scheduleViewportHighlighting() {
        scrollDebounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.highlightViewport()
        }
        scrollDebounceItem = item
        // Small delay to coalesce rapid scroll events
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    /// Highlight only the visible range + buffer, skipping already-highlighted regions
    private func highlightViewport() {
        guard let textStorage = textStorage,
              let scrollView = scrollView,
              let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let length = textStorage.length
        guard length > 0 else { return }

        // Get the visible character range from the layout manager
        let visibleRect = scrollView.contentView.bounds
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.location != NSNotFound, glyphRange.length > 0 else { return }

        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Expand by buffer zone
        let bufferStart = max(0, charRange.location - Self.viewportBuffer)
        let bufferEnd = min(length, NSMaxRange(charRange) + Self.viewportBuffer)
        let targetRange = NSRange(location: bufferStart, length: bufferEnd - bufferStart)

        // Expand to line boundaries
        let text = textStorage.string
        let lineAligned = expandToLineRange(targetRange, in: text)

        // Find sub-ranges that haven't been highlighted yet
        let targetSet = IndexSet(integersIn: lineAligned.location..<NSMaxRange(lineAligned))
        let unhighlighted = targetSet.subtracting(highlightedRanges)

        // Highlight each unhighlighted contiguous range.
        // Process in chunks to avoid running regex on mega-lines.
        for range in unhighlighted.rangeView {
            let nsRange = NSRange(location: range.lowerBound, length: range.count)
            let aligned = expandToLineRange(nsRange, in: text)
            guard aligned.length > 0, NSMaxRange(aligned) <= length else { continue }

            // Split large ranges into chunks to avoid running regex on mega-lines
            if aligned.length > Self.maxHighlightRangeSize {
                var offset = aligned.location
                while offset < NSMaxRange(aligned) {
                    let chunkLength = min(Self.maxHighlightRangeSize, NSMaxRange(aligned) - offset)
                    let chunk = NSRange(location: offset, length: chunkLength)
                    highlightRange(chunk, in: textStorage)
                    offset += chunkLength
                }
            } else {
                highlightRange(aligned, in: textStorage)
            }
        }

        // Mark entire target as highlighted
        highlightedRanges.formUnion(targetSet)
    }

    /// Shift tracked ranges when text is edited (insert/delete)
    private func shiftHighlightedRanges(editedLocation: Int, delta: Int) {
        if delta > 0 {
            // Insertion: shift ranges after the edit point forward
            var shifted = IndexSet()
            for range in highlightedRanges.rangeView {
                if range.lowerBound >= editedLocation {
                    shifted.insert(integersIn: (range.lowerBound + delta)..<(range.upperBound + delta))
                } else if range.upperBound > editedLocation {
                    // Range straddles the edit: keep the part before, shift the part after
                    shifted.insert(integersIn: range.lowerBound..<editedLocation)
                    shifted.insert(integersIn: (editedLocation + delta)..<(range.upperBound + delta))
                } else {
                    shifted.insert(integersIn: range)
                }
            }
            highlightedRanges = shifted
        } else if delta < 0 {
            // Deletion: remove the deleted range, shift ranges after it backward
            let deletedEnd = editedLocation - delta // editedLocation + abs(delta)
            var shifted = IndexSet()
            for range in highlightedRanges.rangeView {
                if range.lowerBound >= deletedEnd {
                    shifted.insert(integersIn: (range.lowerBound + delta)..<(range.upperBound + delta))
                } else if range.upperBound <= editedLocation {
                    shifted.insert(integersIn: range)
                } else {
                    // Range overlaps deletion — keep only the parts outside
                    if range.lowerBound < editedLocation {
                        shifted.insert(integersIn: range.lowerBound..<editedLocation)
                    }
                    if range.upperBound > deletedEnd {
                        shifted.insert(integersIn: editedLocation..<(range.upperBound + delta))
                    }
                }
            }
            highlightedRanges = shifted
        }
    }

    // MARK: - Private Helpers

    /// Expand edited range to include full lines
    private func expandToLineRange(_ range: NSRange, in text: String) -> NSRange {
        let nsString = text as NSString
        let length = nsString.length
        guard length > 0, range.location < length else {
            return NSRange(location: 0, length: length)
        }

        let clampedRange = NSRange(
            location: min(range.location, length),
            length: min(range.length, length - min(range.location, length))
        )
        return nsString.lineRange(for: clampedRange)
    }

    /// Apply syntax highlighting to a specific range
    private func highlightRange(_ range: NSRange, in textStorage: NSTextStorage) {
        guard range.length > 0, NSMaxRange(range) <= textStorage.length else {
            return
        }

        let nsText = textStorage.string as NSString
        let substring = nsText.substring(with: range)
        let substringLength = (substring as NSString).length

        // Begin editing (batch attribute changes)
        textStorage.beginEditing()

        // Reset to default attributes in this range
        textStorage.addAttributes([
            .font: SQLEditorTheme.font,
            .foregroundColor: SQLEditorTheme.text
        ], range: range)

        // Detect strings and comments first (these take precedence)
        var stringRanges: [NSRange] = []
        var commentRanges: [NSRange] = []

        // Find all strings
        for regex in Self.stringRegexes {
            regex.enumerateMatches(
                in: substring, range: NSRange(location: 0, length: substringLength)
            ) { match, _, _ in
                if let matchRange = match?.range {
                    let absoluteRange = NSRange(
                        location: range.location + matchRange.location,
                        length: matchRange.length
                    )
                    stringRanges.append(absoluteRange)
                    textStorage.addAttribute(
                        .foregroundColor, value: SQLEditorTheme.string, range: absoluteRange
                    )
                }
            }
        }

        // Find all comments
        Self.singleLineCommentRegex?.enumerateMatches(
            in: substring, range: NSRange(location: 0, length: substringLength)
        ) { match, _, _ in
            if let matchRange = match?.range {
                let absoluteRange = NSRange(
                    location: range.location + matchRange.location, length: matchRange.length
                )
                commentRanges.append(absoluteRange)
                textStorage.addAttribute(
                    .foregroundColor, value: SQLEditorTheme.comment, range: absoluteRange
                )
            }
        }

        Self.multiLineCommentRegex?.enumerateMatches(
            in: substring, range: NSRange(location: 0, length: substringLength)
        ) { match, _, _ in
            if let matchRange = match?.range {
                let absoluteRange = NSRange(
                    location: range.location + matchRange.location, length: matchRange.length
                )
                commentRanges.append(absoluteRange)
                textStorage.addAttribute(
                    .foregroundColor, value: SQLEditorTheme.comment, range: absoluteRange
                )
            }
        }

        // Build IndexSet for O(log n) overlap checks
        var stringOrCommentIndices = IndexSet()
        for r in stringRanges {
            stringOrCommentIndices.insert(integersIn: r.location..<(r.location + r.length))
        }
        for r in commentRanges {
            stringOrCommentIndices.insert(integersIn: r.location..<(r.location + r.length))
        }

        let isInsideStringOrComment: (NSRange) -> Bool = { checkRange in
            !stringOrCommentIndices.intersection(
                IndexSet(integersIn: checkRange.location..<NSMaxRange(checkRange))
            ).isEmpty
        }

        // Highlight keywords (only outside strings/comments)
        Self.keywordRegex?.enumerateMatches(
            in: substring, range: NSRange(location: 0, length: substringLength)
        ) { match, _, _ in
            if let matchRange = match?.range {
                let absoluteRange = NSRange(
                    location: range.location + matchRange.location, length: matchRange.length
                )
                if !isInsideStringOrComment(absoluteRange) {
                    textStorage.addAttribute(
                        .foregroundColor, value: SQLEditorTheme.keyword, range: absoluteRange
                    )
                }
            }
        }

        // Highlight numbers (only outside strings/comments)
        Self.numberRegex?.enumerateMatches(
            in: substring, range: NSRange(location: 0, length: substringLength)
        ) { match, _, _ in
            if let matchRange = match?.range {
                let absoluteRange = NSRange(
                    location: range.location + matchRange.location, length: matchRange.length
                )
                if !isInsideStringOrComment(absoluteRange) {
                    textStorage.addAttribute(
                        .foregroundColor, value: SQLEditorTheme.number, range: absoluteRange
                    )
                }
            }
        }

        // Highlight NULL, TRUE, FALSE (only outside strings/comments)
        Self.nullBoolRegex?.enumerateMatches(
            in: substring, range: NSRange(location: 0, length: substringLength)
        ) { match, _, _ in
            if let matchRange = match?.range {
                let absoluteRange = NSRange(
                    location: range.location + matchRange.location, length: matchRange.length
                )
                if !isInsideStringOrComment(absoluteRange) {
                    textStorage.addAttribute(
                        .foregroundColor, value: SQLEditorTheme.null, range: absoluteRange
                    )
                }
            }
        }

        // End editing (commit changes)
        textStorage.endEditing()
    }
}
