import SwiftUI
import SwiftData
import UIKit

/// The photo you took as the hero, and Claude's estimate on a white sheet under it: the meal,
/// how sure Claude is, the macros and the ring, each ingredient you can adjust, then add or
/// save.
struct EstimateView: View {
    let image: UIImage
    let isLabel: Bool
    let day: Date
    /// When the photo was taken, if it came from the library: the meal keeps that time.
    var takenAt: Date? = nil
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(LogEvents.self) private var events
    @Query(sort: \SavedFood.sortIndex) private var saved: [SavedFood]
    @AppStorage("goal.kcal") private var goalKcal = 2000
    @AppStorage("goal.split") private var splitRaw = MacroSplit.balanced.rawValue

    @State private var phase: Phase = .working
    @State private var estimate: MealEstimate?
    @State private var selected: Int?
    @State private var meal = Meal.likely()
    /// Where you are eating it: picked from the places around you, or none.
    @State private var place: MealPlace?
    /// When you ate it: the photo's own time when it has one, else now; a tap changes it.
    @State private var time: Date?
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

    /// The photo's time, else the usual time for this day; yours once you change it.
    private var timeBinding: Binding<Date> {
        Binding(
            get: { time ?? takenAt ?? FoodDetailView.logDate(for: day) },
            set: { time = $0 }
        )
    }
    private var targets: MacroTargets {
        MacroTargets(kcal: Double(goalKcal), split: MacroSplit(rawValue: splitRaw) ?? .balanced)
    }
    private static let skeleton: [CGFloat] = [220, 170, 250]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    photo
                    sheet
                        .padding(.top, -32)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            backButton
        }
        .background(Theme.card.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if phase == .ready, let estimate, !estimate.items.isEmpty {
                actionBar(estimate)
            }
        }
        .task(id: attempt) { await run() }
        .sheet(isPresented: $showSettings, onDismiss: { attempt += 1 }) {
            SettingsView()
        }
    }

    // MARK: Photo

    private var photo: some View {
        Color.clear
            .frame(height: 400)
            .frame(maxWidth: .infinity)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .overlay {
                        LinearGradient(colors: [.black.opacity(0.32), .clear], startPoint: .top, endPoint: .center)
                    }
            }
            .overlay {
                if phase == .working {
                    ScanBand()
                }
            }
            .clipped()
            .visualEffect { content, proxy in
                let pull = max(proxy.frame(in: .scrollView).minY, 0)
                return content.scaleEffect(1 + pull / max(proxy.size.height, 1), anchor: .bottom)
            }
            .accessibilityHidden(true)
    }

    private var backButton: some View {
        GlassCircleButton(systemImage: "chevron.left", label: "Back to the camera", onPhoto: true) {
            dismiss()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: Sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch phase {
            case .working:
                working
                    .padding(.horizontal, Theme.margin)
            case .needsKey:
                message(
                    "Photo estimates use Claude",
                    detail: String(localized: "Add your Claude API key in Settings once, and every photo gets calories and macros in a few seconds."),
                    action: ("Open Settings", { showSettings = true })
                )
                .padding(.horizontal, Theme.margin)
            case .failed(let text):
                message("That didn't work", detail: text, action: ("Try again", { attempt += 1 }))
                    .padding(.horizontal, Theme.margin)
            case .ready:
                if let estimate {
                    ready(estimate)
                }
            }
        }
        .padding(.top, 26)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
        .background(
            Theme.card,
            in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
        )
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

    private func message(_ title: LocalizedStringKey, detail: String, action: (LocalizedStringKey, () -> Void)) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.ui(22, .semibold))
                .foregroundStyle(Theme.ink)
            Text(detail)
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action.0, action: action.1)
                .buttonStyle(PrimaryButtonStyle(height: 50))
                .padding(.top, 4)
        }
    }

    @ViewBuilder private func ready(_ estimate: MealEstimate) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(estimate.emoji) \(estimate.title)")
                .font(.ui(27, .medium))
                .tracking(-0.6)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 7) {
                TintChip(
                    title: estimate.confidence.label,
                    style: estimate.confidence == .low ? .watch : .info,
                    systemImage: "sparkles"
                )
                if estimate.items.isEmpty {
                    TintChip(title: String(localized: "No food found"), style: .watch)
                }
            }
            .padding(.top, 12)

            if !estimate.note.isEmpty {
                Text(estimate.note)
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }

            if !estimate.items.isEmpty {
                MacroBlock(
                    nutrients: totals,
                    targets: targets,
                    ring: DottedRing.food(totals),
                    number: totals.kcal,
                    unit: "kcal",
                    showsTarget: false,
                    surface: Theme.card
                )
                .padding(.top, 20)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(totals.kcal.kcalText) calories. Protein \(totals.protein.gramsText) grams, carbs \(totals.carbs.gramsText) grams, fat \(totals.fat.gramsText) grams."
                )
                HStack {
                    Text("Time")
                        .font(.ui(17))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .padding(.vertical, 4)
                .padding(.top, 14)
                PlaceRow(place: $place)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, Theme.margin)

        if !estimate.items.isEmpty {
            SectionLabel(title: "Ingredients", detail: "Tap one to adjust", size: 17, symbol: "leaf.fill", symbolColor: Theme.goodIcon)
                .padding(.horizontal, Theme.margin)
                .padding(.top, 24)
                .padding(.bottom, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(estimate.items.indices, id: \.self) { index in
                        IngredientBubble(item: estimate.items[index], isSelected: selected == index) {
                            withAnimation(.snappy) { selected = selected == index ? nil : index }
                        }
                    }
                }
            }
            .contentMargins(.horizontal, Theme.margin, for: .scrollContent)

            if let selected, estimate.items.indices.contains(selected) {
                adjuster(estimate.items[selected], index: selected)
                    .padding(.horizontal, Theme.margin)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
        .padding(.horizontal, Theme.margin)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.card.ignoresSafeArea())
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
            phase = .failed(String(localized: "This photo couldn't be read."))
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
            phase = failure == .missingKey ? .needsKey : .failed(failure.errorDescription ?? String(localized: "Try again."))
        } catch {
            phase = .failed(String(localized: "Check your connection and try again."))
        }
    }

    private func change(_ index: Int, by delta: Double) {
        guard var current = estimate, current.items.indices.contains(index) else { return }
        let item = current.items[index]
        current.items[index] = item.with(grams: max(item.grams + delta, 5))
        withAnimation(.snappy) { estimate = current }
    }

    /// The plate as one food, keeping the photo sharp enough to be the day's cover.
    private func plate(_ estimate: MealEstimate) -> Food {
        estimate.food(imageData: ImageTools.jpeg(image, maxSide: 1000, quality: 0.7))
    }

    private func add(_ estimate: MealEstimate) {
        let food = plate(estimate)
        let entry = FoodEntry(food: food, amount: 1, meal: meal, date: timeBinding.wrappedValue, place: place)
        context.insert(entry)
        try? context.save()
        events.added(entry)
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
