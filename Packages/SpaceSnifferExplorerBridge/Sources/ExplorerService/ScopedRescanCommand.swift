import Foundation

/// A scope is JSON data, never another line-oriented control command.
enum ScopedRescanCommand {
    static func matches(_ line: String) -> Bool {
        line.hasPrefix("focus-json ") || line.hasPrefix("focus ")
    }
    static func path(_ line: String) throws -> String {
        if line.hasPrefix("focus-json ") {
            return try JSONDecoder().decode(String.self, from: Data(line.dropFirst(11).utf8))
        }
        return String(line.dropFirst(6)) // Previous native clients remain readable.
    }
}
