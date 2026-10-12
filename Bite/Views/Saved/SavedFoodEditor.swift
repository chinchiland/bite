import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Make a saved food yours: its picture (an emoji on a color, its product photo, or a photo
/// you take), its name and a line under it, and what one tap adds.
struct SavedFoodEditor: View {
    enum Mode {
        case new
        case edit(SavedFood)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedFood.sortIndex) private var saved: [SavedFood]

    @State private var name = ""
    @State private var subtitle = ""
    @State private var usesPhoto = false
    @State private var emoji = "🍽️"
    @State private var tint: FoodTint = .sand
    @State private var photoData: Data?
    @State private var productImageURL: URL?
    @State private var amountText = "1"
    @State private var unit: FoodUnit = .serving
    @State private var meal: Meal?
    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showCamera = false
    @State private var loaded = false
    /// The saved food's calories and the amount they are for, copied on open, so the screen
    /// never reads a food that "Remove from shelf" is about to delete.
    @State private var savedKcal = 0.0
    @State private var savedPer = 1.0
    @State private var removeOnClose = false

    private var isNew: Bool {
        if case .new = mode { return true }
        return false
    }

    private var existing: SavedFood? {
        if case .edit(let item) = mode { return item }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.gap) {
                    preview
                    lookCard
                    wordsCard
                    tapCard
                    if isNew { nutritionCard }
                    if existing != nil {
                        Button("Remove from shelf", role: .destructive) {
                            // Deleted once the sheet is gone, like entries on Today.
                            removeOnClose = true
                            dismiss()
                        }
                        .buttonStyle(SoftButtonStyle(tint: Theme.over))
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.page.ignoresSafeArea())
            .navigationTitle(isNew ? "New saved food" : "Saved food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
            .onDisappear {
                guard removeOnClose, let existing else { return }
                context.delete(existing)
                try? context.save()
            }
            .onChange(of: pickedPhoto) { _, item in
                Task { await loadPhoto(item) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    photoData = ImageTools.jpeg(image, maxSide: 1000, quality: 0.7)
                    usesPhoto = photoData != nil
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: Preview

    /// How it will look on the shelf, live.
    private var preview: some View {
        VStack(spacing: 6) {
            FoodThumb(
                imageData: usesPhoto ? photoData : nil,
                imageURL: usesPhoto && photoData == nil ? productImageURL : nil,
                emoji: usesPhoto ? nil : emoji,
                tint: tint,
                size: 108
            )
            .padding(.bottom, 6)
            Text(name.isEmpty ? String(localized: "Name") : name)
                .font(.ui(24, .semibold))
                .foregroundStyle(name.isEmpty ? Theme.tertiary : Theme.ink)
                .multilineTextAlignment(.center)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
            }
            if let kcal = previewKcal {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(kcal.kcalText)
                        .font(.number(20))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(value: kcal))
                    Text("kcal")
                        .font(.ui(15))
                        .foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Theme.fill, in: Capsule())
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: Look

    private var lookCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Picture")
                    .font(.ui(17, .semibold))
                    .foregroundStyle(Theme.ink)
                Picker("Picture", selection: $usesPhoto.animation(.snappy)) {
                    Text("Emoji").tag(false)
                    Text("Photo").tag(true)
                }
                .pickerStyle(.segmented)

                if usesPhoto {
                    photoChoices
                } else {
                    emojiChoices
                    tintChoices
                }
            }
        }
    }

    private static let emojis = [
        "🍽️", "🥣", "🍳", "🥚", "🥞", "🥐", "🍞", "🥯",
        "🍌", "🍎", "🍓", "🫐", "🍊", "🥝", "🥑", "🥗",
        "🥦", "🥕", "🍅", "🍚", "🍝", "🍜", "🍛", "🌮",
        "🍕", "🍔", "🥪", "🍗", "🥩", "🐟", "🍣", "🫘",
        "🧀", "🥛", "☕", "🍵", "🥤", "🍺", "🍷", "🧃",
        "🍫", "🍪", "🍰", "🍦", "🍯", "🥜", "🌰", "🍿",
    ]

    private var emojiChoices: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
            ForEach(Self.emojis, id: \.self) { option in
                Button {
                    emoji = option
                    tint = FoodTint.suggested(for: option)
                } label: {
                    Text(option)
                        .font(.system(size: 22))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            emoji == option ? Theme.tint(tint) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay {
                            if emoji == option {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Theme.ink, lineWidth: 1.5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option)
            }
        }
    }

    private var tintChoices: some View {
        HStack(spacing: 10) {
            ForEach(FoodTint.allCases) { option in
                Button {
                    tint = option
                } label: {
                    Circle()
                        .fill(Theme.tint(option))
                        .frame(width: 30, height: 30)
                        .overlay {
                            Circle().strokeBorder(Theme.ink, lineWidth: tint == option ? 2 : 0)
                        }
                        .overlay {
                            Circle().strokeBorder(Theme.hairline, lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(tint == option ? .isSelected : [])
            }
        }
    }

    private var photoChoices: some View {
        HStack(spacing: 8) {
            if productImageURL != nil {
                Button {
                    photoData = nil
                } label: {
                    choice("Product", systemImage: "shippingbox")
                }
                .buttonStyle(PressableStyle())
            }
            Button {
                showCamera = true
            } label: {
                choice("Take", systemImage: "camera")
            }
            .buttonStyle(PressableStyle())
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                choice("Choose", systemImage: "photo")
            }
            .buttonStyle(PressableStyle())
        }
    }

    /// A photo source as a soft tile: its icon over its word, so three fit side by side in any
    /// language.
    private func choice(_ title: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .regular))
            Text(title)
                .font(.ui(13, .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Words

    private var wordsCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Name")
                    .font(.ui(17, .semibold))
                    .foregroundStyle(Theme.ink)
                TextField("Name", text: $name)
                    .font(.ui(17))
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(Theme.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                TextField("A line under it, like “with honey”", text: $subtitle)
                    .font(.ui(17))
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(Theme.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    // MARK: One tap

    private var tapCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("One tap adds")
                    .font(.ui(17, .semibold))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 8) {
                    TextField("1", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.number(22))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .padding(.horizontal, 10)
                        .frame(height: 46)
                        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(unit.symbol)
                        .font(.ui(17))
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    Menu {
                        Picker("Meal", selection: $meal) {
                            Text("By time of day").tag(Meal?.none)
                            ForEach(Meal.allCases) { option in
                                Text(option.title).tag(Optional(option))
                            }
                        }
                    } label: {
                        MealMenuLabel(title: meal?.title ?? String(localized: "By time"), height: 44)
                    }
                }
            }
        }
    }

    // MARK: Nutrition (new foods)

    private var nutritionCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Per serving")
                    .font(.ui(17, .semibold))
                    .foregroundStyle(Theme.ink)
                numberField("Calories", unit: "kcal", text: $kcalText, icon: AnyView(SymbolTile(systemImage: "flame.fill", color: Theme.energy, glyph: Theme.energyDeep)))
                numberField("Protein", unit: "g", text: $proteinText, icon: AnyView(MacroTile(macro: .protein)))
                numberField("Carbs", unit: "g", text: $carbsText, icon: AnyView(MacroTile(macro: .carbs)))
                numberField("Fat", unit: "g", text: $fatText, icon: AnyView(MacroTile(macro: .fat)))
            }
        }
    }

    private func numberField(_ title: LocalizedStringKey, unit: LocalizedStringKey, text: Binding<String>, icon: AnyView) -> some View {
        HStack(spacing: 10) {
            icon
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
        .frame(height: 40)
    }

    // MARK: Logic

    private var amount: Double? { FoodDetailView.parse(amountText).flatMap { $0 > 0 ? $0 : nil } }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, amount != nil else { return false }
        return isNew ? FoodDetailView.parse(kcalText) != nil : true
    }

    private var previewKcal: Double? {
        if existing != nil {
            guard let amount, savedPer > 0 else { return nil }
            return savedKcal * amount / savedPer
        }
        guard let kcal = FoodDetailView.parse(kcalText), let amount else { return nil }
        return kcal * amount
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let existing else { return }
        name = existing.name
        subtitle = existing.subtitle ?? ""
        usesPhoto = existing.emoji == nil && existing.hasPhoto
        emoji = existing.emoji ?? "🍽️"
        tint = existing.tint
        photoData = existing.imageData
        productImageURL = existing.imageURLString.flatMap { URL(string: $0) }
        unit = FoodUnit(rawValue: existing.unitRaw) ?? .gram
        amountText = FoodDetailView.format(existing.amount)
        meal = existing.meal
        savedKcal = existing.kcal
        savedPer = existing.per
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        photoData = ImageTools.jpeg(image, maxSide: 1000, quality: 0.7)
        usesPhoto = photoData != nil
    }

    private func save() {
        guard let amount else { return }
        let item: SavedFood
        if let existing {
            item = existing
        } else {
            let food = Food(
                id: "saved:\(UUID().uuidString)",
                name: name,
                emoji: emoji,
                source: .manual,
                unit: .serving,
                per: 1,
                nutrients: Nutrients(
                    kcal: FoodDetailView.parse(kcalText) ?? 0,
                    protein: FoodDetailView.parse(proteinText) ?? 0,
                    carbs: FoodDetailView.parse(carbsText) ?? 0,
                    fat: FoodDetailView.parse(fatText) ?? 0
                ),
                tint: tint
            )
            item = SavedFood(food: food, amount: amount, sortIndex: (saved.map(\.sortIndex).max() ?? 0) + 1)
            context.insert(item)
        }
        item.name = name.trimmingCharacters(in: .whitespaces)
        item.subtitle = subtitle.isEmpty ? nil : subtitle
        item.amount = amount
        item.meal = meal
        item.tint = tint
        if usesPhoto {
            item.emoji = nil
            if let photoData { item.imageData = photoData }
        } else {
            item.emoji = emoji
        }
        try? context.save()
        dismiss()
    }
}

/// Shrinks a photo to keep: longest side `maxSide` points, JPEG.
enum ImageTools {

    static func jpeg(_ image: UIImage, maxSide: CGFloat, quality: CGFloat = 0.78) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

/// The system camera, for taking a picture of a food or a plate.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
