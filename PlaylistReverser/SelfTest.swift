import Foundation
import AppKit

/// Headless-Ende-zu-Ende-Test gegen die echte Musik-App: `--selftest <Playlistname|ID>`.
/// Legt eine Testkopie „ZZ_PR_SELFTEST“ an, validiert sie und löscht sie wieder. Ausgabe auf Englisch.
enum SelfTest {
    static func run(arguments: [String]) async -> Bool {
        let bridge = MusicBridge()
        var ok = true
        func check(_ label: String, _ cond: Bool, _ detail: String = "") {
            print((cond ? "PASS " : "FAIL ") + label + (detail.isEmpty ? "" : " – " + detail))
            if !cond { ok = false }
        }
        guard let idx = arguments.firstIndex(of: "--selftest"), arguments.indices.contains(idx + 1) else {
            print("Usage: --selftest <playlist name|ID> [--rewrite]"); return false
        }
        let key = arguments[idx + 1]
        if arguments.contains("--rewrite") { return await rewriteTest(key: key, bridge: bridge) }
        var created: String?
        do {
            let lists = try await bridge.listPlaylists()
            check("Read playlists", !lists.isEmpty, "\(lists.count)")
            guard let info = lists.first(where: { $0.id == key || $0.name == key }) else { print("FAIL Playlist not found"); return false }
            let before = try await bridge.trackIDs(playlistID: info.id)
            let snap = try await bridge.loadSnapshot(playlistID: info.id)
            check("Snapshot complete", snap.tracks.count == info.trackCount && snap.tracks.map(\.persistentID) == before, "\(snap.tracks.count) songs, duplicates: \(snap.tracks.count - Set(before).count)")

            if let t = snap.tracks.first(where: { !$0.album.isEmpty }), let data = try await bridge.trackArtwork(playlistID: info.id, position: t.position) {
                check("Track artwork readable", NSImage(data: data) != nil, "\(data.count) bytes")
            } else { print("INFO no track artwork available") }

            let countBefore = try await bridge.listPlaylists().count
            let saver = PlaylistSaver(bridge: bridge)
            let t0 = Date()
            let report = try await saver.save(snapshot: snap, name: "ZZ_PR_SELFTEST", reversed: true) { _, _ in }
            created = report.playlistID
            print(String(format: "INFO Saving took %.1f s", Date().timeIntervalSince(t0)))
            let copy = try await bridge.trackIDs(playlistID: report.playlistID)
            check("Copy saved in reversed order", copy == before.reversed())
            check("Original unchanged", try await bridge.trackIDs(playlistID: info.id) == before)
            check("Playlist count +1", try await bridge.listPlaylists().count == countBefore + 1)
            for n in report.notes { print("INFO " + n) }
        } catch {
            check("Run without errors", false, error.localizedDescription)
        }
        if let created {
            do {
                try await bridge.deletePlaylist(id: created)
                let remaining = try await bridge.listPlaylists().filter { $0.name == "ZZ_PR_SELFTEST" }
                check("Test copy removed", remaining.isEmpty)
            } catch { check("Remove test copy", false, error.localizedDescription) }
        }
        print(ok ? "ALL PASSED" : "FAILED")
        return ok
    }

    /// Testet „Original neu ordnen“ ausschließlich an einer selbst angelegten Fixture-Playlist.
    static func rewriteTest(key: String, bridge: MusicBridge) async -> Bool {
        var ok = true
        func check(_ label: String, _ cond: Bool, _ detail: String = "") {
            print((cond ? "PASS " : "FAIL ") + label + (detail.isEmpty ? "" : " – " + detail)); if !cond { ok = false }
        }
        var created: [String] = []
        do {
            guard let info = try await bridge.listPlaylists().first(where: { $0.id == key || $0.name == key }) else { print("FAIL Playlist not found"); return false }
            let src = try await bridge.loadSnapshot(playlistID: info.id)
            let n = min(40, src.tracks.count)
            let fixtureID = try await bridge.createPlaylist(name: "ZZ_PR_FIXTURE", like: src)
            created.append(fixtureID)
            try await bridge.duplicateTracks(sourceID: info.id, targetID: fixtureID, positions: Array(1...n))
            let snap = try await bridge.loadSnapshot(playlistID: fixtureID)
            let before = snap.tracks.map(\.persistentID)
            check("Fixture created", before.count == n, "\(n) songs")
            let report = try await PlaylistSaver(bridge: bridge, chunkSize: 10).rewriteOriginal(snapshot: snap, backupName: "ZZ_PR_FIXTURE_BACKUP", reversed: true) { _, _ in }
            if let b = try await bridge.listPlaylists().first(where: { $0.name == "ZZ_PR_FIXTURE_BACKUP" }) { created.append(b.id)
                check("Backup in previous order", try await bridge.trackIDs(playlistID: b.id) == before)
            } else { check("Backup exists", false) }
            check("Original reordered (reversed)", try await bridge.trackIDs(playlistID: fixtureID) == before.reversed())
            check("Original playlist is the same (same ID)", report.playlistID == fixtureID && report.modifiedOriginal)
            check("Source playlist untouched", try await bridge.trackIDs(playlistID: info.id) == src.tracks.map(\.persistentID))
        } catch { check("Run without errors", false, error.localizedDescription) }
        for id in created { try? await bridge.deletePlaylist(id: id) }
        let left = (try? await bridge.listPlaylists().filter { $0.name.hasPrefix("ZZ_PR_") }) ?? []
        check("Test playlists removed", left.isEmpty)
        print(ok ? "ALL PASSED" : "FAILED")
        return ok
    }
}
