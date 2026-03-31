//
//  IOSDriverFactory.swift
//  TableProMobile
//

import Foundation
import TableProDatabase
import TableProModels

final class IOSDriverFactory: DriverFactory {
    func createDriver(for connection: DatabaseConnection, password: String?) throws -> any DatabaseDriver {
        switch connection.type {
        case .sqlite:
            return SQLiteDriver(path: connection.database)
        default:
            throw ConnectionError.driverNotFound(connection.type.rawValue)
        }
    }

    func supportedTypes() -> [DatabaseType] {
        [.sqlite]
    }
}
