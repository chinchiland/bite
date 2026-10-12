import SwiftUI
import SwiftData
import UIKit

/// A dish at a place, as the community counted it: its photo as the hero, the calories and
/// macros the estimates add up to, how accurate that is, every estimate with the people who
/// agree, your stars, and the button to add it to today.
struct DishView: View {
    let dish: CommunityDish
    /// Opens the dish's place. Nil when the place is already the screen underneath.
    var onOpenPlace: ((MealPlace) -> Void)? = nil
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(LogEvents.self) private var events
    @AppStorage("goal.kcal") private var goalKcal = 2000
    @AppStorage("goal.split") private var splitRaw = MacroSplit.balanced.rawValue
    @State private var meal = Meal.likely()
    @State private var showAccuracy = false
    @State private var showAddEstimate = false

    private var consensus: Consensus { dish.consensus }
    private var targets: MacroTargets {
        MacroTargets(kcal: Double(goalKcal), split: MacroSplit(rawValue: splitRaw) ?? .balanced)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FoodHero(food: dish.food, height: 300)
                sheet
                    .padding(.top, -32)
            }
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(ScreenshotFlags.scrollAnchor)
        .ignoresSafeArea(edges: .top)
        .background(Theme.card.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAccuracy) {
            AccuracyExplainer(consensus: consensus)
        }
        .sheet(isPresented: $showAddEstimate) {
            AddEstimateView(dish: dish)
        }
        #if DEBUG
        .onAppear {
            switch UserDefaults.standard.string(forKey: "screen") {
            case "addestimate": showAddEstimate = true
            case "accuracy": showAccuracy = true
            default: break
            }
        }
        #endif
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(dish.name)
                .font(.ui(27, .medium))
                .tracking(-0.6)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            placeLink
                .padding(.top, 3)
            metaLine
                .padding(.top, 12)
            MacroBlock(
                nutrients: consensus.nutrients,
                targets: targets,
                ring: DottedRing.food(consensus.nutrients),
                number: consensus.nutrients.kcal,
                unit: "kcal",
                showsTarget: false,
                surface: Theme.card
            )
            .padding(.top, 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(consensus.nutrients.kcal.kcalText) calories. Protein \(consensus.nutrients.protein.gramsText) grams, carbs \(consensus.nutrients.carbs.gramsText) grams, fat \(consensus.nutrients.fat.gramsText) grams."
            )

            SectionLabel(title: "Calorie estimates", symbol: "flame.fill", symbolColor: Theme.energy)
                .padding(.top, 32)
                .padding(.bottom, 8)
            AccuracyRow(consensus: consensus) { showAccuracy = true }
            ForEach(dish.rankedEstimates) { estimate in
                Rectangle().fill(Theme.hairline).frame(height: 1)
                EstimateRow(estimate: estimate) { toggleAgree(estimate) }
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            addEstimateRow

            Rectangle().fill(Theme.hairline).frame(height: 1)
                .padding(.top, 14)
            ratingRow
                .padding(.top, 14)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 26)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.card,
            in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
        )
    }

    @ViewBuilder private var placeLink: some View {
        let place = dish.place
        if let onOpenPlace {
            Button {
                onOpenPlace(place)
            } label: {
                HStack(spacing: 3) {
                    Text(place.line)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                }
                .font(.ui(15))
                .foregroundStyle(Theme.link)
            }
            .buttonStyle(.plain)
        } else {
            Text(place.line)
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
        }
    }

    /// Stars and how many people counted it, in one quiet line.
    private var metaLine: some View {
        HStack(spacing: 6) {
            if let rating = dish.rating {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.energy)
                Text(rating.average.formatted(.number.precision(.fractionLength(1))))
                    .font(.ui(15, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(verbatim: "(\(rating.count))")
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
                Text(verbatim: "·")
                    .foregroundStyle(Theme.secondary)
            }
            Text("\(consensus.estimates) estimates")
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    private var addEstimateRow: some View {
        Button {
            showAddEstimate = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accurate)
                    .frame(width: 32, height: 32)
                    .background(Theme.accurate.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(dish.estimates.contains(where: \.isMine) ? "Change your estimate" : "Add your estimate")
                    .font(.ui(15))
                    .foregroundStyle(Theme.accurate)
                Spacer()
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var ratingRow: some View {
        HStack {
            HStack(spacing: 12) {
                SymbolTile(systemImage: "star.fill", color: Theme.energy, glyph: Theme.energyDeep, size: 32)
                Text("Your rating")
                    .font(.ui(15))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
            StarRating(rating: dish.myRating) { stars in
                withAnimation(.snappy) {
                    dish.myRating = dish.myRating == stars ? nil : stars
                    try? context.save()
                }
            }
        }
    }

    private var actionBar: some View {
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

            Button("Add to today", action: addToToday)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(dish.estimates.isEmpty)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.card.ignoresSafeArea())
    }

    // MARK: Actions

    private func toggleAgree(_ estimate: DishEstimate) {
        withAnimation(.snappy) {
            estimate.agreedByMe.toggle()
            estimate.agrees = max(0, estimate.agrees + (estimate.agreedByMe ? 1 : -1))
            try? context.save()
        }
    }

    private func addToToday() {
        let entry = FoodEntry(food: dish.food, amount: 1, meal: meal, date: .now, place: dish.place)
        context.insert(entry)
        try? context.save()
        events.added(entry)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onDone()
    }
}
