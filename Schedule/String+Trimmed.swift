//
//  String+Trimmed.swift
//  Schedule
//
//  Created by Codex on 2026/2/28.
//

import Foundation

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
