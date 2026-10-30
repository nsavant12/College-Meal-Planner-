import SwiftUI
import UIKit

/// Shared colors and components for the app's warm, botanical day/night theme.
enum MealTheme {
    static let background = adaptive(0xF6F5ED, 0x151E19)
    static let surface = adaptive(0xFFFEF9, 0x233128)
    static let ink = adaptive(0x23392B, 0xEDF2E5)
    static let secondary = adaptive(0x62705F, 0xB4C1AC)
    static let accent = adaptive(0x355A41, 0xC0E29C)
    static let onAccent = adaptive(0xFFFEF9, 0x203421)
    static let soft = adaptive(0xE8EDDd, 0x304332)
    static let gold = adaptive(0xF3D492, 0x594628)
    static let border = adaptive(0xDEE4D6, 0x40513E)
    static let forest = Color(red: 0.16, green: 0.27, blue: 0.20)
    static let cream = Color(red: 0.97, green: 0.96, blue: 0.88)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

extension View {
    func mealSurface() -> some View {
        scrollContentBackground(.hidden)
            .background(MealTheme.background)
            .foregroundStyle(MealTheme.ink)
            .tint(MealTheme.accent)
    }

    func mealCard(padding: CGFloat = 18, fill: Color = MealTheme.surface) -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading).padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(MealTheme.border.opacity(0.6), lineWidth: 1))
    }
}

struct MealActionStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .foregroundStyle(prominent ? MealTheme.onAccent : MealTheme.ink)
            .background(prominent ? MealTheme.accent : MealTheme.soft,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(!isEnabled ? 0.45 : (configuration.isPressed ? 0.75 : 1))
    }
}

struct MealBadge: View {
    let title: String
    var gold = false
    var body: some View {
        Text(title).font(.caption.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(MealTheme.ink)
            .background(gold ? MealTheme.gold : MealTheme.soft, in: Capsule())
    }
}

struct MealEmptyState: View {
    let title: String
    let message: String
    let symbol: String
    let identifier: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 32, weight: .light))
                .foregroundStyle(MealTheme.accent)
                .frame(width: 76, height: 76).background(MealTheme.soft, in: Circle())
                .accessibilityHidden(true)
            Text(title).font(.system(.title3, design: .serif, weight: .semibold))
                .accessibilityIdentifier(identifier)
            Text(message).font(.subheadline).foregroundStyle(MealTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 16)
    }
}
