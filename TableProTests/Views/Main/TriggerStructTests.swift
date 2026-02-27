//
//  TriggerStructTests.swift
//  TableProTests
//
//  Tests for InspectorTrigger and PendingChangeTrigger equality logic.
//

import Foundation
@testable import TablePro
import Testing

// MARK: - InspectorTrigger Tests

@Suite("InspectorTrigger")
struct InspectorTriggerTests {
    @Test("Same values are equal")
    func sameValuesAreEqual() {
        let a = InspectorTrigger(tableName: "users", resultVersion: 1, metadataTableName: "users")
        let b = InspectorTrigger(tableName: "users", resultVersion: 1, metadataTableName: "users")
        #expect(a == b)
    }

    @Test("Both nil fields are equal")
    func bothNilFieldsAreEqual() {
        let a = InspectorTrigger(tableName: nil, resultVersion: 0, metadataTableName: nil)
        let b = InspectorTrigger(tableName: nil, resultVersion: 0, metadataTableName: nil)
        #expect(a == b)
    }

    @Test("Different tableName produces unequal triggers")
    func differentTableName() {
        let a = InspectorTrigger(tableName: "users", resultVersion: 1, metadataTableName: "users")
        let b = InspectorTrigger(tableName: "orders", resultVersion: 1, metadataTableName: "users")
        #expect(a != b)
    }

    @Test("nil vs non-nil tableName produces unequal triggers")
    func nilVsNonNilTableName() {
        let a = InspectorTrigger(tableName: nil, resultVersion: 1, metadataTableName: "users")
        let b = InspectorTrigger(tableName: "users", resultVersion: 1, metadataTableName: "users")
        #expect(a != b)
    }

    @Test("Different resultVersion produces unequal triggers")
    func differentResultVersion() {
        let a = InspectorTrigger(tableName: "users", resultVersion: 1, metadataTableName: "users")
        let b = InspectorTrigger(tableName: "users", resultVersion: 2, metadataTableName: "users")
        #expect(a != b)
    }

    @Test("Different metadataTableName produces unequal triggers")
    func differentMetadataTableName() {
        let a = InspectorTrigger(tableName: "users", resultVersion: 1, metadataTableName: "users")
        let b = InspectorTrigger(tableName: "users", resultVersion: 1, metadataTableName: "orders")
        #expect(a != b)
    }
}

// MARK: - PendingChangeTrigger Tests

@Suite("PendingChangeTrigger")
struct PendingChangeTriggerTests {
    @Test("Same values are equal")
    func sameValuesAreEqual() {
        let a = PendingChangeTrigger(hasDataChanges: true, pendingTruncates: ["t1"], pendingDeletes: ["t2"], hasStructureChanges: false)
        let b = PendingChangeTrigger(hasDataChanges: true, pendingTruncates: ["t1"], pendingDeletes: ["t2"], hasStructureChanges: false)
        #expect(a == b)
    }

    @Test("Empty sets are equal")
    func emptySetsAreEqual() {
        let a = PendingChangeTrigger(hasDataChanges: false, pendingTruncates: [], pendingDeletes: [], hasStructureChanges: false)
        let b = PendingChangeTrigger(hasDataChanges: false, pendingTruncates: [], pendingDeletes: [], hasStructureChanges: false)
        #expect(a == b)
    }

    @Test("Different hasDataChanges produces unequal triggers")
    func differentHasDataChanges() {
        let a = PendingChangeTrigger(hasDataChanges: true, pendingTruncates: [], pendingDeletes: [], hasStructureChanges: false)
        let b = PendingChangeTrigger(hasDataChanges: false, pendingTruncates: [], pendingDeletes: [], hasStructureChanges: false)
        #expect(a != b)
    }

    @Test("Different pendingTruncates produces unequal triggers")
    func differentPendingTruncates() {
        let a = PendingChangeTrigger(hasDataChanges: false, pendingTruncates: ["t1"], pendingDeletes: [], hasStructureChanges: false)
        let b = PendingChangeTrigger(hasDataChanges: false, pendingTruncates: ["t2"], pendingDeletes: [], hasStructureChanges: false)
        #expect(a != b)
    }

    @Test("Different pendingDeletes produces unequal triggers")
    func differentPendingDeletes() {
        let a = PendingChangeTrigger(hasDataChanges: false, pendingTruncates: [], pendingDeletes: ["d1"], hasStructureChanges: false)
        let b = PendingChangeTrigger(hasDataChanges: false, pendingTruncates: [], pendingDeletes: ["d2"], hasStructureChanges: false)
        #expect(a != b)
    }

    @Test("Different hasStructureChanges produces unequal triggers")
    func differentHasStructureChanges() {
        let a = PendingChangeTrigger(hasDataChanges: false, pendingTruncates: [], pendingDeletes: [], hasStructureChanges: true)
        let b = PendingChangeTrigger(hasDataChanges: false, pendingTruncates: [], pendingDeletes: [], hasStructureChanges: false)
        #expect(a != b)
    }
}
