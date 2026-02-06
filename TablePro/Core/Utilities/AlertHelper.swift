//
//  AlertHelper.swift
//  TablePro
//
//  Created by TablePro on 1/19/26.
//

import AppKit

/// Centralized helper for creating and displaying NSAlert dialogs
/// Provides consistent styling and behavior across the application
@MainActor
final class AlertHelper {
    // MARK: - Destructive Confirmations

    /// Shows a destructive confirmation dialog (warning style)
    /// Uses async sheet presentation when window is available, falls back to modal
    /// - Parameters:
    ///   - title: Alert title
    ///   - message: Detailed message
    ///   - confirmButton: Label for destructive action button (default: "OK")
    ///   - cancelButton: Label for cancel button (default: "Cancel")
    ///   - window: Parent window to attach sheet to (optional)
    /// - Returns: true if user confirmed, false if cancelled
    static func confirmDestructive(
        title: String,
        message: String,
        confirmButton: String = "OK",
        cancelButton: String = "Cancel",
        window: NSWindow? = nil
    ) async -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmButton)
        alert.addButton(withTitle: cancelButton)

        // Use sheet presentation when window is available (non-blocking, Swift 6 friendly)
        if let window = window {
            return await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response == .alertFirstButtonReturn)
                }
            }
        } else {
            // Fallback to modal when no window available
            let response = alert.runModal()
            return response == .alertFirstButtonReturn
        }
    }

    // MARK: - Critical Confirmations

    /// Shows a critical confirmation dialog (critical style)
    /// Uses async sheet presentation when window is available, falls back to modal
    /// Used for dangerous operations like DROP, TRUNCATE, DELETE without WHERE
    /// - Parameters:
    ///   - title: Alert title
    ///   - message: Detailed message
    ///   - confirmButton: Label for dangerous action button (default: "Execute")
    ///   - cancelButton: Label for cancel button (default: "Cancel")
    ///   - window: Parent window to attach sheet to (optional)
    /// - Returns: true if user confirmed, false if cancelled
    static func confirmCritical(
        title: String,
        message: String,
        confirmButton: String = "Execute",
        cancelButton: String = "Cancel",
        window: NSWindow? = nil
    ) async -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: confirmButton)
        alert.addButton(withTitle: cancelButton)

        // Use sheet presentation when window is available (non-blocking, Swift 6 friendly)
        if let window = window {
            return await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response == .alertFirstButtonReturn)
                }
            }
        } else {
            // Fallback to modal when no window available
            let response = alert.runModal()
            return response == .alertFirstButtonReturn
        }
    }

    // MARK: - Three-Way Confirmations

    /// Shows a three-option confirmation dialog
    /// Uses async sheet presentation when window is available, falls back to modal
    /// - Parameters:
    ///   - title: Alert title
    ///   - message: Detailed message
    ///   - first: Label for first button
    ///   - second: Label for second button
    ///   - third: Label for third button
    ///   - window: Parent window to attach sheet to (optional)
    /// - Returns: 0 for first button, 1 for second, 2 for third
    static func confirmThreeWay(
        title: String,
        message: String,
        first: String,
        second: String,
        third: String,
        window: NSWindow? = nil
    ) async -> Int {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: first)
        alert.addButton(withTitle: second)
        alert.addButton(withTitle: third)

        let response: NSApplication.ModalResponse

        // Use sheet presentation when window is available (non-blocking, Swift 6 friendly)
        if let window = window {
            response = await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { resp in
                    continuation.resume(returning: resp)
                }
            }
        } else {
            // Fallback to modal when no window available
            response = alert.runModal()
        }

        switch response {
        case .alertFirstButtonReturn:
            return 0
        case .alertSecondButtonReturn:
            return 1
        case .alertThirdButtonReturn:
            return 2
        default:
            return 2 // Default to third option (usually cancel)
        }
    }

    // MARK: - Error Sheets

    /// Shows an error message as a non-blocking sheet
    /// - Parameters:
    ///   - title: Error title
    ///   - message: Error details
    ///   - window: Parent window to attach sheet to (optional, falls back to modal)
    static func showErrorSheet(
        title: String,
        message: String,
        window: NSWindow?
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")

        if let window = window {
            alert.beginSheetModal(for: window) { _ in
                // Sheet dismissed, no action needed
            }
        } else {
            // Fallback to modal if no window available
            alert.runModal()
        }
    }

    // MARK: - Info Sheets

    /// Shows an informational message as a non-blocking sheet
    /// - Parameters:
    ///   - title: Info title
    ///   - message: Info details
    ///   - window: Parent window to attach sheet to (optional, falls back to modal)
    static func showInfoSheet(
        title: String,
        message: String,
        window: NSWindow?
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        if let window = window {
            alert.beginSheetModal(for: window) { _ in
                // Sheet dismissed, no action needed
            }
        } else {
            // Fallback to modal if no window available
            alert.runModal()
        }
    }
}
