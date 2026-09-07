import SwiftUI
import UIKit

/// Shared visual tokens for every first-party screen.
enum AppTheme {
    static let accent = Color(uiColor: accentUI)
    static let accentUI = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.43, green: 0.74, blue: 0.58, alpha: 1)
            : UIColor(red: 0.24, green: 0.57, blue: 0.42, alpha: 1)
    }
    static let highlight = Color(red: 0.78, green: 0.92, blue: 0.82)
    static let deepGreen = Color(red: 0.16, green: 0.54, blue: 0.36)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let subtleSurface = Color(uiColor: .tertiarySystemGroupedBackground)
    static let border = Color(uiColor: .separator).opacity(0.18)
    static let controlFill = Color(uiColor: .tertiarySystemFill)
    static let selectedFillUI = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.29, blue: 0.23, alpha: 1)
            : UIColor(red: 0.84, green: 0.94, blue: 0.88, alpha: 1)
    }

    enum Spacing {
        static let page: CGFloat = 24
        static let card: CGFloat = 16
        static let section: CGFloat = 16
        static let row: CGFloat = 10
        static let small: CGFloat = 8
    }
    enum Radius {
        static let card: CGFloat = 18
        static let hero: CGFloat = 26
        static let compact: CGFloat = 10
    }
    enum Typography {
        static let pageTitle = Font.system(.title, design: .rounded).weight(.semibold)
        static let sectionTitle = Font.title3.weight(.semibold)
        static let cardTitle = Font.headline
        static let rowTitle = Font.body.weight(.medium)
        static let control = Font.subheadline.weight(.medium)
        static let caption = Font.caption
    }
}
