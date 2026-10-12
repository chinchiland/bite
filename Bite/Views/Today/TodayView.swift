import SwiftUI
import SwiftData
import Combine
import UIKit
import TipKit

/// The three views of home: the day you are logging, and your week and month in numbers.
enum HomeTab: String, CaseIterable, Identifiable {
    case today = "Day"
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }
}

/// What the switcher at the top of home can show: one of the last days, or a range.
enum HomeSelection: Hashable {
    case day(Date)
    case week
    case month
}

/// Every sheet home can open, one at a time.
enum HomeSheet: Identifiable, Hashable {
    case search(Meal?)
    case quickAdd
    case settings
    case newSaved
    case editSaved(SavedFood)
    case place(MealPlace)
    case dish(CommunityDish)

    var id: Self { self }
}

/// Home: the day under your latest meal photo, its macros, your meals and saved foods, with
/// the scan dock; or your last 7 or 30 days.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(LogEvents.self) private var events
    @Environment(AppActions.self) private var actions
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Query private var entries: [FoodEntry]
    @Query(sort: \SavedFood.sortIndex) private var saved: [SavedFood]
    @Query private var waterDays: [WaterDay]
    @Query(sort: \CommunityDish.createdAt) private var dishes: [CommunityDish]

    @AppStorage("goal.kcal") private var goalKcal = 2000
    @AppStorage("goal.split") private var splitRaw = MacroSplit.balanced.rawValue
    @AppStorage("health.asked") private var healthAsked = false
    @AppStorage("health.addBurned") private var addBurned = false
    @AppStorage("health.weightAsked") private var weightAsked = false
    @AppStorage("body.sex") private var sexRaw = Sex.female.rawValue
    @AppStorage("body.age") private var bodyAge = 30
    @AppStorage("body.height") private var bodyHeight = 170
    @AppStorage("body.weight") private var bodyWeight = 70.0
    @AppStorage("body.activity") private var activityRaw = Activity.light.rawValue
    @AppStorage("body.goal") private var weightGoalRaw = WeightGoal.maintain.rawValue
    @AppStorage("water.goal") private var waterGoal = 8
    /// "Not today" on your usual meal: that day and meal, so tomorrow it comes back.
    @AppStorage("usual.dismissed") private var usualDismissed = ""

    @State private var tab: HomeTab = .today
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var sheet: HomeSheet?
    @State private var showScanner = false
    @State private var editing: FoodEntry?
    @State private var deleting: FoodEntry?
    @State private var activity: DayActivity?
    @State private var activityRefresh = 0
    @State private var coverPhotos: [CoverPhoto] = []
    @State private var coverIndex = 0
    @State private var coverOnScreen = true
    @State private var weights: [WeightPoint] = []
    @State private var placeFinder = PlaceFinder()
    @Namespace private var zoom

    /// How far back home reads the log: a month for the ranges, and the month before it so
    /// they can show how things moved.
    static let daysBack = 62

    init() {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -Self.daysBack, to: calendar.startOfDay(for: .now)) ?? .distantPast
        _entries = Query(filter: #Predicate<FoodEntry> { $0.date >= start }, sort: \FoodEntry.date)
        _waterDays = Query(filter: #Predicate<WaterDay> { $0.day >= start })
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Theme.page.ignoresSafeArea()
                switch tab {
                case .today:
                    dayPage(topInset: proxy.safeAreaInsets.top)
                case .week:
                    rangePage(.week)
                case .month:
                    rangePage(.month)
                }
                if tab != .today || !coverOnScreen {
                    TopFade(height: proxy.safeAreaInsets.top)
                        .transition(.opacity)
                }
                bottomStack
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.2), value: coverOnScreen)
        }
        // A photo cover runs to the top edge, where the time would sit dark on the picture.
        .statusBarHidden(tab == .today && !coverPhotos.isEmpty && coverOnScreen && colorScheme == .light)
        .fullScreenCover(isPresented: $showScanner) {
            ScannerView(day: day)
                .zoomTransition(id: "scan", in: zoom)
        }
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
        }
        .sheet(item: $editing, onDismiss: deletePending) { entry in
            NavigationStack {
                FoodDetailView(
                    food: entry.food,
                    entry: entry,
                    day: day,
                    onDone: { editing = nil },
                    onDelete: { entry in
                        deleting = entry
                        editing = nil
                    }
                )
            }
            .presentationDragIndicator(.visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            day = Calendar.current.startOfDay(for: .now)
        }
        .task(id: "\(day.timeIntervalSince1970) \(activityRefresh) \(healthAsked)") {
            await loadActivity()
        }
        .task(id: photoEntries.map(\.persistentModelID)) {
            loadCoverPhotos()
        }
        .task(id: "\(healthAsked) \(weightAsked)") {
            await loadWeights()
        }
        .task {
            await placeFinder.locateIfAllowed()
        }
        .onChange(of: day) { _, _ in
            coverIndex = 0
        }
        // A tick under the finger when the switcher moves, and a quiet success the moment
        // today lands on target. Nothing else buzzes.
        .sensoryFeedback(.selection, trigger: selectionKey)
        .sensoryFeedback(.success, trigger: isOnTargetToday) { old, new in !old && new }
        .onChange(of: selectionKey) { _, _ in
            DaySwitcherTip().invalidate(reason: .actionPerformed)
        }
        // Siri, Spotlight or the Action button asked to scan.
        .onChange(of: actions.pendingScan, initial: true) { _, pending in
            guard pending else { return }
            actions.pendingScan = false
            showScanner = true
        }
        .task {
            await DaySwitcherTip.opened.donate()
        }
        .task(id: saved.map(\.foodID)) {
            BiteShortcuts.updateAppShortcutParameters()
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from a walk: pick up the new steps.
            if phase == .active { activityRefresh += 1 }
        }
        #if DEBUG
        .onAppear(perform: openDemoScreen)
        #endif
    }

    // MARK: Day

    private func dayPage(topInset: CGFloat) -> some View {
        let hasPhoto = !coverPhotos.isEmpty
        return ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: 0) {
                    DayCover(
                        photos: coverPhotos,
                        index: $coverIndex,
                        height: topInset + (hasPhoto ? 404 : 300),
                        topInset: topInset,
                        number: hero.number,
                        unit: hero.unit,
                        lastMeal: hasPhoto ? nil : dayEntries.last.map { String(localized: "Last meal: \($0.name)") },
                        greeting: isToday ? greeting : nil,
                        detail: heroDetail.text,
                        detailIsOver: heroDetail.isOver,
                        onPlace: { sheet = .place($0) }
                    ) {
                        coverControls(onPhoto: hasPhoto)
                    }
                    .onGeometryChange(for: Bool.self) { geometry in
                        geometry.frame(in: .scrollView).maxY > 120
                    } action: { onScreen in
                        coverOnScreen = onScreen
                    }

                    daySheet
                }
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(ScreenshotFlags.scrollAnchor)
            .ignoresSafeArea(edges: .top)
            #if DEBUG
            .task {
                // `-anchor usual` scrolls your usual meal into the middle, for its screenshot.
                guard UserDefaults.standard.string(forKey: "anchor") == "usual" else { return }
                try? await Task.sleep(for: .seconds(1))
                reader.scrollTo(UsualMoment.anchor, anchor: .center)
            }
            #endif
        }
    }

    private func coverControls(onPhoto: Bool) -> some View {
        HStack(spacing: 8) {
            HomeSwitcher(selection: homeSelection, days: recentDays) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.ui(16, .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(onPhoto ? Color.white : Theme.ink)
                .padding(.leading, 16)
                .padding(.trailing, 13)
                .frame(height: 38)
                .coverGlass(in: Capsule(), onPhoto: onPhoto)
            }
            .popoverTip(DaySwitcherTip(), arrowEdge: .top)
            Spacer(minLength: 8)
            if let streak = streakToShow {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.energy)
                        .symbolEffect(.bounce, value: streak)
                    Text("\(streak)-day streak")
                        .font(.ui(14, .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(onPhoto ? Color.white : Theme.ink)
                .padding(.leading, 11)
                .padding(.trailing, 13)
                .frame(height: 38)
                .coverGlass(in: Capsule(), onPhoto: onPhoto)
                .accessibilityElement(children: .combine)
            }
            GlassCircleButton(systemImage: "gearshape", label: "Settings", onPhoto: onPhoto, size: 38) {
                sheet = .settings
            }
        }
    }

    private var daySheet: some View {
        let ring = DottedRing.day(totals, goal: budget)
        return VStack(alignment: .leading, spacing: 0) {
            MacroBlock(
                nutrients: totals,
                targets: targets,
                ring: ring.parts,
                overflow: ring.overflow,
                number: totals.kcal,
                unit: "kcal eaten"
            )
            ActivityChips(
                health: healthState,
                water: waterGlasses,
                waterGoal: waterGoal,
                onWater: addWater,
                onWaterRemove: removeWater,
                onConnect: connectHealth
            )
            .padding(.top, 16)

            if isToday, !entries.isEmpty {
                let learned = self.learned
                let suggested = suggestedGoal(from: learned)
                WeightTrend(
                    weights: trendWeights,
                    forecast: forecast(learned: learned),
                    goal: WeightGoal(rawValue: weightGoalRaw) ?? .maintain,
                    learned: learned,
                    suggestedGoal: suggested,
                    onUseGoal: { if let suggested { useGoal(suggested) } },
                    onAddWeight: addWeight
                )
                .padding(.top, 28)
            }

            SectionLabel(title: "Your day", symbol: "fork.knife")
                .padding(.top, 26)
                .padding(.bottom, 14)
            let usual = self.usual
            if dayEntries.isEmpty, usual == nil {
                EmptyDay(isToday: Calendar.current.isDateInToday(day)) { showScanner = true }
            } else if !dayEntries.isEmpty {
                DayTimeline(
                    entries: dayEntries,
                    isToday: Calendar.current.isDateInToday(day),
                    onSelect: { editing = $0 },
                    onSave: { save($0.food, amount: $0.amount, meal: $0.meal) },
                    onDelete: delete,
                    onAddHere: { sheet = .search($0) },
                    onSaveMeal: saveMeal,
                    onAddToToday: addToToday,
                    onMoveTime: move
                )
            }
            if let usual {
                UsualMoment(
                    meal: usual.meal.meal,
                    entries: usual.entries,
                    time: usual.meal.time(on: day),
                    onAdd: { addToToday(usual.entries) },
                    onDismiss: { withAnimation(.snappy) { usualDismissed = usual.meal.dismissalKey(on: day) } }
                )
                .padding(.top, dayEntries.isEmpty ? 0 : 14)
                .transition(.opacity)
                .id(UsualMoment.anchor)
            }

            SavedShelf(
                title: shelfTitle,
                note: shelfNote,
                saved: shelfOrder,
                onAdd: add,
                onEdit: { sheet = .editSaved($0) },
                onDelete: removeSaved,
                onNew: { sheet = .newSaved }
            )
            .padding(.top, 30)

            if !nearby.isEmpty {
                NearbyDishes(items: nearby) { sheet = .dish($0) }
                    .padding(.top, 30)
            }

            WeekStrip(
                days: weekDays,
                onOpenWeek: { withAnimation(.snappy) { tab = .week } },
                onOpenDay: { date in withAnimation(.snappy) { day = date } }
            )
            .padding(.top, 32)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 10)
        .padding(.bottom, 140)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.page)
    }

    // MARK: Week and month

    private func rangePage(_ range: InsightsRange) -> some View {
        RangeView(
            range: range,
            entries: entries,
            goal: Double(goalKcal),
            targets: targets,
            onOpenDay: { date in
                withAnimation(.snappy) {
                    day = date
                    tab = .today
                }
            },
            onSettings: { sheet = .settings }
        ) {
            HomeSwitcher(selection: homeSelection, days: recentDays) {
                HStack(spacing: 6) {
                    Text(range.title)
                        .font(.ui(30, .semibold))
                        .tracking(-0.6)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .padding(.top, 3)
                }
            }
        }
    }

    // MARK: Dock and toast

    private var bottomStack: some View {
        VStack(spacing: 12) {
            if let event = events.last {
                EventToast(event: event) { undo(event) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: event.id) {
                        // Long enough to reach Undo, short enough to stay out of the way.
                        try? await Task.sleep(for: .seconds(4))
                        if events.last?.id == event.id { events.dismiss() }
                    }
            }
            ScanDock(
                namespace: zoom,
                onSearch: { sheet = .search(nil) },
                onScan: { showScanner = true },
                onQuickAdd: { sheet = .quickAdd }
            )
        }
        .padding(.bottom, 4)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: events.last)
    }

    @ViewBuilder private func sheetContent(_ sheet: HomeSheet) -> some View {
        switch sheet {
        case .search(let meal):
            AddFoodView(day: day, meal: meal)
        case .quickAdd:
            NavigationStack {
                QuickAddView(day: day) { self.sheet = nil }
            }
        case .settings:
            SettingsView()
        case .newSaved:
            SavedFoodEditor(mode: .new)
        case .editSaved(let item):
            SavedFoodEditor(mode: .edit(item))
        case .place(let place):
            PlaceView(place: place) { self.sheet = nil }
        case .dish(let dish):
            NavigationStack {
                DishView(dish: dish, onOpenPlace: { self.sheet = .place($0) }, onDone: { self.sheet = nil })
            }
        }
    }

    // MARK: Data

    private var title: String {
        Self.name(of: day)
    }

    /// "Today", "Yesterday", then "Friday 9".
    static func name(of day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return day.formatted(.dateTime.weekday(.wide).day())
    }

    /// Today and the six days before it, for the switcher.
    private var recentDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private var homeSelection: Binding<HomeSelection> {
        Binding(
            get: {
                switch tab {
                case .today: .day(day)
                case .week: .week
                case .month: .month
                }
            },
            set: { selection in
                withAnimation(.snappy) {
                    switch selection {
                    case .day(let date):
                        day = date
                        tab = .today
                    case .week:
                        tab = .week
                    case .month:
                        tab = .month
                    }
                }
            }
        )
    }

    private var dayEntries: [FoodEntry] {
        let calendar = Calendar.current
        return entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// The day's photos, latest first: plates Claude estimated, dishes and saved foods with
    /// your picture.
    private var photoEntries: [FoodEntry] {
        dayEntries.filter { $0.imageData != nil }.reversed()
    }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private var totals: Nutrients {
        dayEntries.reduce(Nutrients.zero) { $0 + $1.totals }
    }

    private var targets: MacroTargets {
        MacroTargets(kcal: Double(goalKcal), split: MacroSplit(rawValue: splitRaw) ?? .balanced)
    }

    /// The day's calories to eat: the goal, plus what you burned if you chose to eat it back.
    private var budget: Double {
        Double(goalKcal) + (addBurned ? activity?.activeKcal ?? 0 : 0)
    }

    /// Today counts down what is left (or what went over); a past day shows what you ate.
    private var hero: (number: Double, unit: String) {
        guard Calendar.current.isDateInToday(day) else {
            return (number: totals.kcal, unit: String(localized: "kcal eaten"))
        }
        if totals.kcal > budget {
            return (number: totals.kcal - budget, unit: String(localized: "kcal over today"))
        }
        return (number: budget - totals.kcal, unit: String(localized: "kcal left today"))
    }

    /// Right of the place line: the goal today; a past day's verdict, red when it went over.
    private var heroDetail: (text: String, isOver: Bool) {
        if !isToday, let verdict = verdicts[day], let label = verdict.label {
            if case .over = verdict { return (label, true) }
            return (label, false)
        }
        return (String(localized: "Goal \(budget.kcalText)"), false)
    }

    // MARK: Today's extras

    private var waterDay: WaterDay? {
        waterDays.first { Calendar.current.isDate($0.day, inSameDayAs: day) }
    }

    private var waterGlasses: Int { waterDay?.glasses ?? 0 }

    /// "Fits your 967 left" while there is room today; just "Saved" otherwise.
    private var shelfTitle: LocalizedStringKey {
        let left = budget - totals.kcal
        return isToday && left > 0 && !saved.isEmpty ? "Fits your \(left.kcalText) left" : "Saved"
    }

    /// One line when protein is well behind today: how much, and that the shelf leads with it.
    private var shelfNote: String? {
        let behind = targets.protein - totals.protein
        guard isToday, behind >= 20, !saved.isEmpty else { return nil }
        return String(localized: "\(behind.gramsText) g of protein to go: the richest in it come first.")
    }

    /// Good morning, afternoon or evening, with the sky of that hour.
    private var greeting: (text: String, symbol: String) {
        switch Calendar.current.component(.hour, from: ScreenshotFlags.now) {
        case 5..<12: (String(localized: "Good morning"), "sun.horizon.fill")
        case 12..<18: (String(localized: "Good afternoon"), "sun.max.fill")
        default: (String(localized: "Good evening"), "moon.stars.fill")
        }
    }

    /// The meal you usually have around now, while today has none of it and you haven't said
    /// "Not today": the foods of the last day you had it.
    private var usual: (meal: UsualMeal, entries: [FoodEntry])? {
        guard isToday else { return nil }
        let now = ScreenshotFlags.now
        let logged = entries.map { UsualMeal.Logged(date: $0.date, meal: $0.meal, foodID: $0.foodID) }
        guard let found = UsualMeal.find(in: logged, now: now),
              found.dismissalKey(on: now) != usualDismissed else { return nil }
        let calendar = Calendar.current
        let items = entries.filter { $0.meal == found.meal && calendar.isDate($0.date, inSameDayAs: found.lastDay) }
        return items.isEmpty ? nil : (meal: found, entries: items)
    }

    /// Saved foods that fit what is left first; protein-dense first when protein is behind.
    private var shelfOrder: [SavedFood] {
        let left = budget - totals.kcal
        guard isToday, left > 0 else { return saved }
        let proteinBehind = targets.protein - totals.protein > 20
        return saved.sorted { a, b in
            let fitsA = a.totals.kcal <= left
            let fitsB = b.totals.kcal <= left
            if fitsA != fitsB { return fitsA }
            if proteinBehind {
                return a.totals.protein / max(a.totals.kcal, 1) > b.totals.protein / max(b.totals.kcal, 1)
            }
            return a.sortIndex < b.sortIndex
        }
    }

    /// Dishes people counted nearby, nearest first; without location, the ones at your places.
    private var nearby: [NearbyDishes.Item] {
        let items = dishes.map { NearbyDishes.Item(dish: $0, distance: placeFinder.distance(to: $0.place)) }
        let close = items.filter { ($0.distance ?? 0) < 3000 }
        let sorted = close.sorted {
            ($0.distance ?? .infinity, -$0.dish.consensus.accuracy) < ($1.distance ?? .infinity, -$1.dish.consensus.accuracy)
        }
        return Array(sorted.prefix(8))
    }

    /// The last seven days, today last, each with its verdict.
    private var weekDays: [WeekStrip.Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let todays = entries.filter { calendar.isDate($0.date, inSameDayAs: today) }
        let todayKcal = todays.reduce(0) { $0 + $1.totals.kcal }
        let todayVerdict = DayVerdict(kcal: todayKcal, entries: todays.count, goal: Double(goalKcal))
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return WeekStrip.Day(date: date, verdict: offset == 0 ? todayVerdict : verdicts[date] ?? .empty)
        }
    }

    /// Your weighings from Health; else the weight you gave the goal calculator, as today's.
    private var trendWeights: [WeightPoint] {
        if !weights.isEmpty { return weights }
        guard UserDefaults.standard.object(forKey: "body.weight") != nil else { return [] }
        return [WeightPoint(date: .now, kilograms: bodyWeight)]
    }

    /// What your body really burns, once two weeks of weighings and meals can say.
    private var learned: LearnedMaintenance? {
        let kcals = Dictionary(summaries.map { ($0.day, $0.kcal) }, uniquingKeysWith: { a, _ in a })
        return LearnedMaintenance.learn(
            weighings: weights.map { LearnedMaintenance.Weighing(date: $0.date, kilograms: $0.kilograms) },
            dayKcals: kcals,
            now: .now
        )
    }

    /// A daily goal from what you really burn, offered when it is 50 kcal or more from yours.
    private func suggestedGoal(from learned: LearnedMaintenance?) -> Int? {
        guard let learned else { return nil }
        let goal = learned.goal(for: WeightGoal(rawValue: weightGoalRaw) ?? .maintain, sex: Sex(rawValue: sexRaw) ?? .female)
        return abs(goal - goalKcal) >= 50 ? goal : nil
    }

    private func useGoal(_ kcal: Int) {
        withAnimation(.snappy) { goalKcal = kcal }
    }

    /// Where your weight goes at the way you ate over the last week's whole days, against what
    /// your body burns: learned when it can be, else worked out from your body.
    private func forecast(learned: LearnedMaintenance?) -> WeightForecast? {
        guard let current = WeightForecast.trend(trendWeights.map(\.kilograms)).last else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let kcals: [Double] = (1...7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return entries.filter { calendar.isDate($0.date, inSameDayAs: date) }.reduce(0) { $0 + $1.totals.kcal }
        }
        let maintenance = learned?.kcal ?? GoalCalculator.maintenance(
            sex: Sex(rawValue: sexRaw) ?? .female,
            age: bodyAge,
            heightCm: Double(bodyHeight),
            weightKg: current,
            activity: Activity(rawValue: activityRaw) ?? .light
        )
        return WeightForecast.make(currentKg: current, maintenance: maintenance, dayKcals: kcals)
    }

    private var summaries: [DaySummary] {
        InsightsData.summaries(of: entries)
    }

    private var verdicts: [Date: DayVerdict] {
        var result: [Date: DayVerdict] = [:]
        for summary in summaries {
            result[summary.day] = DayVerdict(kcal: summary.kcal, entries: summary.entries, goal: Double(goalKcal))
        }
        return result
    }

    /// What the switcher shows, as one value the haptic can watch.
    private var selectionKey: String {
        "\(tab.rawValue) \(day.timeIntervalSince1970)"
    }

    /// Today, inside 90 to 105% of the goal.
    private var isOnTargetToday: Bool {
        Calendar.current.isDateInToday(day)
            && DayVerdict(kcal: totals.kcal, entries: dayEntries.count, goal: budget).isOnTarget
    }

    /// The streak, on today only and from two days.
    private var streakToShow: Int? {
        guard Calendar.current.isDateInToday(day) else { return nil }
        let streak = Insights.streak(summaries, goal: Double(goalKcal), today: .now)
        return streak >= 2 ? streak : nil
    }

    private var healthState: HealthState {
        guard HealthActivity.isAvailable else { return .unavailable }
        guard healthAsked else { return .notConnected }
        return .connected(activity ?? DayActivity(steps: 0, activeKcal: 0))
    }

    private func loadCoverPhotos() {
        let previous = coverPhotos.count
        coverPhotos = photoEntries.compactMap { entry in
            guard let data = entry.imageData, let image = UIImage(data: data) else { return nil }
            return CoverPhoto(id: AnyHashable(entry.persistentModelID), image: image, dish: entry.name, place: entry.place)
        }
        // A new photo comes to the front; a removed one never leaves the cover past its end.
        if coverPhotos.count > previous, previous > 0 { coverIndex = 0 }
        if coverIndex >= coverPhotos.count { coverIndex = 0 }
    }

    private func loadWeights() async {
        #if DEBUG
        if BiteStore.isDemo {
            weights = DemoData.weights()
            return
        }
        #endif
        guard healthAsked, weightAsked, HealthActivity.isAvailable else {
            weights = []
            return
        }
        weights = await HealthActivity.shared.weights()
    }

    private func addWater() {
        if let waterDay {
            waterDay.glasses += 1
        } else {
            context.insert(WaterDay(day: Calendar.current.startOfDay(for: day), glasses: 1))
        }
        try? context.save()
    }

    private func removeWater() {
        guard let waterDay, waterDay.glasses > 0 else { return }
        waterDay.glasses -= 1
        try? context.save()
    }

    // MARK: Actions

    private func add(_ item: SavedFood) {
        let meal = item.meal ?? Meal.likely()
        let entry = FoodEntry(food: item.food, amount: item.amount, meal: meal, date: FoodDetailView.logDate(for: day))
        context.insert(entry)
        item.timesAdded += 1
        try? context.save()
        events.added(entry)
    }

    /// The same foods again, now, in the same meals: yesterday's lunch as today's.
    private func addToToday(_ items: [FoodEntry]) {
        let now = Date.now
        let copies = items.map { FoodEntry(food: $0.food, amount: $0.amount, meal: $0.meal, date: now) }
        withAnimation(.snappy) {
            for copy in copies {
                context.insert(copy)
            }
            try? context.save()
        }
        events.added(copies)
    }

    /// A meal moved to another time on the same day.
    private func move(_ items: [FoodEntry], to time: Date) {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        withAnimation(.snappy) {
            for item in items {
                item.date = calendar.date(bySettingHour: parts.hour ?? 12, minute: parts.minute ?? 0, second: 0, of: item.date) ?? item.date
            }
            try? context.save()
        }
    }

    /// Takes the last change back: an add is removed, a delete comes back as it was.
    private func undo(_ event: LogEvents.Event) {
        withAnimation(.snappy) {
            switch event.change {
            case .added(let entries):
                for entry in entries where !entry.isDeleted {
                    context.delete(entry)
                }
            case .deleted(let snapshots):
                for snapshot in snapshots {
                    context.insert(FoodEntry(food: snapshot.food, amount: snapshot.amount, meal: snapshot.meal, date: snapshot.date))
                }
            }
            try? context.save()
        }
        events.dismiss()
    }

    private func save(_ food: Food, amount: Double, meal: Meal?) {
        let item = SavedFood(food: food, amount: amount, sortIndex: (saved.map(\.sortIndex).max() ?? 0) + 1)
        item.meal = meal
        context.insert(item)
        try? context.save()
    }

    /// The whole meal as one saved item, then straight into the editor to name it.
    private func saveMeal(_ meal: Meal, _ items: [FoodEntry]) {
        let total = items.reduce(Nutrients.zero) { $0 + $1.totals }
        let first = items.first?.food
        let food = Food(
            id: "meal:\(UUID().uuidString)",
            name: meal.savedTitle,
            emoji: first?.emoji ?? "🍽️",
            source: .manual,
            unit: .serving,
            per: 1,
            nutrients: total,
            tint: first?.displayTint
        )
        let item = SavedFood(food: food, amount: 1, sortIndex: (saved.map(\.sortIndex).max() ?? 0) + 1)
        item.meal = meal
        item.subtitle = items.map(\.name).joined(separator: ", ")
        context.insert(item)
        try? context.save()
        sheet = .editSaved(item)
    }

    private func removeSaved(_ item: SavedFood) {
        withAnimation(.snappy) { context.delete(item) }
    }

    private func connectHealth() {
        Task {
            await HealthActivity.shared.requestAccess()
            healthAsked = true
            weightAsked = true
        }
    }

    /// Weight from Apple Health when there is Health; else the goal calculator in Settings.
    private func addWeight() {
        guard HealthActivity.isAvailable else {
            sheet = .settings
            return
        }
        Task {
            await HealthActivity.shared.requestAccess()
            healthAsked = true
            weightAsked = true
        }
    }

    private func loadActivity() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            activity = DemoData.activity(on: day)
            return
        }
        #endif
        guard healthAsked, HealthActivity.isAvailable else {
            activity = nil
            return
        }
        activity = await HealthActivity.shared.activity(on: day)
    }

    /// Gone at once, with Undo in the toast instead of an "are you sure?".
    private func delete(_ entry: FoodEntry) {
        let snapshot = LogEvents.Snapshot(entry)
        withAnimation(.snappy) {
            context.delete(entry)
            try? context.save()
        }
        events.deleted([snapshot])
    }

    private func deletePending() {
        guard let entry = deleting else { return }
        deleting = nil
        delete(entry)
    }

    #if DEBUG
    /// `-screen food|plate|search|settings|scanner|photo|estimate|edit|saved|week|month|yesterday|over`
    /// `|place|dish|addestimate|accuracy|where|cover2` opens a screen straight away, for
    /// screenshots. `over` is the demo's heaviest day, three days back: four digit calories,
    /// past the goal, carbs and fat past their targets.
    private func openDemoScreen() {
        switch UserDefaults.standard.string(forKey: "screen") {
        case "food": editing = dayEntries.first { $0.imageURLString != nil } ?? dayEntries.first
        case "search": sheet = .search(nil)
        case "settings": sheet = .settings
        case "scanner", "photo", "estimate": showScanner = true
        case "edit": editing = dayEntries.last
        case "plate": editing = dayEntries.first { $0.imageData != nil }
        case "saved": if let first = saved.first { sheet = .editSaved(first) }
        case "week": tab = .week
        case "month": tab = .month
        case "yesterday": day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
        case "over": day = Calendar.current.date(byAdding: .day, value: -3, to: day) ?? day
        case "place", "dish", "addestimate", "accuracy":
            if let first = dishes.first { sheet = .place(first.place) }
        case "where": editing = dayEntries.first { $0.place != nil } ?? dayEntries.last
        case "cover2": coverIndex = 1
        default: break
        }
    }
    #endif
}

