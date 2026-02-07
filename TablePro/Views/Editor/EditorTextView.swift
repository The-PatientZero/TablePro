//
//  EditorTextView.swift
//  TablePro
//
//  NSTextView subclass for SQL editor with auto-pairing and visual features
//

import AppKit

/// NSTextView subclass that handles input, auto-pairing, and drawing visual features
final class EditorTextView: NSTextView {
    // MARK: - Properties

    /// Callback for handling Cmd+Enter (execute query)
    var onExecute: (() -> Void)?

    /// Callback for handling Ctrl+Space (manual completion trigger)
    var onManualCompletion: (() -> Void)?

    /// Callback for handling key events (returns true if handled)
    var onKeyEvent: ((NSEvent) -> Bool)?

    /// Callback when user clicks at a different position (to dismiss completion)
    var onClickOutsideCompletion: (() -> Void)?

    /// Track the last cursor Y position for smart invalidation (O(1) comparison)
    private var lastCursorLineY: CGFloat = -.greatestFiniteMagnitude
    /// Cached rect of the last cursor line for invalidation
    private var lastCursorLineRect: NSRect?

    /// Margin to expand invalidation rect to ensure borders/effects are redrawn
    private let lineInvalidationMargin: CGFloat = 2

    // MARK: - Auto-Pairing Configuration

    private let bracketPairs: [Character: Character] = [
        "(": ")",
        "[": "]",
        "{": "}",
    ]

    private let quotePairs: [Character: Character] = [
        "'": "'",
        "\"": "\"",
        "`": "`",
    ]

    // UTF-16 bracket pair maps for O(1) bracket matching without Array(string)
    private let bracketPairMap: [unichar: unichar] = [
        unichar(UnicodeScalar("(").value): unichar(UnicodeScalar(")").value),
        unichar(UnicodeScalar("[").value): unichar(UnicodeScalar("]").value),
        unichar(UnicodeScalar("{").value): unichar(UnicodeScalar("}").value),
    ]

    private let reverseBracketPairMap: [unichar: unichar] = [
        unichar(UnicodeScalar(")").value): unichar(UnicodeScalar("(").value),
        unichar(UnicodeScalar("]").value): unichar(UnicodeScalar("[").value),
        unichar(UnicodeScalar("}").value): unichar(UnicodeScalar("{").value),
    ]

