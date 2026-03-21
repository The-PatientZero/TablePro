//
//  WindowOpener.swift
//  TablePro
//
//  Bridges SwiftUI's openWindow environment action to imperative code.
//  Stored by ContentView on appear so MainContentCommandActions can open native tabs.
//

import os
import SwiftUI

@MainActor
internal final class WindowOpener {
    private static let logger = Logger(subsystem: "com.TablePro", category: "WindowOpener")

    internal static let shared = WindowOpener()

    /// True once any SwiftUI scene has appeared and stored `openWindow`.
    /// Used as a readiness check by AppDelegate cold-start queue.
    internal var isReady: Bool = false

    /// The connectionId for the next window about to be opened.
    /// Set by `openNativeTab` before calling `openWindow`, consumed by
    /// `AppDelegate.windowDidBecomeKey` to set the correct `tabbingIdentifier`.
    internal var pendingConnectionId: UUID?

    /// Opens a new native window tab by posting a notification.
    /// The `OpenWindowHandler` in TableProApp receives it and calls `openWindow`.
    internal func openNativeTab(_ payload: EditorTabPayload) {
        pendingConnectionId = payload.connectionId
        NotificationCenter.default.post(name: .openMainWindow, object: payload)
    }

    /// Returns and clears the pending connectionId (consume-once pattern).
    internal func consumePendingConnectionId() -> UUID? {
        defer { pendingConnectionId = nil }
        return pendingConnectionId
    }
}

/// Pure logic for resolving the tabbingIdentifier for a new main window.
/// Extracted for testability — no AppKit dependencies.
internal enum TabbingIdentifierResolver {
    /// Resolve the tabbingIdentifier for a new main window.
    /// - Parameters:
    ///   - pendingConnectionId: The connectionId from WindowOpener (if a tab was just opened)
    ///   - existingIdentifier: The tabbingIdentifier from an existing visible main window (if any)
    /// - Returns: The tabbingIdentifier to assign to the new window
    internal static func resolve(pendingConnectionId: UUID?, existingIdentifier: String?) -> String {
        if let connectionId = pendingConnectionId {
            return "com.TablePro.main.\(connectionId.uuidString)"
        }
        if let existing = existingIdentifier {
            return existing
        }
        return "com.TablePro.main"
    }
}
