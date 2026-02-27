//
//  ExportStateTests.swift
//  TableProTests
//
//  Tests for ExportState consolidated struct.
//

import Foundation
@testable import TablePro
import Testing

@Suite("ExportState")
struct ExportStateTests {
    @Test("Default init has correct defaults")
    func defaultInitHasCorrectDefaults() {
        let state = ExportState()
        #expect(state.isExporting == false)
        #expect(state.progress == 0.0)
        #expect(state.currentTable == "")
        #expect(state.currentTableIndex == 0)
        #expect(state.totalTables == 0)
        #expect(state.processedRows == 0)
        #expect(state.totalRows == 0)
        #expect(state.statusMessage == "")
        #expect(state.errorMessage == nil)
        #expect(state.warningMessage == nil)
    }

    @Test("Value semantics — copy is independent")
    func valueSemanticsAreIndependent() {
        var original = ExportState()
        original.isExporting = true
        original.progress = 0.5
        original.currentTable = "users"

        var copy = original
        copy.isExporting = false
        copy.progress = 1.0
        copy.currentTable = "orders"

        #expect(original.isExporting == true)
        #expect(original.progress == 0.5)
        #expect(original.currentTable == "users")
        #expect(copy.isExporting == false)
        #expect(copy.progress == 1.0)
        #expect(copy.currentTable == "orders")
    }

    @Test("Partial init with set fields + defaults for rest")
    func partialInitWithDefaults() {
        var state = ExportState()
        state.isExporting = true
        state.totalTables = 5
        state.statusMessage = "Exporting..."

        #expect(state.isExporting == true)
        #expect(state.totalTables == 5)
        #expect(state.statusMessage == "Exporting...")
        #expect(state.progress == 0.0)
        #expect(state.errorMessage == nil)
    }

    @Test("All fields are readable and writable")
    func allFieldsAreReadableAndWritable() {
        var state = ExportState()

        state.isExporting = true
        #expect(state.isExporting == true)

        state.progress = 0.75
        #expect(state.progress == 0.75)

        state.currentTable = "products"
        #expect(state.currentTable == "products")

        state.currentTableIndex = 3
        #expect(state.currentTableIndex == 3)

        state.totalTables = 10
        #expect(state.totalTables == 10)

        state.processedRows = 500
        #expect(state.processedRows == 500)

        state.totalRows = 1000
        #expect(state.totalRows == 1000)

        state.statusMessage = "In progress"
        #expect(state.statusMessage == "In progress")

        state.errorMessage = "Some error"
        #expect(state.errorMessage == "Some error")

        state.warningMessage = "Some warning"
        #expect(state.warningMessage == "Some warning")
    }
}
