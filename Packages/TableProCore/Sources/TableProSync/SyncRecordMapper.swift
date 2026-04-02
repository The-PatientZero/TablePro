import CloudKit
import Foundation
import os

import TableProModels

public enum SyncRecordMapper {
    private static let logger = Logger(subsystem: "com.TablePro", category: "SyncRecordMapper")
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static let schemaVersion: Int64 = 1

    // MARK: - Record Name Helpers

    public static func recordID(type: SyncRecordType, id: String, in zone: CKRecordZone.ID) -> CKRecord.ID {
        let recordName: String
        switch type {
        case .connection: recordName = "Connection_\(id)"
        case .group: recordName = "Group_\(id)"
        }
        return CKRecord.ID(recordName: recordName, zoneID: zone)
    }

    // MARK: - Connection -> CKRecord

    public static func toRecord(_ connection: DatabaseConnection, zoneID: CKRecordZone.ID) -> CKRecord {
        let id = recordID(type: .connection, id: connection.id.uuidString, in: zoneID)
        let record = CKRecord(recordType: SyncRecordType.connection.rawValue, recordID: id)

        record["connectionId"] = connection.id.uuidString as CKRecordValue
        record["name"] = connection.name as CKRecordValue
        record["host"] = connection.host as CKRecordValue
        record["port"] = Int64(connection.port) as CKRecordValue
        record["database"] = connection.database as CKRecordValue
        record["username"] = connection.username as CKRecordValue
        record["type"] = connection.type.rawValue as CKRecordValue
        record["sortOrder"] = Int64(connection.sortOrder) as CKRecordValue
        record["isReadOnly"] = Int64(connection.isReadOnly ? 1 : 0) as CKRecordValue
        record["sshEnabled"] = Int64(connection.sshEnabled ? 1 : 0) as CKRecordValue
        record["sslEnabled"] = Int64(connection.sslEnabled ? 1 : 0) as CKRecordValue

        if let colorTag = connection.colorTag {
            record["colorTag"] = colorTag as CKRecordValue
        }
        if let groupId = connection.groupId {
            record["groupId"] = groupId.uuidString as CKRecordValue
        }
        if let queryTimeout = connection.queryTimeoutSeconds {
            record["queryTimeoutSeconds"] = Int64(queryTimeout) as CKRecordValue
        }

        if let sshConfig = connection.sshConfiguration {
            do {
                let data = try encoder.encode(sshConfig)
                record["sshConfigJson"] = data as CKRecordValue
            } catch {
                logger.warning("Failed to encode SSH config for sync: \(error.localizedDescription)")
            }
        }

        if let sslConfig = connection.sslConfiguration {
            do {
                let data = try encoder.encode(sslConfig)
                record["sslConfigJson"] = data as CKRecordValue
            } catch {
                logger.warning("Failed to encode SSL config for sync: \(error.localizedDescription)")
            }
        }

        if !connection.additionalFields.isEmpty {
            do {
                let data = try encoder.encode(connection.additionalFields)
                record["additionalFieldsJson"] = data as CKRecordValue
            } catch {
                logger.warning("Failed to encode additional fields for sync: \(error.localizedDescription)")
            }
        }

        record["modifiedAtLocal"] = Date() as CKRecordValue
        record["schemaVersion"] = schemaVersion as CKRecordValue

        return record
    }

    // MARK: - CKRecord -> Connection

    public static func toConnection(_ record: CKRecord) -> DatabaseConnection? {
        guard let idString = record["connectionId"] as? String,
              let id = UUID(uuidString: idString),
              let name = record["name"] as? String,
              let typeRaw = record["type"] as? String
        else {
            logger.warning("Failed to decode connection from CKRecord: missing required fields")
            return nil
        }

        let host = record["host"] as? String ?? "127.0.0.1"
        let port = (record["port"] as? Int64).map { Int($0) } ?? 3306
        let database = record["database"] as? String ?? ""
        let username = record["username"] as? String ?? ""
        let colorTag = record["colorTag"] as? String
        let groupId = (record["groupId"] as? String).flatMap { UUID(uuidString: $0) }
        let sortOrder = (record["sortOrder"] as? Int64).map { Int($0) } ?? 0
        let isReadOnly = (record["isReadOnly"] as? Int64 ?? 0) != 0
        let queryTimeout = (record["queryTimeoutSeconds"] as? Int64).map { Int($0) }
        let sshEnabled = (record["sshEnabled"] as? Int64 ?? 0) != 0
        let sslEnabled = (record["sslEnabled"] as? Int64 ?? 0) != 0

        var sshConfig: SSHConfiguration?
        if let sshData = record["sshConfigJson"] as? Data {
            sshConfig = try? decoder.decode(SSHConfiguration.self, from: sshData)
        }

        var sslConfig: SSLConfiguration?
        if let sslData = record["sslConfigJson"] as? Data {
            sslConfig = try? decoder.decode(SSLConfiguration.self, from: sslData)
        }

        var additionalFields: [String: String] = [:]
        if let fieldsData = record["additionalFieldsJson"] as? Data {
            additionalFields = (try? decoder.decode([String: String].self, from: fieldsData)) ?? [:]
        }

        return DatabaseConnection(
            id: id,
            name: name,
            type: DatabaseType(rawValue: typeRaw),
            host: host,
            port: port,
            username: username,
            database: database,
            colorTag: colorTag,
            isReadOnly: isReadOnly,
            queryTimeoutSeconds: queryTimeout,
            additionalFields: additionalFields,
            sshEnabled: sshEnabled,
            sshConfiguration: sshConfig,
            sslEnabled: sslEnabled,
            sslConfiguration: sslConfig,
            groupId: groupId,
            sortOrder: sortOrder
        )
    }

    // MARK: - Group -> CKRecord

    public static func toRecord(_ group: ConnectionGroup, zoneID: CKRecordZone.ID) -> CKRecord {
        let id = recordID(type: .group, id: group.id.uuidString, in: zoneID)
        let record = CKRecord(recordType: SyncRecordType.group.rawValue, recordID: id)

        record["groupId"] = group.id.uuidString as CKRecordValue
        record["name"] = group.name as CKRecordValue
        record["sortOrder"] = Int64(group.sortOrder) as CKRecordValue
        record["modifiedAtLocal"] = Date() as CKRecordValue
        record["schemaVersion"] = schemaVersion as CKRecordValue

        return record
    }

    // MARK: - CKRecord -> Group

    public static func toGroup(_ record: CKRecord) -> ConnectionGroup? {
        guard let idStr = record["groupId"] as? String,
              let id = UUID(uuidString: idStr),
              let name = record["name"] as? String
        else {
            logger.warning("Failed to decode group from CKRecord: missing required fields")
            return nil
        }

        let sortOrder = (record["sortOrder"] as? Int64).map { Int($0) } ?? 0

        return ConnectionGroup(id: id, name: name, sortOrder: sortOrder)
    }
}
