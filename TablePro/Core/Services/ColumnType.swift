//
//  ColumnType.swift
//  TablePro
//
//  Column type metadata for type-aware formatting and display.
//  Extracted from database drivers and used throughout the app.
//

import Foundation

/// Represents the semantic type of a database column
enum ColumnType: Equatable {
    case text(rawType: String?)
    case integer(rawType: String?)
    case decimal(rawType: String?)
    case date(rawType: String?)
    case timestamp(rawType: String?)
    case datetime(rawType: String?)
    case boolean(rawType: String?)
    case blob(rawType: String?)

    /// Raw database type name (e.g., "LONGTEXT", "VARCHAR(255)", "CLOB")
    var rawType: String? {
        switch self {
        case .text(let raw), .integer(let raw), .decimal(let raw),
             .date(let raw), .timestamp(let raw), .datetime(let raw),
             .boolean(let raw), .blob(let raw):
            return raw
        }
    }

    // MARK: - MySQL Type Mapping

    /// Initialize from MySQL MYSQL_TYPE_* enum value
    /// Reference: https://dev.mysql.com/doc/c-api/8.0/en/c-api-data-structures.html
    init(fromMySQLType type: UInt32, rawType: String? = nil) {
        switch type {
        // Integer types
        case 1, 2, 3, 8, 9:  // TINY, SHORT, LONG, LONGLONG, INT24
            self = .integer(rawType: rawType)

        // Decimal types
        case 4, 5, 246:  // FLOAT, DOUBLE, NEWDECIMAL
            self = .decimal(rawType: rawType)

        // Date/time types
        case 10:  // DATE
            self = .date(rawType: rawType)
        case 7:   // TIMESTAMP
            self = .timestamp(rawType: rawType)
        case 12:  // DATETIME
            self = .datetime(rawType: rawType)
        case 11:  // TIME
            self = .timestamp(rawType: rawType)  // Treat TIME as timestamp for formatting

        // Boolean (TINYINT(1))
        // Note: MySQL doesn't have a dedicated boolean type
        // We detect TINYINT(1) in the driver itself

        // Binary/blob types
        case 249, 250, 251, 252:  // TINY_BLOB, MEDIUM_BLOB, LONG_BLOB, BLOB
            self = .blob(rawType: rawType)

        // Text types (default)
        default:
            self = .text(rawType: rawType)
        }
    }

    /// Initialize from MySQL field metadata with size hint for boolean detection
    init(fromMySQLType type: UInt32, length: UInt64, rawType: String? = nil) {
        // Special case: TINYINT(1) is often used for boolean
        if type == 1 && length == 1 {
            self = .boolean(rawType: rawType)
        } else {
            self.init(fromMySQLType: type, rawType: rawType)
        }
    }

    // MARK: - PostgreSQL Type Mapping

    /// Initialize from PostgreSQL Oid
    /// Reference: https://www.postgresql.org/docs/current/datatype-oid.html
    init(fromPostgreSQLOid oid: UInt32, rawType: String? = nil) {
        switch oid {
        // Boolean
        case 16:  // BOOLOID
            self = .boolean(rawType: rawType)

        // Integer types
        case 20, 21, 23, 26:  // INT8, INT2, INT4, OID
            self = .integer(rawType: rawType)

        // Decimal types
        case 700, 701, 1_700:  // FLOAT4, FLOAT8, NUMERIC
            self = .decimal(rawType: rawType)

        // Date/time types
        case 1_082:  // DATE
            self = .date(rawType: rawType)
        case 1_083, 1_266:  // TIME, TIMETZ
            self = .timestamp(rawType: rawType)
        case 1_114, 1_184:  // TIMESTAMP, TIMESTAMPTZ
            self = .timestamp(rawType: rawType)

        // Binary types
        case 17:  // BYTEA
            self = .blob(rawType: rawType)

        // Text types (default)
        default:
            self = .text(rawType: rawType)
        }
    }

    // MARK: - SQLite Type Mapping

    /// Initialize from SQLite declared type string
    /// SQLite uses type affinity rules: https://www.sqlite.org/datatype3.html
    init(fromSQLiteType declaredType: String?) {
        guard let type = declaredType?.uppercased() else {
            self = .text(rawType: declaredType)
            return
        }

        // SQLite type affinity rules
        if type.contains("INT") {
            self = .integer(rawType: declaredType)
        } else if type.contains("CHAR") || type.contains("CLOB") || type.contains("TEXT") {
            self = .text(rawType: declaredType)
        } else if type.contains("BLOB") || type.isEmpty {
            self = .blob(rawType: declaredType)
        } else if type.contains("REAL") || type.contains("FLOA") || type.contains("DOUB") {
            self = .decimal(rawType: declaredType)
        } else if type.contains("DATE") && !type.contains("TIME") {
            self = .date(rawType: declaredType)
        } else if type.contains("TIME") || type.contains("TIMESTAMP") {
            self = .timestamp(rawType: declaredType)
        } else if type.contains("BOOL") {
            self = .boolean(rawType: declaredType)
        } else {
            // Numeric affinity (catch-all for numeric types)
            self = .text(rawType: declaredType)
        }
    }

    // MARK: - Display Properties

    /// Human-readable name for this column type
    var displayName: String {
        switch self {
        case .text: return "Text"
        case .integer: return "Integer"
        case .decimal: return "Decimal"
        case .date: return "Date"
        case .timestamp: return "Timestamp"
        case .datetime: return "DateTime"
        case .boolean: return "Boolean"
        case .blob: return "Binary"
        }
    }

    /// Whether this type represents a date/time value that should be formatted
    var isDateType: Bool {
        switch self {
        case .date, .timestamp, .datetime:
            return true
        default:
            return false
        }
    }

    /// Whether this type represents long text that should use multi-line editor
    /// Checks for TEXT, LONGTEXT, MEDIUMTEXT, TINYTEXT, CLOB types
    var isLongText: Bool {
        guard let raw = rawType?.uppercased() else {
            return false
        }

        // MySQL long text types (exact match to avoid matching VARCHAR, etc.)
        if raw == "TEXT" || raw == "TINYTEXT" || raw == "MEDIUMTEXT" || raw == "LONGTEXT" {
            return true
        }

        // PostgreSQL/SQLite CLOB type
        if raw == "CLOB" {
            return true
        }

        return false
    }
}
