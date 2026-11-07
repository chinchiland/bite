import SwiftUI
import UIKit

/// Bite's design tokens. The rules they serve are written up in DESIGN.md.
///
/// Two looks share one set of names. Glass, the default, is the dark side of every token: your
/// food's own color as the room, groups of panes floating in it, white numbers, and one solid
/// white button a screen. Paper is the light side: a warm page, white sheets, ink numbers. Both
/// are DM Sans, and in both color always means something: the three macros, burned and steps, a
/// verdict, a rank, or the tile that tells foods apart.
enum Theme {
    // MARK: Surfaces and text

    /// The warm paper every screen sits on; in Glass the near-black ground under the room.
    static let page = Color(lightHex: 0xFAFAF8, darkHex: 0x0A0B0C)
    /// White sheets and cards on the page; in Glass a pane the room shows through. The room is
    /// already blurred, so a pane needs no blur of its own and costs nothing to scroll.
    static let card = Color(lightHex: 0xFFFFFF, darkHex: 0x121315, darkOpacity: 0.62)
    /// A card that must hide what is behind it: tips, sheets that open over a page.
    static let solidCard = Color(lightHex: 0xFFFFFF, darkHex: 0x17181A)
    /// The soft box inside a card that groups secondary facts; in Glass a well sunk into it.
    static let inset = Color(lightHex: 0xF4F3EF, darkHex: 0x000000, darkOpacity: 0.3)
    /// The paler box inside a sheet: the paper showing through, or a well in Glass.
    static let well = Color(lightHex: 0xFAFAF8, darkHex: 0x000000, darkOpacity: 0.3)
    static let ink = Color(lightHex: 0x141414, darkHex: 0xFFFFFF)
    static let secondary = Color(lightHex: 0x75736E, darkHex: 0xFFFFFF, darkOpacity: 0.74)
    static let tertiary = Color(lightHex: 0xA9A69F, darkHex: 0xFFFFFF, darkOpacity: 0.54)
    /// Quiet controls: chips, soft buttons, step buttons.
    static let fill = Color(lightHex: 0xF0EEE9, darkHex: 0xFFFFFF, darkOpacity: 0.11)
    /// What you chose: ink on paper. In Glass a lit pane, because only the main action is solid.
    static let selected = Color(lightHex: 0x141414, darkHex: 0xFFFFFF, darkOpacity: 0.17)
    static let selectedInk = Color(lightHex: 0xFAFAF8, darkHex: 0xFFFFFF)
    /// The fine light round a lit pane. Paper has none.
    static let rim = Color(lightHex: 0x141414, darkHex: 0xFFFFFF, lightOpacity: 0, darkOpacity: 0.16)
    /// The empty part of a bar.
    static let track = Color(lightHex: 0xECE9E1, darkHex: 0xFFFFFF, darkOpacity: 0.1)
    /// The dots of the ring that are still to eat.
    static let ringRest = Color(lightHex: 0xE6E3DA, darkHex: 0xFFFFFF, darkOpacity: 0.15)
    static let hairline = Color(lightHex: 0xECEAE5, darkHex: 0xFFFFFF, darkOpacity: 0.09)
    /// The hairline that keeps a white product tile from melting into a white sheet.
    static let edge = Color(lightHex: 0xEEECE7, darkHex: 0xFFFFFF, darkOpacity: 0.1)
    /// Product photos sit on white in both modes so their white backgrounds melt away.
    static let photoTile = Color(lightHex: 0xFFFFFF, darkHex: 0xEDEBE6)

    // MARK: Data

