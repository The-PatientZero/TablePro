import Foundation

public struct SSLConfiguration: Codable, Hashable, Sendable {
    public var mode: SSLMode
    public var caCertificatePath: String?
    public var clientCertificatePath: String?
    public var clientKeyPath: String?

    public enum SSLMode: String, Codable, Sendable {
        case disable
        case require
        case verifyCa
        case verifyFull
    }

    public init(
        mode: SSLMode = .disable,
        caCertificatePath: String? = nil,
        clientCertificatePath: String? = nil,
        clientKeyPath: String? = nil
    ) {
        self.mode = mode
        self.caCertificatePath = caCertificatePath
        self.clientCertificatePath = clientCertificatePath
        self.clientKeyPath = clientKeyPath
    }
}
