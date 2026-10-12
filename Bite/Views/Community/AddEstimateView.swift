import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Your own count of a dish, or a new dish at a place: Claude reads a photo of your plate, or
/// you type what the menu, the pack or your own count says. It joins the others at once.
struct AddEstimateView: View {
    /// The dish you count; nil adds a new dish at `place`.
    let dish: CommunityDish?
    var place: MealPlace? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    enum Mode: Hashable {
        case hand
        case photo
    }

    enum PhotoState: Equatable {
        case idle
        case working
        case done
        case failed(String)
    }

    @State private var mode: Mode = .hand
    @State private var name = ""
    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var photoState: PhotoState = .idle
    @State private var fromPhoto = false

    private var isNewDish: Bool { dish == nil }
    private var kcal: Double? { FoodDetailView.parse(kcalText).flatMap { $0 > 0 ? $0 : nil } }
    private var canSave: Bool {
        kcal != nil && (!isNewDish || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isNewDish {
                    Section {
                        TextField("Name of the dish", text: $name)
                            .font(.ui(17))
                    } header: {
                        Text(place?.line ?? "")
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    Picker("How", selection: $mode) {
                        Text("By hand").tag(Mode.hand)
                        Text("From a photo").tag(Mode.photo)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if mode == .photo {
                    Section {
                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            HStack(spacing: 12) {
                                if let photo {
                                    Image(uiImage: photo)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                } else {
                                    SymbolTile(systemImage: "photo", color: Theme.accurate, glyph: Theme.accurate, size: 44)
                                }
                                Text(photo == nil ? "Choose a photo of your plate" : "Choose another photo")
                                    .font(.ui(17))
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                        photoStatus
                    } footer: {
                        Text("Claude estimates it, and you can correct the numbers before saving.")
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    numberRow("Calories", unit: "kcal", text: $kcalText) {
                        SymbolTile(systemImage: "flame.fill", color: Theme.energy, glyph: Theme.energyDeep)
                    }
                    numberRow("Protein", unit: "g", text: $proteinText) { MacroTile(macro: .protein) }
                    numberRow("Carbs", unit: "g", text: $carbsText) { MacroTile(macro: .carbs) }
                    numberRow("Fat", unit: "g", text: $fatText) { MacroTile(macro: .fat) }
                } footer: {
                    Text("One serving, the way it comes to the table.")
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.page.ignoresSafeArea())
            .navigationTitle(isNewDish ? "New dish" : "Your estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            // A new pick, or closing the sheet, cancels the one still being counted.
            .task(id: pickedPhoto) {
                await estimate(from: pickedPhoto)
            }
            .onAppear(perform: prefill)
        }
    }

    @ViewBuilder private var photoStatus: some View {
        switch photoState {
        case .idle:
            EmptyView()
        case .working:
            HStack(spacing: 10) {
                ProgressView()
                Text("Claude is counting…")
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
            }
        case .done:
            Label("Filled in from your photo", systemImage: "sparkles")
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
        case .failed(let message):
            Text(message)
                .font(.ui(15))
                .foregroundStyle(Theme.over)
        }
    }

    private func numberRow<Icon: View>(_ title: LocalizedStringKey, unit: LocalizedStringKey, text: Binding<String>, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 10) {
            icon()
            Text(title)
                .font(.ui(17))
                .foregroundStyle(Theme.ink)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.number(17))
                .frame(maxWidth: 90)
            Text(unit)
                .font(.ui(17))
                .foregroundStyle(Theme.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }

    // MARK: Actions

    /// Changing your estimate starts from the one you gave.
    private func prefill() {
        guard let mine = dish?.estimates.first(where: \.isMine) else { return }
        set(mine.nutrients)
        mode = mine.source == .ai ? .photo : .hand
    }

    private func set(_ nutrients: Nutrients) {
        kcalText = FoodDetailView.format(nutrients.kcal.rounded())
        proteinText = FoodDetailView.format(nutrients.protein.rounded())
        carbsText = FoodDetailView.format(nutrients.carbs.rounded())
        fatText = FoodDetailView.format(nutrients.fat.rounded())
    }

    private func estimate(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = ImageTools.downsample(data, maxPixel: 2048) else { return }
        photo = image
        photoState = .working
        #if DEBUG || BITE_DEMO
        if BiteStore.isDemo {
            try? await Task.sleep(for: .seconds(1))
            if isNewDish {
                photo = DemoData.estimatePhoto
                if name.isEmpty { name = DemoData.estimate.title }
            }
            set(dish?.consensus.nutrients ?? DemoData.estimate.totals)
            fromPhoto = true
            photoState = .done
            return
        }
        #endif
        let key = Keychain.string(for: Keychain.claudeKey) ?? ""
        guard let jpeg = ImageTools.jpeg(image, maxSide: 1024, quality: 0.72) else {
            photoState = .failed(String(localized: "This photo couldn't be read."))
            return
        }
        do {
            let result = try await ClaudeVision(apiKey: key).estimate(jpeg: jpeg, language: OpenFoodFacts.languages.first ?? "en")
            guard !Task.isCancelled else { return }
            set(result.totals)
            if isNewDish, name.isEmpty { name = result.title }
            fromPhoto = true
            photoState = .done
        } catch let failure as ClaudeVision.Failure {
            guard !Task.isCancelled else { return }
            photoState = .failed(failure.errorDescription ?? String(localized: "Try again."))
        } catch {
            guard !Task.isCancelled else { return }
            photoState = .failed(String(localized: "Check your connection and try again."))
        }
    }

    private func save() {
        guard let kcal else { return }
        let nutrients = Nutrients(
            kcal: kcal,
            protein: FoodDetailView.parse(proteinText) ?? 0,
            carbs: FoodDetailView.parse(carbsText) ?? 0,
            fat: FoodDetailView.parse(fatText) ?? 0
        )
        let source: EstimateSource = fromPhoto && mode == .photo ? .ai : .entered
        let target: CommunityDish
        if let dish {
            target = dish
        } else {
            let place = place ?? MealPlace(name: String(localized: "Somewhere"))
            let photoData = photo.flatMap { ImageTools.jpeg($0, maxSide: 1000, quality: 0.7) }
            let created = CommunityDish(name: name.trimmingCharacters(in: .whitespaces), emoji: "🍽️", photo: photoData, place: place)
            context.insert(created)
            target = created
        }
        if let mine = target.estimates.first(where: \.isMine) {
            mine.kcal = nutrients.kcal
            mine.protein = nutrients.protein
            mine.carbs = nutrients.carbs
            mine.fat = nutrients.fat
            mine.sourceRaw = source.rawValue
        } else {
            let mine = DishEstimate(author: String(localized: "You"), source: source, nutrients: nutrients, isMine: true, tint: .peach)
            context.insert(mine)
            target.estimates.append(mine)
        }
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
