import SwiftUI

/// What stands between you and an estimate, said plainly with the one thing to do: the age
/// question Bite's own estimates ask once, a Claude key to fix, or what went wrong. For a menu
/// and a dish typed in search; a photo of a plate has its own words in EstimateView.
struct EstimateGate: View {
    let trouble: EstimateTrouble
    /// Ask again: after an answer, a new key, or a failure.
    let retry: () -> Void
    let close: () -> Void

    @State private var showSettings = false

    var body: some View {
        content
            .sheet(isPresented: $showSettings, onDismiss: retry) {
                SettingsView()
            }
    }

    @ViewBuilder private var content: some View {
        switch trouble {
        case .needsAge:
            message(
                "Estimates are for 18 and over",
                detail: String(localized: "They run on Google's Gemini, whose terms ask for 18 and over. Barcodes, product search and your saved foods work at any age."),
                action: ("I'm 18 or over", {
                    AgeAnswer.current = .adult
                    retry()
                }),
                secondary: ("I'm under 18", {
                    AgeAnswer.current = .under
                    retry()
                })
            )
        case .underAge:
            message(
                "Estimates wait until 18",
                detail: String(localized: "Barcodes, product search and your saved foods work as usual."),
                action: ("Back", close)
            )
        case .needsKey:
            message(
                "Photo estimates use Claude",
                detail: String(localized: "Add your Claude API key in Settings once, and every photo gets calories and macros in a few seconds."),
                action: ("Open Settings", { showSettings = true })
            )
        case .keyRejected:
            message(
                "Claude didn't take your key",
                detail: String(localized: "Paste it again in Settings, or make a new one at platform.claude.com."),
                action: ("Open Settings", { showSettings = true })
            )
        case .failed(let text):
            message("That didn't work", detail: text, action: ("Try again", retry))
        }
    }

    private func message(
        _ title: LocalizedStringKey,
        detail: String,
        action: (LocalizedStringKey, () -> Void),
        secondary: (LocalizedStringKey, () -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.ui(22, .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action.0, action: action.1)
                .buttonStyle(PrimaryButtonStyle(height: 50))
                .padding(.top, 4)
            if let secondary {
                Button(secondary.0, action: secondary.1)
                    .font(.ui(16))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
        }
    }
}
