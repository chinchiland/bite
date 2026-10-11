import SwiftUI
import SwiftData
import UIKit

/// The photo you took, with Claude's estimate floating on it and the details underneath:
/// the meal, its calories and macros, each ingredient you can adjust, then add or save.
struct EstimateView: View {
    let image: UIImage
    let isLabel: Bool
    let day: Date
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(LogEvents.self) private var events
    @Query(sort: \SavedFood.sortIndex) private var saved: [SavedFood]

    @State private var phase: Phase = .working
    @State private var estimate: MealEstimate?
    @State private var selected: Int?
    @State private var meal = Meal.likely()
    @State private var isSaved = false
    @State private var showSettings = false
    @State private var attempt = 0

    enum Phase: Equatable {
        case working
        case ready
        case needsKey
        case failed(String)
    }

    private var totals: Nutrients { estimate?.totals ?? .zero }
    private static let skeleton: [CGFloat] = [220, 170, 250]

    var body: some View {
        GeometryReader { geometry in
            let photoHeight = geometry.size.height * 0.5
            ZStack(alignment: .top) {
                Theme.page.ignoresSafeArea()
                photo(height: photoHeight + geometry.safeAreaInsets.top)
                    .ignoresSafeArea(edges: .top)
                sheet
                    .padding(.top, photoHeight - 28)
            }
        }
        .overlay(alignment: .top) { topBar }
        .task(id: attempt) { await run() }
        .sheet(isPresented: $showSettings, onDismiss: { attempt += 1 }) {
            SettingsView()
        }
    }

    // MARK: Photo

