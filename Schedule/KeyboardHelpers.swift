//
//  KeyboardHelpers.swift
//  Schedule
//
//  Created by Codex on 2026/2/28.
//

import SwiftUI
import UIKit

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    func dismissKeyboardOnTap() -> some View {
        background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.endEditing()
                }
        )
    }
}
