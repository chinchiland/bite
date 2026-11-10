import Foundation

/// A way of fasting: whole days without food, then one meal, over and over. Once a week is six
/// days without food and the meal on the seventh. Bite plans fasts of up to a week: past that,
/// each extra day adds little to what the year loses, and the risks keep growing.
struct FastingCycle: Hashable, Identifiable {
    /// Whole days without food before the meal.
    let fastDays: Int

    var id: Int { fastDays }
    /// The days one turn takes: the fast, then the day of the meal.
    var length: Int { fastDays + 1 }

    /// How much of a fast that never ends this one keeps, when each meal is a day of what you
    /// burn: six days of seven, 86%. Week-long fasts keep 88%.
    var shareOfNonstop: Double { Double(fastDays) / Double(length) }

    static let all = [1, 2, 3, 4, 6, 7].map(FastingCycle.init)
    static let onceAWeek = FastingCycle(fastDays: 6)
    static let longest = 7

    var title: String {
        switch fastDays {
        case 1: tr("Every other day")
        case 6: tr("Once a week")
        case 7: tr("Week-long fasts")
        default: tr("A meal every %@ days", "\(length)")
        }
    }

    var detail: String {
        fastDays == 1 ? tr("A day without food, then a meal") : tr("%@ days without food, then a meal", "\(fastDays)")
    }
}

/// What the plan knows of you: the goal calculator's numbers, your latest weighing, and how
/// you move on an average day.
struct FastingBody: Equatable {
    var sex: Sex
    var age: Int
    var heightCm: Double
    var weightKg: Double
    var moving: Moving

    var bmi: Double { weightKg / pow(max(heightCm, 100) / 100, 2) }

    func weight(atBMI bmi: Double) -> Double { bmi * pow(max(heightCm, 100) / 100, 2) }

    /// Body fat from BMI, age and sex (Deurenberg, 1991), between 8% and 55%. An estimate: two
    /// people of one BMI can carry very different amounts of fat.
    var fatShare: Double {
        let percent = 1.2 * bmi + 0.23 * Double(age) - 10.8 * (sex == .male ? 1 : 0) - 5.4
        return min(max(percent / 100, 0.08), 0.55)
    }

    /// What this body burns in a day at a given weight, part by part. Each part moves with the
    /// weight: resting energy the way Mifflin-St Jeor does, walking and sport kilo for kilo.
    func burnParts(atKg kilograms: Double) -> DailyBurn {
        let rest = GoalCalculator.resting(sex: sex, age: age, heightCm: heightCm, weightKg: kilograms)
        return DailyBurn(
            rest: rest,
            life: rest * DailyBurn.lifeShare,
            walking: walkingKm * DailyBurn.walkKcalPerKgKm * kilograms,
            sport: moving.sports.reduce(0) { $0 + $1.kcalPerDay(atKg: kilograms) }
        )
    }

    func burn(atKg kilograms: Double) -> Double { burnParts(atKg: kilograms).total }

    /// Your steps as a distance: a stride is about 41% of your height.
    var walkingKm: Double {
        Double(max(moving.steps, 0)) * min(max(heightCm, 100), 250) * DailyBurn.strideShareOfHeight / 100_000
    }
}

/// What a day burns, part by part.
struct DailyBurn: Equatable {
    /// Resting energy: Mifflin-St Jeor.
    let rest: Double
    /// Standing, chores and digesting.
    let life: Double
    let walking: Double
    let sport: Double

    var total: Double { rest + life + walking + sport }

    /// Daily life as a share of resting energy: with 4,000 steps it lands where the goal
    /// calculator's Mostly sitting does.
    static let lifeShare = 0.15
    /// Walking costs about half a kilocalorie for each kilo and kilometre above rest.
    static let walkKcalPerKgKm = 0.5
    static let strideShareOfHeight = 0.414
}

