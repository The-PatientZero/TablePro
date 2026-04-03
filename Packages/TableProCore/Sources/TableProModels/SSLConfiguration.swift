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

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            switch raw {
            case "disable", "Disabled": self = .disable
            case "require", "Required", "Preferred": self = .require
            case "verifyCa", "Verify CA": self = .verifyCa
            case "verifyFull", "Verify Identity": self = .verifyFull
            default: self = .disable
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mode, caCertificatePath, clientCertificatePath, clientKeyPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? container.decode(SSLMode.self, forKey: .mode)) ?? .disable
        caCertificatePath = try? container.decode(String.self, forKey: .caCertificatePath)
        clientCertificatePath = try? container.decode(String.self, forKey: .clientCertificatePath)
        clientKeyPath = try? container.decode(String.self, forKey: .clientKeyPath)
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
