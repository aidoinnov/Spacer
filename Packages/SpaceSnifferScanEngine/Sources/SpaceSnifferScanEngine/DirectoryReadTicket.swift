import Foundation

public final class DirectoryReadTicket<Output: Sendable>: @unchecked Sendable {
    // Creation/completion belong to the producer module, never consumers.
    init() {}
    private let condition = NSCondition()
    private var result: Output?
    func finish(_ result: Output) {
        condition.lock(); precondition(self.result == nil); self.result = result; condition.broadcast(); condition.unlock()
    }
    public func wait(progress: () -> Void = {}) -> Output {
        while true {
            condition.lock()
            if let result { condition.unlock(); return result }
            let timedOut = !condition.wait(until: Date(timeIntervalSinceNow: 0.02))
            condition.unlock()
            if timedOut { progress() }
        }
    }
}

