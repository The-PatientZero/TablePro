//
//  ProFeature.swift
//  TablePro
//
//  Pro feature definitions and access control types
//

import Foundation

/// Features that require a Pro (active) license
internal enum ProFeature: String, CaseIterable {
    case iCloudSync
    case safeMode
    case xlsxExport

    var displayName: String {
        switch self {
        case .iCloudSync:
            return String(localized: "iCloud Sync")
        case .safeMode:
            return String(localized: "Safe Mode")
        case .xlsxExport:
            return String(localized: "XLSX Export")
        }
    }

    var systemImage: String {
        switch self {
        case .iCloudSync:
            return "icloud"
        case .safeMode:
            return "lock.shield"
        case .xlsxExport:
            return "tablecells"
        }
    }

    var featureDescription: String {
        switch self {
        case .iCloudSync:
            return String(localized: "Sync connections, settings, and history across your Macs.")
        case .safeMode:
            return String(localized: "Require confirmation or Touch ID before executing queries.")
        case .xlsxExport:
            return String(localized: "Export query results and tables to Excel format.")
        }
    }
}

/// Result of checking Pro feature availability
internal enum ProFeatureAccess {
    case available
    case unlicensed
    case expired
    case validationFailed
}
