//
//  QueryPlanParser.swift
//  TablePro
//
//  Parses EXPLAIN output into QueryPlan tree for visualization.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.TablePro", category: "QueryPlanParser")

// MARK: - Parser Protocol

protocol QueryPlanParser {
    func parse(rawText: String) -> QueryPlan?
}

// MARK: - PostgreSQL JSON Parser

/// Parses PostgreSQL `EXPLAIN (FORMAT JSON)` and `EXPLAIN (ANALYZE, FORMAT JSON)` output.
struct PostgreSQLPlanParser: QueryPlanParser {
    func parse(rawText: String) -> QueryPlan? {
        guard let data = rawText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let planDict = json.first,
              let plan = planDict["Plan"] as? [String: Any]
        else {
            logger.debug("Failed to parse PostgreSQL EXPLAIN JSON")
            return nil
        }

        let planningTime = planDict["Planning Time"] as? Double
        let executionTime = planDict["Execution Time"] as? Double
        let rootNode = parseNode(plan)

        var queryPlan = QueryPlan(
            rootNode: rootNode,
            planningTime: planningTime,
            executionTime: executionTime,
            rawText: rawText
        )
        queryPlan.computeCostFractions()
        return queryPlan
    }

    private func parseNode(_ dict: [String: Any]) -> QueryPlanNode {
        let children: [QueryPlanNode]
        if let plans = dict["Plans"] as? [[String: Any]] {
            children = plans.map { parseNode($0) }
        } else {
            children = []
        }

        // Collect all properties except the ones we extract explicitly
        let knownKeys: Set<String> = [
            "Node Type", "Relation Name", "Schema", "Alias",
            "Startup Cost", "Total Cost", "Plan Rows", "Plan Width",
            "Actual Startup Time", "Actual Total Time", "Actual Rows", "Actual Loops",
            "Plans",
        ]
        var properties: [String: String] = [:]
        for (key, value) in dict where !knownKeys.contains(key) {
            properties[key] = "\(value)"
        }

        return QueryPlanNode(
            operation: dict["Node Type"] as? String ?? "Unknown",
            relation: dict["Relation Name"] as? String,
            schema: dict["Schema"] as? String,
            alias: dict["Alias"] as? String,
            estimatedStartupCost: dict["Startup Cost"] as? Double,
            estimatedTotalCost: dict["Total Cost"] as? Double,
            estimatedRows: dict["Plan Rows"] as? Int,
            estimatedWidth: dict["Plan Width"] as? Int,
            actualStartupTime: dict["Actual Startup Time"] as? Double,
            actualTotalTime: dict["Actual Total Time"] as? Double,
            actualRows: dict["Actual Rows"] as? Int,
            actualLoops: dict["Actual Loops"] as? Int,
            properties: properties,
            children: children
        )
    }
}

// MARK: - MySQL JSON Parser

/// Parses MySQL `EXPLAIN FORMAT=JSON` output.
struct MySQLPlanParser: QueryPlanParser {
    func parse(rawText: String) -> QueryPlan? {
        guard let data = rawText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queryBlock = json["query_block"] as? [String: Any]
        else {
            logger.debug("Failed to parse MySQL EXPLAIN JSON")
            return nil
        }

        let rootNode = parseQueryBlock(queryBlock)
        var queryPlan = QueryPlan(
            rootNode: rootNode,
            planningTime: nil,
            executionTime: nil,
            rawText: rawText
        )
        queryPlan.computeCostFractions()
        return queryPlan
    }

