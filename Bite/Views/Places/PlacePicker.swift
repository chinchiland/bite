import SwiftUI
import UIKit

/// Where you ate: the places around you, nearest first, or any place by name. Location is
/// asked for here, the first time, with a line on why.
struct PlacePicker: View {
    let current: MealPlace?
    let onPick: (MealPlace?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var finder = PlaceFinder()
    @State private var query = ""
    @State private var results: [PlaceFinder.Nearby] = []

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    nearbySection
                } else {
                    Section {
                        if results.isEmpty {
                            Text("No places found by that name.")
                                .font(.ui(15))
                                .foregroundStyle(Theme.secondary)
                        }
                        ForEach(results) { row($0) }
                    }
                    .listRowBackground(Theme.card)
                }
                if current != nil {
                    Section {
                        Button("No place", role: .destructive) { pick(nil) }
                            .font(.ui(17))
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.page.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search places"))
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(300))
                results = await finder.search(query)
            }
            .navigationTitle("Where did you eat?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await finder.findNearby() }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder private var nearbySection: some View {
        switch finder.state {
        case .askPermission:
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("See the places around you")
                        .font(.ui(17, .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Bite uses your location here, to list the restaurants and cafes nearby. It stays on your phone.")
                        .font(.ui(15))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Use my location") { finder.allow() }
                        .buttonStyle(PrimaryButtonStyle(height: 48))
                        .padding(.top, 4)
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Theme.card)
        case .denied:
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Location is off for Bite. Search by name, or turn it on in Settings.")
                        .font(.ui(15))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.ui(15, .semibold))
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Theme.card)
        case .idle, .searching:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Looking around you…")
                        .font(.ui(15))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .listRowBackground(Theme.card)
        case .failed:
            Section {
                Text("Couldn't find the places around you. Search by name instead.")
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
            }
            .listRowBackground(Theme.card)
        case .found:
            Section {
                ForEach(finder.nearby) { row($0) }
            } header: {
                Text("Near you")
            }
            .listRowBackground(Theme.card)
        }
    }

    private func row(_ item: PlaceFinder.Nearby) -> some View {
        Button {
            pick(item.place)
        } label: {
            HStack(spacing: 12) {
                SymbolTile(systemImage: item.place.category?.symbol ?? "mappin", color: Theme.ink, glyph: Theme.ink, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.place.name)
                        .font(.ui(17))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    HStack(spacing: 0) {
                        if let area = item.place.area {
                            Text(area)
                        }
                        if let distance = item.distance {
                            Text(verbatim: item.place.area == nil ? "" : " · ")
                            Text(distance.distanceText)
                                .monospacedDigit()
                        }
                    }
                    .font(.ui(14))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                if item.place.key == current?.key {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pick(_ place: MealPlace?) {
        UISelectionFeedbackGenerator().selectionChanged()
        onPick(place)
        dismiss()
    }
}

/// Where a meal is from, as a row beside its time: the place, or Add. A tap opens the places
/// around you.
struct PlaceRow: View {
    @Binding var place: MealPlace?
    @State private var showPicker = false

    var body: some View {
        HStack {
            Text("Place")
                .font(.ui(17))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button {
                showPicker = true
            } label: {
                HStack(spacing: 5) {
                    if let place {
                        Image(systemName: "mappin")
                            .font(.system(size: 13, weight: .semibold))
                        Text(place.name)
                            .lineLimit(1)
                    } else {
                        Text("Add")
                    }
                }
                .font(.ui(17))
                .foregroundStyle(place == nil ? Theme.secondary : Theme.ink)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Theme.fill, in: Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.95))
            .accessibilityLabel(place.map { Text("Place: \($0.name)") } ?? Text("Add a place"))
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showPicker) {
            PlacePicker(current: place) { picked in
                withAnimation(.snappy) { place = picked }
            }
        }
        #if DEBUG
        .onAppear {
            if UserDefaults.standard.string(forKey: "screen") == "where" { showPicker = true }
        }
        #endif
    }
}