    private func photo(height: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay {
                if phase == .working {
                    ScanBand()
                }
            }
            .overlay(alignment: .bottom) {
                if phase == .ready, estimate != nil {
                    VStack(spacing: 8) {
                        KcalPill(kcal: totals.kcal, onPhoto: true)
                        HStack(spacing: 8) {
                            ForEach(Macro.allCases, id: \.self) { macro in
                                MacroPill(macro: macro, grams: macro.grams(in: totals), onPhoto: true)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 44)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: phase)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .floatingGlass(in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel("Back to the camera")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: Sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch phase {
                    case .working:
                        working
                    case .needsKey:
                        message(
                            "Photo estimates use Claude",
                            detail: "Add your Claude API key in Settings once, and every photo gets calories and macros in a few seconds.",
                            action: ("Open Settings", { showSettings = true })
                        )
                    case .failed(let text):
                        message("That didn't work", detail: text, action: ("Try again", { attempt += 1 }))
                    case .ready:
                        if let estimate {
                            ready(estimate)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 26)
                .padding(.bottom, 16)
            }
            if phase == .ready, let estimate, !estimate.items.isEmpty {
                actionBar(estimate)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            Theme.page,
            in: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private var working: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProgressView()
                Text(isLabel ? "Claude is reading the label" : "Claude is looking at your plate")
                    .font(.ui(17, .medium))
                    .foregroundStyle(Theme.ink)
            }
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.track)
                    .frame(width: Self.skeleton[index], height: 14)
            }
            Text("Usually a few seconds.")
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
        }
    }

    private func message(_ title: String, detail: String, action: (String, () -> Void)) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.ui(22, .semibold))
                .foregroundStyle(Theme.ink)
            Text(detail)
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action.0, action: action.1)
                .buttonStyle(PrimaryButtonStyle(height: 48))
                .padding(.top, 4)
        }
    }

    @ViewBuilder private func ready(_ estimate: MealEstimate) -> some View {
        Text("\(estimate.emoji) \(estimate.title)")
            .font(.ui(28, .semibold))
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)

        FlowLayout(spacing: 8) {
            TintChip(title: estimate.confidence.label, style: estimate.confidence == .low ? .watch : .info)
            if estimate.items.isEmpty {
                TintChip(title: "No food found", style: .watch)
            }
        }

        if !estimate.note.isEmpty {
            Text(estimate.note)
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !estimate.items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Ingredients", detail: "Tap one to adjust", size: 17)
                    .padding(.horizontal, -4)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(estimate.items.indices, id: \.self) { index in
                            IngredientBubble(item: estimate.items[index], isSelected: selected == index) {
                                withAnimation(.snappy) { selected = selected == index ? nil : index }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal, -20)

                if let selected, estimate.items.indices.contains(selected) {
                    adjuster(estimate.items[selected], index: selected)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func adjuster(_ item: MealEstimate.Item, index: Int) -> some View {
        InsetBox(padding: 12) {
            HStack(spacing: 12) {
                Text(item.emoji)
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.ui(15, .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text("\(item.kcal.kcalText) kcal")
                        .font(.ui(13))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                StepButton(systemImage: "minus", label: "Less") { change(index, by: -10) }
                Text("\(item.grams.kcalText) g")
                    .font(.number(17))
                    .frame(minWidth: 58)
                StepButton(systemImage: "plus", label: "More") { change(index, by: 10) }
            }
        }
    }

    private func actionBar(_ estimate: MealEstimate) -> some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                MealMenuLabel(title: meal.title)
            }
            .accessibilityLabel("Meal: \(meal.title)")

            Button("Add meal") { add(estimate) }
                .buttonStyle(PrimaryButtonStyle())

            BookmarkButton(isSaved: isSaved) { save(estimate) }
                .disabled(isSaved)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 30)
        .background(Theme.page)
    }

    // MARK: Actions

    private func run() async {
        phase = .working
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            try? await Task.sleep(for: .seconds(1.2))
            estimate = DemoData.estimate
            phase = .ready
            return
        }
        #endif
        let key = Keychain.string(for: Keychain.claudeKey) ?? ""
        guard !key.isEmpty else {
            phase = .needsKey
            return
        }
        guard let jpeg = ImageTools.jpeg(image, maxSide: 1024, quality: 0.72) else {
            phase = .failed("This photo couldn't be read.")
            return
        }
        let language = OpenFoodFacts.languages.first ?? "en"
        do {
            let result = try await ClaudeVision(apiKey: key).estimate(jpeg: jpeg, language: language, isLabel: isLabel)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                estimate = result
                phase = .ready
            }
        } catch let failure as ClaudeVision.Failure {
            phase = failure == .missingKey ? .needsKey : .failed(failure.errorDescription ?? "Try again.")
        } catch {
            phase = .failed("Check your connection and try again.")
        }
    }

    private func change(_ index: Int, by delta: Double) {
        guard var current = estimate, current.items.indices.contains(index) else { return }
        let item = current.items[index]
        current.items[index] = item.with(grams: max(item.grams + delta, 5))
        withAnimation(.snappy) { estimate = current }
    }

    private func plate(_ estimate: MealEstimate) -> Food {
        estimate.food(imageData: ImageTools.jpeg(image, maxSide: 600))
    }

    private func add(_ estimate: MealEstimate) {
        let food = plate(estimate)
        context.insert(FoodEntry(food: food, amount: 1, meal: meal, date: FoodDetailView.logDate(for: day)))
        try? context.save()
        events.added(food, amount: 1, meal: meal)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onDone()
    }

    private func save(_ estimate: MealEstimate) {
        let item = SavedFood(food: plate(estimate), amount: 1, sortIndex: (saved.map(\.sortIndex).max() ?? 0) + 1)
        item.subtitle = estimate.items.map(\.name).joined(separator: ", ")
        context.insert(item)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        isSaved = true
    }
}

/// An ingredient as a round emoji with its name and grams under it.
private struct IngredientBubble: View {
    let item: MealEstimate.Item
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(item.emoji)
                    .font(.system(size: 30))
                    .frame(width: 64, height: 64)
                    .background(Theme.tint(FoodTint.suggested(for: item.emoji)), in: Circle())
                    .overlay {
                        Circle().strokeBorder(Theme.ink, lineWidth: isSelected ? 2 : 0)
                    }
                    .padding(.bottom, 2)
                Text(item.name)
                    .font(.ui(13, .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(item.grams.kcalText) g")
                    .font(.ui(13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
            }
            .frame(width: 80)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel("\(item.name), \(item.grams.kcalText) grams, \(item.kcal.kcalText) calories")
    }
}

/// A soft band of light sweeping over the photo while Claude works.
private struct ScanBand: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var down = false

    var body: some View {
        GeometryReader { geometry in
            LinearGradient(
                colors: [.white.opacity(0), .white.opacity(0.35), .white.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: geometry.size.height * 0.3)
            .offset(y: down ? geometry.size.height * 0.75 : -geometry.size.height * 0.05)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { down = true }
        }
    }
}
