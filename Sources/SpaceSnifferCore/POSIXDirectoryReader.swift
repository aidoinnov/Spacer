import Foundation
import Darwin

enum DirectoryNameBudgetError: Error { case exceeded }
enum DirectoryReadPolling: Int, Sendable { case everyEntry = 0, batch64 = 63 }

/// One listing's cursor, native error capture and FD cleanup. No tree,
/// scheduling or UI state. Call seams reproduce failures deterministically.
struct POSIXDirectoryReader {
    var openDirectory: (String) -> UnsafeMutablePointer<DIR>? = { opendir($0) }
    var nextEntry: (UnsafeMutablePointer<DIR>) -> UnsafeMutablePointer<dirent>? = { readdir($0) }
    var closeDirectory: (UnsafeMutablePointer<DIR>) -> Void = { _ = closedir($0) }
    var wait: (ScanControl, TimeInterval) -> Bool = { $0.waitForRetry($1) }

    func names(at path: String, control: ScanControl, statistics: inout ScanIOStatistics,
               budget: (entries: Int, bytes: Int)? = nil,
               polling: DirectoryReadPolling = .batch64,
               progress: () -> Void) throws -> [String] {
        var result: [String] = []
        _ = try visitNames(at: path, control: control, statistics: &statistics, budget: budget,
                           polling: polling, progress: progress) { result.append($0); return true }
        return result.sorted()
    }

    /// Stream an independent namespace census without retaining a second name
    /// array. A false visitor result stops immediately and still closes the FD.
    func visitNames(at path: String, control: ScanControl, statistics: inout ScanIOStatistics,
                    budget: (entries: Int, bytes: Int)? = nil,
                    polling: DirectoryReadPolling = .batch64,
                    progress: () -> Void, visit: (String) -> Bool) throws -> Bool {
        var attempt = 0
        while !control.isCancelled {
            attempt += 1
            statistics.openDirectoryCalls += 1
            guard let directory = openDirectory(path) else {
                // errno is thread-local; capture before any policy or callback.
                let code = errno
                guard let delay = ScanRetryPolicy.delay(after: code, failedAttempt: attempt) else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
                }
                statistics.openRetryDecisions += 1
                statistics.requestedRetryDelaySeconds += delay
                guard wait(control, delay) else { return false }
                continue
            }
            defer { closeDirectory(directory) }
            var count = 0
            var chargedBytes = 0
            var readIndex = 0
            while readIndex & polling.rawValue != 0 || !control.isCancelled {
                errno = 0
                statistics.readDirectoryCalls += 1
                readIndex += 1
                guard let entry = nextEntry(directory) else {
                    let code = errno
                    // Preserve read-error behavior: do not restart a partial
                    // listing and accidentally duplicate observations.
                    if code != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
                    break
                }
                let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                        String(cString: $0)
                    }
                }
                if name != ".", name != ".." {
                    if let budget {
                        let charge = name.utf8.count + 64
                        guard count < budget.entries, charge <= budget.bytes - chargedBytes else { throw DirectoryNameBudgetError.exceeded }
                        chargedBytes += charge
                    }
                    count += 1
                    guard visit(name) else { return false }
                }
                if count % 256 == 0 { progress() }
            }
            return !control.isCancelled
        }
        return false
    }
}
