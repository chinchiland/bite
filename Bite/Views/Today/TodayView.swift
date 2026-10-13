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
    case food(Food)
    case firstRun(FirstRunSheet.Step)
    /// Your mirror; true to open straight on its camera.
    case mirror(Bool)

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
    /// Health refused to ask, as in a copy signed without the Health capability.
    @AppStorage("health.unavailable") private var healthUnavailable = false
    @AppStorage("body.sex") private var sexRaw = Sex.female.rawValue
    @AppStorage("body.age") private var bodyAge = 30
    @AppStorage("body.height") private var bodyHeight = 170
    @AppStorage("body.weight") private var bodyWeight = 70.0
    @AppStorage("body.activity") private var activityRaw = Activity.light.rawValue
    @AppStorage("body.goal") private var weightGoalRaw = WeightGoal.maintain.rawValue
    @AppStorage("water.goal") private var waterGoal = 8
    /// "Not today" on your usual meal: that day and meal, so tomorrow it comes back.
    @AppStorage("usual.dismissed") private var usualDismissed = ""
    /// "Not now" on the learned goal: hidden for a week, then offered again if it still differs.
    /// When the weekly check-in shows and what you answered, as JSON.
    @AppStorage("checkin.history") private var checkInHistoryData = Data()
    /// "No target": Bite counts and shows the pattern, with no budget to stay under.
    @AppStorage("goal.noTarget") private var noTarget = false
    @AppStorage("firstRun.stage") private var firstRunRaw = FirstRun.done.rawValue
    /// The day the welcome's Start was tapped: day one.
    @AppStorage("firstRun.day") private var firstRunDay = 0.0
    /// "Start tomorrow" was chosen: the journal begins that day.
    @AppStorage("firstRun.startsOn") private var firstRunStartsOn = 0.0
    /// The mealtime nudge was offered and answered, either way.
    @AppStorage("reminder.answered") private var reminderAnswered = false
    /// When your mirror asks for a photo and what you said, as JSON.
    @AppStorage("mirror.history") private var mirrorHistoryData = Data()

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
    /// True for a moment while the clock or code moves the day or the cover: no tick then.
    @State private var movedByCode = false
    /// The day today last landed on target through a log, so it is celebrated once.
    @AppStorage("celebrated.day") private var celebratedDay = 0.0
    @State private var celebrations = 0
    /// The last day Bite was opened, so the switcher tip counts days, not launches.
    @AppStorage("tips.openedDay") private var openedDay = 0.0
    @State private var chrome = CoverChrome()
    /// The top inset with the status bar showing. Hiding the status bar on an iPhone with a
    /// Home button takes the inset to 0, which would make the cover 20 pt shorter and move the
    /// page each time the bar shows or hides.
    @State private var steadyTopInset: CGFloat = 0
    /// The first run's own sheet is up, so closing it ends the first run.
    @State private var firstRunSheetUp = false
    /// Scan was chosen in a sheet: the scanner opens once that sheet has gone.
    @State private var scanAfterSheet = false
    @State private var weights: [WeightPoint] = []
    @State private var placeFinder = PlaceFinder()
    @Namespace private var zoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            let topInset = max(proxy.safeAreaInsets.top, steadyTopInset)
            ZStack(alignment: .bottom) {
                Theme.page.ignoresSafeArea()
                switch tab {
                case .today:
                    dayPage(topInset: topInset)
                case .week:
                    rangePage(.week)
                case .month:
                    rangePage(.month)
                }
                TopChrome(
                    chrome: chrome,
                    height: topInset,
                    onDay: tab == .today,
                    photoCover: !coverPhotos.isEmpty && colorScheme == .light
                )
                toast
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dockBar {
                ScanDock(
                    namespace: zoom,
                    onSearch: { sheet = .search(nil) },
                    onScan: { showScanner = true },
                    onQuickAdd: { sheet = .quickAdd }
                )
                // With no Home indicator below it (an iPhone with a Home button), the dock
                // keeps clear of the bottom edge.
                .padding(.bottom, proxy.safeAreaInsets.bottom > 0 ? 4 : 12)
            }
            .onAppear { steadyTopInset = max(steadyTopInset, proxy.safeAreaInsets.top) }
            .onChange(of: proxy.safeAreaInsets.top) { _, top in steadyTopInset = max(steadyTopInset, top) }
        }
        .fullScreenCover(isPresented: $showScanner, onDismiss: continueFirstRun) {
            ScannerView(day: day)
                .zoomTransition(id: "scan", in: zoom)
        }
        .sheet(item: $sheet, onDismiss: sheetClosed) { sheet in
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
            // The tile you tapped grows into its page and shrinks back into its place.
            .zoomTransition(id: entry.persistentModelID, in: zoom)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            quietly { day = Calendar.current.startOfDay(for: .now) }
        }
        .task(id: "\(day.timeIntervalSince1970) \(activityRefresh) \(healthAsked)") {
            await loadActivity()
        }
        .task(id: dayEntries.map(\.persistentModelID)) {
            await loadCoverPhotos()
        }
        .task(id: "\(healthAsked) \(weightAsked) \(activityRefresh)") {
            await loadWeights()
            startCheckInDayIfNeeded()
        }
        .task {
            await placeFinder.locateIfAllowed()
            if let here = placeFinder.here {
                await CommunitySync.pullNear(here, context: context)
            }
        }
        .onChange(of: day) { _, _ in
            quietly { coverIndex = 0 }
        }
        // A tick under the finger when you switch, never when the clock does; and once a day,
        // when a log takes today onto target, success as the food settles.
        .sensoryFeedback(trigger: selectionKey) { _, _ in movedByCode ? nil : Feel.tick }
        .onChange(of: selectionKey) { _, _ in
            guard !movedByCode else { return }
            DaySwitcherTip().invalidate(reason: .actionPerformed)
        }
        .onChange(of: events.last?.id) { _, _ in
            celebrateIfEarned()
            // The first food came in by scan or search: the goal comes next.
            if firstRun == .awaitingLog, case .added? = events.last?.change {
                firstRunRaw = FirstRun.goal.rawValue
            }
        }
        .onChange(of: firstRunRaw, initial: true) { _, _ in continueFirstRun() }
        .sensoryFeedback(Feel.reached, trigger: celebrations)
        // Siri, Spotlight or the Action button asked to scan.
        .onChange(of: actions.pendingScan, initial: true) { _, pending in
            guard pending else { return }
            actions.pendingScan = false
            showScanner = true
        }
        .task {
            let today = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
            guard openedDay != today else { return }
            openedDay = today
            await DaySwitcherTip.openedOnDay.donate()
        }
        .task(id: saved.map(\.foodID)) {
            BiteShortcuts.updateAppShortcutParameters()
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from a walk: pick up the new steps, and whether your mirror is due.
            if phase == .active {
                activityRefresh += 1
                MirrorLog.shared.refresh()
            }
        }
        .task { MirrorLog.shared.refresh() }
        #if DEBUG
        .onAppear(perform: openDemoScreen)
        #endif
    }

    // MARK: Day

    private static let coverAnchor = "cover"

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
                        greetingNote: isFirstDay ? String(localized: "Your first page") : nil,
                        detail: heroDetail.text,
                        detailIsOver: heroDetail.isOver,
                        onPlace: { sheet = .place($0) },
                        quietPaging: movedByCode
                    ) {
                        coverControls(onPhoto: hasPhoto || colorScheme == .dark)
                    }
                    .onGeometryChange(for: Bool.self) { geometry in
                        geometry.frame(in: .scrollView).maxY > 120
                    } action: { onScreen in
                        chrome.onScreen = onScreen
                    }
                    .id(Self.coverAnchor)

                    daySheet
                }
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(ScreenshotFlags.scrollAnchor)
            .ignoresSafeArea(edges: .top)
            // Another day opens on its cover and number, not wherever the last one was left.
            .onChange(of: day) { _, _ in
                reader.scrollTo(Self.coverAnchor, anchor: .top)
            }
            #if DEBUG
            .task {
                // `-anchor usual` scrolls your usual meal into the middle, `-anchor mirror` your
                // mirror's ask, for their screenshots.
                let anchor = UserDefaults.standard.string(forKey: "anchor")
                guard anchor == "usual" || anchor == "mirror" else { return }
                try? await Task.sleep(for: .seconds(1))
                reader.scrollTo(anchor == "usual" ? UsualMoment.anchor : MirrorMoment.anchor, anchor: .center)
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
                        .minimumScaleFactor(0.8)
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
                        .minimumScaleFactor(0.8)
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
                overflow: noTarget ? 0 : ring.overflow,
                number: totals.kcal,
                unit: "kcal eaten",
                glint: celebrations,
                fiber: fiberToShow,
                fiberTarget: FiberTarget.grams(forGoal: Double(goalKcal)),
                aimOnly: isToday && dayEntries.isEmpty
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

            if let ask = mirrorAsk {
                MirrorMoment(
                    kind: ask,
                    onOpen: { sheet = .mirror(false) },
                    onTake: { sheet = .mirror(true) },
                    onNotNow: mirrorNotNow
                )
                .padding(.top, 18)
                .transition(.opacity)
                .id(MirrorMoment.anchor)
            }

            if isToday, !entries.isEmpty {
                let learned = self.learned
                let checkIn = dueCheckIn
                WeightTrend(
                    weights: trendWeights,
                    forecast: forecast(learned: learned),
                    goal: WeightGoal(rawValue: weightGoalRaw) ?? .maintain,
                    learned: learned,
                    checkIn: checkIn,
                    onUseCheckIn: { if let checkIn { useCheckIn(checkIn) } },
                    onKeepCheckIn: { if let checkIn { keepCheckIn(checkIn) } },
                    goalSet: checkInHistory.canUndo(now: .now) ? goalKcal : nil,
                    onUndoGoal: undoCheckIn,
                    onAddWeight: addWeight
                )
                .padding(.top, 28)
            }

            SectionLabel(title: "Your day", symbol: "fork.knife")
                .padding(.top, 26)
                .padding(.bottom, 14)
            let usual = self.usual
            // Every add, delete and Undo settles in, wherever it came from; the first food of
            // the day replaces the empty line instead of jumping in under it.
            VStack(alignment: .leading, spacing: 0) {
                if dayEntries.isEmpty, usual == nil {
                    EmptyDay(
                        isToday: Calendar.current.isDateInToday(day),
                        startsTomorrow: startsTomorrow,
                        foods: hourFoods,
                        onFood: { sheet = .food($0) }
                    )
                    .transition(.opacity)
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
                        onMoveTime: move,
                        zoom: zoom
                    )
                    .transition(.opacity.combined(with: .offset(y: 8)))
                    if let offer = reminderOffer {
                        ReminderOffer(reminder: offer) {
                            Task {
                                _ = await Reminders.turnOn(offer, context: context)
                                withAnimation(Motion.settle) { reminderAnswered = true }
                            }
                        } onNotNow: {
                            withAnimation(Motion.settle) { reminderAnswered = true }
                        }
                        .padding(.top, 14)
                        .transition(.opacity)
                    }
                    if isFirstDay {
                        // Day one's next step, in place of a tip.
                        Text("Hold a food to add it again, or scan your next meal.")
                            .font(.ui(15))
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 68)
                            .padding(.top, 2)
                            .transition(.opacity)
                    }
                }
                if let usual {
                    UsualMoment(
                        question: usual.meal.question,
                        entries: usual.entries,
                        time: usual.meal.time(on: day),
                        onAdd: { addToToday(usual.entries) },
                        onDismiss: { withAnimation(Motion.settle) { usualDismissed = usual.meal.dismissalKey(on: day) } }
                    )
                    .padding(.top, dayEntries.isEmpty ? 0 : 14)
                    .transition(.opacity)
                    .id(UsualMoment.anchor)
                }
            }
            .animation(reduceMotion ? nil : Motion.settle, value: dayEntries.map(\.persistentModelID))

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
        .padding(.bottom, 24)
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

    // MARK: Toast

    /// What you just did, resting on the dock: the page's safe area already ends at the dock.
    private var toast: some View {
        VStack(spacing: 0) {
            if let event = events.last {
                EventToast(event: event) { undo(event) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: event.id) {
                        // Long enough to reach Undo, short enough to stay out of the way.
                        try? await Task.sleep(for: .seconds(4))
                        if events.last?.id == event.id { events.dismiss() }
                    }
            }
        }
        .padding(.bottom, 12)
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
        case .food(let food):
            NavigationStack {
                FoodDetailView(food: food, day: day, onDone: { self.sheet = nil })
            }
            .presentationDragIndicator(.visible)
        case .firstRun(let step):
            FirstRunSheet(
                startAt: step,
                day: day,
                onScan: {
                    firstRunRaw = FirstRun.awaitingLog.rawValue
                    firstRunSheetUp = false
                    // The scanner opens once the sheet has gone, in sheetClosed.
                    scanAfterSheet = true
                    self.sheet = nil
                },
                onSearch: {
                    firstRunRaw = FirstRun.awaitingLog.rawValue
                    firstRunSheetUp = false
                    self.sheet = .search(nil)
                },
                onGoal: { firstRunRaw = FirstRun.goal.rawValue },
                onFinished: {
                    firstRunRaw = FirstRun.done.rawValue
                    self.sheet = nil
                }
            )
            .onAppear { firstRunSheetUp = true }
        case .mirror(let camera):
            NavigationStack {
                MirrorHome(startOnCamera: camera)
            }
            .modelContainer(MirrorStore.container)
        }
    }

    // MARK: First run

    private var firstRun: FirstRun { FirstRun(rawValue: firstRunRaw) ?? .done }

    /// The nudge, offered once after the second log, at the first meal's time.
    private var reminderOffer: MealReminder? {
        guard isToday, !reminderAnswered, !BiteStore.isDemo,
              MealReminder.shouldOffer(entries: entries.count, answered: reminderAnswered),
              let first = entries.first else { return nil }
        return MealReminder(firstLog: first.date, meal: first.meal)
    }

    /// Four foods for this hour, for the empty day.
    private var hourFoods: [Food] {
        let basics = Dictionary(BasicFoods.all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return HourFoods.foodIDs(at: .now).prefix(4).compactMap { basics[$0] }
    }

    /// Day one, the day Start was tapped, while it is still that day.
    private var isFirstDay: Bool {
        isToday && firstRunDay > 0 && Calendar.current.isDate(Date(timeIntervalSince1970: firstRunDay), inSameDayAs: .now)
    }

    /// "Start tomorrow" was chosen tonight.
    private var startsTomorrow: Bool {
        isToday && Date.now.timeIntervalSince1970 < firstRunStartsOn
    }

    /// The first run's next sheet, once nothing else is up: the first bite after the welcome,
    /// the goal once the first food is in.
    private func continueFirstRun() {
        guard sheet == nil, !showScanner else { return }
        let next: FirstRunSheet.Step
        switch firstRun {
        case .firstBite: next = .firstBite
        case .goal: next = .goal
        default: return
        }
        // Called once whatever was up has gone; a turn of the run loop lets this screen settle.
        Task {
            await Task.yield()
            guard sheet == nil, !showScanner else { return }
            sheet = .firstRun(next)
        }
    }

    /// A sheet closed. Swiping the first run's sheet away ends the first run; a search sheet
    /// that logged the first food brings the goal.
    private func sheetClosed() {
        if scanAfterSheet {
            scanAfterSheet = false
            showScanner = true
            return
        }
        let closedFirstRun = firstRunSheetUp
        firstRunSheetUp = false
        switch firstRun {
        case .firstBite, .goal:
            if closedFirstRun {
                firstRunRaw = FirstRun.done.rawValue
            } else {
                continueFirstRun()
            }
        default:
            break
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
        entries(on: day)
    }

    /// The entries of one day. The log is sorted by date, so two binary searches find them.
    private func entries(on date: Date) -> [FoodEntry] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        func first(atOrAfter limit: Date) -> Int {
            var low = 0
            var high = entries.count
            while low < high {
                let middle = (low + high) / 2
                if entries[middle].date < limit { low = middle + 1 } else { high = middle }
            }
            return low
        }
        return Array(entries[first(atOrAfter: start)..<first(atOrAfter: end)])
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
        guard Calendar.current.isDateInToday(day), !noTarget else {
            return (number: totals.kcal, unit: String(localized: "kcal eaten"))
        }
        if totals.kcal > budget {
            return (number: totals.kcal - budget, unit: String(localized: "kcal over today"))
        }
        return (number: budget - totals.kcal, unit: String(localized: "kcal left today"))
    }

    /// Right of the place line: the goal today; a past day's verdict, red when it went over.
    private var heroDetail: (text: String, isOver: Bool) {
        if noTarget { return (String(localized: "No target"), false) }
        if !isToday, let verdict = verdicts[day], let label = verdict.label {
            if case .over = verdict { return (label, true) }
            return (label, false)
        }
        return (String(localized: "Goal \(budget.kcalText) kcal"), false)
    }

    /// The day's fiber, once enough of what was eaten has it on record.
    private var fiberToShow: FiberDay? {
        let day = FiberDay.make(dayEntries.map { entry in
            let totals = entry.totals
            return FiberDay.Item(fiber: totals.fiber, carbs: totals.carbs)
        })
        return day.isShown ? day : nil
    }

    // MARK: Today's extras

    private var waterDay: WaterDay? {
        waterDays.first { Calendar.current.isDate($0.day, inSameDayAs: day) }
    }

    private var waterGlasses: Int { waterDay?.glasses ?? 0 }

    /// "Fits your 967 kcal left" while there is room today; just "Saved" otherwise.
    private var shelfTitle: LocalizedStringKey {
        let left = budget - totals.kcal
        return isToday && !noTarget && left > 0 && !saved.isEmpty ? "Fits your \(left.kcalText) kcal left" : "Saved"
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
        guard let found = UsualMeal.find(in: logged, now: now) ?? UsualMeal.yesterday(in: logged, now: now),
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
        let todays = entries(on: today)
        let todayKcal = todays.reduce(0) { $0 + $1.totals.kcal }
        let todayVerdict = DayVerdict(kcal: todayKcal, entries: todays.count, goal: Double(goalKcal))
        let verdicts = self.verdicts
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

    private var checkInHistory: CheckInHistory {
        (try? JSONDecoder().decode(CheckInHistory.self, from: checkInHistoryData)) ?? CheckInHistory()
    }

    private func saveCheckInHistory(_ history: CheckInHistory) {
        checkInHistoryData = (try? JSONEncoder().encode(history)) ?? Data()
    }

    /// This week's check-in, when it has something to say and it is its day. The first time it
    /// has something to say, that weekday becomes the check-in day.
    private var weekCheckIn: CheckIn? {
        guard !noTarget else { return nil }
        let kcals = Dictionary(summaries.map { ($0.day, $0.kcal) }, uniquingKeysWith: { a, _ in a })
        return CheckIn.make(
            now: .now,
            dayKcals: kcals,
            weighings: weights.map { LearnedMaintenance.Weighing(date: $0.date, kilograms: $0.kilograms) },
            currentGoal: goalKcal,
            weightGoal: WeightGoal(rawValue: weightGoalRaw) ?? .maintain,
            sex: Sex(rawValue: sexRaw) ?? .female
        )
    }

    private var dueCheckIn: CheckIn? {
        guard let checkIn = weekCheckIn else { return nil }
        var history = checkInHistory
        if history.weekday == nil { history.start(now: .now) }
        return history.isDue(now: .now, gap: checkIn.gap) ? checkIn : nil
    }

    /// The check-in day is set the first time there is something to say, never in body.
    private func startCheckInDayIfNeeded() {
        guard checkInHistory.weekday == nil, weekCheckIn != nil else { return }
        var history = checkInHistory
        history.start(now: .now)
        saveCheckInHistory(history)
    }

    private func useCheckIn(_ checkIn: CheckIn) {
        var history = checkInHistory
        history.start(now: .now)
        history.used(previousGoal: goalKcal, now: .now)
        withAnimation(Motion.settle) {
            saveCheckInHistory(history)
            goalKcal = checkIn.offeredGoal
        }
    }

    private func keepCheckIn(_ checkIn: CheckIn) {
        var history = checkInHistory
        history.start(now: .now)
        history.kept(gap: checkIn.gap, now: .now)
        withAnimation(Motion.settle) { saveCheckInHistory(history) }
    }

    private func undoCheckIn() {
        var history = checkInHistory
        guard let previous = history.undoGoal else { return }
        history.undoGoal = nil
        withAnimation(Motion.settle) {
            saveCheckInHistory(history)
            goalKcal = previous
        }
    }

    private var mirrorHistory: MirrorHistory {
        (try? JSONDecoder().decode(MirrorHistory.self, from: mirrorHistoryData)) ?? MirrorHistory()
    }

    /// Your mirror asking for a photo, on today only and never beside the week's check-in: the
    /// first one from your third day, then every four weeks, or from 25 days the morning a
    /// weighing comes in. The first ask waits on a day that already asks for your weight.
    private var mirrorAsk: MirrorMoment.Kind? {
        guard isToday, dueCheckIn == nil else { return nil }
        let history = mirrorHistory
        let log = MirrorLog.shared
        if let newest = log.newest {
            let weighedToday = weights.last.map { Calendar.current.isDateInToday($0.date) } ?? false
            guard history.asksNext(now: .now, newest: newest, weighedToday: weighedToday) else { return nil }
            return .next(MirrorGap.between(newest, .now))
        }
        if !entries.isEmpty, trendWeights.isEmpty { return nil }
        let firstDay = firstRunDay > 0 ? Date(timeIntervalSince1970: firstRunDay) : nil
        return history.asksFirst(now: .now, firstDay: firstDay) ? .first : nil
    }

    /// "Not now": back in a week; three in a row and only Settings opens your mirror.
    private func mirrorNotNow() {
        var history = mirrorHistory
        history.notNow(now: .now)
        withAnimation(Motion.settle) {
            mirrorHistoryData = (try? JSONEncoder().encode(history)) ?? Data()
        }
    }

    /// Where your weight goes at the way you ate over the last week's whole days, against what
    /// your body burns: learned when it can be, else worked out from your body.
    private func forecast(learned: LearnedMaintenance?) -> WeightForecast? {
        guard let current = WeightForecast.trend(trendWeights.map(\.kilograms)).last else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let kcals: [Double] = (1...7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return entries(on: date).reduce(0) { $0 + $1.totals.kcal }
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
        guard HealthActivity.isAvailable, !healthUnavailable else { return .unavailable }
        guard healthAsked else { return .notConnected }
        return .connected(activity ?? DayActivity(steps: 0, activeKcal: 0))
    }

    /// The day's photos for the cover, latest first: decoded off the main thread at the size
    /// the cover shows them, with the soft copy for the melt; photos already shown are kept.
    private func loadCoverPhotos() async {
        let previous = coverPhotos
        let known = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var sources: [(id: AnyHashable, data: Data?, dish: String, place: MealPlace?)] = []
        for entry in photoEntries {
            let id = AnyHashable(entry.persistentModelID)
            sources.append((id: id, data: known[id] == nil ? entry.imageData : nil, dish: entry.name, place: entry.place))
        }
        let loaded: [CoverPhoto] = await Task.detached(priority: .userInitiated) {
            sources.compactMap { source -> CoverPhoto? in
                if let kept = known[source.id] { return kept }
                guard let data = source.data, let image = ImageTools.downsample(data, maxPixel: 1320) else { return nil }
                return CoverPhoto(id: source.id, image: image, soft: ImageTools.softened(data) ?? image, dish: source.dish, place: source.place)
            }
        }.value
        guard !Task.isCancelled, loaded.map(\.id) != previous.map(\.id) else { return }
        withAnimation(Motion.settle) { coverPhotos = loaded }
        // A new photo comes to the front; a removed one never leaves the cover past its end.
        if (loaded.count > previous.count && !previous.isEmpty) || coverIndex >= loaded.count {
            quietly { coverIndex = 0 }
        }
    }

    /// A change made by the clock or by code, not by your finger: it moves without a tick.
    private func quietly(_ change: () -> Void) {
        movedByCode = true
        change()
        DispatchQueue.main.async { movedByCode = false }
    }

    /// Once a day, when a log (not a switch, a Health refresh, a new goal or an Undo) takes
    /// today onto target: success a moment after the food lands, so the two never blur.
    private func celebrateIfEarned() {
        guard !noTarget, case .added? = events.last?.change, isOnTargetToday else { return }
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        guard celebratedDay != today else { return }
        celebratedDay = today
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            celebrations += 1
        }
    }

    private func loadWeights() async {
        #if DEBUG || BITE_DEMO
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
        withAnimation(Motion.settle) {
            context.insert(entry)
            item.timesAdded += 1
            try? context.save()
        }
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

    /// A meal moved to another time on the same day: every entry shifts by the same amount,
    /// so a snack at 10:30 and one at 16:10 keep their hours apart.
    private func move(_ items: [FoodEntry], to time: Date) {
        guard let first = items.min(by: { $0.date < $1.date }) else { return }
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        guard let target = calendar.date(bySettingHour: parts.hour ?? 12, minute: parts.minute ?? 0, second: 0, of: first.date) else { return }
        let shift = target.timeIntervalSince(first.date)
        guard calendar.dateComponents([.hour, .minute], from: first.date) != parts else { return }
        withAnimation(.snappy) {
            for item in items {
                let day = calendar.startOfDay(for: item.date)
                // The day's last minute, right on the days the clocks change too.
                let last = calendar.date(byAdding: .day, value: 1, to: day)?.addingTimeInterval(-60) ?? item.date
                item.date = min(max(item.date.addingTimeInterval(shift), day), last)
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
                    let entry = FoodEntry(food: snapshot.food, amount: snapshot.amount, meal: snapshot.meal, date: snapshot.date, place: snapshot.place)
                    entry.entryID = snapshot.entryID
                    context.insert(entry)
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
            guard await HealthActivity.shared.requestAccess() else {
                healthUnavailable = true
                return
            }
            healthAsked = true
            weightAsked = true
        }
    }

    /// Weight from Apple Health when there is Health; else the goal calculator in Settings.
    private func addWeight() {
        guard HealthActivity.isAvailable, !healthUnavailable, !weightAsked else {
            sheet = .settings
            return
        }
        Task {
            guard await HealthActivity.shared.requestAccess() else {
                healthUnavailable = true
                sheet = .settings
                return
            }
            healthAsked = true
            weightAsked = true
        }
    }

    private func loadActivity() async {
        #if DEBUG || BITE_DEMO
        if BiteStore.isDemo {
            activity = DemoData.activity(on: day)
            return
        }
        #endif
        guard healthAsked, HealthActivity.isAvailable else {
            activity = nil
            return
        }
        let read = await HealthActivity.shared.activity(on: day)
        activity = read
        if isToday { WidgetBridge.shared.publishBurned(read.activeKcal, on: day) }
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
        case "place", "dish", "addestimate", "accuracy", "share":
            if let first = dishes.first { sheet = .place(first.place) }
        case "where": editing = dayEntries.first { $0.place != nil } ?? dayEntries.last
        case "cover2": coverIndex = 1
        case let screen? where screen.hasPrefix("mirror"):
            sheet = MirrorFixture.open(screen)
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
/// Whether the day's cover is still on screen, kept apart from Today so that scrolling past it
/// redraws only the top of the screen.
@Observable final class CoverChrome {
    var onScreen = true
}

/// The paper under the status bar once the cover has gone, and the status bar itself, hidden
/// over a photo in light mode: the only views that change as the cover leaves.
private struct TopChrome: View {
    let chrome: CoverChrome
    let height: CGFloat
    let onDay: Bool
    let photoCover: Bool

    var body: some View {
        let paper = !onDay || !chrome.onScreen
        TopFade(height: height)
            .opacity(paper ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: paper)
            .allowsHitTesting(false)
            // A photo cover runs to the top edge, where the time would sit dark on the picture.
            .statusBarHidden(onDay && photoCover && chrome.onScreen)
    }
}

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

/// "A nudge tomorrow at 8:10, only if breakfast isn't in?": the reminder as an offer with a
/// time, once, after the second log. Remind me asks iOS; Not now means never again on its own.
private struct ReminderOffer: View {
    let reminder: MealReminder
    let onRemind: () -> Void
    let onNotNow: () -> Void

    private var timeText: String {
        let day = Calendar.current.startOfDay(for: .now)
        let time = Calendar.current.date(byAdding: .minute, value: reminder.minute, to: day) ?? day
        return time.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(reminder.question(timeText: timeText))
                        .font(.ui(16, .medium))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("One a day at most.")
                        .font(.ui(14))
                        .foregroundStyle(Theme.secondary)
                }
            }
            HStack(spacing: 18) {
                Button(action: onRemind) {
                    Text("Remind me")
                        .font(.ui(15, .semibold))
                        .foregroundStyle(Theme.page)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(Theme.ink, in: Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.94))
                Button("Not now", action: onNotNow)
                    .font(.ui(15, .medium))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.leading, 46)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Nothing logged yet. Today: four foods for the hour, one tap from their page (Scan and Search
/// are in the dock right under it); tonight after "Start tomorrow", a line for the morning. A
/// past day: one line.
private struct EmptyDay: View {
    let isToday: Bool
    var startsTomorrow = false
    var foods: [Food] = []
    var onFood: (Food) -> Void = { _ in }

    var body: some View {
        if !isToday {
            Text("Nothing logged this day.")
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if startsTomorrow {
            Text("Your journal starts tomorrow. See you at breakfast.")
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("First bite")
                    .font(.ui(16, .semibold))
                    .foregroundStyle(Theme.ink)
                Text("What did you have? Tap it, scan it or search.")
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
                HStack(alignment: .top, spacing: 8) {
                    ForEach(foods) { food in
                        Button { onFood(food) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                FoodThumb(food: food, size: 70)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(HourFoods.label(for: food.id) ?? food.name)
                                        .font(.ui(13))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("\(food.nutrients(for: food.defaultAmount).kcal.kcalText) kcal")
                                        .font(.ui(12))
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.95))
                    }
                }
                .padding(.top, 14)
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
