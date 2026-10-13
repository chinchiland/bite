import SwiftUI
import UIKit

// MARK: - Containers

/// A white card on the paper, edged with a hairline so it reads without a shadow.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.edge, lineWidth: 1)
            }
    }
}

/// The soft box for the quieter facts that belong together.
struct InsetBox<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: Theme.insetRadius, style: .continuous))
    }
}

/// A title with an optional quiet detail on the right. 20 pt for a section, 17 pt inside one.
struct SectionLabel: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey? = nil
    var size: CGFloat = 20
    /// Apple Health style: the section's symbol before the title, in the color of what it
    /// counts (the calories flame in amber, a rank in gold), ink otherwise.
    var symbol: String? = nil
    var symbolColor: Color = Theme.ink

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.8, weight: .semibold))
                    .foregroundStyle(symbolColor)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.ui(size, .semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.ui(14))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }
}

/// Which of the day's photos shows: a dot for each on a small dark glass, like Photos.
struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        Group {
            if count > 8 {
                Text(verbatim: "\(index + 1) / \(count)")
                    .font(.ui(12, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(index)))
            } else {
                HStack(spacing: 6) {
                    ForEach(0..<count, id: \.self) { dot in
                        Circle()
                            .fill(Color.white.opacity(dot == index ? 1 : 0.45))
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 18)
        .coverGlass(in: Capsule(), onPhoto: true)
        .animation(.snappy, value: index)
        .accessibilityHidden(true)
    }
}

/// A hairline between rows, inset to start where the text starts.
struct RowDivider: View {
    var leading: CGFloat = 72

    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
            .padding(.leading, leading)
    }
}

// MARK: - Buttons

/// The one filled button on a screen: an ink capsule with paper words.
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        PrimaryLabel(configuration: configuration, height: height)
    }

    private struct PrimaryLabel: View {
        let configuration: ButtonStyleConfiguration
        let height: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.ui(17, .medium))
                .foregroundStyle(Theme.page)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(Theme.ink, in: Capsule())
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.3)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.snappy(duration: 0.2), value: configuration.isPressed)
        }
    }
}

/// A quiet button: soft fill, ink words. For everything that is not the main action.
struct SoftButtonStyle: ButtonStyle {
    var height: CGFloat = 44
    var tint: Color = Theme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(16, .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .frame(minHeight: height)
            .background(Theme.fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Shrinks a little under the finger, for tiles and cards that act as buttons.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// A selectable pill, for portions and filters: ink when chosen, soft otherwise.
struct ChipButtonStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(15, .medium))
            .foregroundStyle(isSelected ? Theme.page : Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 15)
            .frame(height: 36)
            .background(isSelected ? Theme.ink : Theme.fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A shelf that runs edge to edge: its first item lines up with the page margin, the next one
/// peeks at the right edge, a swipe settles on an item, and it only moves sideways when there
/// is more to see. Placed inside a section padded by the page margin, it takes the full width
/// back, so every tile you can see can be tapped.
struct Rail<Content: View>: View {
    var spacing: CGFloat = 10
    var alignment: VerticalAlignment = .top
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: alignment, spacing: spacing) {
                content
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, Theme.margin, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
        // The axes default is vertical: without .horizontal this would do nothing for a rail.
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .padding(.horizontal, -Theme.margin)
    }
}

/// − and + around a number. Holding repeats, and each step that moves the number ticks under
/// the finger; a step at the limit stays quiet.
struct StepButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    /// The number the button changes, so a step that can't move it doesn't tick.
    var value: Double? = nil
    let action: () -> Void

    @State private var ticks = 0
    @State private var stepping = false

    var body: some View {
        Button {
            if value == nil {
                ticks += 1
            } else {
                stepping = true
            }
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: 42, height: 42)
                .background(Theme.fill, in: Circle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .onChange(of: value) { _, _ in
            guard stepping else { return }
            stepping = false
            ticks += 1
        }
        .sensoryFeedback(Feel.tick, trigger: ticks)
        .accessibilityLabel(label)
    }
}

/// A round header button on paper: soft circle, outline icon.
struct CircleIconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.ink)
                .frame(width: 38, height: 38)
                .background(Theme.fill, in: Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(label)
    }
}

