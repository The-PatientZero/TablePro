//
//  RowParser.swift
//  TablePro
//
//  Parses clipboard text data into rows for insertion.
//  Supports TSV (tab-separated values) format with extensibility for CSV/JSON.
//

import Foundation

/// Protocol for parsing row data from text
protocol RowDataParser {
    /// Parse text into array of parsed rows
    /// - Parameters:
    ///   - text: Raw text from clipboard
    ///   - schema: Table schema for validation
    /// - Returns: Result containing parsed rows or error
    func parse(_ text: String, schema: TableSchema) -> Result<[ParsedRow], RowParseError>
}

/// TSV (Tab-Separated Values) parser
/// Matches the format produced by RowOperationsManager.copySelectedRowsToClipboard()
struct TSVRowParser: RowDataParser {
    func parse(_ text: String, schema: TableSchema) -> Result<[ParsedRow], RowParseError> {
        // Check for empty input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.emptyClipboard)
        }

        // Split into lines
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return .failure(.noValidRows)
        }

        var parsedRows: [ParsedRow] = []

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1

            // Parse TSV line
            let rawValues = line.components(separatedBy: "\t")
            var values = rawValues.map { normalizeValue($0) }

            // Handle column count mismatch
            if values.count < schema.columnCount {
                // Pad with NULL for missing columns
                while values.count < schema.columnCount {
                    values.append(nil)
                }
            } else if values.count > schema.columnCount {
                // Truncate extra columns
                values = Array(values.prefix(schema.columnCount))
            }

            // Set primary key to __DEFAULT__ (let DB auto-generate)
            if let pkIndex = schema.primaryKeyIndex, pkIndex < values.count {
                values[pkIndex] = "__DEFAULT__"
            }

            let parsedRow = ParsedRow(values: values, sourceLineNumber: lineNumber)
            parsedRows.append(parsedRow)
        }

        guard !parsedRows.isEmpty else {
            return .failure(.noValidRows)
        }

        return .success(parsedRows)
    }

    // MARK: - Private Helpers

    /// Normalize a single value from clipboard
    /// - Parameter rawValue: Raw string value
    /// - Returns: Normalized value (nil for NULL, trimmed string otherwise)
    private func normalizeValue(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)

        // Empty string or "NULL" (case-insensitive) → nil
        if trimmed.isEmpty || trimmed.uppercased() == "NULL" {
            return nil
        }

        return trimmed
    }
}

// MARK: - Future Parsers

/// CSV parser (future implementation)
/// Handles comma-separated values with quoted strings
struct CSVRowParser: RowDataParser {
    func parse(_ text: String, schema: TableSchema) -> Result<[ParsedRow], RowParseError> {
        // TODO: Implement CSV parsing with proper quote handling
        // For now, delegate to TSV parser
        TSVRowParser().parse(text, schema: schema)
    }
}