/// How you move on an average day: your steps and your sport.
struct Moving: Codable, Equatable {
    var steps: Int
    var sports: [Sport] = []

    /// Steps for each of the goal calculator's activity levels, until you say.
    static func usual(for activity: Activity) -> Moving {
        switch activity {
        case .sedentary: Moving(steps: 4000)
        case .light: Moving(steps: 7000)
        case .moderate: Moving(steps: 9000)
        case .active: Moving(steps: 11000)
        }
    }

    /// As it is kept in settings.
    var stored: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    init(steps: Int, sports: [Sport] = []) {
        self.steps = steps
        self.sports = sports
    }

    init?(stored: String) {
        guard let data = stored.data(using: .utf8), let moving = try? JSONDecoder().decode(Moving.self, from: data) else { return nil }
        self = moving
    }
}

/// A sport you do in an average week: how long a session lasts and how many you do.
struct Sport: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: SportKind
    var minutes: Int
    var perWeek: Int

    private enum CodingKeys: String, CodingKey {
        case kind, minutes, perWeek
    }

    init(kind: SportKind, minutes: Int = 45, perWeek: Int = 2) {
        self.kind = kind
        self.minutes = minutes
        self.perWeek = perWeek
    }

    /// Two sports are the same when you do the same thing as often: the id only tells rows apart.
    static func == (lhs: Sport, rhs: Sport) -> Bool {
        lhs.kind == rhs.kind && lhs.minutes == rhs.minutes && lhs.perWeek == rhs.perWeek
    }

    /// What it adds to an average day at a weight: its MET above rest, times kilos and hours,
    /// spread over the week.
    func kcalPerDay(atKg kilograms: Double) -> Double {
        (kind.met - 1) * kilograms * Double(max(minutes, 0)) / 60 * Double(max(perWeek, 0)) / 7
    }
}

enum SportKind: String, Codable, CaseIterable, Identifiable {
    case running
    case cycling
    case swimming
    case gym
    case hiit
    case yoga
    case hiking
    case football
    case tennis
    case boxing

    var id: String { rawValue }

    /// From the Compendium of Physical Activities: what an hour of it costs for each kilo, rest
    /// counted as 1.
    var met: Double {
        switch self {
        case .running: 9
        case .cycling: 7
        case .swimming: 6
        case .gym: 5
        case .hiit: 8
        case .yoga: 2.5
        case .hiking: 6
        case .football: 7
        case .tennis: 6.5
        case .boxing: 7.5
        }
    }

    var title: String {
        switch self {
        case .running: tr("Running")
        case .cycling: tr("Cycling")
        case .swimming: tr("Swimming")
        case .gym: tr("Weights")
        case .hiit: tr("HIIT")
        case .yoga: tr("Yoga")
        case .hiking: tr("Hiking")
        case .football: tr("Football")
        case .tennis: tr("Tennis, padel")
        case .boxing: tr("Boxing")
        }
    }

    var symbol: String {
        switch self {
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .gym: "figure.strengthtraining.traditional"
        case .hiit: "figure.highintensity.intervaltraining"
        case .yoga: "figure.yoga"
        case .hiking: "figure.hiking"
        case .football: "figure.soccer"
        case .tennis: "figure.tennis"
        case .boxing: "figure.boxing"
        }
    }
}

/// One day of a projection.
struct FastingDay: Equatable {
    /// 1 is the first day of the plan.
    let day: Int
    /// What the scale says: fat and lean, minus the glycogen and its water a fast takes away
    /// and a meal partly gives back. It drops fast in the first days and bounces after a meal.
    let scaleKg: Double
    /// Fat and lean tissue only: the trend under the scale's swings.
    let tissueKg: Double
    let fatKg: Double
    let leanKg: Double
    let ate: Bool
}

