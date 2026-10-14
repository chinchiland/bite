import SwiftUI

/// The one sheet before the camera ever opens, the first time: what your mirror is, where the
/// photos stay, Face ID on, Start. It is the consent, said in three lines instead of four
/// paragraphs; swiping it away makes no key and keeps no photo. Where they stay is a choice:
/// only on this phone, free, or kept forever for $4.99 once, an encrypted copy only your
/// iPhones can open. On a new iPhone with photos kept from the last one, it offers them back.
struct MirrorPromise: View {
    /// Photos kept from another iPhone, found through iCloud Keychain.
    var kept: Int? = nil
    /// Start: Face ID or the passcode on, and whether to keep them forever.
    let onStart: (_ faceID: Bool, _ keepForever: Bool) -> Void
    /// Bring the kept photos back, Face ID on or not.
    var onRestore: (Bool) -> Void = { _ in }

    @State private var faceID = true
    @State private var keepForever = false
    @State private var starting = false
    private var keep: MirrorKeep { MirrorKeep.shared }

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
                Text(kept == nil ? LocalizedStringKey("Your mirror") : LocalizedStringKey("Welcome back"))
                    .font(.ui(27, .medium))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Group {
                    if let kept {
                        Text("\(kept) photos are kept for you.")
                    } else {
                        Text("A photo of yourself every four weeks, to see what the numbers can't show.")
                    }
                }
                .font(.ui(15))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

                if kept == nil {
                    VStack(alignment: .leading, spacing: 14) {
                        promise("iphone", "These photos stay on this phone.")
                        promise("icloud.slash", "Never iCloud, never Claude, never your camera roll.")
                        promise("checkmark.seal", "Bite scores your day, never your body.")
                    }
                    .padding(.top, 24)

                    VStack(spacing: 10) {
                        choice(
                            selected: !keepForever,
                            title: "Only on this phone",
                            price: Text("Free"),
                            detail: "Never leaves it. A new phone starts fresh."
                        ) { keepForever = false }
                        choice(
                            selected: keepForever,
                            title: "Keep forever",
                            price: Text("\(keep.price) once"),
                            detail: "An encrypted copy only your iPhones can open, back on your next one."
                        ) { keepForever = true }
                    }
                    .padding(.top, 24)
                    .animation(Motion.respond, value: keepForever)
                }

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
                    if kept != nil {
                        onRestore(faceID)
                    } else {
                        onStart(faceID, keepForever)
                    }
                    // Back on, should the purchase be cancelled or the restore fail.
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        starting = false
                    }
                } label: {
                    if kept != nil {
                        Text("Restore them")
                    } else {
                        Text("Start")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(starting || keep.buying || keep.status == .restoring)
                .padding(.top, 28)

                if kept == nil, !keepForever {
                    Text("A new phone starts fresh. Export before you switch.")
                        .font(.ui(13))
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
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

    /// Where the photos stay, as two cards: the chosen one ringed in ink.
    private func choice(selected: Bool, title: LocalizedStringKey, price: Text, detail: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.ui(16, .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    price
                        .font(.ui(15, .medium))
                        .foregroundStyle(selected ? Theme.ink : Theme.secondary)
                }
                Text(detail)
                    .font(.ui(13))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.insetRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.insetRadius, style: .continuous)
                    .strokeBorder(selected ? Theme.ink : Theme.edge, lineWidth: selected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .sensoryFeedback(Feel.tick, trigger: selected) { _, new in new }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
