//
//  Color+Hex.swift
//  TablePro
//

import os
import SwiftUI

extension Color {
    private static let logger = Logger(subsystem: "com.TablePro", category: "Color+Hex")

    init(hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))

        guard cleaned.count == 6, let rgbValue = UInt64(cleaned, radix: 16) else {
            Self.logger.warning("Invalid hex color: \(hex)")
            self = .gray
            return
        }

        let red = Double((rgbValue >> 16) & 0xFF) / 255.0
        let green = Double((rgbValue >> 8) & 0xFF) / 255.0
        let blue = Double(rgbValue & 0xFF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }
}
