//
//  RegistryModels.swift
//  TablePro
//

import Foundation

enum PluginArchitecture: String, Codable, Sendable {
    case arm64
    case x86_64

    static var current: PluginArchitecture {
        #if arch(arm64)
        .arm64
        #else
        .x86_64
        #endif
    }
}

struct RegistryBinary: Codable, Sendable {
    let architecture: PluginArchitecture
    let downloadURL: String
    let sha256: String
}

struct RegistryManifest: Codable, Sendable {
    let schemaVersion: Int
    let plugins: [RegistryPlugin]
}

struct RegistryPlugin: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let version: String
    let summary: String
    let author: RegistryAuthor
    let homepage: String?
    let category: RegistryCategory
    let databaseTypeIds: [String]?
    let downloadURL: String?
    let sha256: String?
    let binaries: [RegistryBinary]?
    let minAppVersion: String?
    let minPluginKitVersion: Int?
    let iconName: String?
    let isVerified: Bool
}

extension RegistryPlugin {
    func resolvedBinary(for arch: PluginArchitecture = .current) throws -> (url: String, sha256: String) {
        if let binaries, let match = binaries.first(where: { $0.architecture == arch }) {
            return (match.downloadURL, match.sha256)
        }
        if let url = downloadURL, let hash = sha256 {
            return (url, hash)
        }
        throw PluginError.noCompatibleBinary
    }
}

struct RegistryAuthor: Codable, Sendable {
    let name: String
    let url: String?
}

enum RegistryCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case databaseDriver = "database-driver"
    case exportFormat = "export-format"
    case importFormat = "import-format"
    case theme = "theme"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .databaseDriver: String(localized: "Database Drivers")
        case .exportFormat: String(localized: "Export Formats")
        case .importFormat: String(localized: "Import Formats")
        case .theme: String(localized: "Themes")
        case .other: String(localized: "Other")
        }
    }
}
