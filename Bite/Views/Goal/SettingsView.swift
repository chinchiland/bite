import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Your goal and macros, Apple Health, the key that turns photos into estimates, your mirror,
/// and your log to take with you.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("goal.kcal") private var kcal = 2000
    @AppStorage("goal.split") private var splitRaw = MacroSplit.balanced.rawValue
    @AppStorage("goal.noTarget") private var noTarget = false
    @AppStorage("health.asked") private var healthAsked = false
    @AppStorage("health.weightAsked") private var weightAsked = false
    @AppStorage("health.unavailable") private var healthUnavailable = false
    @AppStorage("health.addBurned") private var addBurned = false
    @AppStorage(HealthSync.enabledKey) private var saveMeals = false
    /// Health said no when saving was turned on, or it was turned off in the Health app.
    @State private var savingRefused = false
    @State private var removing = false
    @State private var apiKey = ""
    @State private var account = CommunityAccount.shared
    @State private var communityName = ""
    @State private var confirmDelete = false
    @State private var deleteFailed = false
    @State private var nudge = Reminders.current
    @State private var nudgeRefused = false
    @Environment(\.modelContext) private var modelContext
    @State private var storedKey = ""
    @AppStorage("mirror.consented") private var mirrorConsented = false
    @AppStorage("mirror.faceID") private var mirrorFaceID = true
    @State private var confirmMirrorErase = false
    private var mirrorKeep: MirrorKeep { MirrorKeep.shared }

    /// Changing the lock opens the mirror first, through the lock it has now.
    private var mirrorFaceIDBinding: Binding<Bool> {
        Binding(
            get: { mirrorFaceID },
            set: { on in
                Task {
                    guard await MirrorLock.open(faceID: mirrorFaceID) else { return }
                    let changed = await Task.detached(priority: .userInitiated) {
                        MirrorVault.shared.setProtected(on)
                    }.value
                    if changed { mirrorFaceID = on }
                    // Changed, then closed again: the next visit asks through the new lock.
                    MirrorVault.shared.lockNow()
                }
            }
        )
    }

    private var split: MacroSplit { MacroSplit(rawValue: splitRaw) ?? .balanced }

    /// On asks iOS once and plans the nudge at breakfast time; off stops it.
    private var nudgeBinding: Binding<Bool> {
        Binding(
            get: { nudge != nil },
            set: { on in
                guard on else {
                    Reminders.turnOff()
                    nudge = nil
                    return
                }
                let reminder = MealReminder(meal: .breakfast, minute: 8 * 60)
                Task {
                    let allowed = await Reminders.turnOn(reminder, context: modelContext)
                    nudgeRefused = !allowed
                    nudge = allowed ? reminder : nil
                }
            }
        )
    }

    /// The nudge's time, as a date today for the wheel.
    private func nudgeTime(_ reminder: MealReminder) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(byAdding: .minute, value: reminder.minute, to: Calendar.current.startOfDay(for: .now)) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                let moved = MealReminder(meal: reminder.meal, minute: (parts.hour ?? 8) * 60 + (parts.minute ?? 0))
                Reminders.current = moved
                nudge = moved
                Task { await Reminders.reschedule(context: modelContext) }
            }
        )
    }

    /// Turning it on asks Health first, then writes the last month; turning it off keeps what
    /// is already there, which belongs to Health now.
    private var saveMealsBinding: Binding<Bool> {
        Binding(
            get: { saveMeals },
            set: { on in
                guard on else {
                    saveMeals = false
                    return
                }
                Task {
                    let allowed = await HealthMeals.shared.requestAccess()
                    savingRefused = !allowed
                    saveMeals = allowed
                    if allowed { await HealthSync.shared.run(days: HealthSync.firstWindow) }
                }
            }
        )
    }
    private var targets: MacroTargets { MacroTargets(kcal: Double(kcal), split: split) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                List {
                    Section {
                        VStack(spacing: 4) {
                            HStack {
                                StepButton(systemImage: "minus", label: "Lower", value: Double(kcal)) { change(by: -50) }
                                Spacer()
                                Text(kcal.formatted())
                                    .font(.number(44))
                                    .foregroundStyle(Theme.ink)
                                    .contentTransition(.numericText(value: Double(kcal)))
                                Spacer()
                                StepButton(systemImage: "plus", label: "Higher", value: Double(kcal)) { change(by: 50) }
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

                        Toggle(isOn: $noTarget) {
                            Text("No target")
                                .font(.ui(17))
                                .foregroundStyle(Theme.ink)
                        }
                        .listRowBackground(Theme.card)
                    } header: {
                        SectionTitle(text: "Daily goal")
                    } footer: {
                        if noTarget {
                            Text("Bite counts what you eat and shows the pattern, with no budget to stay under. Macros still show what to aim for.")
                        }
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
                            if healthUnavailable {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("This copy of Bite was installed without Apple Health, so steps, burned calories and weighings stay off.")
                                        .font(.ui(15))
                                        .foregroundStyle(Theme.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Button("Try again") {
                                        Task {
                                            guard await HealthActivity.shared.requestAccess() else { return }
                                            healthUnavailable = false
                                            healthAsked = true
                                            weightAsked = true
                                        }
                                    }
                                    .font(.ui(17))
                                }
                                .padding(.vertical, 4)
                                .listRowBackground(Theme.card)
                            } else if healthAsked {
                                Toggle(isOn: $addBurned) {
                                    Text("Add burned calories to my goal")
                                        .font(.ui(17))
                                        .foregroundStyle(Theme.ink)
                                }
                                .listRowBackground(Theme.card)
                            } else {
                                Button {
                                    Task {
                                        guard await HealthActivity.shared.requestAccess() else {
                                            healthUnavailable = true
                                            return
                                        }
                                        healthAsked = true
                                        weightAsked = true
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
                                ? "Your goal already counts a normal week. Turn this on if you picked Mostly sitting, so workouts give you room to eat more. What Bite reads is in the iPhone's Settings: Privacy & Security, Health, Bite."
                                : "See your steps and burned calories next to what you eat.")
                        }

                        if !healthUnavailable {
                            Section {
                                Toggle(isOn: saveMealsBinding) {
                                    Text("Save meals to Apple Health")
                                        .font(.ui(17))
                                        .foregroundStyle(Theme.ink)
                                }
                                .listRowBackground(Theme.card)
                                if saveMeals || removing {
                                    Button(role: .destructive) {
                                        removing = true
                                        Task {
                                            saveMeals = false
                                            await HealthMeals.shared.removeAll()
                                            removing = false
                                        }
                                    } label: {
                                        Text(removing ? "Removing…" : "Remove Bite's meals from Health")
                                            .font(.ui(17))
                                    }
                                    .disabled(removing)
                                    .listRowBackground(Theme.card)
                                }
                            } footer: {
                                Text(savingRefused
                                    ? "Turned off in Health. To turn it on: Settings, Health, Data Access & Devices, Bite."
                                    : "Each food goes in at the time you ate it. If another app saves your meals too, keep only one on, so nothing counts twice.")
                            }
                        }
                    }

                    Section {
                        Toggle(isOn: nudgeBinding) {
                            Text("Mealtime nudge")
                                .font(.ui(17))
                                .foregroundStyle(Theme.ink)
                        }
                        .listRowBackground(Theme.card)
                        if let nudge {
                            DatePicker("Time", selection: nudgeTime(nudge), displayedComponents: .hourAndMinute)
                                .font(.ui(17))
                                .listRowBackground(Theme.card)
                        }
                    } header: {
                        SectionTitle(text: "Reminders")
                    } footer: {
                        Text(nudgeRefused
                            ? LocalizedStringKey("Notifications are off for Bite. Settings, Notifications, Bite.")
                            : LocalizedStringKey("One a day at most, only when that meal isn't in yet. It stops by itself when you don't open Bite."))
                    }

                    if CommunityServer.isConfigured && account.isSignedIn {
                        Section {
                            HStack {
                                Text("Your name")
                                    .font(.ui(17))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                TextField("Your name", text: $communityName)
                                    .multilineTextAlignment(.trailing)
                                    .font(.ui(17))
                                    .submitLabel(.done)
                                    .onSubmit { Task { await account.rename(to: communityName) } }
                            }
                            .listRowBackground(Theme.card)
                            Button("Sign out") { account.signOut() }
                                .font(.ui(17))
                                .listRowBackground(Theme.card)
                            Button("Delete my shared counts and account", role: .destructive) { confirmDelete = true }
                                .font(.ui(17))
                                .listRowBackground(Theme.card)
                                .confirmationDialog("Delete my shared counts and account", isPresented: $confirmDelete, titleVisibility: .visible) {
                                    Button("Delete", role: .destructive) {
                                        Task {
                                            do {
                                                try await account.deleteAccount()
                                                deleteFailed = false
                                            } catch {
                                                deleteFailed = true
                                            }
                                        }
                                    }
                                } message: {
                                    Text("Your shared counts and your account go from the server. Your food log stays on this phone.")
                                }
                        } header: {
                            SectionTitle(text: "Community")
                        } footer: {
                            Text(deleteFailed
                                ? LocalizedStringKey("That didn't work. Try again in a moment.")
                                : LocalizedStringKey("People see your estimates under this name. Your food log stays on this phone."))
                        }
                        .onAppear { communityName = account.displayName }
                    }

                    Section {
                        SecureField("Your own Claude key (optional)", text: $apiKey)
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
                            Label("Photos use your Claude key", systemImage: "checkmark.circle.fill")
                                .font(.ui(17))
                                .foregroundStyle(Theme.goodText)
                                .listRowBackground(Theme.card)
                        }
                        Link(destination: URL(string: "https://platform.claude.com/settings/keys")!) {
                            Label("Get a key from Anthropic", systemImage: "arrow.up.right")
                                .font(.ui(17))
                        }
                        .listRowBackground(Theme.card)
                    } header: {
                        SectionTitle(text: "Photo estimates")
                    } footer: {
                        Text(CommunityServer.isConfigured
                            ? LocalizedStringKey("Photos you scan go to Bite's server and on to Google's Gemini, which sends back the calories and macros. No photo is kept. With your own Claude key, photos go to Anthropic instead, billed to your Anthropic account. Your log never leaves your phone.")
                            : LocalizedStringKey("Photos you scan go to Anthropic's Claude, which sends back the calories and macros. About 2 cents a photo, billed to your Anthropic account. Your log never leaves your phone."))
                    }

                    Section {
                        NavigationLink {
                            MirrorHome(showsDone: false)
                                .modelContainer(MirrorStore.container)
                        } label: {
                            Label {
                                Text("Open your mirror")
                                    .font(.ui(17))
                                    .foregroundStyle(Theme.ink)
                            } icon: {
                                Image(systemName: "person.crop.rectangle")
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                        .listRowBackground(Theme.card)
                        if mirrorConsented {
                            Toggle(isOn: mirrorFaceIDBinding) {
                                Text("Require Face ID")
                                    .font(.ui(17))
                                    .foregroundStyle(Theme.ink)
                            }
                            .listRowBackground(Theme.card)
                            if mirrorKeep.owned {
                                Label("Kept forever", systemImage: "checkmark.icloud")
                                    .font(.ui(17))
                                    .foregroundStyle(Theme.ink)
                                    .listRowBackground(Theme.card)
                            } else {
                                Button("Keep forever, \(mirrorKeep.price) once") {
                                    Task {
                                        guard await mirrorKeep.buy() else { return }
                                        await mirrorKeep.sync()
                                    }
                                }
                                .font(.ui(17))
                                .disabled(mirrorKeep.product == nil || mirrorKeep.buying)
                                .listRowBackground(Theme.card)
                            }
                            Button("Restore Purchases") { Task { await mirrorKeep.restorePurchases() } }
                                .font(.ui(17))
                                .listRowBackground(Theme.card)
                            Button("Delete all your photos", role: .destructive) { confirmMirrorErase = true }
                                .font(.ui(17))
                                .listRowBackground(Theme.card)
                                .confirmationDialog("Delete all your photos", isPresented: $confirmMirrorErase, titleVisibility: .visible) {
                                    Button("Delete", role: .destructive) { MirrorErase.everything() }
                                } message: {
                                    Text(mirrorKeep.owned
                                        ? LocalizedStringKey("The photos, the copy kept for your next iPhone and the key that opens them all go. Nothing can bring them back.")
                                        : LocalizedStringKey("The photos and the key that opens them both go. Nothing can bring them back."))
                                }
                        }
                    } header: {
                        SectionTitle(text: "Your mirror")
                    } footer: {
                        Text(mirrorKeep.owned
                            ? LocalizedStringKey("Kept forever: an encrypted copy waits for your next iPhone, and only your iPhones can open it. Never iCloud, never your camera roll.")
                            : LocalizedStringKey("These photos stay on this phone, out of iCloud and out of your camera roll. A new phone starts fresh, so export before you switch."))
                    }

                    Section {
                        ExportLogRow()
                            .listRowBackground(Theme.card)
                            .id(ExportLogRow.anchor)
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
                #if DEBUG
                .task {
                    // `-anchor bottom` scrolls to your data, for its screenshot.
                    guard UserDefaults.standard.string(forKey: "anchor") == "bottom" else { return }
                    try? await Task.sleep(for: .seconds(1))
                    reader.scrollTo(ExportLogRow.anchor, anchor: .center)
                }
                #endif
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            keepTypedKey()
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    storedKey = Keychain.string(for: Keychain.claudeKey) ?? ""
                    apiKey = storedKey
                }
                // A key pasted and left without Save, or a swipe down, is kept all the same.
                .onDisappear(perform: keepTypedKey)
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
        // Only a key the Keychain really kept shows as saved.
        guard Keychain.set(key, for: Keychain.claudeKey) else {
            apiKey = storedKey
            return
        }
        storedKey = key
        apiKey = key
    }

    /// Saves a pasted key on the way out. Only a whole Anthropic key: a secure field wipes itself
    /// on the first keystroke after a refocus, and a fragment must never replace a working key.
    /// Save key still saves anything.
    private func keepTypedKey() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key != storedKey, key.hasPrefix(Keychain.claudeKeyPrefix), key.count > 40 else { return }
        saveKey()
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
    /// Its id in the list, for scrolling to it.
    static let anchor = "export"

    /// One entry is enough to know there is something to export.
    static var anyEntry: FetchDescriptor<FoodEntry> {
        var descriptor = FetchDescriptor<FoodEntry>()
        descriptor.fetchLimit = 1
        return descriptor
    }

    @Environment(\.modelContext) private var context
    @Query(ExportLogRow.anyEntry) private var first: [FoodEntry]

    var body: some View {
        ShareLink(item: LogFile(container: context.container), preview: SharePreview(LogExport.title)) {
            Label("Export your log", systemImage: "square.and.arrow.up")
                .font(.ui(17))
        }
        .disabled(first.isEmpty)
    }
}

/// The log as a CSV file for the share sheet: Files, Mail, Numbers or a dietitian. It reads
/// the log only when the file is asked for.
struct LogFile: Transferable {
    let container: ModelContainer

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let entries = try ModelContext(file.container).fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date)]))
            let url = FileManager.default.temporaryDirectory.appending(path: LogExport.fileName)
            try LogExport.file(entries.map(LogExport.Row.init)).write(to: url, options: .atomic)
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
