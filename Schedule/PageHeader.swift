//
//  PageHeader.swift
//  Schedule
//
//  Created by Codex on 2026/2/28.
//

import SwiftUI

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTheme.Typography.pageTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.accent)
                }
            }
            Spacer()
            trailing()
        }
        .frame(minHeight: 44)
        .padding(.top, 8)
    }
}