struct FastingProjection: Equatable {
    let start: FastingDay
    let days: [FastingDay]
    /// The first day the trend reaches the goal, nil when it doesn't within the projection.
    let goalDay: Int?
    /// The projection stopped at the lowest weight Bite plans for, before the goal.
    let stoppedAtFloor: Bool

    var last: FastingDay { days.last ?? start }

    func day(_ number: Int) -> FastingDay {
        guard !days.isEmpty else { return start }
        return days[min(max(number, 1), days.count) - 1]
    }

    /// Tissue lost by a day, and how much of it was fat.
    func lost(by number: Int) -> (total: Double, fat: Double, lean: Double) {
        let then = day(number)
        return (start.tissueKg - then.tissueKg, start.fatKg - then.fatKg, start.leanKg - then.leanKg)
    }

    /// Kilos of tissue a week, on average over the projection.
    var perWeek: Double {
        guard !days.isEmpty else { return 0 }
        return (start.tissueKg - last.tissueKg) / Double(days.count) * 7
    }
}

/// Why Bite does not plan a fast for these numbers.
enum FastingRefusal: Equatable {
    case underAge
    case lowBMI
}

/// The projection, worked out a day at a time the way the body pays for a deficit (Hall, 2008):
/// what you burn falls a little as you get lighter and deep into each fast; the first days
/// without food take the glycogen in your liver and muscles, and the water stored with it; the
/// rest comes from tissue, split between fat and lean the way Forbes found (2000), so a leaner
/// body loses more muscle for each kilo.
enum FastingModel {
    /// Energy in a kilo of body fat (39.5 MJ) and of lean tissue (7.6 MJ).
    static let fatKcalPerKg = 9440.0
    static let leanKcalPerKg = 1820.0
    /// Forbes' constant: with this many kilos of fat, half of a loss is lean.
    static let forbesKg = 10.4
    /// A kilo of glycogen with its water holds about 250 g of glycogen, at 4 kcal a gram.
    static let glycogenKcalPerKg = 1000.0
    /// Glycogen and its water as a share of lean mass: about 1.8 kg in a 70 kg lean body.
    static let glycogenShareOfLean = 0.025
    /// How much of a full store each of the first three days without food takes.
    static let glycogenDrain = [0.45, 0.35, 0.2]
    /// What a meal of a day of what you burn gives back to the store.
    static let glycogenRefill = 0.7
    /// What you burn falls by 2% a day after the third day without food, at most 10%.
    static let dipPerDay = 0.02
    static let maxDip = 0.1
    /// Bite never plans below this BMI, whatever the goal.
    static let floorBMI = 20.0
    /// The single fasts the plan offers, a week at most like the cycles.
    static let onceLengths = [2, 3, 5, 7]
    static let adultAge = 18

    enum Intake: Equatable {
        /// Fasting days, then a meal of this many kilocalories.
        case cycle(FastingCycle, mealKcal: Double)
        /// One fast of so many days, then a day of this many kilocalories, every day after.
        case once(fastDays: Int, mealKcal: Double)
        /// The same every day, your daily goal.
        case daily(kcal: Double)
        /// No food at all, for comparison only: nobody should plan it.
        case nothing
    }

    static func refusal(for body: FastingBody) -> FastingRefusal? {
        if body.age < adultAge { return .underAge }
        if body.bmi < floorBMI { return .lowBMI }
        return nil
    }

    /// The lowest weight a plan goes to.
    static func floorKg(for body: FastingBody) -> Double {
        body.weight(atBMI: floorBMI)
    }

    /// A goal to start from: a tenth off, never under a BMI of 22.
    static func suggestedGoal(for body: FastingBody) -> Double {
        let goal = max(body.weightKg * 0.9, body.weight(atBMI: 22))
        return min((goal * 2).rounded() / 2, body.weightKg)
    }

