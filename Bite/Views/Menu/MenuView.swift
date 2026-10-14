import SwiftUI

/// A restaurant's menu: its photo as the hero, then every dish on it with the calories of the
/// portion a place like this usually serves, and a dish opens to make it yours. A photo you just
/// took is read, then kept on your menus at once, so the next visit is one tap.
struct MenuView: View {
    enum Source {
        /// A photo just taken or picked, read on the way in.
        case photo(UIImage, takenAt: Date?)
        /// A menu you kept.
        case saved(UUID)
    }

    let source: Source
    let day: Date
    /// Opened over the camera: the back button returns to it.
    var overCamera = false
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase
    @State private var menuID: UUID?
    @State private var heroImage: UIImage?
    @State private var attempt = 0
    @State private var filter = ""
    /// Read just now: the line that says it was kept.
    @State private var justRead = false
    @State private var heroGone = false
    @State private var showPhoto = false
    @State private var confirmDelete = false

    enum Phase: Equatable {
        case reading
        case ready
        /// The photo was read but held no dishes.
        case empty
        case trouble(EstimateTrouble)
    }

    init(source: Source, day: Date, overCamera: Bool = false, onDone: @escaping () -> Void) {
        self.source = source
        self.day = day
        self.overCamera = overCamera
        self.onDone = onDone
        switch source {
        case .photo(let image, _):
            _heroImage = State(initialValue: image)
            _phase = State(initialValue: .reading)
        case .saved(let id):
            _menuID = State(initialValue: id)
            _phase = State(initialValue: .ready)
        }
    }

    private var menu: MenuScan? {
        menuID.flatMap { MenuShelf.shared.menu($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                    .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY < 120 } action: { heroGone = $0 }
                sheet
                    .padding(.top, -32)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .ignoresSafeArea(edges: .top)
        .background(Theme.card.ignoresSafeArea())
        .modifier(HeroBar(heroGone: heroGone, title: menu?.title ?? String(localized: "Menu")))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(overCamera)
        .toolbar {
            if overCamera {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back to the camera")
                }
            }
        }
        .sensoryFeedback(trigger: phase) { _, new in
            if new == .ready { return Feel.reached }
            if case .trouble(.failed(_)) = new { return Feel.failed }
            if new == .empty { return Feel.snag }
            return nil
        }
        .task(id: attempt) { await read() }
        .task { loadPhoto() }
        .fullScreenCover(isPresented: $showPhoto) {
            if let heroImage {
                MenuPhotoViewer(image: heroImage)
            }
        }
        .confirmationDialog("Delete this menu", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let menuID { MenuShelf.shared.remove(menuID) }
                dismiss()
            }
        } message: {
            Text("Its dishes leave your search. What you logged from it stays.")
        }
    }

    // MARK: Photo

    private var hero: some View {
        Color.clear
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .overlay {
                if let heroImage {
                    Image(uiImage: heroImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Theme.track
                }
            }
            .overlay {
                LinearGradient(colors: [.black.opacity(0.32), .clear], startPoint: .top, endPoint: .center)
            }
            .overlay {
                if phase == .reading { ScanBand() }
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                if heroImage != nil, phase != .reading { showPhoto = true }
            }
            .visualEffect { content, proxy in
                let pull = max(proxy.frame(in: .scrollView).minY, 0)
                return content.scaleEffect(1 + pull / max(proxy.size.height, 1), anchor: .bottom)
            }
            .accessibilityElement()
            .accessibilityLabel("The menu's photo")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens it full screen")
    }

    // MARK: Sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch phase {
            case .reading:
                reading
                    .padding(.horizontal, Theme.margin)
            case .empty:
                empty
                    .padding(.horizontal, Theme.margin)
            case .trouble(let trouble):
                EstimateGate(trouble: trouble, retry: { attempt += 1 }, close: { dismiss() })
                    .padding(.horizontal, Theme.margin)
            case .ready:
                if let menu {
                    ready(menu)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
            }
        }
        .padding(.top, 26)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
        .background(
            Theme.card,
            in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
        )
    }

    private var reading: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProgressView()
                Text("Reading the menu")
                    .font(.ui(17, .medium))
                    .foregroundStyle(Theme.ink)
            }
            ForEach([230, 180, 250, 200], id: \.self) { width in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.track)
                    .frame(width: CGFloat(width), height: 14)
            }
            Text("Each dish gets a calorie estimate. A long menu can take up to a minute.")
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No dishes found in this photo")
                .font(.ui(22, .semibold))
                .foregroundStyle(Theme.ink)
            Text("Try again with the whole menu in the frame, in good light.")
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(overCamera ? LocalizedStringKey("Back to the camera") : LocalizedStringKey("Back")) { dismiss() }
                .buttonStyle(PrimaryButtonStyle(height: 50))
                .padding(.top, 4)
        }
    }

    @ViewBuilder private func ready(_ menu: MenuScan) -> some View {
        let count = menu.dishes.count
        let shown = filter.trimmingCharacters(in: .whitespaces).isEmpty ? menu.dishes : menu.dishes(matching: filter)
        VStack(alignment: .leading, spacing: 0) {
            Text(menu.title)
                .font(.ui(27, .medium))
                .tracking(-0.6)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                Text("\(count) dishes")
                Text(verbatim: " · " + menu.takenAt.formatted(.dateTime.day().month(.abbreviated)))
            }
            .font(.ui(15))
            .foregroundStyle(Theme.secondary)
            .padding(.top, 2)
            if justRead {
                TintChip(title: String(localized: "Kept in your menus"), style: .good, systemImage: "checkmark")
                    .padding(.top, 12)
                    .transition(.opacity)
            }
            PlaceRow(place: placeBinding(menu))
                .padding(.top, 14)
            if count > 8 {
                findField
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, Theme.margin)

        VStack(spacing: 0) {
            ForEach(shown) { dish in
                NavigationLink(value: FoodRoute.menuDish(menu.id, dish)) {
                    MenuDishRow(dish: dish)
                }
                .buttonStyle(.plain)
                if dish.id != shown.last?.id {
                    RowDivider(leading: Theme.margin + 56)
                }
            }
            if shown.isEmpty {
                Text("No dish by that name on this menu.")
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.margin)
                    .padding(.vertical, 14)
            }
        }
        .padding(.top, 10)

        VStack(alignment: .leading, spacing: 14) {
            Text("Typical portions for a place like this. Open a dish to say how rich and how big yours was.")
                .font(.ui(13))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Delete this menu", role: .destructive) { confirmDelete = true }
                .font(.ui(15, .medium))
                .foregroundStyle(Theme.over)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 18)
    }

    private var findField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.secondary)
            TextField("Find a dish", text: $filter)
                .font(.ui(17))
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !filter.isEmpty {
                Button {
                    filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Theme.inset, in: Capsule())
    }

    private func placeBinding(_ menu: MenuScan) -> Binding<MealPlace?> {
        Binding(
            get: { MenuShelf.shared.menu(menu.id)?.place },
            set: { place in
                guard var current = MenuShelf.shared.menu(menu.id) else { return }
                current.place = place
                MenuShelf.shared.update(current)
            }
        )
    }

    // MARK: Actions

    private func loadPhoto() {
        guard heroImage == nil, let menuID, let data = MenuShelf.shared.photo(of: menuID) else { return }
        heroImage = ImageTools.downsample(data, maxPixel: 1600)
    }

    private func read() async {
        guard case .photo(let image, let takenAt) = source, menuID == nil else { return }
        phase = .reading
        #if DEBUG || BITE_DEMO
        if BiteStore.isDemo {
            // The demo reads every photo as El Beirout's menu, already on its shelf.
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(Motion.settle) {
                menuID = MenuShelf.shared.menus.first?.id
                justRead = true
                phase = .ready
            }
            return
        }
        #endif
        guard let jpeg = ImageTools.jpeg(image, maxSide: 2048, quality: 0.8) else {
            phase = .trouble(.failed(String(localized: "This photo couldn't be read.")))
            return
        }
        do {
            var scanned = try await PhotoEstimator.menu(jpeg: jpeg, language: PhotoEstimator.language)
            guard !scanned.dishes.isEmpty else {
                withAnimation(Motion.settle) { phase = .empty }
                return
            }
            scanned.takenAt = takenAt ?? .now
            MenuShelf.shared.add(scanned, photo: ImageTools.jpeg(image, maxSide: 1600, quality: 0.7))
            withAnimation(Motion.settle) {
                menuID = scanned.id
                justRead = true
                phase = .ready
            }
        } catch {
            withAnimation(Motion.settle) { phase = .trouble(EstimateTrouble(error)) }
        }
    }
}

