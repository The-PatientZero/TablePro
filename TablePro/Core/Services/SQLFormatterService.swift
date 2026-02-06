//
//  SQLFormatterService.swift
//  TablePro
//
//  Created by OpenCode on 1/17/26.
//

import Foundation

// MARK: - Formatter Protocol

protocol SQLFormatterProtocol {
    /// Format SQL with optional cursor position preservation
    func format(
        _ sql: String,
        dialect: DatabaseType,
        cursorOffset: Int?,
        options: SQLFormatterOptions
    ) throws -> SQLFormatterResult
}

// MARK: - Main Formatter Service

struct SQLFormatterService: SQLFormatterProtocol {
    // MARK: - Constants

    /// Maximum input size: 10MB (protection against DoS)
    private static let maxInputSize = 10 * 1_024 * 1_024

    /// Alignment for SELECT columns (length of "SELECT ")
    private static let selectKeywordLength = 7

    // MARK: - Public API

    func format(
        _ sql: String,
        dialect: DatabaseType,
        cursorOffset: Int? = nil,
        options: SQLFormatterOptions = .default
    ) throws -> SQLFormatterResult {
        // Fix #4: Input size limit (DoS protection)
        guard sql.utf8.count <= Self.maxInputSize else {
            throw SQLFormatterError.internalError("SQL too large (max \(Self.maxInputSize / 1_024 / 1_024)MB)")
        }

        // Validate input
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SQLFormatterError.emptyInput
        }

        if let cursor = cursorOffset, cursor > sql.count {
            throw SQLFormatterError.invalidCursorPosition(cursor, max: sql.count)
        }

        // Get dialect provider
        let dialectProvider = SQLDialectFactory.createDialect(for: dialect)

        // Format the SQL
        let formatted = formatSQL(sql, dialect: dialectProvider, options: options)

        // Cursor preservation
        let newCursor = cursorOffset.map { original in
            preserveCursorPosition(original: original, oldText: sql, newText: formatted)
        }