    private func parseQueryBlock(_ block: [String: Any]) -> QueryPlanNode {
        var children: [QueryPlanNode] = []

        // Parse table access
        if let table = block["table"] as? [String: Any] {
            children.append(parseTable(table))
        }

        // Parse nested loop joins
        if let nestedLoop = block["nested_loop"] as? [[String: Any]] {
            for item in nestedLoop {
                if let table = item["table"] as? [String: Any] {
                    children.append(parseTable(table))
                }
            }
        }

        // Parse ordering/grouping operations
        if let orderingOp = block["ordering_operation"] as? [String: Any] {
            children.append(parseOrderingOp(orderingOp))
        }

        let costInfo = block["cost_info"] as? [String: Any]
        let queryCost = (costInfo?["query_cost"] as? String).flatMap { Double($0) }

        return QueryPlanNode(
            operation: "Query Block",
            relation: nil, schema: nil, alias: nil,
            estimatedStartupCost: nil,
            estimatedTotalCost: queryCost,
            estimatedRows: nil, estimatedWidth: nil,
            actualStartupTime: nil, actualTotalTime: nil,
            actualRows: nil, actualLoops: nil,
            properties: [:],
            children: children
        )
    }

    private func parseTable(_ table: [String: Any]) -> QueryPlanNode {
        let costInfo = table["cost_info"] as? [String: Any]
        let readCost = (costInfo?["read_cost"] as? String).flatMap { Double($0) }
        let rows = table["rows_examined_per_scan"] as? Int ?? table["rows_produced_per_join"] as? Int

        var properties: [String: String] = [:]
        if let key = table["key"] as? String { properties["Key"] = key }
        if let ref = table["ref"] as? [String] { properties["Ref"] = ref.joined(separator: ", ") }
        if let extra = table["attached_condition"] as? String { properties["Filter"] = extra }

        return QueryPlanNode(
            operation: table["access_type"] as? String ?? "ALL",
            relation: table["table_name"] as? String,
            schema: nil,
            alias: nil,
            estimatedStartupCost: nil,
            estimatedTotalCost: readCost,
            estimatedRows: rows,
            estimatedWidth: nil,
            actualStartupTime: nil, actualTotalTime: nil,
            actualRows: nil, actualLoops: nil,
            properties: properties,
            children: []
        )
    }

    private func parseOrderingOp(_ op: [String: Any]) -> QueryPlanNode {
        var children: [QueryPlanNode] = []
        if let nestedLoop = op["nested_loop"] as? [[String: Any]] {
            for item in nestedLoop {
                if let table = item["table"] as? [String: Any] {
                    children.append(parseTable(table))
                }
            }
        }
        if let table = op["table"] as? [String: Any] {
            children.append(parseTable(table))
        }

        return QueryPlanNode(
            operation: op["using_filesort"] as? Bool == true ? "Sort" : "Order",
            relation: nil, schema: nil, alias: nil,
            estimatedStartupCost: nil, estimatedTotalCost: nil,
            estimatedRows: nil, estimatedWidth: nil,
            actualStartupTime: nil, actualTotalTime: nil,
            actualRows: nil, actualLoops: nil,
            properties: [:],
            children: children
        )
    }
}

// MARK: - SQLite Parser

/// Parses SQLite `EXPLAIN QUERY PLAN` output (id/parent/notused/detail columns).
struct SQLitePlanParser: QueryPlanParser {
    func parse(rawText: String) -> QueryPlan? {
        let lines = rawText.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        // SQLite EXPLAIN QUERY PLAN returns: id | parent | notused | detail
        // Parse tab-separated or pipe-separated rows
        var nodes: [(id: Int, parent: Int, detail: String)] = []
        for line in lines {
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 4,
               let id = Int(parts[0].trimmingCharacters(in: .whitespaces)),
               let parent = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                nodes.append((id: id, parent: parent, detail: parts[3].trimmingCharacters(in: .whitespaces)))
            } else {
                // Fallback: treat entire line as a detail node
                nodes.append((id: nodes.count, parent: nodes.isEmpty ? -1 : 0, detail: line))
            }
        }

        guard !nodes.isEmpty else { return nil }

        func buildChildren(parentId: Int) -> [QueryPlanNode] {
            nodes.filter { $0.parent == parentId }.map { node in
                QueryPlanNode(
                    operation: node.detail,
                    relation: nil, schema: nil, alias: nil,
                    estimatedStartupCost: nil, estimatedTotalCost: nil,
                    estimatedRows: nil, estimatedWidth: nil,
                    actualStartupTime: nil, actualTotalTime: nil,
                    actualRows: nil, actualLoops: nil,
                    properties: [:],
                    children: buildChildren(parentId: node.id)
                )
            }
        }

