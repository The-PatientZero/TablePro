import Foundation

public struct SSHConfiguration: Codable, Hashable, Sendable {
    public var host: String
    public var port: Int
    public var username: String
    public var authMethod: SSHAuthMethod
    public var privateKeyPath: String?
    public var jumpHosts: [SSHJumpHost]

    public enum SSHAuthMethod: String, Codable, Sendable {
        case password
        case publicKey
        case agent
    }

    public init(
        host: String = "",
        port: Int = 22,
        username: String = "",
        authMethod: SSHAuthMethod = .password,
        privateKeyPath: String? = nil,
        jumpHosts: [SSHJumpHost] = []
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.privateKeyPath = privateKeyPath
        self.jumpHosts = jumpHosts
    }
}

public struct SSHJumpHost: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var host: String
    public var port: Int
    public var username: String

    public init(
        id: UUID = UUID(),
        host: String = "",
        port: Int = 22,
        username: String = ""
    ) {
        self.id = id
        self.host = host
        self.port = port
        self.username = username
    }
}
