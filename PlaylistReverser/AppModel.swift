import AppKit
import Observation

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
    }

    struct SaveProgress: Equatable {
        var mode: SaveMode = .newCopy
        var done = 0
        var total = 0

        var isValidating: Bool { total > 0 && done >= total }
        /// Beim Neuordnen ist nur die erste Hälfte (Backup anlegen) abbrechbar.
        var isCancellable: Bool { mode == .newCopy ? !isValidating : done < total / 2 }
    }

    let bridge = MusicBridge()

    var playlists: [PlaylistInfo] = []
    var isLoadingList = false
    var listError: MusicError?
    var selectedID: String? { didSet { if oldValue != selectedID { selectionChanged() } } }

    var phase: Phase = .idle
    var snapshot: PlaylistSnapshot?
    var isReversed = false
    var copyName = ""
    var saveMode: SaveMode = .newCopy
    var backupName = ""

    var saveProgress: SaveProgress?
    var report: SaveReport?
    var error: MusicError?

    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var artworkCache: [String: NSImage] = [:]
    private var artworkMisses: Set<String> = []
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    /// Reihenfolge, wie sie angezeigt und gespeichert wird.
    var displayedTracks: [TrackItem] {
        guard let snapshot else { return [] }
        return isReversed ? snapshot.tracks.reversed() : snapshot.tracks
    }

    var canSave: Bool {
        guard let snapshot, !snapshot.tracks.isEmpty, !isSaving else { return false }
        switch saveMode {
        case .newCopy: return !copyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .rewriteOriginal: return isReversed && !snapshot.info.isSmart && !backupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var isSaving: Bool { saveProgress != nil }

    var hasNameCollision: Bool {
        let n = (saveMode == .newCopy ? copyName : backupName).trimmingCharacters(in: .whitespacesAndNewlines)
        return playlists.contains { $0.name == n }
    }

    func toggleReversed() {
        guard snapshot != nil, !isSaving else { return }
        isReversed.toggle()
    }

    // MARK: Playlists

    func reloadPlaylists() async {
        guard !isLoadingList else { return }
        isLoadingList = true
        defer { isLoadingList = false }
        do {
            playlists = try await bridge.listPlaylists()
            listError = nil
        } catch {
            listError = Self.musicError(error)
        }
    }

    private func selectionChanged() {
        loadTask?.cancel()
        artworkCache = [:]
        artworkMisses = []
        inFlight = [:]
        snapshot = nil
        isReversed = false
        guard let id = selectedID else { phase = .idle; return }
        phase = .loading
        loadTask = Task { [bridge] in
            do {
                let loaded = try await bridge.loadSnapshot(playlistID: id)
                guard !Task.isCancelled else { return }
                snapshot = loaded
                copyName = loaded.info.name
                backupName = String(localized: "\(loaded.info.name) (Backup)")
                saveMode = .newCopy
                phase = .ready
            } catch {
                guard !Task.isCancelled else { return }
                phase = .idle
                selectedID = nil
                present(error)
            }
        }
    }

    func reloadSelected() {
        guard let id = selectedID else { return }
        selectedID = nil
        selectedID = id
    }

    func reloadAll() {
        reloadSelected()
        Task { await reloadPlaylists() }
    }

    // MARK: Speichern

    func save() {
        guard let snapshot, canSave, saveTask == nil else { return }
        let name = copyName, reversed = isReversed, mode = saveMode, backup = backupName
        saveProgress = SaveProgress(mode: mode, done: 0, total: mode == .newCopy ? snapshot.tracks.count : snapshot.tracks.count * 2)
        saveTask = Task { [bridge] in
            let update: @Sendable (Int, Int) -> Void = { done, total in
                Task { @MainActor in
                    guard self.saveProgress != nil else { return }
                    self.saveProgress?.done = done
                    self.saveProgress?.total = total
                }
            }
            let saver = PlaylistSaver(bridge: bridge)
            let result: Result<SaveReport, Error>
            do {
                result = .success(mode == .newCopy
                    ? try await saver.save(snapshot: snapshot, name: name, reversed: reversed, progress: update)
                    : try await saver.rewriteOriginal(snapshot: snapshot, backupName: backup, reversed: reversed, progress: update))
            } catch {
                result = .failure(error)
            }
            // Erst den Fortschritt schließen, dann Bericht bzw. Fehler zeigen – nie zwei Dialoge gleichzeitig.
            saveProgress = nil
            saveTask = nil
            switch result {
            case .success(let report):
                if report.modifiedOriginal { reloadSelected() }
                await reloadPlaylists()
                self.report = report
            case .failure(let error):
                let e = Self.musicError(error)
                if e.needsReload { reloadSelected() }
                await reloadPlaylists()
                present(e)
            }
        }
    }

    func cancelSave() {
        guard saveProgress?.isCancellable == true else { return }
        saveTask?.cancel()
    }

    func reveal(_ report: SaveReport) {
        Task { await bridge.reveal(playlistID: report.playlistID) }
    }

    private func present(_ error: Error) {
        self.error = Self.musicError(error)
    }

    private static func musicError(_ error: Error) -> MusicError {
        error as? MusicError ?? .unexpected(error.localizedDescription)
    }

    // MARK: Cover-Bilder (nur lesend, träge geladen, nach Album dedupliziert)

    func cachedArtwork(for track: TrackItem) -> NSImage? { artworkCache[track.artworkKey] }

    func artwork(for track: TrackItem) async -> NSImage? {
        let key = track.artworkKey
        if let image = artworkCache[key] { return image }
        if artworkMisses.contains(key) { return nil }
        if let task = inFlight[key] { return await task.value }
        guard let playlistID = snapshot?.info.id else { return nil }
        let task = Task { [bridge] () -> NSImage? in
            guard let data = try? await bridge.trackArtwork(playlistID: playlistID, position: track.position) else { return nil }
            return NSImage(data: data)
        }
        inFlight[key] = task
        let image = await task.value
        guard selectedID == playlistID else { return image }
        inFlight[key] = nil
        if let image { artworkCache[key] = image } else { artworkMisses.insert(key) }
        return image
    }

    /// Bis zu vier verschiedene Alben in aktueller Reihenfolge – so bildet Apple Music das automatische Cover.
    var mosaicTracks: [TrackItem] {
        var seen = Set<String>(), result: [TrackItem] = []
        for t in displayedTracks where !t.album.isEmpty && seen.insert(t.artworkKey).inserted {
            result.append(t)
            if result.count == 4 { break }
        }
        return result
    }
}
