import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Your goal and macros, Apple Health, the key that turns photos into estimates, and your log
/// to take with you.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("goal.kcal") private var kcal = 2000
    @AppStorage("goal.split") private var splitRaw = MacroSplit.balanced.rawValue
    @AppStorage("health.asked") private var healthAsked = false
    @AppStorage("health.addBurned") private var addBurned = false
    @State private var apiKey = ""
    @State private var storedKey = ""

    private var split: MacroSplit { MacroSplit(rawValue: splitRaw) ?? .balanced }
    private var targets: MacroTargets { MacroTargets(kcal: Double(kcal), split: split) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 4) {
                        HStack {
                            StepButton(systemImage: "minus", label: "Lower") { change(by: -50) }
                            Spacer()
                            Text(kcal.formatted())
                                .font(.number(44))
                                .foregroundStyle(Theme.ink)
                                .contentTransition(.numericText(value: Double(kcal)))
                            Spacer()
                            StepButton(systemImage: "plus", label: "Higher") { change(by: 50) }
                        }
                        Text("kcal a day")
                            .font(.ui(15))
                            .foregroundStyle(Theme.secondary)
                    }
                    .padding(.vertical, 10)
                    .listRowBackground(Theme.card)

                    NavigationLink {
                        GoalCalculatorView { kcal = $0 }
                    } label: {
                        Label {
                            Text("Work it out from my body")
                                .font(.ui(17))
                                .foregroundStyle(Theme.ink)
                        } icon: {
                            Image(systemName: "figure")
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    .listRowBackground(Theme.card)
                } header: {
                    SectionTitle(text: "Daily goal")
                }

                Section {
                    Picker(selection: $splitRaw) {
                        ForEach(MacroSplit.allCases) { split in
                            Text(split.title).tag(split.rawValue)
                        }
                    } label: {
                        Text("Split")
                            .font(.ui(17))
                            .foregroundStyle(Theme.ink)
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.secondary)
                    .listRowBackground(Theme.card)

                    ForEach(Macro.allCases, id: \.self) { macro in
                        MacroTargetRow(macro: macro, grams: macro.target(in: targets), share: share(of: macro))
                    }
                } header: {
                    SectionTitle(text: "Macros")
                }

                if HealthActivity.isAvailable {
                    Section {
                        if healthAsked {
                            Toggle(isOn: $addBurned) {
                                Text("Add burned calories to my goal")
                                    .font(.ui(17))
                                    .foregroundStyle(Theme.ink)
                            }
                            .listRowBackground(Theme.card)
                        } else {
                            Button {
                                Task {
                                    await HealthActivity.shared.requestAccess()
                                    healthAsked = true
                                }
                            } label: {
                                Label {
                                    Text("Connect Apple Health")
                                        .font(.ui(17))
                                } icon: {
                                    Image(systemName: "heart.fill")
                                        .foregroundStyle(Theme.burned)
                                }
                            }
                            .listRowBackground(Theme.card)
                        }
                    } header: {
                        SectionTitle(text: "Apple Health")
                    } footer: {
                        Text(healthAsked
                            ? "Your goal already counts a normal week. Turn this on if you picked Mostly sitting, so workouts give you room to eat more."
                            : "See your steps and burned calories next to what you eat. Bite only reads.")
                    }
                }

                Section {
                    SecureField("Claude API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.ui(17))
                        .onSubmit(saveKey)
                        .listRowBackground(Theme.card)
                    if apiKey != storedKey {
                        Button(apiKey.isEmpty ? "Remove key" : "Save key", action: saveKey)
                            .font(.ui(17, .medium))
                            .listRowBackground(Theme.card)
                    } else if !storedKey.isEmpty {
                        Label("Photo estimates are on", systemImage: "checkmark.circle.fill")
                            .font(.ui(17))
                            .foregroundStyle(Theme.goodText)
                            .listRowBackground(Theme.card)
                    }
                    Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                        Label("Get a key from Anthropic", systemImage: "arrow.up.right")
                            .font(.ui(17))
                    }
                    .listRowBackground(Theme.card)
                } header: {
                    SectionTitle(text: "Photo estimates")
                } footer: {
                    Text("Photos you scan go to Anthropic's Claude, which sends back the calories and macros. About 2 cents a photo, billed to your Anthropic account. Your log never leaves your phone.")
                }

                Section {
                    ExportLogRow()
                        .listRowBackground(Theme.card)
                } header: {
                    SectionTitle(text: "Your data")
                } footer: {
                    Text("Every food you logged, as a spreadsheet. Your log stays on your phone: Bite never sells it or shares it.")
                }

                Section {
                    Text("Food data comes from Open Food Facts, the free and open food database, and from USDA FoodData Central.")
                        .font(.ui(15))
                        .foregroundStyle(Theme.secondary)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.page.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                storedKey = Keychain.string(for: Keychain.claudeKey) ?? ""
                apiKey = storedKey
            }
        }
    }

    private func share(of macro: Macro) -> Double {
        switch macro {
        case .protein: split.shares.protein
        case .carbs: split.shares.carbs
        case .fat: split.shares.fat
        }
    }

    private func change(by delta: Int) {
        withAnimation(.snappy) { kcal = min(max(kcal + delta, 1000), 6000) }
    }

    private func saveKey() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set(key, for: Keychain.claudeKey)
        storedKey = key
        apiKey = key
    }
}

private struct MacroTargetRow: View {
    let macro: Macro
    let grams: Double
    let share: Double

    var body: some View {
        HStack(spacing: 10) {
            MacroTile(macro: macro)
            Text(macro.title)
                .font(.ui(17))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text("\(grams.kcalText) g")
                .font(.number(17))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText(value: grams))
            Text("\((share * 100).safeInt)%")
                .font(.ui(15))
                .monospacedDigit()
                .foregroundStyle(Theme.secondary)
                .frame(width: 46, alignment: .trailing)
        }
        .animation(.snappy, value: grams)
        .listRowBackground(Theme.card)
    }
}

/// Your whole log as a spreadsheet, written when you share it.
private struct ExportLogRow: View {
    @Query(sort: \FoodEntry.date) private var entries: [FoodEntry]

    var body: some View {
        ShareLink(item: LogFile(rows: entries.map(LogExport.Row.init)), preview: SharePreview(LogExport.title)) {
            Label("Export your log", systemImage: "square.and.arrow.up")
                .font(.ui(17))
        }
        .disabled(entries.isEmpty)
    }
}

/// The log as a CSV file for the share sheet: Files, Mail, Numbers or a dietitian.
struct LogFile: Transferable {
    let rows: [LogExport.Row]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appending(path: LogExport.fileName)
            try LogExport.file(file.rows).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

extension LogExport.Row {
    init(_ entry: FoodEntry) {
        let factor = entry.per > 0 ? entry.amount / entry.per : 0
        let totals = entry.totals
        self.init(
            date: entry.date,
            meal: entry.meal,
            name: entry.name,
            brand: entry.brand,
            amount: entry.amount,
            unit: FoodUnit(rawValue: entry.unitRaw) ?? .gram,
            kcal: totals.kcal,
            protein: totals.protein,
            carbs: totals.carbs,
            fat: totals.fat,
            fiber: entry.fiber.map { $0 * factor },
            sugar: entry.sugar.map { $0 * factor },
            place: entry.placeName
        )
    }
}

#if DEBUG
#Preview {
    SettingsView()
}
#endif
