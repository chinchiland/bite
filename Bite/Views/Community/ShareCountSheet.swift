import AuthenticationServices
import SwiftUI

/// "Share your count": one sheet, one decision. The dish, your name as people eating there will
/// see it, that your food log stays on this phone, then Continue with Apple, or Share once you
/// are in. The same sheet asks the first time you agree with a count or rate a dish, since
/// those count only from people who signed in.
struct ShareCountSheet: View {
    enum Reason: Identifiable {
        case share
        case agree
        case rate

        var id: Self { self }
    }

    let dish: CommunityDish
    /// Your estimate, for sharing.
    var estimate: DishEstimate? = nil
    let reason: Reason
    /// True once you are signed in (and, for sharing, once it is shared).
    let onDone: (Bool) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @State private var account = CommunityAccount.shared
    @State private var name = ""
    @State private var editingName = false
    @State private var working = false
    @State private var failed = false
    @State private var taps = 0
    @FocusState private var nameFocused: Bool

    private var title: LocalizedStringKey {
        switch reason {
        case .share: "Share your count"
        case .agree: "Agree with this count"
        case .rate: "Rate this dish"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Text(title)
                .font(.ui(26, .semibold))
                .tracking(-0.5)
                .foregroundStyle(Theme.ink)
                .padding(.top, 22)
                .accessibilityAddTraits(.isHeader)
            if reason != .share {
                Text("Agrees and stars come from people who sign in, so nobody can fake them.")
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            nameLine
                .padding(.top, 14)
            Text("Your food log stays on this phone.")
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 10)
            if failed {
                Text("That didn't work. Try again in a moment.")
                    .font(.ui(15))
                    .foregroundStyle(Theme.over)
                    .padding(.top, 10)
                    .transition(.opacity)
            }
            Spacer(minLength: 20)
            action
            Button("Not now") { onDone(false) }
                .font(.ui(16))
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .padding(.top, 4)
            if let rules = CommunityServer.rulesURL {
                Link(destination: rules) {
                    Text("By sharing you accept the community rules.")
                        .font(.ui(13))
                        .underline()
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .background(Theme.card.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .animation(Motion.settle, value: failed)
        .sensoryFeedback(trigger: taps) { _, _ in failed ? Feel.failed : Feel.click }
        .onAppear {
            name = account.displayName
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            FoodThumb(food: dish.food, size: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(dish.place.line)
                    .font(.ui(14))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                Text(dish.name)
                    .font(.ui(17, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let estimate {
                    Text("\(estimate.kcal.kcalText) kcal, your count")
                        .font(.ui(15))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Your name as people see it, changed in place.
    private var nameLine: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("People eating here will see it as")
                .font(.ui(16))
                .foregroundStyle(Theme.ink)
            if editingName {
                TextField("Your name", text: $name)
                    .font(.ui(16, .semibold))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .onSubmit(saveName)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Theme.fill, in: Capsule())
            } else {
                Button {
                    editingName = true
                    nameFocused = true
                } label: {
                    HStack(spacing: 6) {
                        Text(name.isEmpty ? String(localized: "Your first name") : name)
                            .font(.ui(16, .semibold))
                            .foregroundStyle(name.isEmpty ? Theme.secondary : Theme.ink)
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Theme.fill, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Changes the name people see")
            }
        }
    }

    @ViewBuilder private var action: some View {
        if account.isSignedIn {
            Button(reason == .share ? LocalizedStringKey("Share") : LocalizedStringKey("Continue")) {
                Task { await finish() }
            }
            .buttonStyle(PrimaryButtonStyle(height: 52))
            .disabled(working)
        } else {
            SignInWithAppleButton(.continue) { request in
                saveName()
                account.prepare(request)
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    Task {
                        working = true
                        do {
                            try await account.complete(authorization)
                            await finish()
                        } catch {
                            taps += 1
                            failed = true
                        }
                        working = false
                    }
                case .failure:
                    // Closed by the person, or Apple could not sign in: nothing to say.
                    break
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .clipShape(Capsule())
            .disabled(working)
        }
    }

    private func saveName() {
        editingName = false
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != account.displayName else { return }
        Task { await account.rename(to: trimmed) }
    }

    /// Signed in: share, or hand back so the agree or the stars go through.
    private func finish() async {
        guard reason == .share, let estimate else {
            onDone(true)
            return
        }
        working = true
        do {
            try await CommunitySync.share(estimate, of: dish, context: context)
            taps += 1
            onDone(true)
        } catch {
            taps += 1
            failed = true
        }
        working = false
    }
}
