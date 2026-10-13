import SwiftUI

/// The one screen before the journal: the cover's colors, the ring drawing itself once, what
/// Bite is in one line, the three ways in that the first minute then uses, and what it never
/// does. Then the page.
struct WelcomeView: View {
    let onStart: () -> Void

    @State private var taps = 0

    /// A first light on the ring: some protein, some carbs, some fat.
    private static let sample: [DottedRing.Part] = [
        DottedRing.Part(share: 0.10, color: Theme.protein, macro: .protein),
        DottedRing.Part(share: 0.20, color: Theme.carbs, macro: .carbs),
        DottedRing.Part(share: 0.13, color: Theme.fat, macro: .fat),
    ]

    var body: some View {
        ZStack {
            Theme.coverGradient.ignoresSafeArea()
            LinearGradient(colors: [Theme.page.opacity(0), Theme.page], startPoint: UnitPoint(x: 0.5, y: 0.35), endPoint: UnitPoint(x: 0.5, y: 0.75))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)
                ZStack {
                    DottedRing(parts: Self.sample)
                    Text(verbatim: "Bite")
                        .font(.ui(34, .semibold))
                        .tracking(-0.8)
                        .foregroundStyle(Theme.ink)
                }
                .frame(width: 168, height: 168)
                .accessibilityHidden(true)

                Text("A calm food journal.")
                    .font(.ui(30, .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 32)
                    .padding(.horizontal, 28)

                VStack(alignment: .leading, spacing: 18) {
                    WayIn(systemImage: "camera", title: "Snap your plate", line: "Calories and macros in a few seconds")
                    WayIn(systemImage: "barcode.viewfinder", title: "Scan a barcode", line: "The label's own numbers")
                    WayIn(systemImage: "bookmark", title: "Save what you eat often", line: "Next time, one tap adds it")
                }
                .frame(maxWidth: 340, alignment: .leading)
                .padding(.top, 30)
                .padding(.horizontal, 36)

                Spacer(minLength: 32)

                Button("Start") {
                    taps += 1
                    onStart()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Theme.margin)

                Text("Free. No account. Your log stays on this phone.")
                    .font(.ui(13))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .padding(.horizontal, Theme.margin)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: 520)
        }
        .sensoryFeedback(Feel.click, trigger: taps)
    }
}

/// One of the three ways in, as the home draws them: a glyph on its tile, a name, a line.
private struct WayIn: View {
    let systemImage: String
    let title: LocalizedStringKey
    let line: LocalizedStringKey

    var body: some View {
        HStack(spacing: 14) {
            SymbolTile(systemImage: systemImage, color: Theme.ink, glyph: Theme.ink, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.ui(16, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(line)
                    .font(.ui(14))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