/// The meal picker beside the main button: the meal's name and the up-down chevrons.
struct MealMenuLabel: View {
    let title: String
    var height: CGFloat = 56

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.ui(16, .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 18)
        .frame(height: height)
        .background(Theme.fill, in: Capsule())
    }
}

// MARK: - Chips and badges

/// A fact in a soft pill. Color only when the fact is good news or worth a look.
struct TintChip: View {
    enum Style {
        case neutral
        case good
        case watch
        case info
    }

    let title: String
    var style: Style = .neutral
    /// An SF Symbol before the words, in `iconColor` or the chip's own icon color.
    var systemImage: String? = nil
    var iconColor: Color? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconColor ?? defaultIconColor)
            }
            Text(title)
                .font(.ui(13, .medium))
                .foregroundStyle(textColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(fillColor, in: Capsule())
    }

    private var textColor: Color {
        switch style {
        case .neutral: Theme.ink
        case .good: Theme.goodText
        case .watch: Theme.watchText
        case .info: Theme.infoText
        }
    }

    private var defaultIconColor: Color {
        style == .good ? Theme.goodIcon : textColor
    }

    private var fillColor: Color {
        switch style {
        case .neutral: Theme.fill
        case .good: Theme.goodFill
        case .watch: Theme.watchFill
        case .info: Theme.infoFill
        }
    }
}

extension Highlight.Kind {
    var chipStyle: TintChip.Style {
        switch self {
        case .good: .good
        case .watch: .watch
        }
    }

    /// A leaf for good news, nothing for the rest: the words carry it.
    var chipSymbol: String? {
        self == .good ? "leaf" : nil
    }
}

extension DayVerdict {
    /// The chip for a day: on target is good news, over is worth a look, light is a fact.
    var chipStyle: TintChip.Style {
        switch self {
        case .onTarget: .good
        case .over: .watch
        case .light, .empty: .info
        }
    }

    var symbol: String {
        switch self {
        case .onTarget: "target"
        case .over: "arrow.up"
        case .light, .empty: "leaf"
        }
    }
}

/// A rank, Brandsearch style: a gold laurel for 1, green for 2 and 3, plain "#4" after that.
struct LaurelBadge: View {
    let rank: Int

    private var color: Color {
        switch rank {
        case 1: Theme.gold
        case 2, 3: Theme.laurelGreen
        default: Theme.secondary
        }
    }

    var body: some View {
        HStack(spacing: 1) {
            if rank <= 3 {
                Image(systemName: "laurel.leading")
                    .font(.system(size: 17))
            }
            Text(verbatim: rank <= 3 ? "\(rank)" : "#\(rank)")
                .font(.number(15))
            if rank <= 3 {
                Image(systemName: "laurel.trailing")
                    .font(.system(size: 17))
            }
        }
        .foregroundStyle(color)
        .frame(minWidth: 54)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rank \(rank)")
    }
}

/// An icon in a soft circle, for list rows and fields.
struct IconCircle: View {
    let systemImage: String
    var color: Color = Theme.ink
    var fill: Color = Theme.fill
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .accessibilityHidden(true)
    }
}

