#if DEBUG
import SwiftUI
import WidgetKit

/// Every widget at its real size, drawn by the app from the same faces the extension uses, so
/// a simulator screenshot can show them: `-screen widgets` for the Home Screen and StandBy,
/// `-screen widgets-lock` for the Lock Screen and its controls. Debug builds only.
struct WidgetGallery: View {
    let lock: Bool

    static var requested: WidgetGallery? {
        switch UserDefaults.standard.string(forKey: "screen") {
        case "widgets": WidgetGallery(lock: false)
        case "widgets-lock": WidgetGallery(lock: true)
        default: nil
        }
    }

    private let today = TodayEntry(date: .now, snapshot: .sample, canRead: true)
    private var log: LogEntry {
        LogEntry(date: .now, snapshot: .sample, foods: [
            ShelfFood(id: "demo:skyr", name: tr("Morning skyr"), kcal: 68, emoji: "🥣", tint: .butter, photo: nil),
            ShelfFood(id: "demo:coffee", name: tr("Coffee, black"), kcal: 2, emoji: "☕", tint: .sky, photo: nil,
                      addedAt: .now.addingTimeInterval(-60), undoID: "demo"),
            ShelfFood(id: "demo:almonds", name: tr("Almonds"), kcal: 162, emoji: "🌰", tint: .sand, photo: nil),
        ], canRead: true)
    }

    var body: some View {
        if lock { lockScreen } else { homeScreen }
    }

    // MARK: Home Screen

    private var homeScreen: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.73, green: 0.79, blue: 0.86), Color(red: 0.91, green: 0.85, blue: 0.77)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 22) {
                HStack(spacing: 22) {
                    system(.systemSmall) { TodayWidgetView(entry: today, family: .systemSmall) }
                    system(.systemSmall, background: Theme.ink) { ScanWidgetView(family: .systemSmall) }
                }
                system(.systemMedium) { TodayWidgetView(entry: today, family: .systemMedium) }
                system(.systemMedium) { LogWidgetView(entry: log, family: .systemMedium) }
                HStack(spacing: 22) {
                    system(.systemSmall) { LogWidgetView(entry: log, family: .systemSmall) }
                    Color.clear.frame(width: 170, height: 170)
                }
            }
            .padding(.top, 40)
        }
    }

    private func system<Face: View>(_ family: WidgetFamily, background: Color = Theme.page, @ViewBuilder face: () -> Face) -> some View {
        face()
            .padding(16)
            .frame(width: family == .systemMedium ? 364 : 170, height: 170)
            .background(background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, .light)
    }

    // MARK: Lock Screen

    private var lockScreen: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.14, green: 0.18, blue: 0.27), Color(red: 0.33, green: 0.27, blue: 0.33), Color(red: 0.55, green: 0.42, blue: 0.36)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                TodayWidgetView(entry: today, family: .accessoryInline)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.top, 70)
                Text(Date.now.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 92, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                HStack(spacing: 10) {
                    accessory { TodayWidgetView(entry: today, family: .accessoryCircular) }
                    accessory { WaterWidgetView(snapshot: .sample) }
                    accessory { ScanWidgetView(family: .accessoryCircular) }
                }
                .padding(.top, 8)
                accessory(width: 172) { TodayWidgetView(entry: today, family: .accessoryRectangular) }
                    .padding(.top, 10)
                Spacer()
                HStack {
                    control("barcode.viewfinder")
                    Spacer()
                    control("drop.fill")
                }
                .padding(.horizontal, 46)
                .padding(.bottom, 40)
            }
            .foregroundStyle(.white)
        }
        .environment(\.colorScheme, .dark)
    }

    private func accessory<Face: View>(width: CGFloat = 72, @ViewBuilder face: () -> Face) -> some View {
        face()
            .frame(width: width, height: 72)
            .background(.white.opacity(width > 72 ? 0 : 0.12), in: Circle())
    }

    /// One of the Lock Screen's two buttons, where Scan food and Add water can go.
    private func control(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 22, weight: .medium))
            .frame(width: 52, height: 52)
            .background(.white.opacity(0.16), in: Circle())
    }
}
#endif
