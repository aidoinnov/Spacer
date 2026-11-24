import Foundation

/// Foundation file actions only. AppKit reveal/open/preview remain in the UI adapter.
enum DesktopFileActions {
    static func volumes() -> [DiskVolume] {
        (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? []).map { url in
            DiskVolume(url: url, name: (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? url.lastPathComponent)
        }
    }
    static func trash(_ url: URL) throws { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
}
public struct DiskVolume: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
}
