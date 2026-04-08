//
//  PasswordPromptHelper.swift
//  TablePro
//
//  Prompts the user for a database password via a native modal alert.
//

import AppKit

enum PasswordPromptHelper {
    @MainActor
    static func prompt(
        connectionName: String,
        isAPIToken: Bool = false,
        window: NSWindow? = nil
    ) async -> String? {
        let alert = NSAlert()
        alert.messageText = isAPIToken
            ? String(localized: "API Token Required")
            : String(localized: "Password Required")
        alert.informativeText = String(
            format: String(localized: "Enter the %@ for \"%@\""),
            isAPIToken ? String(localized: "API token") : String(localized: "password"),
            connectionName
        )
        alert.addButton(withTitle: String(localized: "Connect"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = isAPIToken
            ? String(localized: "API Token") : String(localized: "Password")
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        if let window = window ?? NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            let response = await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response)
                }
            }
            guard response == .alertFirstButtonReturn else { return nil }
            return input.stringValue
        }

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return input.stringValue
    }
}
