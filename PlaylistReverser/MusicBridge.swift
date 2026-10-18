import Foundation

/// Dünne Schicht über der Skriptschnittstelle der Musik-App.
/// Alle Funktionen hier außer `createPlaylist`, `duplicateTracks`, `deletePlaylist`
/// arbeiten ausschließlich lesend.
final class MusicBridge: @unchecked Sendable {
    private let runner = AppleScriptRunner()

    private func find(_ id: String, as name: String) -> String {
        "set \(name) to first user playlist whose persistent ID is \(appleScriptLiteral(id))"
    }

    // MARK: Lesen

    func listPlaylists() async throws -> [PlaylistInfo] {
        // Eigenschaften gesammelt abfragen – deutlich schneller als eine Schleife über alle Playlists.
        let source = """
        tell application "Music"
            set ids to persistent ID of every user playlist
            set nms to name of every user playlist
            set sms to smart of every user playlist
            set kinds to special kind of every user playlist
            set cnts to {}
            repeat with i from 1 to count of ids
                if item i of kinds is none then
                    set end of cnts to count of tracks of user playlist i
                else
                    set end of cnts to -1
                end if
            end repeat
            return {ids, nms, sms, cnts}
        end tell
        """
        return try await runner.run(source) { result in
            let cols = result.items.map(\.items)
            guard cols.count == 4, cols.allSatisfy({ $0.count == cols[0].count }) else { return [] }
            return cols[0].indices.compactMap { i in
                let count = Int(cols[3][i].number)
                guard count >= 0 else { return nil }   // Systemplaylists und Ordner
                return PlaylistInfo(id: cols[0][i].text, name: cols[1][i].text, trackCount: count, isSmart: cols[2][i].booleanValue)
            }
        }
    }

    func trackIDs(playlistID: String) async throws -> [String] {
        let source = """
        tell application "Music"
            \(find(playlistID, as: "p"))
            if (count of tracks of p) is 0 then return {}
            return persistent ID of every track of p
        end tell
        """
        return try await runner.run(source) { $0.items.map(\.text) }
    }

    func loadSnapshot(playlistID: String) async throws -> PlaylistSnapshot {
        let source = """
        tell application "Music"
            \(find(playlistID, as: "p"))
            set meta to {name of p, description of p, favorited of p, smart of p, count of artworks of p}
            if (count of tracks of p) is 0 then return {meta, {}, {}, {}, {}, {}, {}, {}, {}}
            return {meta, persistent ID of every track of p, name of every track of p, artist of every track of p, album of every track of p, duration of every track of p, genre of every track of p, year of every track of p, track number of every track of p}
        end tell
        """
        let raw: (meta: [NSAppleEventDescriptor], cols: [[NSAppleEventDescriptor]]) = try await runner.run(source) { result in
            let parts = result.items
            return (parts[0].items, parts.dropFirst().map(\.items))
        }
        let m = raw.meta
        let cols = raw.cols
        let count = cols[0].count
        guard cols.allSatisfy({ $0.count == count }) else {
            throw MusicError.validation(String(localized: "The song data could not be read completely."))
        }
        let tracks = (0..<count).map { i in
            TrackItem(position: i + 1, persistentID: cols[0][i].text, name: cols[1][i].text, artist: cols[2][i].text,
                      album: cols[3][i].text, genre: cols[5][i].text, year: Int(cols[6][i].number),
                      trackNumber: Int(cols[7][i].number), duration: cols[4][i].number)
        }
        let info = PlaylistInfo(id: playlistID, name: m[0].text, trackCount: count, isSmart: m[3].booleanValue)
        let hasCover = Int(m[4].number) > 0
        let cover = hasCover ? try? await playlistCover(playlistID: playlistID) : nil
        return PlaylistSnapshot(info: info, description: m[1].text, isFavorited: m[2].booleanValue, tracks: tracks, originalCover: cover ?? nil)
    }

    func playlistCover(playlistID: String) async throws -> Data? {
        let source = """
        tell application "Music"
            \(find(playlistID, as: "p"))
            return raw data of artwork 1 of p
        end tell
        """
        return try await runner.run(source) { $0.data.count > 100 ? $0.data : nil }
    }

    func trackArtwork(playlistID: String, position: Int) async throws -> Data? {
        let source = """
        tell application "Music"
            \(find(playlistID, as: "p"))
            set t to track \(position) of p
            if (count of artworks of t) is 0 then return missing value
            return raw data of artwork 1 of t
        end tell
        """
        return try await runner.run(source) { $0.data.count > 100 ? $0.data : nil }
    }

    // MARK: Schreiben (nur beim ausdrücklichen Speichern, nur an der eigenen Kopie)

