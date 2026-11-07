import SwiftUI
import UIKit

/// The two looks. Glass is the dark side of every token in `Theme` and Paper the light side, so
/// the color scheme says which one a view is in, and everything follows it when you switch.
enum Look: String, CaseIterable, Identifiable {
    case glass
    case paper

    static let key = "look"

    var id: String { rawValue }
    var scheme: ColorScheme { self == .glass ? .dark : .light }
    var title: LocalizedStringKey { self == .glass ? "Glass" : "Paper" }
}

/// The color of what you are eating, behind every screen: the photo on the day's cover, blurred
/// and dimmed by `ImageTools.room`. Screens opened over Today read it from here, so a sheet stands
/// in the same room as the day it came from.
@Observable final class Room {
    static let shared = Room()
    /// Nil before the day's first photo.
    var picture: UIImage?
}

/// What a screen sits on. In Glass the room: a page's own picture, or the light of its food, or
/// the day's picture. On Paper a flat color. It never scrolls, so the panes on it can stay flat
/// tints: the blur they seem to have is already in the room.
struct RoomBackground: View {
    var picture: UIImage? = nil
    /// A page with no picture of its own lit by its food's color.
    var glow: Color? = nil
    var paper: Color = Theme.page

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if scheme != .dark {
                paper
            } else if reduceTransparency {
                // With no color behind them the panes read as solid.
                Theme.page
            } else {
                glass
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var shown: UIImage? {
        picture ?? (glow == nil ? Room.shared.picture : nil)
    }

    private var glass: some View {
        ZStack {
            Theme.page
            if let shown {
                Color.clear
                    .overlay {
                        Image(uiImage: shown)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    }
                    .clipped()
                    .id(ObjectIdentifier(shown))
                    .transition(.opacity)
            } else if let glow {
                RadialGradient(
                    colors: [glow.opacity(0.5), glow.opacity(0.16), .clear],
                    center: UnitPoint(x: 0.5, y: 0.2),
                    startRadius: 0,
                    endRadius: 560
                )
            } else {
                // A day before its first photo: fresh green into butter, the kitchen with the
                // lights off.
                RadialGradient(
                    colors: [Color(hex: 0x3F8A58).opacity(0.5), .clear],
                    center: UnitPoint(x: 0.12, y: 0.06),
                    startRadius: 0,
                    endRadius: 480
                )
                RadialGradient(
                    colors: [Color(hex: 0xB78F2C).opacity(0.36), .clear],
                    center: UnitPoint(x: 0.95, y: 0.72),
                    startRadius: 0,
                    endRadius: 520
                )
            }
        }
        .animation(.easeInOut(duration: 0.5), value: shown)
    }
}

extension RoomBackground {
    /// A food's page: its photo as the room, or the light of its tint.
    init(food: Food, paper: Color = Theme.page) {
        self.init(
            picture: food.imageData.flatMap { ImageTools.room($0) },
            glow: Theme.glow(food.displayTint),
            paper: paper
        )
    }
}

/// The room again over the foot of a page, in Glass: what scrolls down goes back into the room
/// before it reaches the buttons floating there, so no word shows through under them.
struct RoomFoot: View {
    var room = RoomBackground()
    var height: CGFloat = 150

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if scheme == .dark {
            room
                .mask(alignment: .bottom) {
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: height)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

/// The bottom bar of a page and the band under the clock. Pages scroll under them, so in Glass
/// this is the one surface with a real blur, and a flat color on Paper.
struct BarGround: View {
    var paper: Color = Theme.card
    /// For a `dockBar`, which softens the page under itself on iOS 26: in Glass its buttons just
    /// float, with no band behind them.
    var floats = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if scheme != .dark {
            paper
        } else if floats, Self.pageSoftens {
            Color.clear
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay { Color.black.opacity(0.28) }
        }
    }

    private static var pageSoftens: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }
}

/// See `bigNumber(_:)`.
private struct BigNumber: ViewModifier {
    let size: CGFloat

    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .font(.number(size, scheme == .dark ? .regular : .medium))
            .numberTracking(size)
    }
}

/// See `meltsIntoRoom()`.
private struct RoomMelt: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let glass = scheme == .dark
        content.mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.5),
                    .init(color: .black.opacity(glass ? 0.34 : 1), location: 0.8),
                    .init(color: .black.opacity(glass ? 0 : 1), location: 0.95),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

/// See `heroSheet()`.
private struct HeroSheet: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if scheme == .dark {
            // Masked, not padded: what is inside keeps its place, and a rail in it ends with the
            // pane instead of running on to the edge of the screen.
            content
                .background(Theme.card)
                .mask {
                    RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous)
                        .padding(.horizontal, Theme.margin - Theme.groupReach)
                }
        } else {
            content.background(
                Theme.card,
                in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
            )
        }
    }
}

/// See `glassGroup(after:)`.
private struct GlassGroup: ViewModifier {
    let gap: CGFloat

    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if scheme == .dark {
            content
                .padding(.horizontal, Theme.groupReach)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
                // A rail inside runs to the group's edge and slides under its corners.
                .clipShape(RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous))
                .padding(.horizontal, -Theme.groupReach)
                .padding(.top, gap > 0 ? Theme.groupGap : 0)
        } else {
            content.padding(.top, gap)
        }
    }
}

extension View {
    /// The screen's room behind this view.
    func roomBackground(paper: Color = Theme.page) -> some View {
        background { RoomBackground(paper: paper) }
    }

    /// Things that belong together. In Glass they float as one pane, reaching past the page
    /// margin so nothing inside moves; on Paper they sit straight on the page, `gap` below what
    /// comes before.
    func glassGroup(after gap: CGFloat = 0) -> some View {
        modifier(GlassGroup(gap: gap))
    }

    /// A number that leads its block. White on dark reads a step heavier than ink on paper, so
    /// in Glass it is a step lighter, and stays as fine.
    func bigNumber(_ size: CGFloat) -> some View {
        modifier(BigNumber(size: size))
    }

    /// A photo at the top of a page, fading out at its foot in Glass so it turns into the room
    /// made of its own colors. On Paper it stays whole.
    func meltsIntoRoom() -> some View {
        modifier(RoomMelt())
    }

    /// What rises over a page's hero: a white sheet on Paper, a pane like any group in Glass.
    func heroSheet() -> some View {
        modifier(HeroSheet())
    }

    /// A choice: `Theme.selected` with its rim when on, `off` otherwise.
    func selectedFill<S: InsettableShape>(_ isOn: Bool, in shape: S, off: Color = Theme.fill) -> some View {
        background(isOn ? Theme.selected : off, in: shape)
            .overlay {
                if isOn {
                    shape.strokeBorder(Theme.rim, lineWidth: 1)
                }
            }
    }
}
