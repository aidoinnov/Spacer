import Foundation
/// Pure Windows path spelling strategy. No existence-dependent alias lookup.
enum WindowsPath {
    static func rootSpelling(_ path: String) -> String { path.replacingOccurrences(of: "/", with: "\\") }
    static func nativeSpelling(_ input: String) -> String {
        let path = rootSpelling(input)
        if path.hasPrefix("\\\\?\\") { return path }
        if path.hasPrefix("\\\\") { return "\\\\?\\UNC\\" + path.dropFirst(2) }
        return "\\\\?\\" + path
    }
}