    // MARK: - Initialization

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        // Observe selection changes for visual updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: self
        )
        // Observe text changes to invalidate line cache
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: self
        )
    }

    @objc private func textDidChange(_ notification: Notification) {
        // Invalidate line cache when text changes
        lineCache = nil
        // NOTE: Do NOT reset lastCursorLineY here. Resetting it forces
        // invalidateLineHighlightIfNeeded() to query the layout manager on
        // every single keystroke, even when typing on the same line. For 40MB
        // files this triggers expensive layout computation per keystroke.
        // The selectionDidChange handler naturally detects line changes via
        // Y-position comparison, so the highlight stays correct without reset.
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func selectionDidChange(_ notification: Notification) {
        // Smart invalidation: only redraw the affected line regions
        // instead of the entire view
        invalidateLineHighlightIfNeeded()
    }

    /// Invalidate only the current and previous line regions for redraw.
    /// Uses O(1) layout manager glyph lookup + Y-position comparison instead of
    /// iterating all lines before the cursor.
    ///
    /// Key optimization for large files: `textDidChange` does NOT reset
    /// `lastCursorLineY`, so typing on the same line is a no-op here
    /// (the Y comparison short-circuits). Layout manager queries for the
    /// visible area are O(1) since layout is already cached.
    private func invalidateLineHighlightIfNeeded() {
        guard let layoutManager = layoutManager,
              layoutManager.numberOfGlyphs > 0 else {
            needsDisplay = true
            return
        }

        let charCount = (string as NSString).length
        guard charCount > 0 else {
            needsDisplay = true
            return
        }

        let cursorPos = selectedRange().location
        let clampedPos = min(max(cursorPos, 0), charCount)

        // Get the Y position of the current cursor line via layout manager.
        // For the visible area, these calls are O(1) — layout is already cached
        // by the text view's display cycle. No ensureLayout needed.
        let currentLineY: CGFloat
        var currentRect: NSRect?

        // O(1) trailing newline check via NSString UTF-16 access
        let nsText = string as NSString
        if clampedPos >= charCount && nsText.character(at: charCount - 1) == 0x0A {
            // Cursor on empty last line after trailing newline
            let lastGlyph = layoutManager.numberOfGlyphs - 1
            guard lastGlyph >= 0 else { needsDisplay = true; return }
            let lastRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
            currentLineY = lastRect.maxY + textContainerOrigin.y
            // Compute currentRect so lastCursorLineRect is set — otherwise the
            // old highlight can never be invalidated when the cursor moves away.
            let emptyLineRect = NSRect(
                x: textContainerOrigin.x,
                y: lastRect.maxY + textContainerOrigin.y,
                width: bounds.width - textContainerOrigin.x * 2,
                height: lastRect.height
            )
            currentRect = emptyLineRect
        } else {
            let safePos = min(clampedPos, max(charCount - 1, 0))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: safePos)
            guard glyphIndex < layoutManager.numberOfGlyphs else {
                needsDisplay = true
                return
            }
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            currentLineY = lineRect.origin.y + textContainerOrigin.y
            var adjustedRect = lineRect
            adjustedRect.origin.x = textContainerOrigin.x
            adjustedRect.origin.y += textContainerOrigin.y
            adjustedRect.size.width = bounds.width - textContainerOrigin.x * 2
            currentRect = adjustedRect
        }

        // Skip if cursor is on the same line (compare Y positions).
        // This is the fast path for typing — since textDidChange does NOT
        // reset lastCursorLineY, consecutive keystrokes on the same line
        // hit this early return and skip all invalidation work.
        if abs(currentLineY - lastCursorLineY) < 1.0 {
            return
        }

        // Invalidate the previous line rect so super.drawBackground clears
        // the old highlight. If lastCursorLineRect is nil (rare — should be
        // initialized by initializeCursorLineTracking), fall back to a full
        // redraw to ensure the stale highlight is cleared.
        if let prevRect = lastCursorLineRect {
            setNeedsDisplay(prevRect.insetBy(dx: -lineInvalidationMargin, dy: -lineInvalidationMargin))
        } else {
            needsDisplay = true
        }

        // Invalidate the current line rect
        if let rect = currentRect {
            setNeedsDisplay(rect.insetBy(dx: -lineInvalidationMargin, dy: -lineInvalidationMargin))
        }

        lastCursorLineY = currentLineY
        lastCursorLineRect = currentRect
    }

    /// Simple cache for line lookups to avoid repeated O(n) scans for consecutive lines.
    ///
    /// NOTE:
    /// - This cache is shared by both `invalidateLineHighlightIfNeeded()` (which typically
    ///   queries the current and previous cursor lines) and generic callers of
    ///   `lineRectForLine(_:,layoutManager:textContainer:)`, which may request any line.
    /// - The cache only provides a benefit when the requested line is the same as, or
    ///   adjacent to, the last cached line (see the `abs(cache.lastLine - lineNumber) <= 1`
    ///   check in `lineRectForLine`). Calls for distant line numbers will effectively
    ///   overwrite the cache and may reduce its effectiveness for cursor-movement tracking.
    /// - This limitation is intentional: the cache is an opportunistic optimization and
    ///   must not be relied upon for correctness or for guaranteeing fast lookups for
    ///   arbitrary line numbers.
    private var lineCache: (lastLine: Int, charIndex: Int, searchRange: NSRange)?

    /// Get the rect for a specific line number using efficient NSString lineRange
    private func lineRectForLine(_ lineNumber: Int, layoutManager: NSLayoutManager, textContainer: NSTextContainer) -> NSRect? {
        guard layoutManager.numberOfGlyphs > 0 else { return nil }

        let text = string as NSString
        guard text.length > 0 else { return nil }

        var charIndex = 0
        var searchRange = NSRange(location: 0, length: text.length)
        var startLine = 0

        // Use cache if we're looking for a nearby line AND cache is still valid for current text
        if let cache = lineCache,
           cache.searchRange.location < text.length,
           NSMaxRange(cache.searchRange) <= text.length,
           abs(cache.lastLine - lineNumber) <= 1 {
            if cache.lastLine == lineNumber {
                // Exact cache hit - use cached position
                charIndex = min(cache.charIndex, text.length - 1)
                searchRange = cache.searchRange
                startLine = lineNumber
            } else if cache.lastLine + 1 == lineNumber {
                // Start iteration from cached line to reach the next line
                charIndex = min(cache.charIndex, text.length - 1)
                searchRange = cache.searchRange
                startLine = cache.lastLine
            }
        }

        // Iterate from cached position (or start) to the target line
        for _ in startLine..<lineNumber {
            guard searchRange.location < text.length else {
                // Line number is beyond document, clamp to last valid position
                charIndex = max(0, text.length - 1)
                lineCache = nil // Invalidate cache for out-of-bounds
                break
            }

            let lineRange = text.lineRange(for: searchRange)

            // Move to next line
            searchRange.location = NSMaxRange(lineRange)
            searchRange.length = text.length - searchRange.location
            charIndex = searchRange.location
        }

        // Only cache if the result is valid
        if charIndex < text.length && searchRange.location <= text.length {
            lineCache = (lineNumber, charIndex, searchRange)
        } else {
            lineCache = nil
        }

        // If we reached the target line, charIndex is already set to its start
        // Otherwise it was clamped to the last valid position

        // Do NOT call ensureLayout — with allowsNonContiguousLayout = true,
        // glyphIndexForCharacter triggers local layout lazily as needed.
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

        var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)

        // Adjust for text container origin
        let origin = textContainerOrigin
        lineRect.origin.x = origin.x
        lineRect.origin.y += origin.y
        lineRect.size.width = bounds.width - origin.x * 2

        return lineRect
    }

    /// Initialize cursor line tracking state.
    /// Must be called after the delegate is set up so that the first cursor
    /// movement can properly invalidate the initial highlight position.
    /// Without this, `lastCursorLineRect` stays nil and the stale highlight
    /// drawn at the initial cursor position (end of text) is never cleared.
    func initializeCursorLineTracking() {
        guard let layoutManager = layoutManager,
              layoutManager.numberOfGlyphs > 0 else { return }

        let charCount = (string as NSString).length
        guard charCount > 0 else { return }

        let cursorPos = selectedRange().location
        let clampedPos = min(max(cursorPos, 0), charCount)

        let nsText = string as NSString
        if clampedPos >= charCount && nsText.character(at: charCount - 1) == 0x0A {
            let lastGlyph = layoutManager.numberOfGlyphs - 1
            guard lastGlyph >= 0 else { return }
            let lastRect = layoutManager.lineFragmentRect(
                forGlyphAt: lastGlyph, effectiveRange: nil
            )
            lastCursorLineY = lastRect.maxY + textContainerOrigin.y
            lastCursorLineRect = NSRect(
                x: textContainerOrigin.x,
                y: lastRect.maxY + textContainerOrigin.y,
                width: bounds.width - textContainerOrigin.x * 2,
                height: lastRect.height
            )
        } else {
            let safePos = min(clampedPos, max(charCount - 1, 0))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: safePos)
            guard glyphIndex < layoutManager.numberOfGlyphs else { return }
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex, effectiveRange: nil
            )
            lastCursorLineY = lineRect.origin.y + textContainerOrigin.y
            var adjustedRect = lineRect
            adjustedRect.origin.x = textContainerOrigin.x
            adjustedRect.origin.y += textContainerOrigin.y
            adjustedRect.size.width = bounds.width - textContainerOrigin.x * 2
            lastCursorLineRect = adjustedRect
        }
    }

    // MARK: - Drawing

    /// Draw background elements (current line highlight, bracket matching)
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        // Draw visual features after background, clipped to the dirty rect.
        // Only draw the highlight if it intersects the area being redrawn —
        // otherwise we'd re-paint a stale highlight in a region that
        // super.drawBackground didn't clear.
        drawCurrentLineHighlight(in: rect)
        drawBracketHighlights()
    }

    /// Draw highlight for the current line, clipped to the given dirty rect.
    /// If the highlight rect does not intersect `dirtyRect`, drawing is skipped
    /// to prevent re-painting a stale highlight in a region that was not cleared.
    private func drawCurrentLineHighlight(in dirtyRect: NSRect) {
        guard let layoutManager = layoutManager else { return }

        let cursorPos = selectedRange().location
        let nsString = string as NSString
        let textLength = nsString.length

        // Handle empty document
        if textLength == 0 {
            let origin = textContainerOrigin
            let lineRect = NSRect(
                x: origin.x,
                y: origin.y,
                width: bounds.width - origin.x * 2,
                height: 17
            )
            guard lineRect.intersects(dirtyRect) else { return }
            SQLEditorTheme.currentLineHighlight.setFill()
            NSBezierPath(
                roundedRect: lineRect,
                xRadius: SQLEditorTheme.highlightCornerRadius,
                yRadius: SQLEditorTheme.highlightCornerRadius
            ).fill()
            return
        }

        // Do NOT call ensureLayout — with allowsNonContiguousLayout = true,
        // glyphIndexForCharacter / lineFragmentRect trigger local layout lazily.
        guard layoutManager.numberOfGlyphs > 0 else { return }

        var lineRect: NSRect

        // Handle cursor at end of document
        if cursorPos >= textLength {
            // O(1) check for trailing newline using NSString UTF-16 access
            let hasTrailingNewline = nsString.character(at: textLength - 1) == 0x0A
            let lastGlyphIndex = layoutManager.numberOfGlyphs - 1
            if hasTrailingNewline {
                let lastLineRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
                lineRect = NSRect(x: 0, y: lastLineRect.maxY, width: bounds.width, height: lastLineRect.height)
            } else {
                lineRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
            }
        } else {
            // Normal case - cursor within text
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: cursorPos)
            guard glyphIndex < layoutManager.numberOfGlyphs else { return }
            lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        }

        // Adjust for text container origin
        let origin = textContainerOrigin
        lineRect.origin.x = origin.x
        lineRect.origin.y += origin.y
        lineRect.size.width = bounds.width - origin.x * 2

        // Only draw the highlight if it intersects the dirty rect.
        // When the cursor moves, only the old and new line rects are
        // invalidated. If drawBackground is called for a dirty rect that
        // does NOT include the current cursor line (e.g., the old line
        // being cleared), we must skip drawing here — otherwise we'd
        // re-paint the highlight at the cursor position in a region whose
        // old content was not cleared by super.drawBackground.
        guard lineRect.intersects(dirtyRect) else { return }

        SQLEditorTheme.currentLineHighlight.setFill()
        NSBezierPath(
            roundedRect: lineRect,
            xRadius: SQLEditorTheme.highlightCornerRadius,
            yRadius: SQLEditorTheme.highlightCornerRadius
        ).fill()
    }

    /// Draw highlights for matching brackets
    private func drawBracketHighlights() {
        guard let layoutManager = layoutManager,
              textContainer != nil,
              !string.isEmpty,
              layoutManager.numberOfGlyphs > 0 else { return }

        let nsString = string as NSString
        let length = nsString.length

        // Skip bracket highlighting for very large documents — the layout manager
        // queries and bracket search add overhead that causes lag during editing.
        if length > 1_000_000 { return }

        let cursorPos = selectedRange().location

        // Find bracket at or before cursor using UTF-16 access (O(1) per char)
        var bracketPos: Int?
        var bracketUnichar: unichar?

        if cursorPos < length {
            let ch = nsString.character(at: cursorPos)
            if bracketPairMap[ch] != nil || reverseBracketPairMap[ch] != nil {
                bracketPos = cursorPos
                bracketUnichar = ch
            }
        }

        if bracketUnichar == nil && cursorPos > 0 && cursorPos - 1 < length {
            let ch = nsString.character(at: cursorPos - 1)
            if bracketPairMap[ch] != nil || reverseBracketPairMap[ch] != nil {
                bracketPos = cursorPos - 1
                bracketUnichar = ch
            }
        }

        guard let foundPos = bracketPos,
              let foundBracket = bracketUnichar,
              let matchPos = findMatchingBracketUTF16(
                  at: foundPos, bracket: foundBracket, in: nsString
              ) else { return }

        // Do NOT call ensureLayout — with allowsNonContiguousLayout = true,
        // the layout manager handles lazy layout for glyph queries.

        // Draw highlight for both brackets
        SQLEditorTheme.bracketMatchHighlight.setFill()

        for pos in [foundPos, matchPos] {
            if let rect = rectForCharacter(at: pos) {
                NSBezierPath(
                    roundedRect: rect,
                    xRadius: SQLEditorTheme.highlightCornerRadius,
                    yRadius: SQLEditorTheme.highlightCornerRadius
                ).fill()
            }
        }
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        // Dismiss autocomplete when clicking at a different position in the text editor
        // This matches VSCode/IntelliJ behavior - clicking sidebar/tabs won't dismiss
        let clickLocation = convert(event.locationInWindow, from: nil)
        let characterIndex = characterIndexForInsertion(at: clickLocation)

        // If click is far from current cursor position, dismiss completion
        let currentCursor = selectedRange().location
        if abs(characterIndex - currentCursor) > 0 {
            onClickOutsideCompletion?()
        }

        super.mouseDown(with: event)
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        // Let callback handle key events first (for completion navigation)
        if let handler = onKeyEvent, handler(event) {
            return
        }

        guard let key = KeyCode(rawValue: event.keyCode) else {
            super.keyDown(with: event)
            return
        }

        // Cmd+Enter to execute query
        if event.modifierFlags.contains(.command) && key == .return {
            onExecute?()
            return
        }

        // Ctrl+Space to trigger manual completion
        if event.modifierFlags.contains(.control) && key == .space {
            onManualCompletion?()
            return
        }

        // Handle auto-pairing for brackets and quotes
        if let char = event.characters?.first {
            // Opening brackets - insert pair
            if let closing = bracketPairs[char] {
                insertPair(opening: char, closing: closing)
                return
            }

            // Quotes - insert pair or skip if already at closing quote
            if let closing = quotePairs[char] {
                if shouldSkipClosingQuote(char) {
                    moveRight(nil)
                    return
                }
                insertPair(opening: char, closing: closing)
                return
            }

            // Closing brackets - skip if next char is the same
            if bracketPairs.values.contains(char) {
                if shouldSkipClosingBracket(char) {
                    moveRight(nil)
                    return
                }
            }
        }

        // Handle backspace to delete matching pairs
        if key == .delete {
            if shouldDeletePair() {
                deletePair()
                return
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - Tab Handling

    /// Override tab to insert spaces based on tab width setting
    override func insertTab(_ sender: Any?) {
        let tabWidth = SQLEditorTheme.tabWidth
        let spaces = String(repeating: " ", count: tabWidth)
        insertText(spaces, replacementRange: selectedRange())
    }

    // MARK: - Auto-Indent

    /// Override newline to auto-indent based on previous line.
    /// Uses NSString range scanning to avoid O(n) String allocation for large files.
    override func insertNewline(_ sender: Any?) {
        guard SQLEditorTheme.autoIndent else {
            super.insertNewline(sender)
            return
        }

        let nsText = string as NSString
        let cursorPos = min(selectedRange().location, nsText.length)

        // Find the last newline before cursor using NSString backwards search (O(line length))
        let searchRange = NSRange(location: 0, length: cursorPos)
        let newlineRange = nsText.range(of: "\n", options: .backwards, range: searchRange)

        guard newlineRange.location != NSNotFound else {
            // First line, no indent to copy
            super.insertNewline(sender)
            return
        }

        // Extract leading whitespace from the line after the newline
        let lineStart = newlineRange.location + 1
        var indent = ""
        var pos = lineStart
        while pos < cursorPos {
            let ch = nsText.character(at: pos)
            if ch == 0x20 { // space
                indent.append(" ")
                pos += 1
            } else if ch == 0x09 { // tab
                indent.append("\t")
                pos += 1
            } else {
                break
            }
        }

        // Insert newline
        super.insertNewline(sender)

        // Insert indent if exists
        if !indent.isEmpty {
            insertText(indent, replacementRange: selectedRange())
        }
    }

    // MARK: - Auto-Pairing Logic

    private func insertPair(opening: Character, closing: Character) {
        let insertText = "\(opening)\(closing)"
        let range = selectedRange()

        if shouldChangeText(in: range, replacementString: insertText) {
            replaceCharacters(in: range, with: insertText)
            // Move cursor between the pair
            setSelectedRange(NSRange(location: range.location + 1, length: 0))
            didChangeText()
        }
    }

    private func shouldSkipClosingQuote(_ quote: Character) -> Bool {
        let pos = selectedRange().location
        let nsString = string as NSString
        guard pos < nsString.length else { return false }
        guard let scalar = UnicodeScalar(nsString.character(at: pos)) else { return false }
        return Character(scalar) == quote
    }

    private func shouldSkipClosingBracket(_ bracket: Character) -> Bool {
        let pos = selectedRange().location
        let nsString = string as NSString
        guard pos < nsString.length else { return false }
        guard let scalar = UnicodeScalar(nsString.character(at: pos)) else { return false }
        return Character(scalar) == bracket
    }

    private func shouldDeletePair() -> Bool {
        let pos = selectedRange().location
        let nsString = string as NSString
        guard pos > 0, pos < nsString.length else { return false }

        guard let prevScalar = UnicodeScalar(nsString.character(at: pos - 1)),
              let nextScalar = UnicodeScalar(nsString.character(at: pos)) else { return false }

        let prevChar = Character(prevScalar)
        let nextChar = Character(nextScalar)

        // Check if we're between a matching pair
        if let closing = bracketPairs[prevChar], closing == nextChar {
            return true
        }
        if let closing = quotePairs[prevChar], closing == nextChar {
            return true
        }
        return false
    }

    private func deletePair() {
        let pos = selectedRange().location
        let range = NSRange(location: pos - 1, length: 2)

        if shouldChangeText(in: range, replacementString: "") {
            replaceCharacters(in: range, with: "")
            didChangeText()
        }
    }

    // MARK: - Bracket Matching

    /// Maximum distance to search for matching bracket (prevents scanning 170k chars)
    private static let maxBracketSearchDistance = 5_000

    /// UTF-16 bracket matching using NSString — avoids O(n) Array(string) allocation.
    /// Caps search at ±5000 characters to stay responsive on large files.
    private func findMatchingBracketUTF16(at position: Int, bracket: unichar, in nsString: NSString) -> Int? {
        let isOpening = bracketPairMap[bracket] != nil
        let matchingBracket: unichar
        let direction: Int

        if isOpening {
            guard let match = bracketPairMap[bracket] else { return nil }
            matchingBracket = match
            direction = 1
        } else {
            guard let match = reverseBracketPairMap[bracket] else { return nil }
            matchingBracket = match
            direction = -1
        }

        let length = nsString.length
        let limit = Self.maxBracketSearchDistance
        var depth = 1
        var pos = position + direction
        var searched = 0

        while pos >= 0 && pos < length && searched < limit {
            let ch = nsString.character(at: pos)

            if ch == bracket {
                depth += 1
            } else if ch == matchingBracket {
                depth -= 1
                if depth == 0 {
                    return pos
                }
            }

            pos += direction
            searched += 1
        }

        return nil
    }

    private func rectForCharacter(at index: Int) -> NSRect? {
        guard let layoutManager = layoutManager,
              let container = textContainer,
              index < (string as NSString).length,
              layoutManager.numberOfGlyphs > 0 else { return nil }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: index)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

        var glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)

        // Adjust for text container origin
        let origin = textContainerOrigin
        glyphRect.origin.x += origin.x
        glyphRect.origin.y += origin.y

        // Make rect slightly larger for visibility
        glyphRect = glyphRect.insetBy(dx: -1, dy: -1)

        return glyphRect
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()

        // Add separator if menu already has items
        if !menu.items.isEmpty {
            menu.addItem(NSMenuItem.separator())
        }

        // Add "Format SQL" menu item
        let formatItem = NSMenuItem(
            title: "Format SQL",
            action: #selector(formatSQLAction),
            keyEquivalent: ""
        )
        formatItem.target = self
        menu.addItem(formatItem)

        return menu
    }

    @objc private func formatSQLAction() {
        // Post notification to trigger formatting
        NotificationCenter.default.post(name: .formatQueryRequested, object: nil)
    }
}
