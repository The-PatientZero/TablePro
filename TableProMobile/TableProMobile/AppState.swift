//
//  AppState.swift
//  TableProMobile
//

import Foundation
import Observation
import TableProDatabase
import TableProModels

@MainActor @Observable
final class AppState {
    var connections: [DatabaseConnection] = []
    let connectionManager: ConnectionManager

    init() {
        let driverFactory = IOSDriverFactory()
        let secureStore = KeychainSecureStore()
        self.connectionManager = ConnectionManager(
            driverFactory: driverFactory,
            secureStore: secureStore
        )
    }

    func addConnection(_ connection: DatabaseConnection) {
        connections.append(connection)
    }

    func removeConnection(_ connection: DatabaseConnection) {
        connections.removeAll { $0.id == connection.id }
    }
}
