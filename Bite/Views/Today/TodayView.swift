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

    var title: LocalizedStringKey {
        switch self {
        case .today: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }
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

/// Home: today's calories and meals with the scan dock, or your week and month.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(LogEvents.self) private var events
    @Environment(\.scenePhase) private var scenePhase
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
    @Namespace private var zoom

    init() {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -WeekPager.daysBack, to: calendar.startOfDay(for: .now)) ?? .distantPast
        _entries = Query(filter: #Predicate<FoodEntry> { $0.date >= start }, sort: \FoodEntry.date)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: Theme.gap) {
                    header
                    switch tab {
                    case .today:
                        todayContent
                    case .week:
                        InsightsView(range: .week, entries: entries, goal: Double(goalKcal), targets: targets)
                    case .month:
                        InsightsView(range: .month, entries: entries, goal: Double(goalKcal), targets: targets)
                    }
                }
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 140)
            }
            .scrollIndicators(.hidden)

            bottomStack
        }
        .background(Theme.page.ignoresSafeArea())
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
        .onChange(of: scenePhase) { _, phase in
            // Back from a walk: pick up the new steps.
            if phase == .active { activityRefresh += 1 }
        }
        #if DEBUG
        .onAppear(perform: openDemoScreen)
        #endif
    }

    // MARK: Header and tabs

    private var header: some View {
        HStack(spacing: 10) {
            Picker("Show", selection: $tab.animation(.snappy)) {
                ForEach(HomeTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 228)
            Spacer()
            CircleIconButton(systemImage: "gearshape", label: "Settings") { sheet = .settings }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private var todayContent: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.ui(32, .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            if let chip = dayChip {
                TintChip(title: chip.title, style: chip.style, systemImage: chip.symbol, iconColor: chip.iconColor)
            }
            if !Calendar.current.isDateInToday(day) {
                Button("Today") {
                    withAnimation(.snappy) { day = Calendar.current.startOfDay(for: .now) }
                }
                .buttonStyle(ChipButtonStyle(isSelected: false))
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)

        WeekPager(selection: $day, verdicts: verdicts)

        DayCard(totals: totals, goal: budget, targets: targets, health: healthState, onConnectHealth: connectHealth)

        SavedShelf(
            saved: saved,
            onAdd: add,
            onEdit: { sheet = .editSaved($0) },
            onDelete: removeSaved,
            onNew: { sheet = .newSaved }
        )
        .padding(.top, 8)

        if dayEntries.isEmpty {
            EmptyDayCard(isToday: Calendar.current.isDateInToday(day)) { showScanner = true }
        } else {
            ForEach(Meal.allCases) { meal in
                let items = dayEntries.filter { $0.meal == meal }
                if !items.isEmpty {
                    MealCard(
                        meal: meal,
                        entries: items,
                        onSelect: { editing = $0 },
                        onSave: { save($0.food, amount: $0.amount, meal: $0.meal) },
                        onDelete: delete,
                        onAddHere: { sheet = .search(meal) },
                        onSaveMeal: { saveMeal(meal, items) }
                    )
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
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private var dayEntries: [FoodEntry] {
        let calendar = Calendar.current
        return entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
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

    /// A streak for today, the verdict for a past day.
    private var dayChip: (title: String, style: TintChip.Style, symbol: String, iconColor: Color?)? {
        if Calendar.current.isDateInToday(day) {
            let streak = Insights.streak(summaries, goal: Double(goalKcal), today: .now)
            guard streak >= 2 else { return nil }
            return (title: String(localized: "\(streak)-day streak"), style: .neutral, symbol: "flame.fill", iconColor: Theme.energy)
        }
        let verdict = verdicts[day] ?? .empty
        guard let label = verdict.label else { return nil }
        return (title: label, style: verdict.chipStyle, symbol: verdict.symbol, iconColor: nil)
    }

    private var healthState: HealthState {
        guard HealthActivity.isAvailable else { return .unavailable }
        guard healthAsked else { return .notConnected }
        return .connected(activity ?? DayActivity(steps: 0, activeKcal: 0))
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
    /// `-screen food|search|settings|scanner|photo|estimate|edit|saved|week|month` opens a
    /// screen straight away, for screenshots.
    private func openDemoScreen() {
        switch UserDefaults.standard.string(forKey: "screen") {
        case "food": editing = dayEntries.first
        case "search": sheet = .search(nil)
        case "settings": sheet = .settings
        case "scanner", "photo", "estimate": showScanner = true
        case "edit": editing = dayEntries.last
        case "saved": if let first = saved.first { sheet = .editSaved(first) }
        case "week": tab = .week
        case "month": tab = .month
        default: break
        }
    }
    #endif
}

/// Nothing logged yet: the scan glyph, one line, and the way in.
private struct EmptyDayCard: View {
    let isToday: Bool
    let onScan: () -> Void

    var body: some View {
        Card(padding: 24) {
            VStack(spacing: 14) {
                ScanGlyph(color: Theme.ink)
                    .frame(width: 40, height: 34)
                    .frame(width: 72, height: 72)
                    .background(Theme.inset, in: Circle())
                Text(isToday ? "Scan a barcode or snap your plate to log your first bite." : "Nothing logged this day.")
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                if isToday {
                    Button("Scan food", action: onScan)
                        .buttonStyle(SoftButtonStyle())
                }
            }
            .frame(maxWidth: .infinity)
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