    static func project(body: FastingBody, intake: Intake, goalKg: Double, days: Int) -> FastingProjection {
        var fat = body.weightKg * body.fatShare
        var lean = body.weightKg - fat
        let glycogenFull = lean * glycogenShareOfLean
        var emptied = 0.0
        let floor = floorKg(for: body)
        let start = FastingDay(day: 0, scaleKg: fat + lean, tissueKg: fat + lean, fatKg: fat, leanKg: lean, ate: true)
        var result: [FastingDay] = []
        var goalDay: Int?
        var stoppedAtFloor = false
        var withoutFood = 0

        for index in 0..<max(days, 0) {
            let kcal: Double?
            switch intake {
            case .cycle(let cycle, let meal):
                kcal = index % cycle.length == cycle.fastDays ? max(meal, 0) : nil
            case .once(let fastDays, let meal):
                kcal = index < fastDays ? nil : max(meal, 0)
            case .daily(let daily):
                kcal = max(daily, 0)
            case .nothing:
                kcal = nil
            }
            withoutFood = kcal == nil ? withoutFood + 1 : 0
            let dip = min(Double(max(withoutFood - 3, 0)) * dipPerDay, maxDip)
            let burn = body.burn(atKg: fat + lean) * (1 - dip)
            var balance = (kcal ?? 0) - burn

            if let kcal {
                // A meal puts some of the glycogen back first, and its water with it.
                let refill = min(emptied, glycogenFull * glycogenRefill * min(kcal / max(burn, 1), 1))
                emptied -= refill
                balance -= refill * glycogenKcalPerKg
            } else if withoutFood <= glycogenDrain.count {
                let drain = min(glycogenFull * glycogenDrain[withoutFood - 1], glycogenFull - emptied)
                emptied += drain
                balance += drain * glycogenKcalPerKg
            }

            let leanShare = forbesKg / (forbesKg + max(fat, 0.5))
            let change = balance / ((1 - leanShare) * fatKcalPerKg + leanShare * leanKcalPerKg)
            fat += (1 - leanShare) * change
            lean += leanShare * change

            let tissue = fat + lean
            result.append(FastingDay(day: index + 1, scaleKg: tissue - emptied, tissueKg: tissue, fatKg: fat, leanKg: lean, ate: kcal != nil))
            if goalDay == nil, tissue <= goalKg { goalDay = index + 1 }
            if tissue <= floor {
                stoppedAtFloor = goalDay == nil
                break
            }
        }
        return FastingProjection(start: start, days: result, goalDay: goalDay, stoppedAtFloor: stoppedAtFloor)
    }

    /// The days a plan is drawn over: to the goal and one more turn of the cycle, at least 4
    /// weeks and at most 26.
    static func horizon(goalDay: Int?, cycle: FastingCycle) -> Int {
        guard let goalDay else { return 26 * 7 }
        return min(max(goalDay + cycle.length, 28), 26 * 7)
    }
}

/// What happens through a fast, hour by hour: what is known, said plainly, nothing promised.
struct FastingStage: Equatable {
    let hour: Int
    let title: String
    let detail: String

    /// The stages a fast of so many days goes through, then the meal that ends it.
    static func through(fastDays: Int) -> [FastingStage] {
        let all = [
            FastingStage(hour: 0, title: tr("Your last meal"), detail: tr("Your body runs on it, then on the sugar stored in your liver and muscles.")),
            FastingStage(hour: 24, title: tr("Glycogen runs low"), detail: tr("The water stored with it goes too: the first kilos are mostly water.")),
            FastingStage(hour: 48, title: tr("Ketosis"), detail: tr("Your body runs mostly on fat, and ketones feed your brain.")),
            FastingStage(hour: 72, title: tr("Hunger often eases"), detail: tr("It tends to peak on day 2 or 3, then fade.")),
        ]
        let reached = all.filter { $0.hour < fastDays * 24 }
        let meal = FastingStage(hour: fastDays * 24, title: tr("The meal"), detail: tr("Break it gently: something small first, then eat slowly."))
        return reached + [meal]
    }
}