    // The macro trio is calm and passes the color-vision checks as a set on the paper and on
    // the dark page, so ring segments and bars stay tellable apart.
    static let protein = Color(lightHex: 0xD2693C, darkHex: 0xD2693C)
    static let carbs = Color(lightHex: 0x4C7FC0, darkHex: 0x4C7FC0)
    static let fat = Color(lightHex: 0x3E9A76, darkHex: 0x3E9A76)
    /// The streak flame and the calories flame.
    static let energy = Color(lightHex: 0xF2A93B, darkHex: 0xFFC24D)
    /// The calories flame on its tile, a step deeper so it reads on the amber wash.
    static let energyDeep = Color(lightHex: 0xC47A12, darkHex: 0xFFC24D)
    /// Burned calories wear the Move ring's pink, steps wear indigo. Food never uses either.
    static let burned = Color(lightHex: 0xE8335C, darkHex: 0xFF5C7F)
    static let steps = Color(lightHex: 0x5B4FD9, darkHex: 0x8A80F0)
    /// How sure a dish's calories are, by tier: green, blue, orange, then gray for too few.
    static let accurate = Color(lightHex: 0x2F7FD8, darkHex: 0x5EA2F0)
    static let rough = Color(lightHex: 0xE0872B, darkHex: 0xF2A35A)
    /// A calorie estimate typed in by hand, as the badge on its author.
    static let entered = Color(lightHex: 0x5E5C57, darkHex: 0x8E8B85)
    /// Water: the glasses chip. The drop means water only; fat wears the avocado.
    static let water = Color(lightHex: 0x2E9BD6, darkHex: 0x5AC8FA)
    /// Over the goal: a day's dot, a bar, the ring's last dots.
    static let over = Color(lightHex: 0xD9482B, darkHex: 0xF06A50)
    /// On target and light days, as the dot beside a day.
    static let onTarget = Color(lightHex: 0x2E9E62, darkHex: 0x4CC283)
    static let light = Color(lightHex: 0xC8C5BE, darkHex: 0xFFFFFF, darkOpacity: 0.36)
    /// The scan laser in the camera.
    static let laser = Color(lightHex: 0xFF453A, darkHex: 0xFF6961)

    // MARK: Status chips (soft fill, strong text)

    static let goodText = Color(lightHex: 0x2F6B34, darkHex: 0x9CD49A)
    static let goodFill = Color(lightHex: 0xE8F3DF, darkHex: 0x7CC47F, darkOpacity: 0.16)
    static let goodIcon = Color(lightHex: 0x3E8A45, darkHex: 0x7CC47F)
    static let watchText = Color(lightHex: 0x9A4A12, darkHex: 0xF0A66C)
    static let watchFill = Color(lightHex: 0xFBEBDD, darkHex: 0xF0A66C, darkOpacity: 0.16)
    static let infoText = Color(lightHex: 0x2F5E9E, darkHex: 0x9DBBE8)
    static let infoFill = Color(lightHex: 0xE6EEF8, darkHex: 0x9DBBE8, darkOpacity: 0.16)
    /// A brand that links to its page.
    static let link = Color(lightHex: 0x3E7F45, darkHex: 0x8FCB8F)

    // MARK: Ranks

    static let gold = Color(lightHex: 0xB7892E, darkHex: 0xE2B95B)
    static let laurelGreen = Color(lightHex: 0x2E8B57, darkHex: 0x62C48D)

    // MARK: Food tints

    static func tint(_ tint: FoodTint) -> Color {
        switch tint {
        case .sand: Color(lightHex: 0xF3EEE7, darkHex: 0xD8C4A8, darkOpacity: 0.17)
        case .peach: Color(lightHex: 0xFDE8DB, darkHex: 0xFFB38A, darkOpacity: 0.19)
        case .butter: Color(lightHex: 0xFBF2CF, darkHex: 0xF5D878, darkOpacity: 0.18)
        case .mint: Color(lightHex: 0xE0F3E7, darkHex: 0x7FDDAA, darkOpacity: 0.17)
        case .sky: Color(lightHex: 0xE1EDFA, darkHex: 0x8CC0FF, darkOpacity: 0.18)
        case .lilac: Color(lightHex: 0xEDE7FA, darkHex: 0xBBA3FF, darkOpacity: 0.19)
        case .blush: Color(lightHex: 0xFBE3E8, darkHex: 0xFF9FB4, darkOpacity: 0.18)
        }
    }

    /// The light a food with no photo of its own gives the room in Glass.
    static func glow(_ tint: FoodTint) -> Color {
        switch tint {
        case .sand: Color(hex: 0xB08E66)
        case .peach: Color(hex: 0xD9794A)
        case .butter: Color(hex: 0xC9A63A)
        case .mint: Color(hex: 0x3FA877)
        case .sky: Color(hex: 0x4A8AD6)
        case .lilac: Color(hex: 0x8A6DD6)
        case .blush: Color(hex: 0xD6607C)
        }
    }

