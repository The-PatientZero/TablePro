//
//  MainContentCoordinator+SidebarActions.swift
//  TablePro
//
//  Sidebar context menu actions for MainContentCoordinator.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

extension MainContentCoordinator {
    // MARK: - View Operations

    func createView() {
        guard !connection.safeModeLevel.blocksAllWrites else { return }

        let template: String
        switch connection.type {
        case .postgresql, .redshift, .duckdb:
            template = "CREATE OR REPLACE VIEW view_name AS\nSELECT column1, column2\nFROM table_name\nWHERE condition;"
        case .mysql, .mariadb, .clickhouse:
            template = "CREATE VIEW view_name AS\nSELECT column1, column2\nFROM table_name\nWHERE condition;"
        case .sqlite:
            template = "CREATE VIEW IF NOT EXISTS view_name AS\nSELECT column1, column2\nFROM table_name\nWHERE condition;"
        case .mssql:
            template = "CREATE OR ALTER VIEW view_name AS\nSELECT column1, column2\nFROM table_name\nWHERE condition;"
        case .oracle:
            template = "CREATE OR REPLACE VIEW view_name AS\nSELECT column1, column2\nFROM table_name\nWHERE condition;"
        case .mongodb:
            template = "db.createView(\"view_name\", \"source_collection\", [\n  {\"$match\": {}},\n  {\"$project\": {\"_id\": 1}}\n])"
        case .redis:
            template = "-- Redis does not support views"
        }

        let payload = EditorTabPayload(
            connectionId: connection.id,
            tabType: .query,
            databaseName: connection.database,
            initialQuery: template
        )
        WindowOpener.shared.openNativeTab(payload)
    }

    func editViewDefinition(_ viewName: String) {
        Task { @MainActor in
            do {
                guard let driver = DatabaseManager.shared.driver(for: self.connection.id) else { return }
                let definition = try await driver.fetchViewDefinition(view: viewName)

                let payload = EditorTabPayload(
                    connectionId: connection.id,
                    tabType: .query,
                    initialQuery: definition
                )
                WindowOpener.shared.openNativeTab(payload)
            } catch {
                let fallbackSQL: String
                switch connection.type {
                case .postgresql, .redshift, .duckdb:
                    fallbackSQL = "CREATE OR REPLACE VIEW \(viewName) AS\n-- Could not fetch view definition: \(error.localizedDescription)\nSELECT * FROM table_name;"
                case .mysql, .mariadb, .clickhouse:
                    fallbackSQL = "ALTER VIEW \(viewName) AS\n-- Could not fetch view definition: \(error.localizedDescription)\nSELECT * FROM table_name;"
                case .sqlite:
                    fallbackSQL = "-- SQLite does not support ALTER VIEW. Drop and recreate:\nDROP VIEW IF EXISTS \(viewName);\nCREATE VIEW \(viewName) AS\nSELECT * FROM table_name;"
                case .mssql:
                    fallbackSQL = "CREATE OR ALTER VIEW \(viewName) AS\n-- Could not fetch view definition: \(error.localizedDescription)\nSELECT * FROM table_name;"
                case .oracle:
                    fallbackSQL = "CREATE OR REPLACE VIEW \(viewName) AS\n-- Could not fetch view definition: \(error.localizedDescription)\nSELECT * FROM table_name;"
                case .mongodb:
                    fallbackSQL = "db.runCommand({\"collMod\": \"\(viewName)\", \"viewOn\": \"source_collection\", \"pipeline\": [{\"$match\": {}}]})"
                case .redis:
                    fallbackSQL = "-- Redis does not support views"
                }

                let payload = EditorTabPayload(
                    connectionId: connection.id,
                    tabType: .query,
                    initialQuery: fallbackSQL
                )
                WindowOpener.shared.openNativeTab(payload)
            }
        }
    }

    // MARK: - Export/Import

    func openExportDialog() {
        activeSheet = .exportDialog
    }

    func openImportDialog() {
        guard !connection.safeModeLevel.blocksAllWrites else { return }
        guard connection.type != .mongodb && connection.type != .redis else {
            let typeName = connection.type == .mongodb ? "MongoDB" : "Redis"
            AlertHelper.showErrorSheet(
                title: String(localized: "Import Not Supported"),
                message: String(localized: "SQL import is not supported for \(typeName) connections."),
                window: nil
            )
            return
        }
        let panel = NSOpenPanel()
        var contentTypes: [UTType] = []
        if let sqlType = UTType(filenameExtension: "sql") {
            contentTypes.append(sqlType)
        }
        if let gzType = UTType(filenameExtension: "gz") {
            contentTypes.append(gzType)
        }
        if !contentTypes.isEmpty {
            panel.allowedContentTypes = contentTypes
        }
        panel.allowsMultipleSelection = false
        panel.message = "Select SQL file to import"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.importFileURL = url
            self?.activeSheet = .importDialog
        }
    }
}
