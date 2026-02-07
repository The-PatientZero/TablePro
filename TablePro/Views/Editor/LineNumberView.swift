//
//  LineNumberView.swift
//  TablePro
//
//  Custom line number view without NSRulerView to prevent text blurring
//  Production-ready implementation for macOS SQL editor
//

import AppKit

/// Custom line number view positioned left of NSScrollView
/// Uses non-layer-backed drawing to prevent text blur in adjacent NSTextView
final class LineNumberView: NSView {
    // MARK: - Properties

    private weak var textView: NSTextView?
    private weak var scrollView: NSScrollView?

    /// Cached line start indices (character positions)
    private var lineStartIndices: [Int] = [0]

    /// Current width of the view
    private var currentWidth: CGFloat = SQLEditorTheme.lineNumberRulerMinThickness

    /// Debounce work item for line cache rebuild (avoids rebuilding 170k line cache per keystroke)
    private var lineCacheDebounceItem: DispatchWorkItem?

    // MARK: - Initialization

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        self.scrollView = scrollView
        super.init(frame: .zero)

        // CRITICAL: Do not use layer-backed rendering to prevent blur
        self.wantsLayer = false

        // Observe text changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )

        // Observe scroll/bounds changes for synchronization
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )

        // Initial cache build — defer for large documents to avoid blocking main thread
        let nsText = textView.string as NSString
        let textLength = nsText.length
        if textLength > 100_000 {
            DispatchQueue.main.async { [weak self] in
                guard let self, let tv = self.textView else { return }
                let currentNSText = tv.string as NSString
                self.rebuildLineCache(for: currentNSText)
                self.updateWidth()
                self.needsDisplay = true
            }
        } else {
            rebuildLineCache(for: nsText)
            updateWidth()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Layout

    /// Use flipped coordinates (top-left origin) to match NSTextView
    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: currentWidth, height: NSView.noIntrinsicMetric)
    }

    // MARK: - Notifications

    @objc private func textDidChange(_ notification: Notification) {
        guard let textView = textView else { return }
        let nsText = textView.string as NSString
        let textLength = nsText.length

        // For large documents, debounce the full line cache rebuild.
        // draw() enumerates line fragments from the layout manager directly
        // (not from lineStartIndices), so stale cache only affects the
        // first-visible-line NUMBER — off by ±1 during the debounce window.
        if textLength > 10_000 {
            lineCacheDebounceItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self, let tv = self.textView else { return }
                let currentNSText = tv.string as NSString
                self.rebuildLineCache(for: currentNSText)
                self.updateWidth()
                self.needsDisplay = true
            }
            lineCacheDebounceItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
            needsDisplay = true
        } else {
            rebuildLineCache(for: nsText)
            updateWidth()
            needsDisplay = true
        }
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        // Scroll synchronization happens via coordinator in container
        needsDisplay = true
    }

    // MARK: - Line Cache Management

    /// Rebuild line cache from scratch using fast NSString scanning.
    /// Accepts NSString directly to avoid String<->NSString bridging overhead.
    private func rebuildLineCache(for nsString: NSString) {
        lineStartIndices = [0]

        let length = nsString.length
        var searchStart = 0
        while searchStart < length {
            let range = nsString.range(
                of: "\n",
                range: NSRange(location: searchStart, length: length - searchStart)
            )
            if range.location == NSNotFound { break }
            lineStartIndices.append(range.location + 1)
            searchStart = range.location + 1
        }
    }

    /// Update view width based on line count
    private func updateWidth() {
        let lineCount = lineStartIndices.count
        let digits = max(2, String(lineCount).count)
        let newWidth = CGFloat(digits * 8 + 16)

        if currentWidth != newWidth {
            currentWidth = newWidth
            invalidateIntrinsicContentSize()
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Draw background
        SQLEditorTheme.lineNumberBackground.setFill()
        dirtyRect.fill()

        // Draw right border
        SQLEditorTheme.lineNumberBorder.setStroke()
        let borderPath = NSBezierPath()
        borderPath.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        borderPath.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        borderPath.lineWidth = 1
        borderPath.stroke()

        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView = scrollView else { return }

        let nsText = textView.string as NSString
        let textLength = nsText.length

        // Handle empty document
        guard textLength > 0 else {
            drawLineNumber(1, at: textView.textContainerOrigin.y)
            return
        }

        // Get visible rect from scroll view
        let visibleRect = scrollView.contentView.bounds
        let textContainerOrigin = textView.textContainerOrigin

        // Get visible glyph range (triggers lazy layout for visible area only,
        // avoids forcing full-document layout which freezes on large files)
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleRect, in: textContainer
        )
        guard visibleGlyphRange.location != NSNotFound,
              visibleGlyphRange.length > 0 else { return }

        // Get character range for visible glyphs
        let visibleCharRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange, actualGlyphRange: nil
        )

        // Get the first visible line NUMBER from the (possibly stale) cache.
        // During the 200ms debounce window this may be off by ±1 which is
        // imperceptible. The cache is never used for character POSITIONS —
        // we enumerate line fragments from the layout manager instead.
        let firstVisibleLineIdx = binarySearchLastIndex(
            in: lineStartIndices, atOrBefore: visibleCharRange.location
        )
        var lineNumber = firstVisibleLineIdx + 1

        // Enumerate line fragments in the visible glyph range.
        // This uses the layout manager's current state (always accurate)
        // and only touches the already-laid-out visible region — O(visible lines).
        var glyphIdx = visibleGlyphRange.location
        var lastDrawnY: CGFloat = -1_000

        while glyphIdx < NSMaxRange(visibleGlyphRange) {
            var effectiveRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIdx, effectiveRange: &effectiveRange
            )

            // Check if this fragment starts a real line (not a wrapped continuation).
            // A real line start is at character 0 or right after a newline.
            let charIdx = layoutManager.characterIndexForGlyph(at: glyphIdx)
            let isRealLineStart = charIdx == 0
                || nsText.character(at: charIdx - 1) == 0x0A // '\n'

            if isRealLineStart {
                let yPos = floor(
                    lineRect.origin.y + textContainerOrigin.y - visibleRect.origin.y
                )
                if abs(yPos - lastDrawnY) > 1.0 {
                    drawLineNumber(lineNumber, at: yPos)
                    lastDrawnY = yPos
                }
                lineNumber += 1
            }

            // Advance past this fragment. Safety: always advance by at least 1
            // to prevent infinite loop if effectiveRange is zero-length.
            let nextGlyph = NSMaxRange(effectiveRange)
            glyphIdx = nextGlyph > glyphIdx ? nextGlyph : glyphIdx + 1
        }

        // Handle trailing empty line: if text ends with \n, the last line
        // has no glyphs so it wasn't covered by the fragment enumeration.
        if nsText.character(at: textLength - 1) == 0x0A {
            let lastGlyph = layoutManager.numberOfGlyphs
            guard lastGlyph > 0 else { return }
            let lastRect = layoutManager.lineFragmentRect(
                forGlyphAt: lastGlyph - 1, effectiveRange: nil
            )
            let yPos = floor(
                lastRect.maxY + textContainerOrigin.y - visibleRect.origin.y
            )
            if abs(yPos - lastDrawnY) > 1.0 {
                drawLineNumber(lineNumber, at: yPos)
            }
        }
    }

    /// Binary search for the last index in a sorted array whose value is ≤ target.
    /// Returns 0 if no element satisfies the condition.
    private func binarySearchLastIndex(in array: [Int], atOrBefore target: Int) -> Int {
        var low = 0
        var high = array.count - 1
        var result = 0

        while low <= high {
            let mid = low + (high - low) / 2
            if array[mid] <= target {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return result
    }

    /// Draw a single line number at the specified Y position
    private func drawLineNumber(_ number: Int, at yPosition: CGFloat) {
        let string = "\(number)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: SQLEditorTheme.lineNumberFont,
            .foregroundColor: SQLEditorTheme.lineNumberText
        ]

        let size = string.size(withAttributes: attributes)
        let xPos = currentWidth - size.width - 8
        // Pixel-align Y position for crisp text
        let yPos = floor(yPosition + (17 - size.height) / 2)

        string.draw(at: NSPoint(x: xPos, y: yPos), withAttributes: attributes)
    }
}