    /// A food's hero: its tint as a soft light in the middle, deeper at the edges.
    static func heroGradient(_ tint: FoodTint) -> RadialGradient {
        let (center, edge): (UInt32, UInt32) = switch tint {
        case .sand: (0xF6F1EA, 0xE6DCCE)
        case .peach: (0xFDEDE3, 0xF6D3BD)
        case .butter: (0xFBF4D9, 0xF0E1A8)
        case .mint: (0xE6F4EA, 0xC9E6D2)
        case .sky: (0xE3EEFA, 0xBCD3EE)
        case .lilac: (0xEFEAFA, 0xD6CCF2)
        case .blush: (0xFBE8EC, 0xF2C9D2)
        }
        return RadialGradient(
            colors: [Color(lightHex: center, darkHex: 0x2A2925), Color(lightHex: edge, darkHex: 0x1C1B19)],
            center: UnitPoint(x: 0.5, y: 0.4),
            startRadius: 0,
            endRadius: 420
        )
    }

    /// The cover of a day with no photo yet: fresh green into butter, like a kitchen in the
    /// morning.
    static let coverGradient = LinearGradient(
        colors: [Color(lightHex: 0xDDEBCD, darkHex: 0x1F2A1E), Color(lightHex: 0xF4EFD6, darkHex: 0x2A2719)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Layout

    /// Side margin of every screen.
    static let margin: CGFloat = 20
    /// Space between cards.
    static let gap: CGFloat = 12
    static let cardRadius: CGFloat = 22
    static let insetRadius: CGFloat = 16
    /// The big continuous corners of a group floating in the room.
    static let groupRadius: CGFloat = 30
    /// How far a group reaches past the page margin, so its words stay where they were and the
    /// group sits 8 pt from the edge of the screen.
    static let groupReach: CGFloat = 12
    /// Space between two groups.
    static let groupGap: CGFloat = 8
    /// The rounded top of a sheet that rises over a cover.
    static let sheetRadius: CGFloat = 28
}

extension Color {
    init(lightHex: UInt32, darkHex: UInt32, lightOpacity: CGFloat = 1, darkOpacity: CGFloat = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: darkHex).withAlphaComponent(darkOpacity)
                : UIColor(hex: lightHex).withAlphaComponent(lightOpacity)
        })
    }

    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
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

/// The type scale, all DM Sans: 66 for the day's number, 30 screen titles, 27 a food's name,
/// 20 section titles, 16 and 17 names and body, 14 and 15 details, 13 small print, 12 only for
/// chart axes. Text is regular or medium; semibold is for titles and numbers.
extension Font {
    /// Numbers. Big ones are medium and smaller ones semibold, so every number reads at the
    /// same weight.
    static func number(_ size: CGFloat, _ weight: Font.Weight? = nil) -> Font {
        Typeface.font(size: size, weight: weight ?? (size >= 34 ? .medium : .semibold))
    }

    /// Names, labels and buttons.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Typeface.font(size: size, weight: weight)
    }
}

extension View {
    /// Big numbers sit tighter, the way display type does: 4% of the size at 66 pt, 2% at 22.
    func numberTracking(_ size: CGFloat) -> some View {
        tracking(-size * (size >= 50 ? 0.04 : size >= 28 ? 0.03 : 0.02))
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

/// The three macros, each with its color and glyph, so every screen draws them the same way.
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

    /// The glyph on the macro's tile and on the ring (a drumstick, a wheat ear, half an
    /// avocado): a step deeper than the macro's color on paper, a step lighter at night.
    var glyphColor: Color {
        switch self {
        case .protein: Color(lightHex: 0xB5532B, darkHex: 0xE58D63)
        case .carbs: Color(lightHex: 0x3A69A8, darkHex: 0x86AADD)
        case .fat: Color(lightHex: 0x2B7F5F, darkHex: 0x64BF98)
        }
    }

    /// The tile behind the glyph.
    var tileFill: Color { color.opacity(0.24) }

    /// Calories in a gram.
    var kcalPerGram: Double { self == .fat ? 9 : 4 }

    func grams(in nutrients: Nutrients) -> Double {
        switch self {
        case .protein: nutrients.protein
        case .carbs: nutrients.carbs
        case .fat: nutrients.fat
        }
    }

    /// The macro's share of the calories, 0 to 1.
    func share(in nutrients: Nutrients) -> Double {
        let split = nutrients.energySplit
        return switch self {
        case .protein: split.protein
        case .carbs: split.carbs
        case .fat: split.fat
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
