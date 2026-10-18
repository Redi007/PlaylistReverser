import Foundation

struct PlaylistInfo: Identifiable, Hashable, Sendable {
    let id: String            // Persistent ID der Playlist
    let name: String
    let trackCount: Int
    let isSmart: Bool
}

/// Ein Eintrag der Playlist. `position` (1-basiert) identifiziert den Eintrag eindeutig,
/// auch wenn derselbe Song mehrfach vorkommt.
struct TrackItem: Identifiable, Hashable, Sendable {
    let position: Int
    let persistentID: String
    let name: String
    let artist: String
    let album: String
    let genre: String
    let year: Int
    let trackNumber: Int
    let duration: Double

    var id: Int { position }
    var artworkKey: String { album.isEmpty && artist.isEmpty ? "#\(position)" : "\(artist)|\(album)" }
}

/// Unveränderliche Kopie einer Playlist im Speicher. Basis für Vorschau und Speichern.
struct PlaylistSnapshot: Sendable {
    let info: PlaylistInfo
    let description: String
    let isFavorited: Bool
    let tracks: [TrackItem]
    let originalCover: Data?

    var totalDuration: Double { tracks.reduce(0) { $0 + $1.duration } }
}

struct SaveReport: Identifiable, Sendable {
    let id = UUID()
    let playlistID: String
    let name: String
    let trackCount: Int
    let reversed: Bool
    let notes: [String]
    var modifiedOriginal = false
    var backupName: String?
}

enum SaveMode: String, CaseIterable, Identifiable {
    case newCopy
    case rewriteOriginal
    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .newCopy: "New Copy"
        case .rewriteOriginal: "Reorder Original"
        }
    }
}

enum MusicError: LocalizedError {
    case notAuthorized
    case script(code: Int, message: String)
    case notFound
    case timedOut
    case sourceChanged
    case validation(String)
    case emptyName
    case cancelled
    case restored(String)
    case restoreFailed(String)
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return String(localized: "Playlist Reverser is not allowed to control Music. Allow access under System Settings › Privacy & Security › Automation › Playlist Reverser › Music.")
        case .script(let code, let message):
            return String(localized: "Music reported an error (\(code)): \(message)")
        case .notFound:
            return String(localized: "The playlist or one of its songs could not be found in Music. It may have been deleted or changed. Reload and try again.")
        case .timedOut:
            return String(localized: "Music did not respond in time. Make sure Music is not busy (for example with a dialog or a library update) and try again.")
        case .sourceChanged:
            return String(localized: "The original playlist has changed since it was loaded. Nothing was saved. Please reload the playlist.")
        case .validation(let detail):
            return String(localized: "Validation failed: \(detail) The incomplete copy was removed.")
        case .emptyName:
            return String(localized: "Please enter a name for the new playlist.")
        case .restored(let detail):
            return String(localized: "\(detail) The original playlist was restored to its previous order from the backup and verified. The backup has been kept.")
        case .restoreFailed(let detail):
            return String(localized: "\(detail) Automatic restore failed. Your original order is fully preserved in the backup playlist – please do not delete it.")
        case .cancelled:
            return String(localized: "The operation was cancelled. The partial copy was removed.")
        case .unexpected(let message):
            return message
        }
    }

    var needsReload: Bool {
        switch self {
        case .sourceChanged, .notFound, .restored, .restoreFailed: true
        default: false
        }
    }
}
