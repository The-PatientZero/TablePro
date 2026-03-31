//
//  SQLHelper.swift
//  TableProMobile
//

import Foundation

enum SQLHelper {
    static func buildDelete(
        table: String,
        primaryKeys: [(column: String, value: String)]
    ) -> String {
        let whereClause = primaryKeys.map { "`\($0.column)` = '\(escape($0.value))'" }
            .joined(separator: " AND ")
        return "DELETE FROM `\(table)` WHERE \(whereClause)"
    }

    static func buildUpdate(
        table: String,
        changes: [(column: String, value: String?)],
        primaryKeys: [(column: String, value: String)]
    ) -> String {
        let setClauses = changes.map { col, val in
            if let val { return "`\(col)` = '\(escape(val))'" }
            return "`\(col)` = NULL"
        }.joined(separator: ", ")
        let whereClause = primaryKeys.map { "`\($0.column)` = '\(escape($0.value))'" }
            .joined(separator: " AND ")
        return "UPDATE `\(table)` SET \(setClauses) WHERE \(whereClause)"
    }

    static func buildInsert(
        table: String,
        columns: [String],
        values: [String?]
    ) -> String {
        let cols = columns.map { "`\($0)`" }.joined(separator: ", ")
        let vals = values.map { val in
            if let val { return "'\(escape(val))'" }
            return "NULL"
        }.joined(separator: ", ")
        return "INSERT INTO `\(table)` (\(cols)) VALUES (\(vals))"
    }

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
