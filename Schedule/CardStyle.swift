import SwiftUI

private struct AppCardSurface: ViewModifier {
    let fill: Color
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.035), radius: 5, x: 0, y: 2)
    }
}

extension View {
    func cardBackground(fill: Color = AppTheme.surface, cornerRadius: CGFloat = AppTheme.Radius.card) -> some View {
        modifier(AppCardSurface(fill: fill, radius: cornerRadius))
    }

    func appFormSurface() -> some View {
        scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationBarTitleDisplayMode(.inline)
    }
}
