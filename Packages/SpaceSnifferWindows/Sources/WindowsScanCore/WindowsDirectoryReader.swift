import Foundation
import WindowsDirectoryIO
import SpaceSnifferScanEngine
struct NativeEntry: Sendable {
    let name: String
    let directory: Bool
    let reparse: Bool
    let attributes: UInt32
    let logical: UInt64
    let allocated: UInt64
    let identity: String?
    var mountedVolume: String? = nil
    var createdTicks: UInt64 = 0
    var accessedTicks: UInt64 = 0
    var modifiedTicks: UInt64 = 0
}
enum Batch: Sendable { case listing([NativeEntry]), failure(UInt32), cancelled, retryInline }
/// Win32 handles, UTF-16 and errors stay within the platform adapter.
struct WindowsDirectoryReader: DirectoryBatchReader {
    var maximumEntries: Int = 4096
    var includeMountedVolumes = false
    func readDirectory(at path: String, control: ScanControl) -> Batch {
        guard !control.isCancelled else { return .cancelled }
        let native = WindowsPath.nativeSpelling(path)
        var error: UInt32 = 0
        let handle = (Array(native.utf16) + [0]).withUnsafeBufferPointer { sniffer_open($0.baseAddress, &error) }
        guard let handle else { return .failure(error) }
        defer { sniffer_close(handle) }
        var rows: [NativeEntry] = []
        while !control.isCancelled {
            var entry = sniffer_entry()
            let status = sniffer_next(handle, &entry, &error)
            if status == 0 {
                rows.sort { $0.name.utf16.lexicographicallyPrecedes($1.name.utf16) }
                return .listing(rows)
            }
            if status < 0 { return .failure(error) }
            if rows.count == maximumEntries { return .retryInline }
            let units = Array(UnsafeBufferPointer(start: entry.name, count: Int(entry.name_units)))
            let name = String(decoding: units, as: UTF16.self)
            guard Array(name.utf16) == units else { return .failure(1113) }
            let identity = entry.id_low == 0 && entry.id_high == 0 ? nil : "\(entry.volume):\(entry.id_high):\(entry.id_low)"
            rows.append(NativeEntry(name: name, directory: entry.attributes & 0x10 != 0,
                reparse: entry.attributes & 0x400 != 0, attributes: entry.attributes,
                logical: entry.logical_bytes, allocated: entry.allocated_bytes, identity: identity, mountedVolume:includeMountedVolumes && entry.reparse_tag == 0xA0000003 ? WindowsVolumeIdentity.read(path + (path.hasSuffix("\\") ? "" : "\\") + name, exactMount:true) : nil,createdTicks:entry.created_ticks, accessedTicks:entry.accessed_ticks, modifiedTicks:entry.modified_ticks))
        }
        return .cancelled
    }
}

enum WindowsVolumeIdentity {
    static func read(_ path:String,exactMount:Bool)->String? {
        var output=[UInt16](repeating:0,count:128)
        let success=(Array(WindowsPath.nativeSpelling(path).utf16)+[0]).withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer {sniffer_volume_identity(source.baseAddress,exactMount ? 1 : 0,$0.baseAddress,UInt32($0.count))}
        }
        guard success != 0,let end=output.firstIndex(of:0) else {return nil}
        return String(decoding:output[..<end],as:UTF16.self).lowercased()
    }
}
