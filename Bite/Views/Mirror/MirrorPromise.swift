import SwiftUI

/// The one sheet before the camera ever opens, the first time: what your mirror is, where the
/// photos stay, Face ID on, Start. It is the consent, said in three lines instead of four
/// paragraphs; swiping it away makes no key and keeps no photo.
struct MirrorPromise: View {
    /// Start: true when Face ID or the passcode should guard the photos.
    let onStart: (Bool) -> Void

    @State private var faceID = true
    @State private var starting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // The kind of photo this is, drawn, never a photograph.
                MirrorFigureShape()
                    .stroke(Theme.tertiary.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 70, height: 170)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 22)
                    .accessibilityHidden(true)
                Text("Your mirror")
                    .font(.ui(27, .medium))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("A photo of yourself every four weeks, to see what the numbers can't show.")
                    .font(.ui(15))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 14) {
                    promise("iphone", "These photos stay on this phone.")
                    promise("icloud.slash", "Never iCloud, never Claude, never your camera roll.")
                    promise("checkmark.seal", "Bite scores your day, never your body.")
                }
                .padding(.top, 24)

                InsetBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: $faceID) {
                            Text("Require Face ID to open")
                                .font(.ui(16, .medium))
                                .foregroundStyle(Theme.ink)
                        }
                        Text("Your passcode works too.")
                            .font(.ui(13))
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .padding(.top, 24)

                Button {
                    starting = true
                    onStart(faceID)
                } label: {
                    Text("Start")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(starting)
                .padding(.top, 28)

                Text("A new phone starts fresh. Export before you switch.")
                    .font(.ui(13))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.page.ignoresSafeArea())
    }

    private func promise(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            IconCircle(systemImage: symbol, size: 34)
            Text(text)
                .font(.ui(15))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
