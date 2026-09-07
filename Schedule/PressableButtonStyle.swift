//
//  PressableButtonStyle.swift
//  Schedule
//
//  Created by Codex on 2026/2/28.
//

import SwiftUI

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}