        return SQLFormatterResult(
            formattedSQL: formatted,
            cursorOffset: newCursor
        )
    }

    // MARK: - Core Formatting Logic

    private func formatSQL(
        _ sql: String,
        dialect: SQLDialectProvider,
        options: SQLFormatterOptions
    ) -> String {
        var result = sql

        // Step 1: Preserve comments (replace with UUID placeholders)
        let (sqlWithoutComments, comments) = options.preserveComments
            ? extractComments(from: result)
            : (result, [])

        result = sqlWithoutComments

        // Step 2: Extract string literals (to protect from keyword replacement)
        let (sqlWithoutStrings, stringLiterals) = extractStringLiterals(from: result, dialect: dialect)
        result = sqlWithoutStrings

        // Step 3: Uppercase keywords (now safe - strings removed)
        if options.uppercaseKeywords {
            result = uppercaseKeywords(result, dialect: dialect)
        }

        // Step 4: Restore string literals
        result = restoreStringLiterals(result, literals: stringLiterals)

        // Step 5: Add line breaks before major keywords
        result = addLineBreaks(result, dialect: dialect)

        // Step 6: Add indentation based on nesting
        if options.indentSize > 0 {
            result = addIndentation(result, indentSize: options.indentSize)
        }

        // Step 7: Align SELECT columns
        if options.alignColumns {
            result = alignSelectColumns(result)
        }

        // Step 8: Format JOINs (handled by line breaks)
        if options.formatJoins {
            result = formatJoins(result)
        }

        // Step 9: Align WHERE conditions
        if options.alignWhere {
            result = alignWhereConditions(result)
        }

        // Step 10: Restore comments
        if options.preserveComments {
            result = restoreComments(result, comments: comments)
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - String Literal Protection (Fix #2)

    /// Extract string literals to protect from keyword replacement
    /// Handles: 'single quotes', "double quotes", `backticks`
    private func extractStringLiterals(from sql: String, dialect: SQLDialectProvider) -> (String, [(placeholder: String, content: String)]) {
        var result = sql
        var literals: [(String, String)] = []

        // Determine quote characters based on dialect
        // MySQL/SQLite: single quotes and backticks
        // PostgreSQL: single quotes and double quotes
        let quoteChars: [String]
        switch dialect.identifierQuote {
        case "\"":
            quoteChars = ["'", "\""]  // PostgreSQL
        default:
            quoteChars = ["'", "`"]   // MySQL, SQLite
        }

        // Extract each type of string literal
        for quoteChar in quoteChars {
            let pattern = "\(NSRegularExpression.escapedPattern(for: quoteChar))((?:\\\\\\\\\(quoteChar)|[^\(quoteChar)])*?)\(NSRegularExpression.escapedPattern(for: quoteChar))"

            if let regex = createRegex(pattern) {
                let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))

                // Process in reverse to maintain valid indices
                for match in matches.reversed() {
                    if let range = safeRange(from: match.range, in: result) {
                        let literal = String(result[range])
                        let placeholder = "__STRING_\(UUID().uuidString)__"
                        literals.insert((placeholder, literal), at: 0)
                        result.replaceSubrange(range, with: placeholder)
                    }
                }
            }
        }

        return (result, literals)
    }

    /// Restore string literals after formatting
    private func restoreStringLiterals(_ sql: String, literals: [(placeholder: String, content: String)]) -> String {
        var result = sql
        for (placeholder, content) in literals {
            result = result.replacingOccurrences(of: placeholder, with: content)
        }
        return result
    }

    // MARK: - Comment Handling (Fix #6: UUID placeholders)

    /// Extract comments with UUID-based placeholders (prevents collisions)
    private func extractComments(from sql: String) -> (String, [(placeholder: String, content: String)]) {
        var result = sql
        var comments: [(String, String)] = []

        // Extract line comments (-- ...)
        let lineCommentPattern = "--[^\\n]*"
        if let regex = createRegex(lineCommentPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = safeRange(from: match.range, in: result) {
                    let comment = String(result[range])
                    let placeholder = "__COMMENT_\(UUID().uuidString)__"  // Fix #6: UUID
                    comments.insert((placeholder, comment), at: 0)
                    result.replaceSubrange(range, with: placeholder)
                }
            }
        }

        // Extract block comments (/* ... */)
        // Note: This doesn't handle nested block comments (SQL doesn't officially support them)
        let blockCommentPattern = "/\\*.*?\\*/"
        if let regex = createRegex(blockCommentPattern, options: .dotMatchesLineSeparators) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = safeRange(from: match.range, in: result) {
                    let comment = String(result[range])
                    let placeholder = "__COMMENT_\(UUID().uuidString)__"  // Fix #6: UUID
                    comments.insert((placeholder, comment), at: 0)
                    result.replaceSubrange(range, with: placeholder)
                }
            }
        }

        return (result, comments)
    }

    /// Restore comments after formatting
    private func restoreComments(_ sql: String, comments: [(placeholder: String, content: String)]) -> String {
        var result = sql
        for (placeholder, content) in comments {
            result = result.replacingOccurrences(of: placeholder, with: content)
        }
        return result
    }

    // MARK: - Keyword Uppercasing (Fix #1: Single-pass optimization)

    /// Uppercase keywords using single regex pass (much faster than per-keyword)
    private func uppercaseKeywords(_ sql: String, dialect: SQLDialectProvider) -> String {
        let allKeywords = dialect.keywords.union(dialect.functions).union(dialect.dataTypes)

        // Build alternation pattern: \b(SELECT|FROM|WHERE|...)\b
        let escapedKeywords = allKeywords.map { NSRegularExpression.escapedPattern(for: $0) }
        let pattern = "\\b(\(escapedKeywords.joined(separator: "|")))\\b"

        guard let regex = createRegex(pattern, options: .caseInsensitive) else {
            return sql
        }

        var result = sql
        let matches = regex.matches(in: sql, range: NSRange(sql.startIndex..., in: sql))

        // Process in reverse to maintain valid indices (Fix #3)
        for match in matches.reversed() {
            if let range = safeRange(from: match.range, in: result) {
                let keyword = String(result[range])
                result.replaceSubrange(range, with: keyword.uppercased())
            }
        }

        return result
    }

    // MARK: - Line Breaks

    private func addLineBreaks(_ sql: String, dialect: SQLDialectProvider) -> String {
        var result = sql

        // Keywords that should start on a new line
        let lineBreakKeywords = [
            "SELECT", "FROM", "WHERE", "JOIN", "INNER JOIN", "LEFT JOIN", "RIGHT JOIN",
            "FULL JOIN", "CROSS JOIN", "ORDER BY", "GROUP BY", "HAVING",
            "UNION", "UNION ALL", "INTERSECT", "EXCEPT", "LIMIT", "OFFSET"
        ]

        // Sort by length (longest first) to handle multi-word keywords correctly
        for keyword in lineBreakKeywords.sorted(by: { $0.count > $1.count }) {
            let escapedKeyword = NSRegularExpression.escapedPattern(for: keyword)
            let pattern = "\\s+\(escapedKeyword)\\b"

            if let regex = createRegex(pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: "\n\(keyword.uppercased())"
                )
            }
        }

        return result
    }

    // MARK: - Indentation (Fix #5: Word boundaries instead of contains)

    private func addIndentation(_ sql: String, indentSize: Int) -> String {
        let lines = sql.components(separatedBy: "\n")
        var indentLevel = 0
        var result: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Decrease indent before processing closing parens or END
            if trimmed.starts(with: ")") || hasWordBoundary(trimmed, word: "END") {
                indentLevel = max(0, indentLevel - 1)
            }

            // Add indentation
            let indent = String(repeating: " ", count: indentLevel * indentSize)
            result.append(indent + trimmed)

            // Increase indent after opening parens or CASE keyword
            if trimmed.hasSuffix("(") || hasWordBoundary(trimmed, word: "CASE") {
                indentLevel += 1
            }

            // Special handling for subqueries: (SELECT
            if let regex = createRegex("\\(\\s*SELECT\\b", options: .caseInsensitive),
               regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                indentLevel += 1
            }

            // Decrease after closing paren (if not at start)
            if trimmed.hasSuffix(")") && !trimmed.starts(with: ")") {
                indentLevel = max(0, indentLevel - 1)
            }
        }

        return result.joined(separator: "\n")
    }

    /// Check if a word appears with word boundaries (Fix #5)
    private func hasWordBoundary(_ text: String, word: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        guard let regex = createRegex(pattern, options: .caseInsensitive) else {
            return false
        }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: - Column Alignment

    /// Align SELECT columns vertically
    ///
    /// Example:
    ///   SELECT id, name, email FROM users
    /// Becomes:
    ///   SELECT id,
    ///          name,
    ///          email
    ///   FROM users
    private func alignSelectColumns(_ sql: String) -> String {
        // Find SELECT...FROM region
        guard let selectRange = sql.range(of: "SELECT", options: .caseInsensitive),
              let fromRange = sql.range(of: "FROM", options: .caseInsensitive, range: selectRange.upperBound..<sql.endIndex) else {
            return sql
        }

        // Fix #3: Work with immutable substrings to avoid index invalidation
        let selectClause = String(sql[selectRange.upperBound..<fromRange.lowerBound])
        let columns = selectClause.components(separatedBy: ",")

        guard columns.count > 1 else {
            return sql  // Only one column, no alignment needed
        }

        // Align columns with proper spacing
        let alignedColumns = columns.enumerated().map { index, column in
            let trimmed = column.trimmingCharacters(in: .whitespacesAndNewlines)
            if index == 0 {
                return trimmed
            } else {
                return String(repeating: " ", count: Self.selectKeywordLength) + trimmed
            }
        }.joined(separator: ",\n")

        // Rebuild SQL (Fix #3: Use string concatenation instead of replaceSubrange)
        let before = String(sql[..<selectRange.upperBound])
        let after = String(sql[fromRange.lowerBound...])
        return before + " " + alignedColumns + "\n" + after
    }

    // MARK: - JOIN Formatting

    private func formatJoins(_ sql: String) -> String {
        // Already handled by addLineBreaks
        sql
    }

    // MARK: - WHERE Condition Alignment

    private func alignWhereConditions(_ sql: String) -> String {
        // Find WHERE clause
        guard let whereRange = sql.range(of: "WHERE", options: .caseInsensitive) else {
            return sql
        }

        // Find end of WHERE clause
        let majorKeywords = ["ORDER", "GROUP", "HAVING", "LIMIT", "UNION", "INTERSECT"]
        var endIndex = sql.endIndex

        for keyword in majorKeywords {
            if let range = sql.range(of: keyword, options: .caseInsensitive, range: whereRange.upperBound..<sql.endIndex) {
                endIndex = min(endIndex, range.lowerBound)
            }
        }

        // Fix #3: Work with immutable substring
        let whereClause = String(sql[whereRange.upperBound..<endIndex])

        // Add line breaks before AND/OR
        let pattern = "\\s+(AND|OR)\\s+"
        guard let regex = createRegex(pattern, options: .caseInsensitive) else {
            return sql
        }

        let replaced = regex.stringByReplacingMatches(
            in: whereClause,
            range: NSRange(whereClause.startIndex..., in: whereClause),
            withTemplate: "\n  $1 "
        )

        // Rebuild SQL (Fix #3: Use string concatenation)
        let before = String(sql[..<whereRange.upperBound])
        let after = String(sql[endIndex...])
        return before + replaced + after
    }

    // MARK: - Cursor Preservation

    /// Preserve cursor position using ratio-based approach
    ///
    /// - Note: This is a simple heuristic. For better accuracy, consider:
    ///   - Tracking cursor context (inside string, after keyword, etc.)
    ///   - Using token-based positioning
    /// - Returns: New cursor position, clamped to valid range
    private func preserveCursorPosition(original: Int, oldText: String, newText: String) -> Int {
        guard !oldText.isEmpty else { return 0 }

        let ratio = Double(original) / Double(oldText.count)
        let newPosition = Int(ratio * Double(newText.count))

        return min(newPosition, newText.count)
    }

    // MARK: - Helper Methods

    /// Create regex with error logging (instead of silent failures)
    private func createRegex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            assertionFailure("Failed to create regex '\(pattern)': \(error)")
            return nil
        }
    }

    /// Safe NSRange to Range conversion (Fix #7: Unicode handling)
    ///
    /// NSRange uses UTF-16 code units, Swift String.Index uses Unicode scalars.
    /// This can cause issues with emoji and other multi-byte characters.
    private func safeRange(from nsRange: NSRange, in string: String) -> Range<String.Index>? {
        // Use proper Range initializer that handles UTF-16 conversion
        Range(nsRange, in: string)
    }
}