/// A dish on a menu: its emoji, its name and what the menu says beside it, its calories.
private struct MenuDishRow: View {
    let dish: MenuScan.Dish

    var body: some View {
        HStack(spacing: 12) {
            FoodThumb(emoji: dish.dish.emoji.isEmpty ? "🍽️" : dish.dish.emoji, tint: FoodTint.suggested(for: dish.dish.emoji), size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(dish.name)
                    .font(.ui(17))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                if !dish.detail.isEmpty {
                    Text(dish.detail)
                        .font(.ui(15))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(dish.dish.kcal.kcalText)
                    .font(.number(17))
                    .foregroundStyle(Theme.ink)
                Text("kcal")
                    .font(.ui(13))
                    .foregroundStyle(Theme.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The menu's photo, whole, to read it again at the table: pinch or double tap to look closer.
private struct MenuPhotoViewer: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in scale = min(max(settledScale * value.magnification, 1), 5) }
                        .onEnded { _ in
                            settledScale = scale
                            if scale <= 1 { recenter() }
                        }
                        .simultaneously(with: DragGesture()
                            .onChanged { value in
                                guard scale > 1 else { return }
                                offset = CGSize(width: settledOffset.width + value.translation.width, height: settledOffset.height + value.translation.height)
                            }
                            .onEnded { _ in settledOffset = offset })
                )
                .onTapGesture(count: 2) {
                    withAnimation(Motion.respond) {
                        if scale > 1 {
                            recenter()
                        } else {
                            scale = 2.5
                            settledScale = 2.5
                        }
                    }
                }
                .accessibilityLabel("The menu's photo")
            GlassCircleButton(systemImage: "xmark", label: "Close") { dismiss() }
                .padding(.horizontal, 16)
                .padding(.top, 4)
        }
        .statusBarHidden()
    }

    private func recenter() {
        scale = 1
        settledScale = 1
        offset = .zero
        settledOffset = .zero
    }
}
