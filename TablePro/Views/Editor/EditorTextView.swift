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
    
    // MARK: - Auto-Pairing Configuration
    
    private let bracketPairs: [Character: Character] = [
        "(": ")",
        "[": "]",
        "{": "}",
    ]
    
    private let reverseBracketPairs: [Character: Character] = [
        ")": "(",
        "]": "[",
        "}": "{",
    ]
    
    private let quotePairs: [Character: Character] = [
        "'": "'",
        "\"": "\"",
        "`": "`",
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
    
    /// Track the last cursor position for smart invalidation
    private var lastCursorLine: Int = -1
    
    private func commonInit() {
        // Observe selection changes for visual updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: self
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func selectionDidChange(_ notification: Notification) {
        // Smart invalidation: only redraw the affected line regions
        // instead of the entire view
        invalidateLineHighlightIfNeeded()
    }
    
    /// Invalidate only the current and previous line regions for redraw
    private func invalidateLineHighlightIfNeeded() {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else {
            needsDisplay = true
            return
        }
        
        let cursorPos = selectedRange().location
        
        // Calculate current line
        let currentLine: Int
        if string.isEmpty {
            currentLine = 0
        } else if cursorPos >= string.count {
            currentLine = string.filter { $0 == "\n" }.count
        } else {
            let index = string.index(string.startIndex, offsetBy: cursorPos)
            currentLine = string[..<index].filter { $0 == "\n" }.count
        }
        
        // Skip if cursor is on the same line
        if currentLine == lastCursorLine {
            return
        }
        
        // Invalidate the previous line rect
        if lastCursorLine >= 0 {
            if let rect = lineRectForLine(lastCursorLine, layoutManager: layoutManager, textContainer: textContainer) {
                setNeedsDisplay(rect.insetBy(dx: -2, dy: -2))
            }
        }
        
        // Invalidate the current line rect
        if let rect = lineRectForLine(currentLine, layoutManager: layoutManager, textContainer: textContainer) {
            setNeedsDisplay(rect.insetBy(dx: -2, dy: -2))
        }
        
        lastCursorLine = currentLine
    }
    
    /// Get the rect for a specific line number
    private func lineRectForLine(_ lineNumber: Int, layoutManager: NSLayoutManager, textContainer: NSTextContainer) -> NSRect? {
        guard layoutManager.numberOfGlyphs > 0 else { return nil }
        
        // Find the character index for the start of the line
        var currentLine = 0
        var charIndex = 0
        let text = string
        
        for (index, char) in text.enumerated() {
            if currentLine == lineNumber {
                charIndex = index
                break
            }
            if char == "\n" {
                currentLine += 1
            }
        }
        
        // Handle cursor at end of text
        if currentLine < lineNumber {
            charIndex = text.count > 0 ? text.count - 1 : 0
        }
        
        layoutManager.ensureLayout(for: textContainer)
        
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: min(charIndex, max(0, text.count - 1)))
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        
        var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        
        // Adjust for text container origin
        let origin = textContainerOrigin
        lineRect.origin.x = origin.x
        lineRect.origin.y += origin.y
        lineRect.size.width = bounds.width - origin.x * 2
        
        return lineRect
    }
    
    // MARK: - Drawing
    
    /// Draw background elements (current line highlight, bracket matching)
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        
        // Draw visual features after background
        drawCurrentLineHighlight()
        drawBracketHighlights()
    }
    
    /// Draw highlight for the current line
    private func drawCurrentLineHighlight() {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }
        
        let cursorPos = selectedRange().location
        
        // Handle empty document
        if string.isEmpty {
            let origin = textContainerOrigin
            let lineRect = NSRect(
                x: origin.x,
                y: origin.y,
                width: bounds.width - origin.x * 2,
                height: 17
            )
            SQLEditorTheme.currentLineHighlight.setFill()
            NSBezierPath(roundedRect: lineRect, xRadius: SQLEditorTheme.highlightCornerRadius, yRadius: SQLEditorTheme.highlightCornerRadius).fill()
            return
        }
        
        layoutManager.ensureLayout(for: textContainer)
        
        guard layoutManager.numberOfGlyphs > 0 else { return }
        
        var lineRect: NSRect
        
        // Handle cursor at end of document
        if cursorPos >= string.count {
            // Cursor is at or past the end
            if string.hasSuffix("\n") {
                // Trailing newline - cursor on new empty line
                let lastGlyphIndex = layoutManager.numberOfGlyphs - 1
                let lastLineRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
                lineRect = NSRect(x: 0, y: lastLineRect.maxY, width: bounds.width, height: lastLineRect.height)
            } else {
                // No trailing newline - cursor on same line as last character
                let lastGlyphIndex = layoutManager.numberOfGlyphs - 1
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
        
        SQLEditorTheme.currentLineHighlight.setFill()
        NSBezierPath(roundedRect: lineRect, xRadius: SQLEditorTheme.highlightCornerRadius, yRadius: SQLEditorTheme.highlightCornerRadius).fill()
    }
    
    /// Draw highlights for matching brackets
    private func drawBracketHighlights() {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              !string.isEmpty,
              layoutManager.numberOfGlyphs > 0 else { return }
        
        let cursorPos = selectedRange().location
        let chars = Array(string)
        
        // Find bracket at or before cursor
        var bracketPos: Int?
        var bracket: Character?
        
        if cursorPos < chars.count {
            let char = chars[cursorPos]
            if bracketPairs[char] != nil || reverseBracketPairs[char] != nil {
                bracketPos = cursorPos
                bracket = char
            }
        }
        
        if bracket == nil && cursorPos > 0 {
            let char = chars[cursorPos - 1]
            if bracketPairs[char] != nil || reverseBracketPairs[char] != nil {
                bracketPos = cursorPos - 1
                bracket = char
            }
        }
        
        guard let foundPos = bracketPos,
              let foundBracket = bracket,
              let matchPos = findMatchingBracket(at: foundPos, bracket: foundBracket, in: chars) else { return }
        
        layoutManager.ensureLayout(for: textContainer)
        
        // Draw highlight for both brackets
        SQLEditorTheme.bracketMatchHighlight.setFill()
        
        for pos in [foundPos, matchPos] {
            if let rect = rectForCharacter(at: pos) {
                NSBezierPath(roundedRect: rect, xRadius: SQLEditorTheme.highlightCornerRadius, yRadius: SQLEditorTheme.highlightCornerRadius).fill()
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
        
        // Cmd+Enter to execute query
        if event.modifierFlags.contains(.command) && event.keyCode == 36 {
            onExecute?()
            return
        }
        
        // Ctrl+Space to trigger manual completion
        if event.modifierFlags.contains(.control) && event.keyCode == 49 {
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
        if event.keyCode == 51 { // Backspace
            if shouldDeletePair() {
                deletePair()
                return
            }
        }
        
        super.keyDown(with: event)
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
        guard pos < string.count else { return false }
        let index = string.index(string.startIndex, offsetBy: pos)
        return string[index] == quote
    }
    
    private func shouldSkipClosingBracket(_ bracket: Character) -> Bool {
        let pos = selectedRange().location
        guard pos < string.count else { return false }
        let index = string.index(string.startIndex, offsetBy: pos)
        return string[index] == bracket
    }
    
    private func shouldDeletePair() -> Bool {
        let pos = selectedRange().location
        guard pos > 0, pos < string.count else { return false }
        
        let prevIndex = string.index(string.startIndex, offsetBy: pos - 1)
        let nextIndex = string.index(string.startIndex, offsetBy: pos)
        let prevChar = string[prevIndex]
        let nextChar = string[nextIndex]
        
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
    
    private func findMatchingBracket(at position: Int, bracket: Character, in chars: [Character]) -> Int? {
        let isOpening = bracketPairs[bracket] != nil
        let matchingBracket: Character
        let direction: Int
        
        if isOpening {
            matchingBracket = bracketPairs[bracket]!
            direction = 1
        } else {
            matchingBracket = reverseBracketPairs[bracket]!
            direction = -1
        }
        
        var depth = 1
        var pos = position + direction
        
        while pos >= 0 && pos < chars.count {
            let char = chars[pos]
            
            if char == bracket {
                depth += 1
            } else if char == matchingBracket {
                depth -= 1
                if depth == 0 {
                    return pos
                }
            }
            
            pos += direction
        }
        
        return nil // No matching bracket found
    }
    
    private func rectForCharacter(at index: Int) -> NSRect? {
        guard let layoutManager = layoutManager,
              index < string.count,
              layoutManager.numberOfGlyphs > 0 else { return nil }
        
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: index)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        
        var glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer!)
        
        // Adjust for text container origin
        let origin = textContainerOrigin
        glyphRect.origin.x += origin.x
        glyphRect.origin.y += origin.y
        
        // Make rect slightly larger for visibility
        glyphRect = glyphRect.insetBy(dx: -1, dy: -1)
        
        return glyphRect
    }
}
