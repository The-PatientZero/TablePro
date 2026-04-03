//
//  IOSSyncCoordinator.swift
//  TableProMobile
//

import CloudKit
import Foundation
import Observation
import TableProModels
import TableProSync

@MainActor @Observable
final class IOSSyncCoordinator {
    var status: SyncStatus = .idle
    var lastSyncDate: Date?

    private var engine: CloudKitSyncEngine?
    private let metadata = SyncMetadataStorage()
    private var cachedRecords: [UUID: CKRecord] = [:]

    private func getEngine() -> CloudKitSyncEngine {
        if engine == nil {
            engine = CloudKitSyncEngine()
        }
        return engine!
    }
    private var debounceTask: Task<Void, Never>?

    // Callback to update AppState connections
    var onConnectionsChanged: (([DatabaseConnection]) -> Void)?

    // MARK: - Sync

    func sync(localConnections: [DatabaseConnection]) async {
        guard status != .syncing else { return }
        status = .syncing

        do {
            let accountStatus = try await getEngine().accountStatus()
            guard accountStatus == .available else {
                status = .error("iCloud account not available")
                return
            }

            try await getEngine().ensureZoneExists()
            try await push(localConnections: localConnections)
            let remoteConnections = try await pull()
            let merged = merge(local: localConnections, remote: remoteConnections)
            onConnectionsChanged?(merged)

            metadata.lastSyncDate = Date()
            lastSyncDate = metadata.lastSyncDate
            status = .idle
        } catch let error as SyncError where error == .tokenExpired {
            metadata.saveToken(nil)
            status = .idle
            await sync(localConnections: localConnections)
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func markDirty(_ connectionId: UUID) {
        metadata.markDirty(connectionId.uuidString, type: .connection)
    }

    func markDeleted(_ connectionId: UUID) {
        metadata.addTombstone(connectionId.uuidString, type: .connection)
    }

    func scheduleSyncAfterChange(localConnections: [DatabaseConnection]) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await sync(localConnections: localConnections)
        }
    }

    // MARK: - Push

    private func push(localConnections: [DatabaseConnection]) async throws {
        let zoneID = await getEngine().currentZoneID

        // Dirty connections
        let dirtyIDs = metadata.dirtyIDs(for: .connection)
        let dirtyRecords = localConnections
            .filter { dirtyIDs.contains($0.id.uuidString) }
            .map { connection -> CKRecord in
                if let existing = cachedRecords[connection.id] {
                    SyncRecordMapper.updateRecord(existing, with: connection)
                    return existing
                } else {
                    return SyncRecordMapper.toRecord(connection, zoneID: zoneID)
                }
            }

        // Tombstones
        let tombstones = metadata.tombstones(for: .connection)
        let deletions = tombstones.map {
            CKRecord.ID(recordName: "Connection_\($0.id)", zoneID: zoneID)
        }

        guard !dirtyRecords.isEmpty || !deletions.isEmpty else { return }

        try await getEngine().push(records: dirtyRecords, deletions: deletions)
        metadata.clearDirty(type: .connection)
        metadata.clearTombstones(type: .connection)
    }

    // MARK: - Pull

    private func pull() async throws -> [DatabaseConnection] {
        let token = metadata.loadToken()
        let result = try await getEngine().pull(since: token)

        if let newToken = result.newToken {
            metadata.saveToken(newToken)
        }

        var connections: [DatabaseConnection] = []

        for record in result.changedRecords {
            if record.recordType == SyncRecordType.connection.rawValue {
                if let connection = SyncRecordMapper.toConnection(record) {
                    cachedRecords[connection.id] = record
                    connections.append(connection)
                }
            }
        }

        return connections
    }

    // MARK: - Merge (last-write-wins)

    private func merge(local: [DatabaseConnection], remote: [DatabaseConnection]) -> [DatabaseConnection] {
        var result = local
        let localMap = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })

        for remoteConn in remote {
            if localMap[remoteConn.id] != nil {
                // Exists locally — replace with server version (last-write-wins)
                if let index = result.firstIndex(where: { $0.id == remoteConn.id }) {
                    result[index] = remoteConn
                }
            } else {
                // New from server
                result.append(remoteConn)
            }
        }

        return result
    }
}

// SyncError Equatable for token expiry check
extension SyncError: Equatable {
    public static func == (lhs: SyncError, rhs: SyncError) -> Bool {
        switch (lhs, rhs) {
        case (.tokenExpired, .tokenExpired): return true
        default: return false
        }
    }
}
