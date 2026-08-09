import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.975, green: 0.973, blue: 0.965)
    static let surface = Color.white
    static let surfaceMuted = Color(red: 0.945, green: 0.942, blue: 0.93)
    static let hover = Color(red: 0.92, green: 0.918, blue: 0.905)
    static let border = Color.black.opacity(0.09)
    static let borderStrong = Color.black.opacity(0.16)
    static let textPrimary = Color(red: 0.105, green: 0.105, blue: 0.095)
    static let textSecondary = Color(red: 0.42, green: 0.415, blue: 0.39)
    static let green = Color(red: 0.12, green: 0.58, blue: 0.38)
    static let amber = Color(red: 0.78, green: 0.48, blue: 0.08)
    static let red = Color(red: 0.78, green: 0.22, blue: 0.19)
    static let blue = Color(red: 0.20, green: 0.39, blue: 0.74)

    static let sectionRadius: CGFloat = 8
}

extension View {
    func consolePanel() -> some View {
        self
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.sectionRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.sectionRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
    }
}