    /// Legt eine leere Playlist an und übernimmt Beschreibung, Favorit und – wenn möglich – den Ordner.
    func createPlaylist(name: String, like snapshot: PlaylistSnapshot) async throws -> String {
        let source = """
        tell application "Music"
            \(find(snapshot.info.id, as: "src"))
            set np to missing value
            try
                set par to parent of src
                set np to make new user playlist at par with properties {name:\(appleScriptLiteral(name))}
            end try
            if np is missing value then set np to make new user playlist with properties {name:\(appleScriptLiteral(name))}
            try
                set description of np to \(appleScriptLiteral(snapshot.description))
            end try
            \(snapshot.isFavorited ? "try\n set favorited of np to true\n end try" : "")
            return persistent ID of np
        end tell
        """
        return try await runner.run(source) { $0.text }
    }

    /// Versucht, das Cover der Originalplaylist zu übertragen. Liefert `true` bei Erfolg.
    func tryCopyCover(sourceID: String, targetID: String) async -> Bool {
        let source = """
        tell application "Music"
            \(find(sourceID, as: "src"))
            \(find(targetID, as: "np"))
            try
                set d to data of artwork 1 of src
                make new artwork at np with properties {data:d}
                return true
            on error
                return false
            end try
        end tell
        """
        return (try? await runner.run(source) { $0.booleanValue }) ?? false
    }

    /// Dupliziert die Einträge `positions` der Quelle in genau dieser Reihenfolge ans Ende des Ziels.
    func duplicateTracks(sourceID: String, targetID: String, positions: [Int]) async throws {
        let list = positions.map(String.init).joined(separator: ", ")
        let source = """
        tell application "Music"
            \(find(sourceID, as: "src"))
            \(find(targetID, as: "np"))
            repeat with i in {\(list)}
                duplicate (track (i as integer) of src) to np
            end repeat
        end tell
        """
        try await runner.run(source)
    }

    /// Entfernt alle Einträge aus der Playlist (nicht aus der Mediathek). Nur im Modus „Original neu ordnen“.
    func clearPlaylist(id: String) async throws {
        let source = """
        tell application "Music"
            \(find(id, as: "p"))
            if (count of tracks of p) > 0 then delete every track of p
        end tell
        """
        try await runner.run(source)
    }

    /// Entfernt ausschließlich eine von dieser App angelegte Kopie.
    func deletePlaylist(id: String) async throws {
        let source = """
        tell application "Music"
            \(find(id, as: "p"))
            delete p
        end tell
        """
        try await runner.run(source)
    }

    func reveal(playlistID: String) async {
        let source = """
        tell application "Music"
            \(find(playlistID, as: "p"))
            activate
            reveal p
        end tell
        """
        try? await runner.run(source)
    }
}

/// Orchestriert das Speichern inklusive Validierung und Rückbau bei Fehlern.
struct PlaylistSaver {
    let bridge: MusicBridge
    var chunkSize = 25

    func save(snapshot: PlaylistSnapshot, name: String, reversed: Bool,
              progress: @escaping @Sendable (Int, Int) -> Void) async throws -> SaveReport {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MusicError.emptyName }

        let order = reversed ? Array(snapshot.tracks.reversed()) : snapshot.tracks
        let expected = order.map(\.persistentID)
        let positions = order.map(\.position)
        let originalIDs = snapshot.tracks.map(\.persistentID)

        // 1. Quelle unverändert? (vor jeder Änderung)
        guard try await bridge.trackIDs(playlistID: snapshot.info.id) == originalIDs else { throw MusicError.sourceChanged }

        // 2. Kopie anlegen und füllen; bei Fehler/Abbruch eigene Teilkopie entfernen
        let newID = try await bridge.createPlaylist(name: trimmed, like: snapshot)
        var notes: [String] = []
        do {
            progress(0, positions.count)
            var done = 0
            for start in stride(from: 0, to: positions.count, by: chunkSize) {
                try Task.checkCancellation()
                let chunk = Array(positions[start..<min(start + chunkSize, positions.count)])
                try await bridge.duplicateTracks(sourceID: snapshot.info.id, targetID: newID, positions: chunk)
                done += chunk.count
                progress(done, positions.count)
            }

            // 3. Validierung: Reihenfolge, Identitäten, Duplikate der Kopie
            let copied = try await bridge.trackIDs(playlistID: newID)
            guard copied.count == expected.count else {
                throw MusicError.validation(String(localized: "Expected \(expected.count) songs, found \(copied.count)."))
            }
            if let bad = zip(copied, expected).enumerated().first(where: { $0.element.0 != $0.element.1 }) {
                throw MusicError.validation(String(localized: "Mismatch at position \(bad.offset + 1)."))
            }
            // 4. Original unangetastet?
            guard try await bridge.trackIDs(playlistID: snapshot.info.id) == originalIDs else {
                throw MusicError.validation(String(localized: "The original playlist was changed while saving."))
            }
        } catch is CancellationError {
            try? await bridge.deletePlaylist(id: newID)
            throw MusicError.cancelled
        } catch {
            try? await bridge.deletePlaylist(id: newID)
            throw error
        }

