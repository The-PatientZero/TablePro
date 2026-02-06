//
//  SQLCompletionProvider.swift
//  TablePro
//
//  Main orchestrator for SQL autocomplete
//

import Foundation

/// Main provider for SQL autocomplete suggestions
final class SQLCompletionProvider {
    // MARK: - Properties

    private let contextAnalyzer = SQLContextAnalyzer()
    private let schemaProvider: SQLSchemaProvider
    private var databaseType: DatabaseType?

    /// Minimum prefix length to trigger suggestions
    private let minPrefixLength = 1

    /// Maximum number of suggestions to return
    private let maxSuggestions = 20

    // MARK: - Init

    init(schemaProvider: SQLSchemaProvider, databaseType: DatabaseType? = nil) {
        self.schemaProvider = schemaProvider
        self.databaseType = databaseType
    }

    /// Update the database type for context-aware completions
    func setDatabaseType(_ type: DatabaseType) {
        self.databaseType = type
    }

    // MARK: - Public API

    /// Get completion suggestions for the current cursor position
    func getCompletions(
        text: String,
        cursorPosition: Int
    ) async -> (items: [SQLCompletionItem], context: SQLContext) {
        // Analyze context
        let context = contextAnalyzer.analyze(query: text, cursorPosition: cursorPosition)

        // Don't complete inside strings or comments
        if context.isInsideString || context.isInsideComment {
            return ([], context)
        }

        // Get candidates based on context
        var candidates = await getCandidates(for: context)

        // Filter by prefix
        if !context.prefix.isEmpty {
            candidates = filterByPrefix(candidates, prefix: context.prefix)
        }

        // Rank results
        candidates = rankResults(candidates, prefix: context.prefix, context: context)

        // Limit results
        let limited = Array(candidates.prefix(maxSuggestions))

        return (limited, context)
    }

    // MARK: - Candidate Generation

