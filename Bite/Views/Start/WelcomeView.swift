import SwiftUI

/// The one screen before the journal: the cover's colors, the ring drawing itself once, what
/// Bite is in one line and what it never does in another. Then the page.
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
                .frame(width: 212, height: 212)
                .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text("A calm food journal.")
                        .font(.ui(32, .semibold))
                        .tracking(-0.6)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Log what you eat in a tap. Bite counts the rest.")
                        .font(.ui(17))
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 40)
                .padding(.horizontal, 28)

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
