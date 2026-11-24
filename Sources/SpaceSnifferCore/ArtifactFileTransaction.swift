import Foundation
import Darwin

/// Injection boundary is per write/close/publish, never per node or field.
protocol ArtifactFileIO: Sendable {
    func write(_ descriptor: Int32, bytes: UnsafeRawBufferPointer) throws -> Int
    func close(_ descriptor: Int32) throws
    func publish(_ temporary: String, to destination: String, replaceExisting: Bool) throws
}
struct NativeArtifactFileIO: ArtifactFileIO {
    func write(_ descriptor: Int32, bytes: UnsafeRawBufferPointer) throws -> Int {
        let count = Darwin.write(descriptor, bytes.baseAddress, bytes.count)
        if count < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return count
    }
    func close(_ descriptor: Int32) throws {
        if Darwin.close(descriptor) != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    func publish(_ temporary: String, to destination: String, replaceExisting: Bool) throws {
        let result = replaceExisting ? Darwin.rename(temporary, destination) : Darwin.renamex_np(temporary, destination, UInt32(RENAME_EXCL))
        if result != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}

/// Writes adjacent staging storage and publishes only after all writes and close
/// succeed. Abort never unlinks the destination. Namespace atomicity is not fsync durability.
final class ArtifactFileTransaction {
    let temporaryPath: String
    private let destination: String
    private let replaceExisting: Bool
    private let io: any ArtifactFileIO
    private var descriptor: Int32
    private let device: dev_t
    private let inode: ino_t
    private var published = false
    init(to url: URL, replaceExisting: Bool, io: any ArtifactFileIO = NativeArtifactFileIO()) throws {
        guard url.isFileURL, !url.path.contains("\0") else { throw CocoaError(.fileWriteInvalidFileName) }
        destination = url.path; self.replaceExisting = replaceExisting; self.io = io
        temporaryPath = url.deletingLastPathComponent().appendingPathComponent(".space-sniffer-" + UUID().uuidString + ".tmp").path
        let fd = Darwin.open(temporaryPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o666))
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var info = stat()
        if fstat(fd, &info) != 0 {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            Darwin.close(fd); Darwin.unlink(temporaryPath); throw error
        }
        descriptor = fd; device = info.st_dev; inode = info.st_ino
        if replaceExisting {
            var previous = stat()
            if stat(destination, &previous) == 0, previous.st_mode & S_IFMT == S_IFREG,
               fchmod(fd, previous.st_mode & 0o777) != 0 {
                let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO); abort(); throw error
            }
        }
    }
    func writeAll(_ bytes: UnsafeRawBufferPointer) throws {
        precondition(descriptor >= 0 && !published)
        var offset = 0
        while offset < bytes.count {
            do {
                let count = try io.write(descriptor, bytes: UnsafeRawBufferPointer(rebasing: bytes[offset...]))
                guard count > 0, count <= bytes.count - offset else { throw POSIXError(.EIO) }
                offset += count
            } catch let error as POSIXError where error.code == .EINTR { continue }
        }
    }
    func commit() throws {
        precondition(descriptor >= 0 && !published)
        let fd = descriptor; descriptor = -1
        // Do not retry an ambiguous close failure using a potentially reused fd.
        try io.close(fd)
        guard ownsTemporaryPath() else { throw POSIXError(.ESTALE) }
        try io.publish(temporaryPath, to: destination, replaceExisting: replaceExisting)
        published = true
    }
    func abort() {
        if descriptor >= 0 { let fd = descriptor; descriptor = -1; try? io.close(fd) }
        guard !published else { return }
        if ownsTemporaryPath() { Darwin.unlink(temporaryPath) }
    }
    private func ownsTemporaryPath() -> Bool {
        var info = stat()
        return lstat(temporaryPath, &info) == 0 && info.st_dev == device && info.st_ino == inode
    }
    deinit { abort() }
}

struct ArtifactFileSink: ArtifactByteSink {
    private let transaction: ArtifactFileTransaction
    private var buffer = Data()
    private let limit: Int
    init(_ transaction: ArtifactFileTransaction, limit: Int = 65_536) {
        precondition(limit > 0); self.transaction = transaction; self.limit = limit; buffer.reserveCapacity(limit)
    }
    mutating func append(_ bytes: UnsafeRawBufferPointer) throws {
        if bytes.count >= limit { try flush(); try transaction.writeAll(bytes); return }
        if bytes.count > limit - buffer.count { try flush() }
        buffer.append(bytes.bindMemory(to: UInt8.self))
    }
    mutating func finish() throws { try flush(); try transaction.commit() }
    private mutating func flush() throws {
        if !buffer.isEmpty { try buffer.withUnsafeBytes { try transaction.writeAll($0) }; buffer.removeAll(keepingCapacity: true) }
    }
}
