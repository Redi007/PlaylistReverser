import SwiftUI

struct PreviewView: View {
    @Environment(AppModel.self) private var model
    let snapshot: PlaylistSnapshot
    @Binding var confirmSave: Bool
    @State private var confirmRewrite = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if snapshot.tracks.isEmpty {
                ContentUnavailableView("This Playlist Is Empty", systemImage: "music.note",
                                       description: Text("There is nothing to reverse."))
            } else {
                // Streifen selbst zeichnen: alternatesRowBackgrounds setzt sie unter dem letzten Titel fort.
                List(model.displayedTracks) { track in
                    let index = displayIndex(of: track)
                    TrackRow(track: track, displayIndex: index)
                        .listRowBackground(RowStripe(isOdd: index.isMultiple(of: 2)))
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $confirmRewrite) { RewriteConfirmSheet(snapshot: snapshot) }
        .confirmationDialog("Create a new playlist in Music?", isPresented: $confirmSave, titleVisibility: .visible) {
            Button("Save Now") { model.save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private var confirmMessage: String {
        let name = model.copyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = snapshot.tracks.count
        var text = model.isReversed
            ? String(localized: "“\(name)” will be created with \(count) songs in reversed order. The original playlist stays unchanged.")
            : String(localized: "“\(name)” will be created with \(count) songs in the original order. The original playlist stays unchanged.")
        if model.hasNameCollision {
            text += "\n\n" + String(localized: "Note: A playlist with this name already exists.")
        }
        return text
    }

    private func displayIndex(of track: TrackItem) -> Int {
        model.isReversed ? snapshot.tracks.count - track.position + 1 : track.position
    }

    private func toggleOrder() {
        if snapshot.tracks.count <= 400 {
            withAnimation(.snappy) { model.toggleReversed() }
        } else {
            model.toggleReversed()
        }
    }

    // MARK: Kopfbereich

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            CoverView(snapshot: snapshot)
                .frame(width: 168, height: 168)

            VStack(alignment: .leading, spacing: 8) {
                Label("Preview – not saved to Music yet", systemImage: "eye")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)

                title

                HStack(spacing: 6) {
                    Text("\(snapshot.tracks.count) songs")
                    Text(verbatim: "·")
                    Text(formatTotal(snapshot.totalDuration))
                    Text(verbatim: "·")
                    orderBadge
                }
                .foregroundStyle(.secondary)

                if !snapshot.description.isEmpty {
                    Text(snapshot.description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        .help(snapshot.description)
                }

                controls
                    .padding(.top, 6)
            }
            .frame(minWidth: 380, maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
    }

    @ViewBuilder private var title: some View {
        @Bindable var model = model
        if model.saveMode == .newCopy {
            HStack(spacing: 8) {
                TextField("Playlist Name", text: $model.copyName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 26, weight: .bold))
                    .help("Name of the new playlist – click to edit")
                Image(systemName: "pencil").foregroundStyle(.tertiary).accessibilityHidden(true)
            }
        } else {
            Text(snapshot.info.name).font(.system(size: 26, weight: .bold)).lineLimit(1)
                .help(snapshot.info.name)
        }
    }

    private var orderBadge: some View {
        Text(model.isReversed ? "Reversed" : "Original Order")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(model.isReversed ? Color.white : Color.secondary)
            .background(model.isReversed ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: Capsule())
            .contentTransition(.opacity)
    }

    @ViewBuilder private var controls: some View {
        @Bindable var model = model
        HStack(spacing: 10) {
            Text("Save as").foregroundStyle(.secondary)
            Picker("Save as", selection: $model.saveMode) {
                ForEach(SaveMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(snapshot.info.isSmart)
        }
        .font(.callout)

        if model.saveMode == .rewriteOriginal {
            HStack(spacing: 10) {
                Text("Backup name").foregroundStyle(.secondary)
                TextField("Backup name", text: $model.backupName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
            }
            .font(.callout)
        }

        if let hint {
            Label(hint, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        HStack {
            Button(action: toggleOrder) {
                Label(model.isReversed ? "Restore Original Order" : "Reverse Order", systemImage: "arrow.up.arrow.down")
            }
            .controlSize(.large)
            .keyboardShortcut("r", modifiers: .command)
            .disabled(snapshot.tracks.isEmpty)
            .help("Toggle between reversed and original order (⌘R)")

            Button {
                if model.saveMode == .newCopy { confirmSave = true } else { confirmRewrite = true }
            } label: {
                Label(model.saveMode == .newCopy ? "Save to Music…" : "Reorder Original…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(model.saveMode == .newCopy ? .accentColor : .red)
            .controlSize(.large)
            .disabled(!model.canSave)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.top, 2)

        Text(snapshot.originalCover != nil
             ? "The original artwork is shown for reference only. Music does not allow setting playlist artwork via scripting, so the copy gets an automatic cover."
             : "Music does not expose playlist artwork via scripting. Shown is the automatic album mosaic, which Music also generates for the copy.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(3)
    }

    private var hint: LocalizedStringKey? {
        if snapshot.info.isSmart { return "Smart playlists can only be saved as a new copy." }
        if snapshot.tracks.isEmpty { return nil }
        switch model.saveMode {
        case .newCopy:
            if model.copyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a name for the new playlist." }
        case .rewriteOriginal:
            if !model.isReversed { return "Reverse the order first to reorder the original playlist." }
            if model.backupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a name for the backup playlist." }
        }
        return nil
    }

    private func formatTotal(_ seconds: Double) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        f.unitsStyle = .abbreviated
        return f.string(from: seconds) ?? ""
    }
}

struct TrackRow: View {
    @Environment(AppModel.self) private var model
    let track: TrackItem
    let displayIndex: Int
    @State private var image: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(displayIndex)")
                .monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            ArtworkThumb(image: image, size: 36, radius: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.name).lineLimit(1)
                Text(track.artist).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(track.album).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 220, alignment: .trailing)
            Text(Self.duration(track.duration)).monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .task(id: track.artworkKey) {
            image = model.cachedArtwork(for: track)
            if image == nil { image = await model.artwork(for: track) }
        }
    }

    static func duration(_ s: Double) -> String {
        let total = Int(s.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct RowStripe: View {
    let isOdd: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isOdd ? AnyShapeStyle(.quinary) : AnyShapeStyle(.clear))
            .padding(.horizontal, 10)
    }
}

struct ArtworkThumb: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius).fill(.quaternary)
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

struct CoverView: View {
    @Environment(AppModel.self) private var model
    let snapshot: PlaylistSnapshot
    @State private var images: [String: NSImage] = [:]

    var body: some View {
        Group {
            if let data = snapshot.originalCover, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                mosaic
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    private var mosaic: some View {
        let tiles = model.mosaicTracks
        return ZStack {
            Rectangle().fill(.quaternary)
            if tiles.count >= 4 {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow { tile(tiles[0]); tile(tiles[1]) }
                    GridRow { tile(tiles[2]); tile(tiles[3]) }
                }
            } else if let first = tiles.first ?? model.displayedTracks.first {
                tile(first)
            } else {
                Image(systemName: "music.note.list").font(.largeTitle).foregroundStyle(.tertiary)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func tile(_ track: TrackItem) -> some View {
        MosaicTile(track: track)
    }
}

struct MosaicTile: View {
    @Environment(AppModel.self) private var model
    let track: TrackItem
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(.quaternary)
                if let image { Image(nsImage: image).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped() }
            }
        }
        .task(id: track.artworkKey) {
            image = model.cachedArtwork(for: track)
            if image == nil { image = await model.artwork(for: track) }
        }
    }
}

struct SavingOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.saveProgress ?? .init()
        ZStack {
            Rectangle().fill(.black.opacity(0.2)).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(p.mode == .newCopy ? "Saving Playlist" : "Reordering Playlist").font(.headline)
                ProgressView(value: Double(min(p.done, p.total)), total: Double(max(p.total, 1)))
                Text(status(p))
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    .multilineTextAlignment(.center)
                if p.mode == .rewriteOriginal && !p.isCancellable {
                    Text("The original playlist is being rewritten. This step can’t be cancelled.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Cancel", role: .cancel) { model.cancelSave() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(!p.isCancellable)
            }
            .padding(24)
            .frame(width: 380)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        }
        .transition(.opacity)
    }

    private func status(_ p: AppModel.SaveProgress) -> String {
        if p.isValidating { return String(localized: "Verifying in Music…") }
        switch p.mode {
        case .newCopy:
            return String(localized: "\(p.done) of \(p.total) songs copied")
        case .rewriteOriginal:
            let half = p.total / 2
            return p.done < half
                ? String(localized: "Creating backup: \(p.done) of \(half) songs")
                : String(localized: "Reordering original: \(p.done - half) of \(half) songs")
        }
    }
}

struct SuccessSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let report: SaveReport

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green)
            Text(report.modifiedOriginal ? "Playlist Reordered" : "Playlist Saved").font(.title2.bold())
            Text(summary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Label("Order, songs and duplicates verified in Music", systemImage: "checkmark")
                Label(report.modifiedOriginal ? "Backup and new order verified" : "Original playlist unchanged", systemImage: "checkmark")
                ForEach(report.notes, id: \.self) {
                    Label($0, systemImage: "info.circle").foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("Show in Music") { model.reveal(report); dismiss() }
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 440)
    }

    private var summary: String {
        if report.modifiedOriginal {
            return String(localized: "“\(report.name)” was reordered (\(report.trackCount) songs). Backup: “\(report.backupName ?? "")”.")
        }
        return report.reversed
            ? String(localized: "“\(report.name)” was created with \(report.trackCount) songs in reversed order.")
            : String(localized: "“\(report.name)” was created with \(report.trackCount) songs in the original order.")
    }
}

struct RewriteConfirmSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let snapshot: PlaylistSnapshot
    @State private var understood = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("The Original Playlist Will Be Changed", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.bold()).foregroundStyle(.red)
            Text("“\(snapshot.info.name)” will be rebuilt in reversed order (\(snapshot.tracks.count) songs).")
            VStack(alignment: .leading, spacing: 6) {
                Label("First, the backup “\(model.backupName)” is created in the current order and verified.", systemImage: "1.circle")
                Label("Then the original is emptied and refilled from the backup. Songs stay in your library.", systemImage: "2.circle")
                Label("If anything fails, the previous order is restored from the backup automatically.", systemImage: "3.circle")
                Label("The artwork stays with the original, but the app cannot verify this.", systemImage: "info.circle")
                Label("Shared playlists change for everyone who has access.", systemImage: "person.2")
            }
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if model.hasNameCollision {
                Label("A playlist with the backup name already exists.", systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.orange)
            }
            Toggle("I understand that the original playlist will be changed.", isOn: $understood)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Reorder Original", role: .destructive) { dismiss(); model.save() }
                    .buttonStyle(.borderedProminent).tint(.red).disabled(!understood)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}
