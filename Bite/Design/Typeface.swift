import SwiftUI
import UIKit
import CoreText

/// DM Sans, Bite's one typeface: a variable font with a weight axis and an optical size axis.
/// Optical size follows the point size, so 12 pt labels open up and 66 pt numbers tighten,
/// the way the design pages draw it. If the font is missing, SF Pro stands in at the same
/// size and weight.
enum Typeface {
    private static let postScriptName = "DMSans-9ptRegular"
    private static let weightAxis = 0x7767_6874 // 'wght'
    private static let opticalSizeAxis = 0x6F70_737A // 'opsz'

    private static var cache: [Key: CTFont] = [:]
    private static let lock = NSLock()

    private struct Key: Hashable {
        let size: CGFloat
        let weight: CGFloat
    }

    /// Registers the bundled font for this process the first time it is asked for.
    static let isAvailable: Bool = {
        if let url = Bundle.main.url(forResource: "DMSans", withExtension: "ttf") {
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        return CTFontCopyPostScriptName(font) as String == postScriptName
    }()

    /// Dresses the system bars (navigation titles, bar buttons, segmented controls) in DM Sans.
    static func setUp() {
        guard isAvailable else { return }
        UINavigationBar.appearance().titleTextAttributes = [.font: uiFont(size: 17, weight: .semibold)]
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: uiFont(size: 32, weight: .semibold)]
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: uiFont(size: 17, weight: .regular)], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: uiFont(size: 14, weight: .medium)], for: .normal)
    }

    static func font(size: CGFloat, weight: Font.Weight) -> Font {
        guard isAvailable else { return .system(size: size, weight: weight) }
        return Font(ctFont(size: size, weight: value(of: weight)))
    }

    static func uiFont(size: CGFloat, weight: Font.Weight) -> UIFont {
        guard isAvailable else { return .systemFont(ofSize: size, weight: uiWeight(weight)) }
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: postScriptName,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variations(size: size, weight: value(of: weight)),
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func ctFont(size: CGFloat, weight: CGFloat) -> CTFont {
        let key = Key(size: size, weight: weight)
        lock.lock()
        defer { lock.unlock() }
        if let font = cache[key] { return font }
        let attributes: [CFString: Any] = [
            kCTFontNameAttribute: postScriptName,
            kCTFontVariationAttribute: variations(size: size, weight: weight),
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        cache[key] = font
        return font
    }

    private static func variations(size: CGFloat, weight: CGFloat) -> [NSNumber: NSNumber] {
        [
            NSNumber(value: weightAxis): NSNumber(value: Double(weight)),
            NSNumber(value: opticalSizeAxis): NSNumber(value: Double(min(max(size, 9), 40))),
        ]
    }

    private static func value(of weight: Font.Weight) -> CGFloat {
        switch weight {
        case .ultraLight: 200
        case .thin: 100
        case .light: 300
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        case .heavy: 800
        case .black: 900
        default: 400
        }
    }

    private static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}
