//
//  BooleanCellFormatter.swift
//  TablePro
//
//  Formatter for YES/NO boolean values with auto-completion.
//

import AppKit

/// Formatter that auto-converts common boolean inputs to YES/NO
final class BooleanCellFormatter: Formatter {
    override func string(for obj: Any?) -> String? {
        guard let value = obj as? String else { return nil }
        return normalizeBooleanString(value)
    }

    override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        obj?.pointee = normalizeBooleanString(string) as AnyObject
        return true
    }

    override func isPartialStringValid(
        _ partialString: String,
        newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        // Allow any input during editing
        true
    }

    private func normalizeBooleanString(_ value: String) -> String {
        let uppercased = value.uppercased().trimmingCharacters(in: .whitespaces)

        // Check for YES values
        if ["YES", "Y", "TRUE", "T", "1", "ON"].contains(uppercased) {
            return "YES"
        }

        // Check for NO values
        if ["NO", "N", "FALSE", "F", "0", "OFF", ""].contains(uppercased) {
            return "NO"
        }

        // If it starts with Y, assume YES
        if uppercased.hasPrefix("Y") {
            return "YES"
        }

        // Default to NO
        return "NO"
    }
}
