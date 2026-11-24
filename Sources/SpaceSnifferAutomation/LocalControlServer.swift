import Foundation
import Darwin

/// Private, per-user Unix IPC. No TCP listener or filesystem mutation commands.
public final class LocalControlServer: @unchecked Sendable {
    public static var directory: String { "/tmp/mac-space-sniffer-\(getuid())" }
    private let descriptor: String
    private let socketPath: String
    private let fd: Int32
    private let token = UUID().uuidString + UUID().uuidString
    private let lock = NSLock()
    private var stopped = false
    private let slots = DispatchSemaphore(value: 4)
    private let handler: @Sendable (ControlRequest) async -> ControlResponse
    public init(bundleID: String, handler: @escaping @Sendable (ControlRequest) async -> ControlResponse) throws {
        self.handler = handler
        let directory = Self.directory
        if mkdir(directory, 0o700) != 0 && errno != EEXIST { throw ControlError("ipc_unavailable", "Cannot create control directory") }
        var info = stat()
        guard lstat(directory, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFDIR,
              info.st_mode & 0o077 == 0 else { throw ControlError("ipc_unavailable", "Control directory must be owned by this user with mode 0700") }
        let pid = ProcessInfo.processInfo.processIdentifier
        let nonce = UUID().uuidString.prefix(8)
        socketPath = directory + "/\(pid)-\(nonce).sock"; descriptor = directory + "/\(pid)-\(nonce).json"
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlError("ipc_unavailable", "socket() failed") }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { close(fd); throw ControlError("ipc_unavailable", "Socket path too long") }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes.map { UInt8(bitPattern: $0) }) }
        unlink(socketPath)
        let bound = withUnsafePointer(to: &address) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard bound == 0, chmod(socketPath, 0o600) == 0, listen(fd, 8) == 0 else { close(fd); unlink(socketPath); throw ControlError("ipc_unavailable", "Cannot bind control socket") }
        let data = try JSONEncoder().encode(JSONValue.object(["pid": .int(Int(pid)), "bundle_id": .string(bundleID),
            "socket": .string(socketPath), "token": .string(token), "version": .int(1), "started_at": .date(Date())]))
        do { try data.write(to: URL(fileURLWithPath: descriptor), options: .atomic); chmod(descriptor, 0o600) }
        catch { close(fd); unlink(socketPath); throw error }
        DispatchQueue(label: "local.macspacesniffer.control.accept", qos: .utility).async { [self] in acceptConnections() }
    }
    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    public func stop() {
        lock.lock(); if stopped { lock.unlock(); return }; stopped = true; lock.unlock()
        Darwin.shutdown(fd, SHUT_RDWR); close(fd); unlink(socketPath); unlink(descriptor)
    }
    private func acceptConnections() {
        while !isStopped {
            slots.wait()
            if isStopped { slots.signal(); break }
            let client = accept(fd, nil, nil)
            guard client >= 0 else { slots.signal(); if errno == EINTR { continue }; break }
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { close(client); slots.signal(); continue }
            var noSignal: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: 15, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            DispatchQueue.global(qos: .utility).async { [self] in
                do {
                    let data = try Self.readLine(client)
                    let request = try JSONDecoder().decode(ControlRequest.self, from: data)
                    guard request.token == token else { throw ControlError("unauthorized", "Invalid control token") }
                    Task { [self] in
                        let response = await handler(request)
                        DispatchQueue.global(qos: .utility).async { [self] in
                            Self.send(response, to: client); close(client); slots.signal()
                        }
                    }
                } catch {
                    Self.send(ControlResponse(id: .null, error: (error as? ControlError) ?? ControlError("invalid_request", error.localizedDescription)), to: client)
                    close(client); slots.signal()
                }
            }
        }
    }
    private static func readLine(_ fd: Int32) throws -> Data {
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= 1_048_576 {
            let count = Darwin.read(fd, &buffer, buffer.count)
            guard count > 0 else { throw ControlError("invalid_request", "Request closed or timed out") }
            if let newline = buffer[..<count].firstIndex(of: 10) {
                guard data.count + newline <= 1_048_576 else { throw ControlError("invalid_request", "Request exceeds 1 MiB") }
                data.append(contentsOf: buffer[..<newline]); return data
            }
            data.append(contentsOf: buffer[..<count])
        }
        throw ControlError("invalid_request", "Request exceeds 1 MiB")
    }
    private static func send(_ response: ControlResponse, to fd: Int32) {
        guard var data = try? JSONEncoder().encode(response), data.count <= 16_777_216 else { return }
        data.append(10)
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = Darwin.send(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset, MSG_NOSIGNAL)
                if count <= 0 { break }; offset += count
            }
        }
    }
}
