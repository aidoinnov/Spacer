import Foundation

/// Synchronous byte consumption; the pointer is borrowed only for this call.
public protocol ArtifactByteSink {
    mutating func append(_ bytes: UnsafeRawBufferPointer) throws
}
extension ArtifactByteSink {
    mutating func integer<T: FixedWidthInteger>(_ value: T) throws {
        var little = value.littleEndian
        try withUnsafeBytes(of: &little) { try append($0) }
    }
    mutating func data(_ value: Data) throws { try value.withUnsafeBytes { try append($0) } }
    mutating func utf8(_ value: String) throws {
        let contiguous = try value.utf8.withContiguousStorageIfAvailable { bytes in
            try append(UnsafeRawBufferPointer(bytes)); return true
        } ?? false
        if !contiguous { try data(Data(value.utf8)) }
    }
}
struct ArtifactDataSink: ArtifactByteSink {
    var value = Data()
    mutating func append(_ bytes: UnsafeRawBufferPointer) { value.append(bytes.bindMemory(to: UInt8.self)) }
}
