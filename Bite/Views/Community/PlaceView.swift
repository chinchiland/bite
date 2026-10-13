import SwiftUI
import SwiftData

/// A place and the dishes people counted there: how far it is, the way there, ordering, and
/// each dish with its calories and how sure they are. Dishes open in place.
struct PlaceView: View {
    let place: MealPlace
    let onDone: () -> Void

    @Environment(\.openURL) private var openURL
    @Query private var dishes: [CommunityDish]
    @State private var finder = PlaceFinder()
    @State private var path: [CommunityDish] = []
    @State private var showNewDish = false

    init(place: MealPlace, onDone: @escaping () -> Void) {
        self.place = place
        self.onDone = onDone
        let name = place.name
        _dishes = Query(filter: #Predicate<CommunityDish> { $0.placeName == name }, sort: \CommunityDish.createdAt)
    }

    /// The best counted first.
    private var ranked: [CommunityDish] {
        dishes.sorted { $0.consensus.accuracy > $1.consensus.accuracy }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    actions
                        .padding(.top, 18)

                    SectionLabel(title: "Dishes here", symbol: "fork.knife")
                        .padding(.top, 30)
                        .padding(.bottom, 6)
                    ForEach(ranked) { dish in
                        Button {
                            path.append(dish)
                        } label: {
                            DishListRow(dish: dish)
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 70)
                    }
                    newDishRow

                    Text("The calories here come from estimates people shared. Each dish shows how sure they are, and yours makes it surer.")
                        .font(.ui(13))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 22)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Theme.page.ignoresSafeArea())
            .navigationDestination(for: CommunityDish.self) { dish in
                DishView(dish: dish, onDone: onDone)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
            .sheet(isPresented: $showNewDish) {
                AddEstimateView(dish: nil, place: place)
            }
        }
        .task { await finder.locateIfAllowed() }
        #if DEBUG
        .onAppear {
            let screen = UserDefaults.standard.string(forKey: "screen") ?? ""
            if ["dish", "addestimate", "accuracy", "share"].contains(screen), let first = ranked.first {
                path = [first]
            }
        }
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(place.name)
                .font(.ui(30, .semibold))
                .tracking(-0.6)
                .foregroundStyle(Theme.ink)
            HStack(spacing: 6) {
                if let category = place.category {
                    Image(systemName: category.symbol)
                        .font(.system(size: 13, weight: .medium))
                    Text(category.title)
                }
                if let area = place.area, !area.isEmpty {
                    if place.category != nil { Text(verbatim: "·") }
                    Text(area)
                }
                if let meters = finder.distance(to: place) {
                    Text(verbatim: "·")
                    Text(meters.distanceText)
                        .monospacedDigit()
                }
            }
            .font(.ui(15))
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                if let url = directionsURL { openURL(url) }
            } label: {
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SoftButtonStyle())
            Button {
                if let url = orderURL { openURL(url) }
            } label: {
                Label("Order", systemImage: "bag.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SoftButtonStyle())
            .accessibilityHint("Opens the place in Uber Eats")
        }
        .labelStyle(.titleAndIcon)
    }

    private var newDishRow: some View {
        Button {
            showNewDish = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accurate)
                    .frame(width: 58, height: 58)
                    .background(Theme.accurate.opacity(0.1), in: RoundedRectangle(cornerRadius: FoodThumb.radius(for: 58), style: .continuous))
                Text("Add a dish")
                    .font(.ui(16))
                    .foregroundStyle(Theme.accurate)
                Spacer()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Walking directions in Apple Maps, to the spot when it is known, else by name.
    private var directionsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        if let latitude = place.latitude, let longitude = place.longitude {
            components?.queryItems = [
                URLQueryItem(name: "daddr", value: "\(latitude),\(longitude)"),
                URLQueryItem(name: "dirflg", value: "w"),
                URLQueryItem(name: "q", value: place.name),
            ]
        } else {
            components?.queryItems = [URLQueryItem(name: "q", value: place.line)]
        }
        return components?.url
    }

    /// The place in Uber Eats (the app when it is installed). A partner link once Uber accepts
    /// Bite as a publisher; a plain one until then.
    private var orderURL: URL? {
        var components = URLComponents(string: "https://www.ubereats.com/ch/search")
        components?.queryItems = [URLQueryItem(name: "q", value: place.name)]
        return components?.url
    }
}

/// A dish in a list: its picture, name, calories and how many counted it, and the gauge of how
/// sure that is.
struct DishListRow: View {
    let dish: CommunityDish

    var body: some View {
        let consensus = dish.consensus
        HStack(spacing: 12) {
            DishThumb(dish: dish, width: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text(dish.name)
                    .font(.ui(16, .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                HStack(spacing: 0) {
                    Text("\(consensus.nutrients.kcal.kcalText) kcal")
                    Text(verbatim: " · ")
                    Text("\(consensus.estimates) estimates")
                }
                .font(.ui(14))
                .monospacedDigit()
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            AccuracyGauge(consensus: consensus, size: 34)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
