import SwiftUI
import SwiftData
import Combine
import UIKit

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

    var id: Self { self }
}

/// Home: the day under your latest meal photo, its macros, your meals and saved foods, with
/// the scan dock; or your last 7 or 30 days.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(LogEvents.self) private var events
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Query private var entries: [FoodEntry]
    @Query(sort: \SavedFood.sortIndex) private var saved: [SavedFood]

    @AppStorage("goal.kcal") private var goalKcal = 2000
    @AppStorage("goal.split") private var splitRaw = MacroSplit.balanced.rawValue
    @AppStorage("health.asked") private var healthAsked = false
    @AppStorage("health.addBurned") private var addBurned = false

    @State private var tab: HomeTab = .today
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var sheet: HomeSheet?
    @State private var showScanner = false
    @State private var editing: FoodEntry?
    @State private var deleting: FoodEntry?
    @State private var activity: DayActivity?
    @State private var activityRefresh = 0
    @State private var cover: (id: PersistentIdentifier, image: UIImage)?
    @State private var coverOnScreen = true
    @Namespace private var zoom

    /// How far back home reads the log: a month for the ranges, and the month before it so
    /// they can show how things moved.
    static let daysBack = 62

    init() {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -Self.daysBack, to: calendar.startOfDay(for: .now)) ?? .distantPast
        _entries = Query(filter: #Predicate<FoodEntry> { $0.date >= start }, sort: \FoodEntry.date)
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
                bottomStack
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // A photo cover runs to the top edge, where the time would sit dark on the picture.
        .statusBarHidden(tab == .today && cover != nil && coverOnScreen && colorScheme == .light)
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
        .task(id: coverEntry?.persistentModelID) {
            loadCover()
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
        let photo = cover?.image
        return ScrollView {
            VStack(spacing: 0) {
                DayCover(
                    photo: photo,
                    height: topInset + (photo == nil ? 290 : 371),
                    topInset: topInset,
                    number: hero.number,
                    unit: hero.unit,
                    caption: heroCaption,
                    detail: String(localized: "Goal \(budget.kcalText)")
                ) {
                    coverControls(onPhoto: photo != nil)
                }
                .onGeometryChange(for: Bool.self) { geometry in
                    geometry.frame(in: .scrollView).maxY > 120
                } action: { onScreen in
                    coverOnScreen = onScreen
                }

                daySheet
                    .padding(.top, -26)
            }
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(ScreenshotFlags.scrollAnchor)
        .ignoresSafeArea(edges: .top)
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
            Spacer(minLength: 8)
            if let streak = streakToShow {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.energy)
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
            ActivityChips(health: healthState, onConnect: connectHealth)
                .padding(.top, 16)

            SectionLabel(title: "Your day")
                .padding(.top, 26)
                .padding(.bottom, 14)
            if dayEntries.isEmpty {
                EmptyDay(isToday: Calendar.current.isDateInToday(day)) { showScanner = true }
            } else {
                DayTimeline(
                    entries: dayEntries,
                    onSelect: { editing = $0 },
                    onSave: { save($0.food, amount: $0.amount, meal: $0.meal) },
                    onDelete: delete,
                    onAddHere: { sheet = .search($0) },
                    onSaveMeal: saveMeal
                )
            }

            SavedShelf(
                saved: saved,
                onAdd: add,
                onEdit: { sheet = .editSaved($0) },
                onDelete: removeSaved,
                onNew: { sheet = .newSaved }
            )
            .padding(.top, 30)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 22)
        .padding(.bottom, 140)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.page,
            in: UnevenRoundedRectangle(topLeadingRadius: Theme.sheetRadius, topTrailingRadius: Theme.sheetRadius, style: .continuous)
        )
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
            if let added = events.lastAdded {
                AddedToast(added: added)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { events.dismiss() }
                    .task(id: added.id) {
                        try? await Task.sleep(for: .seconds(2.6))
                        if events.lastAdded?.id == added.id { events.dismiss() }
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
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: events.lastAdded)
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

    /// The day's latest photo: a plate Claude estimated or a saved food with your picture.
    private var coverEntry: FoodEntry? {
        dayEntries.last { $0.imageData != nil }
    }

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

    /// Under the number: the photo's meal, or the last thing you ate; a past day's verdict.
    private var heroCaption: String? {
        if !Calendar.current.isDateInToday(day) {
            return verdicts[day]?.label
        }
        if cover != nil, let name = coverEntry?.name {
            return name
        }
        return dayEntries.last.map { String(localized: "Last meal: \($0.name)") }
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

    private func loadCover() {
        guard let entry = coverEntry, let data = entry.imageData, let image = UIImage(data: data) else {
            cover = nil
            return
        }
        cover = (id: entry.persistentModelID, image: image)
    }

    // MARK: Actions

    private func add(_ item: SavedFood) {
        let meal = item.meal ?? Meal.likely()
        let food = item.food
        context.insert(FoodEntry(food: food, amount: item.amount, meal: meal, date: FoodDetailView.logDate(for: day)))
        item.timesAdded += 1
        try? context.save()
        events.added(food, amount: item.amount, meal: meal)
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

    private func delete(_ entry: FoodEntry) {
        withAnimation(.snappy) { context.delete(entry) }
    }

    private func deletePending() {
        guard let entry = deleting else { return }
        deleting = nil
        delete(entry)
    }

    #if DEBUG
    /// `-screen food|plate|search|settings|scanner|photo|estimate|edit|saved|week|month|yesterday`
    /// opens a screen straight away, for screenshots.
    private func openDemoScreen() {
        switch UserDefaults.standard.string(forKey: "screen") {
        case "food": editing = dayEntries.first
        case "search": sheet = .search(nil)
        case "settings": sheet = .settings
        case "scanner", "photo", "estimate": showScanner = true
        case "edit": editing = dayEntries.last
        case "plate": editing = dayEntries.first { $0.imageData != nil }
        case "saved": if let first = saved.first { sheet = .editSaved(first) }
        case "week": tab = .week
        case "month": tab = .month
        case "yesterday": day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
        default: break
        }
    }
    #endif
}

/// Launch arguments that set screens up for screenshots. Release builds ignore them.
enum ScreenshotFlags {
    /// `-anchor bottom` opens a long page scrolled to its end.
    static var scrollAnchor: UnitPoint? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "anchor") == "bottom" ? .bottom : nil
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
}
#endif
