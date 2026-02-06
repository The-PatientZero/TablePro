//
//  SQLFileParser.swift
//  TablePro
//
//  Streaming SQL file parser that splits SQL statements while handling
//  comments, string literals, and escape sequences.
//
//  Implementation: Uses a finite state machine to track parser context
//  (normal, in-comment, in-string) while processing files in 64KB chunks.
//  Handles edge cases where multi-character sequences (comments, escapes)
//  span chunk boundaries by deferring processing of special characters
//  until the next chunk arrives.
//

import Foundation

/// SQL statement parser that handles comments, strings, and multi-line statements
final class SQLFileParser: Sendable {
    // MARK: - Parser State

    private enum ParserState {
        case normal
        case inSingleLineComment
        case inMultiLineComment
        case inSingleQuotedString
        case inDoubleQuotedString
        case inBacktickQuotedString
    }

    /// Characters that can start multi-character sequences (comments, escapes)
    /// and must not be processed at chunk boundaries without a lookahead character.
    private static func isMultiCharSequenceStart(_ char: Character) -> Bool {
        char == "-" || char == "/" || char == "\\" || char == "*"
    }

    // MARK: - Public API

    /// Parse SQL file and return async stream of statements with line numbers
    /// - Parameters:
    ///   - url: File URL to parse
    ///   - encoding: Text encoding to use
    ///   - countOnly: When true, skips building statement strings for faster counting
    /// - Returns: AsyncStream of (statement, lineNumber) tuples
    func parseFile(
        url: URL,
        encoding: String.Encoding,
        countOnly: Bool = false
    ) async throws -> AsyncStream<(statement: String, lineNumber: Int)> {
        AsyncStream { continuation in
            Task.detached {
                do {
                    let fileHandle = try FileHandle(forReadingFrom: url)
                    defer {
                        do {
                            try fileHandle.close()
                        } catch {
                            print("WARNING: Failed to close file handle for \(url.path): \(error)")
                        }
                    }

                    var state: ParserState = .normal
                    // nil when countOnly — skips all string building via optional chaining
                    var currentStatement: String? = countOnly ? nil : ""
                    var hasStatementContent = false
                    var currentLine = 1
                    var statementStartLine = 1
                    var buffer = ""
                    let chunkSize = 65_536

                    while true {
                        let data = fileHandle.readData(ofLength: chunkSize)
                        if data.isEmpty { break }

                        guard let chunk = String(data: data, encoding: encoding) else {
                            print("ERROR: Failed to decode chunk with encoding \(encoding.description)")
                            continuation.finish()
                            return
                        }

                        buffer += chunk
                        var index = buffer.startIndex

                        while index < buffer.endIndex {
                            let char = buffer[index]
                            let nextIndex = buffer.index(after: index)
                            let nextChar: Character? =
                                nextIndex < buffer.endIndex ? buffer[nextIndex] : nil

                            if nextChar == nil && Self.isMultiCharSequenceStart(char) {
                                break
                            }

                            if char == "\n" { currentLine += 1 }
                            var didManuallyAdvance = false

                            switch state {
                            case .normal:
                                if char == "-" && nextChar == "-" {
                                    state = .inSingleLineComment
                                    if nextChar == "\n" { currentLine += 1 }
                                    index = buffer.index(after: nextIndex)
                                    didManuallyAdvance = true
                                } else if char == "/" && nextChar == "*" {
                                    state = .inMultiLineComment
                                    if nextChar == "\n" { currentLine += 1 }
                                    index = buffer.index(after: nextIndex)
                                    didManuallyAdvance = true
                                } else if char == "'" {
                                    state = .inSingleQuotedString
                                    if !hasStatementContent {
                                        statementStartLine = currentLine
                                        hasStatementContent = true
                                    }
                                    currentStatement?.append(char)
                                } else if char == "\"" {
                                    state = .inDoubleQuotedString
                                    if !hasStatementContent {
                                        statementStartLine = currentLine
                                        hasStatementContent = true
                                    }
                                    currentStatement?.append(char)
                                } else if char == "`" {
                                    state = .inBacktickQuotedString
                                    if !hasStatementContent {
                                        statementStartLine = currentLine
                                        hasStatementContent = true
                                    }
                                    currentStatement?.append(char)
                                } else if char == ";" {
                                    if hasStatementContent {
                                        let text = currentStatement?
                                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                        continuation.yield((text, statementStartLine))
                                    }
                                    currentStatement?.removeAll()
                                    hasStatementContent = false
                                } else {
                                    if !hasStatementContent && !char.isWhitespace {
                                        statementStartLine = currentLine
                                        hasStatementContent = true
                                    }
                                    currentStatement?.append(char)
                                }

                            case .inSingleLineComment:
                                if char == "\n" {
                                    state = .normal
                                }

                            case .inMultiLineComment:
                                if char == "*" && nextChar == "/" {
                                    state = .normal
                                    if nextChar == "\n" { currentLine += 1 }
                                    index = buffer.index(after: nextIndex)
                                    didManuallyAdvance = true
                                }

                            case .inSingleQuotedString:
                                currentStatement?.append(char)
                                if char == "\\", let next = nextChar {
                                    currentStatement?.append(next)
                                    if next == "\n" { currentLine += 1 }
                                    index = buffer.index(after: nextIndex)
                                    didManuallyAdvance = true
                                } else if char == "'", let next = nextChar, next == "'" {
                                    currentStatement?.append(next)
                                    if next == "\n" { currentLine += 1 }
                                    index = buffer.index(after: nextIndex)
                                    didManuallyAdvance = true
                                } else if char == "'" {
                                    state = .normal
                                }

                            case .inDoubleQuotedString:
                                currentStatement?.append(char)
                                if char == "\\", let next = nextChar {
                                    currentStatement?.append(next)
                                    if next == "\n" { currentLine += 1 }
                                    index = buffer.index(after: nextIndex)
                                    didManuallyAdvance = true
                                } else if char == "\"" {
                                    state = .normal
                                }

                            case .inBacktickQuotedString:
                                currentStatement?.append(char)
                                if char == "`" {
                                    if let next = nextChar, next == "`" {
                                        currentStatement?.append(next)
                                        if next == "\n" { currentLine += 1 }
                                        index = buffer.index(after: nextIndex)
                                        didManuallyAdvance = true
                                    } else {
                                        state = .normal
                                    }
                                }
                            }

                            if !didManuallyAdvance {
                                index = buffer.index(after: index)
                            }
                        }

                        if index < buffer.endIndex {
                            buffer = String(buffer[index...])
                        } else {
                            buffer = ""
                        }
                    }

                    // Add final statement if any
                    if hasStatementContent {
                        let text = currentStatement?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        continuation.yield((text, statementStartLine))
                    }

                    continuation.finish()
                } catch {
                    print("ERROR: SQL file parsing failed: \(error.localizedDescription)")
                    print("Error details: \(error)")
                    continuation.finish()
                }
            }
        }
    }

    /// Count total statements in file (requires full file scan)
    /// - Parameters:
    ///   - url: File URL to parse
    ///   - encoding: Text encoding to use
    /// - Returns: Total number of statements
    func countStatements(url: URL, encoding: String.Encoding) async throws -> Int {
        var count = 0

        for await _ in try await parseFile(url: url, encoding: encoding, countOnly: true) {
            try Task.checkCancellation()
            count += 1
        }

        return count
    }
}
