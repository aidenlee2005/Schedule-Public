//
//  Color+Hex.swift
//  Schedule
//
//  Created by Codex on 2026/2/28.
//

import SwiftUI
import UIKit

extension Color {
    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let hexString = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard hexString.count == 6,
              let value = Int(hexString, radix: 16)
        else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0

        self = Color(red: red, green: green, blue: blue)
    }

    func toHex() -> String? {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        let r = Int(red * 255.0)
        let g = Int(green * 255.0)
        let b = Int(blue * 255.0)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