        // 5. Cover (best effort)
        if snapshot.originalCover != nil {
            if await bridge.tryCopyCover(sourceID: snapshot.info.id, targetID: newID) {
                notes.append(String(localized: "Artwork of the original playlist was copied."))
            } else {
                notes.append(String(localized: "The custom artwork could not be copied – Music does not allow setting playlist artwork via scripting."))
            }
        } else {
            notes.append(String(localized: "Music will give the copy an automatic cover."))
        }
        return SaveReport(playlistID: newID, name: trimmed, trackCount: expected.count, reversed: reversed, notes: notes)
    }
}


extension PlaylistSaver {
    private func fill(source: String, target: String, positions: [Int], base: Int, total: Int,
                      checkCancel: Bool, progress: @Sendable (Int, Int) -> Void) async throws {
        var done = 0
        for start in stride(from: 0, to: positions.count, by: chunkSize) {
            if checkCancel { try Task.checkCancellation() }
            let chunk = Array(positions[start..<min(start + chunkSize, positions.count)])
            try await bridge.duplicateTracks(sourceID: source, targetID: target, positions: chunk)
            done += chunk.count
            progress(base + done, total)
        }
    }

    private func expect(_ id: String, _ expected: [String], what: String) async throws {
        let actual = try await bridge.trackIDs(playlistID: id)
        guard actual.count == expected.count else {
            throw MusicError.validation(String(localized: "\(what): expected \(expected.count) songs, found \(actual.count)."))
        }
        if let bad = zip(actual, expected).enumerated().first(where: { $0.element.0 != $0.element.1 }) {
            throw MusicError.validation(String(localized: "\(what): mismatch at position \(bad.offset + 1)."))
        }
    }

    /// Ordnet die Originalplaylist neu (Cover bleibt am Original). Reihenfolge der Schritte:
    /// Backup anlegen und prüfen → Original leeren → aus dem Backup neu füllen und prüfen → bei Fehler zurückschreiben.
    func rewriteOriginal(snapshot: PlaylistSnapshot, backupName: String, reversed: Bool,
                         progress: @escaping @Sendable (Int, Int) -> Void) async throws -> SaveReport {
        let name = backupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MusicError.emptyName }
        guard !snapshot.info.isSmart else { throw MusicError.validation(String(localized: "Smart playlists cannot be reordered.")) }

        let originalIDs = snapshot.tracks.map(\.persistentID)
        let originalPositions = snapshot.tracks.map(\.position)
        let order = reversed ? Array(snapshot.tracks.reversed()) : snapshot.tracks
        let expected = order.map(\.persistentID)
        let total = originalPositions.count * 2
        let sourceID = snapshot.info.id

        guard try await bridge.trackIDs(playlistID: sourceID) == originalIDs else { throw MusicError.sourceChanged }

        // 1. Backup in alter Reihenfolge – abbrechbar, Original bleibt dabei unberührt
        let backupID = try await bridge.createPlaylist(name: name, like: snapshot)
        do {
            progress(0, total)
            try await fill(source: sourceID, target: backupID, positions: originalPositions, base: 0, total: total, checkCancel: true, progress: progress)
            try await expect(backupID, originalIDs, what: String(localized: "Backup"))
            guard try await bridge.trackIDs(playlistID: sourceID) == originalIDs else { throw MusicError.sourceChanged }
        } catch is CancellationError {
            try? await bridge.deletePlaylist(id: backupID)
            throw MusicError.cancelled
        } catch {
            try? await bridge.deletePlaylist(id: backupID)
            throw error
        }

        // 2. Ab hier nicht mehr abbrechbar: Original leeren und aus dem Backup neu füllen
        let backupPositions = order.map(\.position)   // Backup hat dieselben Positionen wie das Original
        do {
            try await bridge.clearPlaylist(id: sourceID)
            try await fill(source: backupID, target: sourceID, positions: backupPositions, base: originalPositions.count, total: total, checkCancel: false, progress: progress)
            try await expect(sourceID, expected, what: String(localized: "Reordered playlist"))
        } catch {
            // 3. Wiederherstellung aus dem Backup
            do {
                try await bridge.clearPlaylist(id: sourceID)
                try await fill(source: backupID, target: sourceID, positions: originalPositions, base: 0, total: total, checkCancel: false) { _, _ in }
                try await expect(sourceID, originalIDs, what: String(localized: "Restore"))
            } catch {
                throw MusicError.restoreFailed(String(localized: "An error occurred while reordering."))
            }
            let detail = if case .validation(let d) = error as? MusicError { d } else { error.localizedDescription }
            throw MusicError.restored(String(localized: "An error occurred while reordering: \(detail)"))
        }

        var notes = [String(localized: "Backup “\(name)” was created in the original order and verified.")]
        notes.append(snapshot.originalCover != nil
                     ? String(localized: "The artwork stays with the original playlist (this cannot be verified by the app – please check in Music). The backup gets an automatic cover.")
                     : String(localized: "Playlist artwork stays with the original playlist; the backup gets an automatic cover."))
        return SaveReport(playlistID: sourceID, name: snapshot.info.name, trackCount: expected.count, reversed: reversed,
                          notes: notes, modifiedOriginal: true, backupName: name)
    }
}

