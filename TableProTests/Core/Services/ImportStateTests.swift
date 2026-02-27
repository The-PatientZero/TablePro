//
//  ImportStateTests.swift
//  TableProTests
//
//  Tests for ImportState consolidated struct.
//

import Foundation
@testable import TablePro
import Testing

@Suite("ImportState")
struct ImportStateTests {
    @Test("Default init has correct defaults")
    func defaultInitHasCorrectDefaults() {
        let state = ImportState()
        #expect(state.isImporting == false)
        #expect(state.progress == 0.0)
        #expect(state.currentStatement == "")
        #expect(state.currentStatementIndex == 0)
        #expect(state.totalStatements == 0)
        #expect(state.statusMessage == "")
        #expect(state.errorMessage == nil)
    }

    @Test("Value semantics — copy is independent")
    func valueSemanticsAreIndependent() {
        var original = ImportState()
        original.isImporting = true
        original.progress = 0.5

        var copy = original
        copy.isImporting = false
        copy.progress = 1.0

        #expect(original.isImporting == true)
        #expect(original.progress == 0.5)
        #expect(copy.isImporting == false)
        #expect(copy.progress == 1.0)
    }

    @Test("Partial init with isImporting=true")
    func partialInitWithImporting() {
        var state = ImportState()
        state.isImporting = true

        #expect(state.isImporting == true)
        #expect(state.progress == 0.0)
        #expect(state.currentStatement == "")
        #expect(state.errorMessage == nil)
    }

    @Test("All fields are readable and writable")
    func allFieldsAreReadableAndWritable() {
        var state = ImportState()

        state.isImporting = true
        #expect(state.isImporting == true)

        state.progress = 0.75
        #expect(state.progress == 0.75)

        state.currentStatement = "CREATE TABLE test"
        #expect(state.currentStatement == "CREATE TABLE test")

        state.currentStatementIndex = 5
        #expect(state.currentStatementIndex == 5)

        state.totalStatements = 20
        #expect(state.totalStatements == 20)

        state.statusMessage = "Importing..."
        #expect(state.statusMessage == "Importing...")

        state.errorMessage = "Import error"
        #expect(state.errorMessage == "Import error")
    }
}
