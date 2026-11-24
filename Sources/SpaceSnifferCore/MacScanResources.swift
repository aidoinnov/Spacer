import SpaceSnifferScanEngine

/// Values calibrated on macOS, kept out of the portable algorithms.
enum MacScanResources {
    struct SiblingSampling: Sendable {
        let probeLimit: Int
        let recheckAfter: Int
        init(probeLimit: Int, recheckAfter: Int) {
            precondition(probeLimit > 0 && recheckAfter > 0)
            self.probeLimit = probeLimit; self.recheckAfter = recheckAfter
        }
    }
    static var siblingSampling: SiblingSampling {
        .init(probeLimit: admissionProbeLimit, recheckAfter: admissionRecheckInterval)
    }
    static let admissionProbeLimit = 4
    static let admissionRecheckInterval = 64
    static let defaultConcurrency = 4
    static let readerWorkers = 3
    static let queueCapacity = 24
    static let directoryIO = DirectoryIOBudget(limit: 8)
    static func readWindow(concurrency: Int) -> DirectoryReadWindowPolicy {
        DirectoryReadWindowPolicy(concurrency: concurrency,
            minimumSiblingCount: 64, admittedEntryRange: 64...1024)
    }
}
