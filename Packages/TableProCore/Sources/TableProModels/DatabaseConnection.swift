import Foundation

public struct DatabaseConnection: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var type: DatabaseType
    public var host: String
    public var port: Int
    public var username: String
    public var database: String
    public var colorTag: String?
    public var isReadOnly: Bool
    public var queryTimeoutSeconds: Int?
    public var additionalFields: [String: String]

    public var sshEnabled: Bool
    public var sshConfiguration: SSHConfiguration?

    public var sslEnabled: Bool
    public var sslConfiguration: SSLConfiguration?

    public var groupId: UUID?
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        name: String = "",
        type: DatabaseType = .mysql,
        host: String = "127.0.0.1",
        port: Int = 3306,
        username: String = "",
        database: String = "",
        colorTag: String? = nil,
        isReadOnly: Bool = false,
        queryTimeoutSeconds: Int? = nil,
        additionalFields: [String: String] = [:],
        sshEnabled: Bool = false,
        sshConfiguration: SSHConfiguration? = nil,
        sslEnabled: Bool = false,
        sslConfiguration: SSLConfiguration? = nil,
        groupId: UUID? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.host = host
        self.port = port
        self.username = username
        self.database = database
        self.colorTag = colorTag
        self.isReadOnly = isReadOnly
        self.queryTimeoutSeconds = queryTimeoutSeconds
        self.additionalFields = additionalFields
        self.sshEnabled = sshEnabled
        self.sshConfiguration = sshConfiguration
        self.sslEnabled = sslEnabled
        self.sslConfiguration = sslConfiguration
        self.groupId = groupId
        self.sortOrder = sortOrder
    }
}