    /// Get candidate completions based on context
    private func getCandidates(for context: SQLContext) async -> [SQLCompletionItem] {
        var items: [SQLCompletionItem] = []

        // If we have a dot prefix, we're looking for columns of a specific table
        if let dotPrefix = context.dotPrefix {
            // Resolve the table name from alias or direct reference
            if let tableName = await schemaProvider.resolveAlias(dotPrefix, in: context.tableReferences) {
                items = await schemaProvider.columnCompletionItems(for: tableName)
            }
            return items
        }

        // Add items based on clause type
        switch context.clauseType {
        case .from, .join, .into:
            // Tables + JOIN keywords (for typing after table name)
            items = await schemaProvider.tableCompletionItems()
            items += filterKeywords([
                "INNER JOIN", "LEFT JOIN", "RIGHT JOIN", "FULL JOIN",
                "LEFT OUTER JOIN", "RIGHT OUTER JOIN", "FULL OUTER JOIN",
                "CROSS JOIN", "JOIN", "ON", "WHERE", "ORDER BY", "GROUP BY", "LIMIT"
            ])

        case .select:
            // Columns, functions, keywords (SELECT, DISTINCT, etc.)
            items += await schemaProvider.allColumnsInScope(for: context.tableReferences)
            items += SQLKeywords.functionItems()
            items += filterKeywords(["DISTINCT", "ALL", "AS", "FROM", "CASE", "WHEN"])

        case .where_, .and, .on, .having:
            // Columns, operators, logical keywords
            items += await schemaProvider.allColumnsInScope(for: context.tableReferences)
            items += SQLKeywords.operatorItems()
            items += filterKeywords([
                "AND", "OR", "NOT", "IN", "LIKE", "ILIKE", "BETWEEN", "IS",
                "NULL", "NOT NULL", "TRUE", "FALSE", "EXISTS", "NOT EXISTS",
                "ANY", "ALL", "SOME", "REGEXP", "RLIKE", "SIMILAR TO"
            ])
            items += SQLKeywords.functionItems()

        case .groupBy, .orderBy:
            // Columns only
            items += await schemaProvider.allColumnsInScope(for: context.tableReferences)
            if context.clauseType == .orderBy {
                items += filterKeywords(["ASC", "DESC", "NULLS", "FIRST", "LAST"])
            }

        case .set:
            // Columns for UPDATE SET clause
            if let firstTable = context.tableReferences.first {
                items = await schemaProvider.columnCompletionItems(for: firstTable.tableName)
            }

        case .insertColumns:
            // Columns for INSERT column list
            if let firstTable = context.tableReferences.first {
                items = await schemaProvider.columnCompletionItems(for: firstTable.tableName)
            }

        case .values:
            // Functions and keywords for VALUES
            items = SQLKeywords.functionItems()
            items += filterKeywords(["NULL", "DEFAULT", "TRUE", "FALSE"])

        case .functionArg:
            // Inside function arguments - suggest columns and other functions
            items += await schemaProvider.allColumnsInScope(for: context.tableReferences)
            items += SQLKeywords.functionItems()
            items += filterKeywords(["NULL", "TRUE", "FALSE", "DISTINCT"])

        case .caseExpression:
            // Inside CASE expression
            items += await schemaProvider.allColumnsInScope(for: context.tableReferences)
            items += filterKeywords(["WHEN", "THEN", "ELSE", "END", "AND", "OR", "IS", "NULL", "TRUE", "FALSE"])
            items += SQLKeywords.operatorItems()
            items += SQLKeywords.functionItems()

        case .inList:
            // Inside IN (...) list - suggest values, subqueries, columns
            items += await schemaProvider.allColumnsInScope(for: context.tableReferences)
            items += filterKeywords(["SELECT", "NULL", "TRUE", "FALSE"])
            items += SQLKeywords.functionItems()

        case .limit:
            // After LIMIT/OFFSET - typically just numbers, but could include variables
            items += filterKeywords(["OFFSET", "FETCH", "NEXT", "ROWS", "ONLY"])

        case .alterTable:
            // After ALTER TABLE tablename - suggest DDL operations
            items = filterKeywords([
                "ADD", "DROP", "MODIFY", "CHANGE", "RENAME",
                "COLUMN", "INDEX", "PRIMARY", "FOREIGN", "KEY",
                "CONSTRAINT", "ENGINE", "CHARSET", "COLLATE", "AUTO_INCREMENT",
                "COMMENT", "DEFAULT", "CHARACTER SET"
            ])

        case .alterTableColumn:
            // After ALTER TABLE tablename DROP/MODIFY/CHANGE/RENAME or AFTER/BEFORE - suggest column names
            if let firstTable = context.tableReferences.first {
                items = await schemaProvider.columnCompletionItems(for: firstTable.tableName)
            }

        case .createTable:
            // Inside CREATE TABLE (...) - suggest constraints and data types
            items = filterKeywords([
                "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "UNIQUE",
                "NOT", "NULL", "DEFAULT", "AUTO_INCREMENT", "SERIAL",
                "CHECK", "CONSTRAINT", "INDEX"
            ])
            items += dataTypeKeywords()

        case .columnDef:
            // Typing column data type (after ADD COLUMN name)
            items = dataTypeKeywords()
            items += filterKeywords([
                "NOT", "NULL", "DEFAULT", "AUTO_INCREMENT", "SERIAL",
                "PRIMARY", "KEY", "UNIQUE", "REFERENCES", "CHECK",
                "UNSIGNED", "SIGNED", "FIRST", "AFTER", "COMMENT",
                "COLLATE", "CHARACTER SET", "ON UPDATE", "ON DELETE",
                "CASCADE", "RESTRICT", "SET NULL", "NO ACTION"
            ])

        case .unknown:
            // Start of query - suggest statement keywords and tables
            items = filterKeywords([
                // DML
                "SELECT", "INSERT", "UPDATE", "DELETE", "REPLACE", "MERGE", "UPSERT",
                // DDL
                "CREATE", "ALTER", "DROP", "TRUNCATE", "RENAME",
                // Database operations
                "SHOW", "DESCRIBE", "DESC", "EXPLAIN", "ANALYZE",
                // Transaction control
                "BEGIN", "COMMIT", "ROLLBACK", "SAVEPOINT", "START TRANSACTION",
                // CTEs and advanced
                "WITH", "RECURSIVE",
                // Database/schema
                "USE", "SET", "GRANT", "REVOKE",
                // Utility
                "CALL", "EXECUTE", "PREPARE"
            ])
            items += await schemaProvider.tableCompletionItems()
        }

        return items
    }

