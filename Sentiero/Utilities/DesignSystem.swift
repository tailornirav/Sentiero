import SwiftUI

// MARK: - Sentiero Design System
//
// Single source of truth for UI constants and shared styling.
// Uses semantic dynamic system colors for full dark-mode compatibility.

enum Theme {
    enum Colors {
        /// Brand accent (outdoor-inspired, dynamic-friendly).
        static let primary = Color(UIColor.systemGreen)
        static let secondary = Color(UIColor.systemBlue)
        
        static let background = Color(UIColor.systemGroupedBackground)
        static let surface = Color(UIColor.secondarySystemGroupedBackground)
        
        static let textPrimary = Color(UIColor.label)
        static let textSecondary = Color(UIColor.secondaryLabel)
    }
    
    enum Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xlarge: CGFloat = 32
    }
    
    enum CornerRadius {
        static let standard: CGFloat = 12
        static let large: CGFloat = 16
    }
    
    enum Shadows {
        static let cardColor = Color.black.opacity(0.12)
        static let cardRadius: CGFloat = 10
        static let cardX: CGFloat = 0
        static let cardY: CGFloat = 5
    }
}

// MARK: - Reusable Modifiers

struct StandardCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.medium)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous))
            .shadow(color: Theme.Shadows.cardColor, radius: Theme.Shadows.cardRadius, x: Theme.Shadows.cardX, y: Theme.Shadows.cardY)
    }
}

struct PrimaryActionButton: ViewModifier {
    let backgroundColor: Color
    
    init(backgroundColor: Color = Theme.Colors.primary) {
        self.backgroundColor = backgroundColor
    }
    
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.medium)
            .background(backgroundColor)
            .clipShape(Capsule())
            .shadow(color: Theme.Shadows.cardColor, radius: Theme.Shadows.cardRadius, x: Theme.Shadows.cardX, y: Theme.Shadows.cardY)
    }
}

struct StandardTextField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.small + 4) // 12pt total for comfortable tap target
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.standard, style: .continuous))
    }
}

extension View {
    func standardCard() -> some View { modifier(StandardCard()) }
    func primaryActionButton(backgroundColor: Color = Theme.Colors.primary) -> some View {
        modifier(PrimaryActionButton(backgroundColor: backgroundColor))
    }
    func standardTextField() -> some View { modifier(StandardTextField()) }
}