/// Launch arguments that set screens up for screenshots. Release builds ignore them.
enum ScreenshotFlags {
    /// Now, or today at the time `-clock 19:30` sets, so a card that waits for its hour can be
    /// shot at any time of day.
    static var now: Date {
        #if DEBUG
        if let text = UserDefaults.standard.string(forKey: "clock") {
            let parts = text.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2, let date = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: .now) {
                return date
            }
        }
        #endif
        return .now
    }

    /// `-anchor bottom` opens a long page scrolled to its end, `-anchor center` halfway.
    static var scrollAnchor: UnitPoint? {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "anchor") {
        case "bottom": return .bottom
        case "center": return .center
        default: return nil
        }
        #else
        return nil
        #endif
    }
}

/// The menu behind the day's name: today and the six days before it, then the last 7 and 30
/// days.
struct HomeSwitcher<Label: View>: View {
    @Binding var selection: HomeSelection
    let days: [Date]
    @ViewBuilder let label: Label

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                ForEach(days, id: \.self) { day in
                    Text(TodayView.name(of: day)).tag(HomeSelection.day(day))
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
            Picker(selection: $selection) {
                Text("Last 7 days").tag(HomeSelection.week)
                Text("Last 30 days").tag(HomeSelection.month)
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            label
        }
        .menuOrder(.fixed)
        .accessibilityHint("Shows another day, or your last 7 or 30 days")
    }
}

/// Paper fading in under the status bar, so content scrolled up never runs into the time.
private struct TopFade: View {
    let height: CGFloat

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Theme.page, location: 0),
                .init(color: Theme.page, location: 0.65),
                .init(color: Theme.page.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Nothing logged yet: the scan glyph and one line.
private struct EmptyDay: View {
    let isToday: Bool
    let onScan: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ScanGlyph(color: Theme.ink, animated: isToday)
                .frame(width: 30, height: 26)
                .frame(width: 76, height: 76)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: FoodThumb.radius(for: 76), style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(isToday ? "Scan a barcode or snap your plate to log your first bite." : "Nothing logged this day.")
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if isToday {
                    Button("Scan food", action: onScan)
                        .font(.ui(15, .semibold))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    TodayView()
        .modelContainer(DemoData.container())
        .environment(LogEvents())
        .environment(AppActions.shared)
}
#endif