    /// SQL data type keywords (database-aware)
    private func dataTypeKeywords() -> [SQLCompletionItem] {
        var types: [String] = [
            // Common numeric types (all databases)
            "INT", "INTEGER", "BIGINT", "SMALLINT", "TINYINT",
            "DECIMAL", "NUMERIC", "FLOAT", "DOUBLE", "REAL",
            // Common string types
            "VARCHAR", "CHAR", "TEXT",
            // Common date/time types
            "DATE", "TIME", "DATETIME", "TIMESTAMP",
            // Boolean
            "BOOLEAN", "BOOL",
        ]

        // Add database-specific types
        switch databaseType {
        case .mysql, .mariadb:
            types += [
                "MEDIUMINT", "DOUBLE PRECISION",
                "TINYTEXT", "MEDIUMTEXT", "LONGTEXT",
                "BLOB", "TINYBLOB", "MEDIUMBLOB", "LONGBLOB",
                "YEAR", "ENUM", "SET", "JSON",
                "BINARY", "VARBINARY",
            ]

        case .postgresql:
            types += [
                "BIGSERIAL", "SERIAL", "SMALLSERIAL",
                "DOUBLE PRECISION", "MONEY",
                "CHARACTER", "CHARACTER VARYING", "CLOB",
                "BYTEA", "UUID", "JSON", "JSONB", "XML", "ARRAY",
                "TIMESTAMPTZ", "TIMETZ", "INTERVAL",
                "POINT", "LINE", "LSEG", "BOX", "PATH", "POLYGON", "CIRCLE",
                "INET", "CIDR", "MACADDR", "MACADDR8",
            ]

        case .sqlite:
            types += [
                "BLOB",
            ]

        case .none:
            // Include all types if database type is unknown
            types += [
                "MEDIUMINT", "DOUBLE PRECISION",
                "TINYTEXT", "MEDIUMTEXT", "LONGTEXT",
                "BLOB", "TINYBLOB", "MEDIUMBLOB", "LONGBLOB",
                "CLOB", "NCHAR", "NVARCHAR",
                "YEAR", "INTERVAL", "TIMESTAMPTZ", "TIMETZ",
                "BIT", "JSON", "JSONB", "XML", "ARRAY",
                "UUID", "BINARY", "VARBINARY", "BYTEA",
                "ENUM", "SET",
                "SERIAL", "BIGSERIAL", "SMALLSERIAL", "MONEY",
                "POINT", "LINE", "LSEG", "BOX", "PATH", "POLYGON", "CIRCLE",
                "INET", "CIDR", "MACADDR", "MACADDR8",
            ]
        }

        return filterKeywords(types)
    }

    /// Filter to specific keywords
    private func filterKeywords(_ keywords: [String]) -> [SQLCompletionItem] {
        keywords.map { SQLCompletionItem.keyword($0) }
    }

    // MARK: - Filtering

    /// Filter candidates by prefix (case-insensitive) with fuzzy matching support
    private func filterByPrefix(_ items: [SQLCompletionItem], prefix: String) -> [SQLCompletionItem] {
        guard !prefix.isEmpty else { return items }

        let lowerPrefix = prefix.lowercased()

        return items.filter { item in
            // Exact prefix match
            if item.filterText.hasPrefix(lowerPrefix) {
                return true
            }

            // Contains match
            if item.filterText.contains(lowerPrefix) {
                return true
            }

            // Fuzzy match: check if all characters appear in order
            return fuzzyMatch(pattern: lowerPrefix, target: item.filterText)
        }
    }

    /// Fuzzy matching: checks if all pattern characters appear in target in order
    private func fuzzyMatch(pattern: String, target: String) -> Bool {
        var patternIndex = pattern.startIndex
        var targetIndex = target.startIndex

        while patternIndex < pattern.endIndex && targetIndex < target.endIndex {
            if pattern[patternIndex] == target[targetIndex] {
                patternIndex = pattern.index(after: patternIndex)
            }
            targetIndex = target.index(after: targetIndex)
        }

        return patternIndex == pattern.endIndex
    }

    // MARK: - Ranking

    /// Rank results by relevance
    private func rankResults(_ items: [SQLCompletionItem], prefix: String, context: SQLContext) -> [SQLCompletionItem] {
        let lowerPrefix = prefix.lowercased()

        return items.sorted { a, b in
            let aScore = calculateScore(for: a, prefix: lowerPrefix, context: context)
            let bScore = calculateScore(for: b, prefix: lowerPrefix, context: context)
            return aScore < bScore // Lower score = higher priority
        }
    }

    /// Calculate ranking score for an item (lower = better)
    private func calculateScore(for item: SQLCompletionItem, prefix: String, context: SQLContext) -> Int {
        var score = item.sortPriority

        // Exact prefix match bonus
        if item.filterText.hasPrefix(prefix) {
            score -= 500
        }

        // Exact match bonus
        if item.filterText == prefix {
            score -= 1_000
        }

        // Context-appropriate bonuses
        switch context.clauseType {
        case .from, .join, .into:
            if item.kind == .table || item.kind == .view {
                score -= 200
            }
        case .select, .where_, .and, .on, .having, .groupBy, .orderBy:
            if item.kind == .column {
                score -= 200
            }
        case .set, .insertColumns:
            if item.kind == .column {
                score -= 300
            }
        default:
            break
        }

        // Shorter names slightly preferred
        score += item.label.count

        return score
    }
}