        let rootChildren = buildChildren(parentId: nodes[0].parent == 0 ? -1 : nodes[0].parent)
        let rootNode: QueryPlanNode
        if rootChildren.count == 1 {
            rootNode = rootChildren[0]
        } else {
            rootNode = QueryPlanNode(
                operation: "Query Plan",
                relation: nil, schema: nil, alias: nil,
                estimatedStartupCost: nil, estimatedTotalCost: nil,
                estimatedRows: nil, estimatedWidth: nil,
                actualStartupTime: nil, actualTotalTime: nil,
                actualRows: nil, actualLoops: nil,
                properties: [:],
                children: rootChildren
            )
        }

        return QueryPlan(rootNode: rootNode, planningTime: nil, executionTime: nil, rawText: rawText)
    }
}

// MARK: - Indented Text Parser (ClickHouse, DuckDB)

/// Parses indented text EXPLAIN output into a tree based on leading whitespace depth.
/// Works for ClickHouse EXPLAIN, DuckDB EXPLAIN, and any text plan with indentation hierarchy.
struct IndentedTextPlanParser: QueryPlanParser {
    func parse(rawText: String) -> QueryPlan? {
        let lines = rawText.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        // Parse each line's indent level and content
        struct ParsedLine {
            let indent: Int
            let text: String
        }
        let parsed: [ParsedLine] = lines.map { line in
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            let indent = line.count - trimmed.count
            return ParsedLine(indent: indent, text: String(trimmed))
        }

        // Build tree from indentation
        func buildNodes(from startIndex: Int, parentIndent: Int) -> (nodes: [QueryPlanNode], nextIndex: Int) {
            var nodes: [QueryPlanNode] = []
            var i = startIndex

            while i < parsed.count {
                let line = parsed[i]
                if line.indent <= parentIndent && i > startIndex {
                    break
                }

                let children: [QueryPlanNode]
                let nextI: Int
                if i + 1 < parsed.count && parsed[i + 1].indent > line.indent {
                    let result = buildNodes(from: i + 1, parentIndent: line.indent)
                    children = result.nodes
                    nextI = result.nextIndex
                } else {
                    children = []
                    nextI = i + 1
                }

                nodes.append(QueryPlanNode(
                    operation: line.text,
                    relation: nil, schema: nil, alias: nil,
                    estimatedStartupCost: nil, estimatedTotalCost: nil,
                    estimatedRows: nil, estimatedWidth: nil,
                    actualStartupTime: nil, actualTotalTime: nil,
                    actualRows: nil, actualLoops: nil,
                    properties: [:],
                    children: children
                ))
                i = nextI
            }
            return (nodes, i)
        }

        let result = buildNodes(from: 0, parentIndent: -1)
        let rootNode: QueryPlanNode
        if result.nodes.count == 1 {
            rootNode = result.nodes[0]
        } else {
            rootNode = QueryPlanNode(
                operation: "Query Plan",
                relation: nil, schema: nil, alias: nil,
                estimatedStartupCost: nil, estimatedTotalCost: nil,
                estimatedRows: nil, estimatedWidth: nil,
                actualStartupTime: nil, actualTotalTime: nil,
                actualRows: nil, actualLoops: nil,
                properties: [:],
                children: result.nodes
            )
        }

        return QueryPlan(rootNode: rootNode, planningTime: nil, executionTime: nil, rawText: rawText)
    }
}

// MARK: - Factory

enum QueryPlanParserFactory {
    static func parser(for databaseType: DatabaseType) -> QueryPlanParser? {
        switch databaseType {
        case .postgresql, .redshift:
            return PostgreSQLPlanParser()
        case .mysql, .mariadb:
            return MySQLPlanParser()
        case .sqlite:
            return SQLitePlanParser()
        case .clickhouse, .duckdb:
            return IndentedTextPlanParser()
        default:
            return nil
        }
    }
}
