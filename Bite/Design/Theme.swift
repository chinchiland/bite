import SwiftUI
import UIKit

/// Bite's design tokens. The rules they serve are written up in DESIGN.md.
///
/// Apple's grouped look: the system background, cards on it, soft insets inside cards for the
/// quieter facts. Text wears the system label colors, so contrast and dark mode come from iOS.
/// Color always means something: calories, the three macros, burned and steps, a status, a
/// rank, or the pastel tile that tells foods apart.
enum Theme {
    // MARK: Surfaces and text (iOS system colors)

    static let page = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    /// The soft box inside a card that groups secondary facts.
    static let inset = Color(uiColor: .tertiarySystemGroupedBackground)
    static let ink = Color(uiColor: .label)
    static let secondary = Color(uiColor: .secondaryLabel)
    static let tertiary = Color(uiColor: .tertiaryLabel)
    /// Quiet controls: soft buttons, neutral chips, step buttons.
    static let fill = Color(uiColor: .tertiarySystemFill)
    /// The empty part of a bar or of the gauge.
    static let track = Color(uiColor: .systemGray5)
    static let hairline = Color(uiColor: .separator)
    /// Product photos sit on a light tile in both modes so their white backgrounds melt away.
    static let photoTile = Color(lightHex: 0xF5F5F7, darkHex: 0xE8E8ED)

    // MARK: Data

    // The macro trio is the dataviz palette's first three slots, which pass the color-vision
    // checks as a set in both modes, so stacked segments stay tellable apart.
    static let protein = Color(lightHex: 0xEB6834, darkHex: 0xD95926)
    static let carbs = Color(lightHex: 0x2A78D6, darkHex: 0x3987E5)
    static let fat = Color(lightHex: 0x1BAF7A, darkHex: 0x199E70)
    /// Calories: sunny amber, warm without shouting. Never drawn next to the macros in one chart.
    static let energy = Color(lightHex: 0xF4A80C, darkHex: 0xF2B233)
    /// The light end of the gauge, which warms to amber as the day fills up.
    static let energyLight = Color(lightHex: 0xFFCB45, darkHex: 0xFFD666)
    static let energySoft = Color(lightHex: 0xFFF3D6, darkHex: 0x33290F)
    /// Burned calories wear the Move ring's pink, steps wear indigo. Food never uses either.
    static let burned = Color(uiColor: .systemPink)
    static let steps = Color(uiColor: .systemIndigo)
    static let over = Color(lightHex: 0xE5484D, darkHex: 0xFF6369)
    /// The scan laser: the one warm red on the home screen, so the eye finds the scan button.
    static let laser = Color(lightHex: 0xFF453A, darkHex: 0xFF6961)

    // MARK: Status chips (soft fill, strong text)

    static let goodText = Color(lightHex: 0x248A3D, darkHex: 0x7AD69E)
    static let goodFill = Color(lightHex: 0xE5F4EA, darkHex: 0x17301F)
    static let watchText = Color(lightHex: 0xA2530B, darkHex: 0xF0A65C)
    static let watchFill = Color(lightHex: 0xFCEEDD, darkHex: 0x382816)
    static let infoText = Color(lightHex: 0x0062CC, darkHex: 0x8DB5F5)
    static let infoFill = Color(lightHex: 0xE6EEFB, darkHex: 0x1B2A40)

    // MARK: Ranks

    static let gold = Color(lightHex: 0xB7892E, darkHex: 0xE2B95B)
    static let laurelGreen = Color(lightHex: 0x2E8B57, darkHex: 0x62C48D)

    // MARK: Food tints

    static func tint(_ tint: FoodTint) -> Color {
        switch tint {
        case .sand: Color(lightHex: 0xF3EEE7, darkHex: 0x2E2925)
        case .peach: Color(lightHex: 0xFDE8DB, darkHex: 0x3B2A21)
        case .butter: Color(lightHex: 0xFBF2CF, darkHex: 0x37311B)
        case .mint: Color(lightHex: 0xE0F3E7, darkHex: 0x1D3428)
        case .sky: Color(lightHex: 0xE1EDFA, darkHex: 0x1C2B3E)
        case .lilac: Color(lightHex: 0xEDE7FA, darkHex: 0x2B2541)
        case .blush: Color(lightHex: 0xFBE3E8, darkHex: 0x3B2128)
        }
    }

    // MARK: Layout

    /// Side margin of every screen.
    static let margin: CGFloat = 16
    /// Space between cards.
    static let gap: CGFloat = 12
    static let cardRadius: CGFloat = 22
    static let insetRadius: CGFloat = 16
}

extension Color {
    init(lightHex: UInt32, darkHex: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? darkHex : lightHex)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The type scale, Apple's: 32 screen titles, 28 and 26 sheet titles, 20 section and card
/// titles, 17 for names and body, 15 for details, 13 for small print, 12 only for chart axes
/// and tiny captions. Text is regular or medium; semibold is for titles and numbers.
extension Font {
    /// SF Pro for numbers, with tabular digits so they line up and roll in place. Big numbers
    /// are medium and smaller ones semibold, so every number reads at the same weight.
    static func number(_ size: CGFloat, _ weight: Font.Weight? = nil) -> Font {
        .system(size: size, weight: weight ?? (size >= 34 ? .medium : .semibold)).monospacedDigit()
    }

    /// SF Pro for names, labels and buttons.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

extension Meal {
    var symbol: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "cup.and.saucer"
        }
    }
}

/// The three macros, each with its color and icon, so every screen draws them the same way.
enum Macro: CaseIterable {
    case protein
    case carbs
    case fat

    var title: String {
        switch self {
        case .protein: String(localized: "Protein")
        case .carbs: String(localized: "Carbs")
        case .fat: String(localized: "Fat")
        }
    }

    var color: Color {
        switch self {
        case .protein: Theme.protein
        case .carbs: Theme.carbs
        case .fat: Theme.fat
        }
    }

    /// Muscle, energy, oil.
    var symbol: String {
        switch self {
        case .protein: "dumbbell.fill"
        case .carbs: "bolt.fill"
        case .fat: "drop.fill"
        }
    }

    func grams(in nutrients: Nutrients) -> Double {
        switch self {
        case .protein: nutrients.protein
        case .carbs: nutrients.carbs
        case .fat: nutrients.fat
        }
    }

    func target(in targets: MacroTargets) -> Double {
        switch self {
        case .protein: targets.protein
        case .carbs: targets.carbs
        case .fat: targets.fat
        }
    }
}
