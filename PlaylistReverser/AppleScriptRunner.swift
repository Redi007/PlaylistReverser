import Foundation

/// Führt AppleScript seriell auf einer eigenen Queue aus (NSAppleScript ist nicht threadsicher).
final class AppleScriptRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.playlistreverser.app.applescript", qos: .userInitiated)

    func run<T>(_ source: String, parse: @escaping (NSAppleEventDescriptor) -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: MusicError.unexpected(String(localized: "The script could not be created.")))
                    return
                }
                var errorInfo: NSDictionary?
                let result = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
                    let message = errorInfo[NSAppleScript.errorMessage] as? String ?? String(localized: "Unknown error")
                    continuation.resume(throwing: MusicError(code: code, message: message))
                } else {
                    continuation.resume(returning: parse(result))
                }
            }
        }
    }

    func run(_ source: String) async throws {
        try await run(source) { _ in () }
    }
}

extension MusicError {
    init(code: Int, message: String) {
        switch code {
        case -1743, -1744: self = .notAuthorized
        case -1728, -1719: self = .notFound
        case -1712: self = .timedOut
        default: self = .script(code: code, message: message)
        }
    }
}

extension NSAppleEventDescriptor {
    var items: [NSAppleEventDescriptor] {
        guard numberOfItems > 0 else { return [] }
        return (1...numberOfItems).compactMap { atIndex($0) }
    }

    var text: String { stringValue ?? "" }

    var number: Double {
        if let s = stringValue {
            return Double(s.replacingOccurrences(of: ",", with: ".")) ?? Double(int32Value)
        }
        return Double(int32Value)
    }
}

/// Maskiert Text als AppleScript-String-Literal (Zeilenumbrüche bleiben erhalten).
func appleScriptLiteral(_ text: String) -> String {
    let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        .components(separatedBy: "\n")
    let quoted = lines.map { line -> String in
        let cleaned = String(line.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        return "\"" + cleaned.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    return quoted.joined(separator: " & linefeed & ")
}