/// A symbol on a tile in its color, the same shape and strength as a macro's tile, for rows
/// that sit beside the macros (calories in the saved food editor).
struct SymbolTile: View {
    let systemImage: String
    /// The tile's wash.
    let color: Color
    /// The symbol, a step deeper than the wash.
    let glyph: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.6, weight: .medium))
            .foregroundStyle(glyph)
            .frame(width: size, height: size)
            .background(color.opacity(0.24), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Food visuals

/// How a food looks everywhere in the app. A product photo stands whole on a white tile, its
/// white background melting into it. A photo you took fills the tile. A basic food is its
/// emoji on its pastel. One shape for all three, so a row of them reads as a set.
struct FoodThumb: View {
    let imageData: Data?
    let imageURL: URL?
    let emoji: String?
    let tint: FoodTint
    var size: CGFloat = 44

    init(imageData: Data? = nil, imageURL: URL? = nil, emoji: String? = nil, tint: FoodTint = .sand, size: CGFloat = 44) {
        self.imageData = imageData
        self.imageURL = imageURL
        self.emoji = emoji
        self.tint = tint
        self.size = size
    }

    init(food: Food, size: CGFloat = 44) {
        self.init(imageData: food.imageData, imageURL: food.imageURL, emoji: food.emoji, tint: food.displayTint, size: size)
    }

    static func radius(for size: CGFloat) -> CGFloat {
        size * 0.19
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius(for: size), style: .continuous)
        content
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay {
                if imageData == nil, imageURL != nil {
                    shape.strokeBorder(Theme.edge, lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        if let data = imageData, let photo = ImageTools.thumbnail(data, points: size) {
            Color.clear
                .overlay {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else if let imageURL {
            ZStack {
                Theme.photoTile
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(size * 0.1)
                            .blendMode(.multiply)
                    } else {
                        emojiFace("🛒")
                            .opacity(0.5)
                    }
                }
            }
            .compositingGroup()
        } else {
            ZStack {
                Theme.tint(tint)
                emojiFace(emoji ?? "🍽️")
            }
        }
    }

    private func emojiFace(_ emoji: String) -> some View {
        Text(emoji)
            .font(.system(size: size * 0.45))
    }
}

// MARK: - Data marks

/// A thin capsule filled to a share of its width.
struct ProgressBar: View {
    let value: Double
    let color: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * min(max(value.isFinite ? value : 0, 0), 1))
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.5), value: value)
    }
}

/// "▼ 4%": the move, colored only when its direction is good or bad news.
struct ChangeLabel: View {
    let change: Double
    var higherIsBetter: Bool? = nil
    var size: CGFloat = 13

    var body: some View {
        let rising = change >= 0
        let color = higherIsBetter.map { $0 == rising ? Theme.goodText : Theme.watchText } ?? Theme.secondary
        HStack(spacing: 4) {
            Image(systemName: rising ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: size * 0.6))
            Text("\((abs(change) * 100).safeInt)%")
                .monospacedDigit()
        }
        .font(.ui(size, .medium))
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rising ? "Up \((abs(change) * 100).safeInt) percent" : "Down \((abs(change) * 100).safeInt) percent")
    }
}

// MARK: - Layout

/// Lays chips out left to right and wraps them onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = Self.measure(subview, maxWidth: maxWidth)
            if x > 0, x + size.width > maxWidth + 0.5 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        // The whole width it was offered, so placing never wraps a row that measuring kept.
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = Self.measure(subview, maxWidth: bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX + 0.5 {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    /// A child's own width, or the row's when it is wider, so it truncates inside the row.
    private static func measure(_ subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard ideal.width > maxWidth, maxWidth.isFinite else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }
}

// MARK: - Glass and transitions

extension View {
    /// Chrome that floats over content (the dock, the toast): Liquid Glass on iOS 26, tinted
    /// with paper so the tiles scrolling under it stay a soft blur instead of a colored smear;
    /// frosted material with a hairline edge before it. Never a drop shadow.
    @ViewBuilder func floatingGlass<S: Shape>(in shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(Theme.page.opacity(0.6)), in: shape)
        } else {
            frosted(in: shape)
        }
        #else
        frosted(in: shape)
        #endif
    }

    private func frosted<S: Shape>(in shape: S) -> some View {
        background(.regularMaterial, in: shape)
            .overlay { shape.stroke(Theme.hairline, lineWidth: 0.5) }
    }

    /// Marks where a screen zooms out from (iOS 18 and later; earlier versions slide as usual).
    @ViewBuilder func zoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Lets a presented screen grow out of its source.
    @ViewBuilder func zoomTransition(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }

    /// A bar floating at the bottom that every scroll view ends above, so nothing needs a
    /// guessed bottom padding. On iOS 26 the page also softens under it.
    @ViewBuilder func dockBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom, spacing: 0, content: bar)
        } else {
            safeAreaInset(edge: .bottom, spacing: 0, content: bar)
        }
        #else
        safeAreaInset(edge: .bottom, spacing: 0, content: bar)
        #endif
    }

    /// A Done button over the number pad, which has no return key of its own.
    func keyboardDone() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}
