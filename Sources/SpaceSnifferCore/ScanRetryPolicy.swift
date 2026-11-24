import Darwin

/// Mac directory-open policy; unlike the Windows blanket ten-attempt retry,
/// unknown and non-transient failures stop immediately.
enum ScanRetryPolicy {
    static let maximumOpenAttempts = 3
    static let retryDelay: Double = 0.01

    /// One-based failed attempt. At most two 10ms waits per directory.
    static func delay(after error: Int32, failedAttempt: Int) -> Double? {
        guard failedAttempt > 0, failedAttempt < maximumOpenAttempts else { return nil }
        switch error {
        case EINTR: return 0
        case EAGAIN, EBUSY, ETIMEDOUT: return retryDelay
        default: return nil
        }
    }
}
