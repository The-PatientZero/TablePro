//
//  MongoDBPlugin.swift
//  TablePro
//

import Foundation
import TableProPluginKit

final class MongoDBPlugin: NSObject, TableProPlugin, DriverPlugin {
    static let pluginName = "MongoDB Driver"
    static let pluginVersion = "1.0.0"
    static let pluginDescription = "MongoDB support via libmongoc C driver"
    static let capabilities: [PluginCapability] = [.databaseDriver]

    static let databaseTypeId = "MongoDB"
    static let databaseDisplayName = "MongoDB"
    static let iconName = "leaf.fill"
    static let defaultPort = 27017
    static let additionalConnectionFields: [ConnectionField] = [
        ConnectionField(id: "mongoAuthSource", label: "Auth Database", placeholder: "admin"),
        ConnectionField(id: "mongoReadPreference", label: "Read Preference", placeholder: "primary"),
        ConnectionField(id: "mongoWriteConcern", label: "Write Concern", placeholder: "majority")
    ]

    func createDriver(config: DriverConnectionConfig) -> any PluginDatabaseDriver {
        MongoDBPluginDriver(config: config)
    }
}
