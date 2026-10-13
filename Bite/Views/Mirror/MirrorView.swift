import SwiftData
import SwiftUI

/// Your mirror: one photo at a time, full width, its day and weight under it, never on it; the
/// rest as a rail to pick from; Compare once there are two. Opened behind Face ID or your
/// passcode; covered when Bite leaves the screen and blurred while the screen is recorded or
/// mirrored. The first time, the promise comes first. Hosted in a NavigationStack with
/// `MirrorStore.container`.
struct MirrorHome: View {
    /// Opened from Take it: straight to the camera, back to Today if no photo is kept.
    var startOnCamera = false
    /// A sheet of its own (Today) has Done; pushed in Settings it has Back.
    var showsDone = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isSceneCaptured) private var isCaptured
    @AppStorage("mirror.consented") private var consented = false
    @AppStorage("mirror.faceID") private var faceID = true
    @Query(sort: \MirrorShot.takenAt, order: .reverse) private var shots: [MirrorShot]

    @State private var cameraUp = false
    @State private var unlocked = MirrorVault.shared.isUnlocked
    @State private var unlocking = false
    @State private var unlockFailed = false
    @State private var currentID: UUID?
    @State private var comparing = false
    /// Deleted a moment ago: hidden at once, gone for good when its Undo leaves.
    @State private var hiddenID: UUID?
    @State private var covered = false
    @State private var leftAt: Date?
    @State private var cameraOpened = false

    /// The photos, newest first, without the one just deleted.
    private var visible: [MirrorShot] { shots.filter { $0.photoID != hiddenID } }

    private var current: MirrorShot? {
        visible.first { $0.photoID == currentID } ?? visible.first
    }

    var body: some View {
        Group {
            if !consented {
                MirrorPromise(onStart: start)
            } else if visible.isEmpty {
                empty
            } else if !unlocked {
                locked
            } else {
                gallery
            }
        }
        .background(Theme.page.ignoresSafeArea())
        .navigationTitle(consented ? Text("Your mirror") : Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .overlay(alignment: .bottom) { toast }
        // Leaving Bite: paper over the photos before the app switcher takes its picture.
        .overlay {
            if covered {
                Theme.page.ignoresSafeArea()
            }
        }
        .blur(radius: isCaptured && unlocked ? 40 : 0)
        .fullScreenCover(isPresented: $cameraUp) {
            MirrorCamera(shots: shots) { kept in cameraClosed(kept: kept) }
                .modelContainer(MirrorStore.container)
        }
        .navigationDestination(isPresented: $comparing) {
            if let pair { MirrorPair(older: pair.older, newer: pair.newer) }
        }
        .task {
            // Agreed before, but the key is gone (a phone restored from a backup): start over.
            if consented, !MirrorVault.shared.hasKeys {
                consented = false
            }
            if startOnCamera, consented, !cameraOpened {
                cameraOpened = true
                cameraUp = true
            } else if consented, !visible.isEmpty {
                await unlock()
            }
            #if DEBUG
            if UserDefaults.standard.string(forKey: "screen") == "mirror.pair" { comparing = true }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                covered = false
                // Back within a minute (Control Center, a glance at a message): still open.
                if let leftAt, Date.now.timeIntervalSince(leftAt) > 60 {
                    MirrorVault.shared.lockNow()
                    unlocked = false
                    Task { await unlock() }
                }
                leftAt = nil
            case .inactive:
                covered = unlocked && !cameraUp
            default:
                covered = unlocked && !cameraUp
                leftAt = leftAt ?? .now
            }
        }
        .onDisappear {
            finishDelete()
            MirrorVault.shared.clearExports()
        }
    }

    // MARK: States

    private var gallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pager
                if let current {
                    info(current)
                        .padding(.top, 12)
                }
                if visible.count > 1 {
                    rail
                        .padding(.top, 22)
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    /// One photo at a time, swiped like a cover.
    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(visible, id: \.photoID) { shot in
                    MirrorPhoto(id: shot.photoID, thumbnail: false, maxPixel: 1400)
                        .containerRelativeFrame(.horizontal)
                        .accessibilityElement()
                        .accessibilityLabel(Text("Your photo from \(shot.takenAt.formatted(date: .long, time: .omitted))"))
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.edge, lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if visible.count > 1, let index = visible.firstIndex(where: { $0.photoID == current?.photoID }) {
                PageDots(count: visible.count, index: index)
                    .padding(10)
            }
        }
        .sensoryFeedback(Feel.tick, trigger: currentID)
    }

    /// Under the photo, never on it: the day, the weight when known, and Compare; a second line
    /// only when the light couldn't be held to the first photo's.
    private func info(_ shot: MirrorShot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                Text(Self.dayLine(shot))
                    .font(.ui(15))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if pair != nil {
                    Button {
                        comparing = true
                    } label: {
                        Label("Compare", systemImage: "rectangle.split.2x1")
                            .font(.ui(15, .medium))
                    }
                    .buttonStyle(SoftButtonStyle(height: 36))
                }
            }
            if shot.lockFailed {
                Text(shot.lightDifference > 0
                    ? LocalizedStringKey("Brighter than your first. Same lamp?")
                    : LocalizedStringKey("Darker than your first. Same lamp?"))
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Every photo as a small tile, newest first; the one showing is ringed. Hold one to delete it.
    private var rail: some View {
        Rail(spacing: 8) {
            ForEach(visible, id: \.photoID) { shot in
                let isCurrent = shot.photoID == current?.photoID
                Button {
                    withAnimation(Motion.settle) { currentID = shot.photoID }
                } label: {
                    MirrorPhoto(id: shot.photoID, thumbnail: true, maxPixel: 180)
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: FoodThumb.radius(for: 58), style: .continuous))
                        .padding(3)
                        .overlay {
                            RoundedRectangle(cornerRadius: FoodThumb.radius(for: 58) + 3, style: .continuous)
                                .strokeBorder(Theme.ink, lineWidth: isCurrent ? 2 : 0)
                        }
                }
                .buttonStyle(PressableStyle(scale: 0.94))
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) { delete(shot) }
                }
                .accessibilityLabel(Text("Your photo from \(shot.takenAt.formatted(date: .long, time: .omitted))"))
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
                .accessibilityAction(named: Text("Delete")) { delete(shot) }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            MirrorFigureShape()
                .stroke(Theme.tertiary.opacity(0.4), lineWidth: 1.5)
                .frame(width: 130, height: 290)
                .accessibilityHidden(true)
            Text("No photos yet.")
                .font(.ui(17))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 24)
            Spacer(minLength: 20)
            Button("Take the first one") { cameraUp = true }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }

    private var locked: some View {
        VStack(spacing: 14) {
            Spacer()
            IconCircle(systemImage: "lock", size: 56)
            Text("Your mirror is locked")
                .font(.ui(17, .medium))
                .foregroundStyle(Theme.ink)
            if unlockFailed {
                Text("That didn't work. Try again in a moment.")
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Unlock") { Task { await unlock() } }
                .buttonStyle(SoftButtonStyle())
                .disabled(unlocking)
            Spacer()
        }
        .padding(.horizontal, Theme.margin)
        .frame(maxWidth: .infinity)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if consented {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    cameraUp = true
                } label: {
                    Image(systemName: "camera")
                }
                .accessibilityLabel("Take a photo")
            }
        }
        if consented, unlocked, !visible.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(items: visible.map { MirrorFile(id: $0.photoID, takenAt: $0.takenAt) }, preview: { _ in
                        SharePreview(Text("Your mirror"))
                    }) {
                        Label("Export your photos", systemImage: "square.and.arrow.up")
                    }
                    if let current {
                        Button("Delete this photo", systemImage: "trash", role: .destructive) { delete(current) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        if showsDone {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: The toast

    @ViewBuilder private var toast: some View {
        if hiddenID != nil {
            HStack(spacing: 10) {
                Text("Photo deleted")
                    .font(.ui(15, .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Button {
                    withAnimation(Motion.settle) { hiddenID = nil }
                } label: {
                    Text("Undo")
                        .font(.ui(15, .semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Theme.fill, in: Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.92))
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .floatingGlass(in: Capsule())
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: hiddenID) {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                finishDelete()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: Text("Undo")) { withAnimation(Motion.settle) { hiddenID = nil } }
        }
    }

    // MARK: Actions

    /// The pair Compare opens: the photo showing against your first; on your first, the newest.
    private var pair: (older: MirrorShot, newer: MirrorShot)? {
        guard visible.count > 1, let current, let first = visible.oldest else { return nil }
        if current.photoID == first.photoID {
            guard let newest = visible.first, newest.photoID != first.photoID else { return nil }
            return (first, newest)
        }
        return (first, current)
    }

    private func start(faceID wanted: Bool) {
        Task {
            let made = await Task.detached(priority: .userInitiated) {
                MirrorVault.shared.createKeys(protected: wanted)
            }.value
            guard made.made else { return }
            faceID = made.protected
            consented = true
            unlocked = true
            cameraOpened = true
            cameraUp = true
        }
    }

    private func unlock() async {
        guard !unlocking else { return }
        unlocking = true
        let opened = await MirrorLock.open(faceID: faceID)
        unlocking = false
        withAnimation(Motion.settle) {
            unlocked = opened
            unlockFailed = !opened
        }
    }

    private func cameraClosed(kept: Bool) {
        cameraUp = false
        if kept {
            // The new photo first, opened while you are still holding the phone.
            currentID = shots.first?.photoID
            Task { await unlock() }
        } else if startOnCamera {
            // Opened from Today's Take it and closed with nothing kept: back to Today.
            dismiss()
        }
    }

    /// Gone at once, with Undo; the files go when the Undo does.
    private func delete(_ shot: MirrorShot) {
        finishDelete()
        withAnimation(Motion.settle) { hiddenID = shot.photoID }
    }

    private func finishDelete() {
        guard let id = hiddenID else { return }
        hiddenID = nil
        if let shot = shots.first(where: { $0.photoID == id }) {
            context.delete(shot)
            try? context.save()
        }
        MirrorVault.shared.remove(id)
        MirrorLog.shared.refresh()
    }

    /// "25 April · 69.8 kg", with the year once it isn't this one.
    static func dayLine(_ shot: MirrorShot) -> String {
        let sameYear = Calendar.current.isDate(shot.takenAt, equalTo: .now, toGranularity: .year)
        let day = sameYear
            ? shot.takenAt.formatted(.dateTime.day().month(.wide))
            : shot.takenAt.formatted(.dateTime.day().month(.wide).year())
        guard let weight = shot.weightKg else { return day }
        return "\(day) · \(weight.weightText)"
    }
}

/// One of your photos, opened off the main thread at the size it shows.
struct MirrorPhoto: View {
    let id: UUID
    let thumbnail: Bool
    let maxPixel: CGFloat

    @State private var picture: MirrorPicture?

    var body: some View {
        ZStack {
            Theme.fill
            if let picture {
                Color.clear
                    .overlay {
                        picture.image
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .transition(.opacity)
            }
        }
        .task(id: id) {
            let id = id
            let thumbnail = thumbnail
            let maxPixel = maxPixel
            let opened = await Task.detached(priority: .userInitiated) {
                MirrorVault.shared.picture(id, thumbnail: thumbnail, maxPixel: maxPixel)
            }.value
            withAnimation(Motion.settle) { picture = opened }
        }
    }
}
